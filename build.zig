const builtin = @import("builtin");
const shipped_open_row_corpus = @import("src/shipped_open_row_corpus_registry.zig");
const std = @import("std");
const zlinter = @import("zlinter");

const ShiftConsumerDeps = struct {
    lowered_runtime_mod: ?*std.Build.Module,
    ability_mod: *std.Build.Module,
    ability_compile_mod: ?*std.Build.Module = null,
    ability_agent_vm_mod: ?*std.Build.Module = null,
};

const TestSuiteSpec = struct {
    suite_id: []const u8,
    description: []const u8,
    default_enabled: bool = true,
    run_step: ?*std.Build.Step = null,
};

const TestSuiteSelection = struct {
    allocator: std.mem.Allocator,
    enabled: []bool,

    fn deinit(self: @This()) void {
        self.allocator.free(self.enabled);
    }

    fn isEnabled(self: @This(), index: usize) bool {
        return self.enabled[index];
    }
};

const TestSuiteSelectionResult = union(enum) {
    duplicate: []const u8,
    empty_token,
    selection: TestSuiteSelection,
    unknown: []const u8,
};

const TestFilterArgs = struct {
    allocator: std.mem.Allocator,
    items: []const []const u8,

    fn deinit(self: @This()) void {
        self.allocator.free(self.items);
    }
};

const TestRunnerArgs = struct {
    filters: TestFilterArgs,
    passthrough: TestFilterArgs,
    owned_passthrough: TestFilterArgs,

    fn deinit(self: @This()) void {
        for (self.owned_passthrough.items) |arg| {
            self.owned_passthrough.allocator.free(arg);
        }
        self.filters.deinit();
        self.passthrough.deinit();
        self.owned_passthrough.deinit();
    }
};

const TestRunnerArgParseResult = union(enum) {
    args: TestRunnerArgs,
    empty_pattern,
    invalid_seed_value: []const u8,
    missing_passthrough_value: []const u8,
    missing_pattern,
    unknown_arg: []const u8,
};

const TestRunnerArgParseMode = enum {
    allow_unknown_args,
    strict,
};

// Linux caps argv+env at 3/4 of the 8 MiB _STK_LIM ceiling. Io.Limit is
// exclusive, so keep one byte of headroom for a cmdline at the platform cap.
const linux_max_argv_env_bytes = 6 * 1024 * 1024;
const max_cmdline_bytes = linux_max_argv_env_bytes + 1;

fn emptyArgs(allocator: std.mem.Allocator) !TestFilterArgs {
    return .{
        .allocator = allocator,
        .items = try allocator.alloc([]const u8, 0),
    };
}

fn emptyTestRunnerArgs(allocator: std.mem.Allocator) !TestRunnerArgs {
    return .{
        .filters = try emptyArgs(allocator),
        .passthrough = try emptyArgs(allocator),
        .owned_passthrough = try emptyArgs(allocator),
    };
}

const BuildInvocationArgs = struct {
    arena: std.heap.ArenaAllocator,
    items: []const []const u8,

    fn deinit(self: *@This()) void {
        self.arena.deinit();
    }
};

fn buildInvocationArgsAlloc() !BuildInvocationArgs {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer arena.deinit();

    const arena_allocator = arena.allocator();
    const items = try switch (builtin.os.tag) {
        .macos, .ios, .tvos, .watchos, .visionos => buildInvocationArgsAllocDarwin(arena_allocator),
        .linux => buildInvocationArgsAllocLinux(arena_allocator),
        .windows => buildInvocationArgsAllocWindows(arena_allocator),
        else => error.UnsupportedHostBuildInvocationArgs,
    };

    return .{
        .arena = arena,
        .items = items,
    };
}

fn buildInvocationRequestsRunnableStepFromArgsResult(
    step_name: []const u8,
    args_result: anyerror!BuildInvocationArgs,
) ?bool {
    var args = args_result catch return null;
    defer args.deinit();

    return buildInvocationRequestsRunnableStepInArgs(args.items, step_name);
}

fn buildInvocationSkipsStepExecutionFromArgsResult(args_result: anyerror!BuildInvocationArgs) ?bool {
    var args = args_result catch return null;
    defer args.deinit();

    return buildInvocationSkipsStepExecutionInArgs(args.items);
}

fn buildInvocationRequestsStepFromArgsResult(
    step_name: []const u8,
    args_result: anyerror!BuildInvocationArgs,
) ?bool {
    var args = args_result catch return null;
    defer args.deinit();

    return buildInvocationRequestsStepInArgs(args.items, step_name);
}

fn buildInvocationArgsAllocDarwin(allocator: std.mem.Allocator) ![]const []const u8 {
    const darwin_externs = struct {
        extern "c" fn _NSGetArgc() *c_int;
        extern "c" fn _NSGetArgv() *[*:null]?[*:0]u8;
    };

    const argc_signed = darwin_externs._NSGetArgc().*;
    if (argc_signed < 0) return error.InvalidBuildInvocationArgCount;

    const argc: usize = @intCast(argc_signed);
    const argv = darwin_externs._NSGetArgv().*[0..argc];
    const items = try allocator.alloc([]const u8, argc);
    for (items, argv) |*dst, maybe_arg| {
        const arg = maybe_arg orelse return error.InvalidBuildInvocationArgVector;
        dst.* = std.mem.sliceTo(arg, 0);
    }
    return items;
}

fn buildInvocationArgsAllocLinux(allocator: std.mem.Allocator) ![]const []const u8 {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        compatIo(),
        "/proc/self/cmdline",
        allocator,
        .limited(max_cmdline_bytes),
    );

    if (bytes.len == 0) return error.InvalidBuildInvocationArgVector;

    var argc: usize = 0;
    var index: usize = 0;
    while (index < bytes.len) {
        const end = std.mem.findScalarPos(u8, bytes, index, 0) orelse
            return error.InvalidBuildInvocationArgVector;
        argc += 1;
        index = end + 1;
    }

    const items = try allocator.alloc([]const u8, argc);
    index = 0;
    for (items) |*item| {
        const end = std.mem.findScalarPos(u8, bytes, index, 0).?;
        item.* = bytes[index..end];
        index = end + 1;
    }
    return items;
}

const SharedTailInvocationInference = struct {
    test_requested: ?bool,
    lint_requested: ?bool,
};

fn sharedTailHasTestSignal(args: []const []const u8) bool {
    var index: usize = 0;
    while (index < args.len) {
        if (recognizedTestRunnerArgSpan(args, index)) |_| return true;

        const arg = args[index];
        if (std.mem.eql(u8, arg, "--test-filter") or
            std.mem.startsWith(u8, arg, "--test-filter=") or
            std.mem.eql(u8, arg, "--seed") or
            std.mem.startsWith(u8, arg, "--seed=") or
            std.mem.eql(u8, arg, "--cache-dir") or
            std.mem.startsWith(u8, arg, "--cache-dir=") or
            std.mem.eql(u8, arg, "--listen=-"))
        {
            return true;
        }
        index += 1;
    }
    return false;
}

fn sharedTailHasLintSignal(args: []const []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--max-warnings") or std.mem.startsWith(u8, arg, "--max-warnings=")) {
            return true;
        }
    }
    return false;
}

fn inferBuildInvocationFromSharedTail(args: ?[]const []const u8) SharedTailInvocationInference {
    const raw_args = args orelse
        return .{
            .test_requested = null,
            .lint_requested = null,
        };

    const test_signal = sharedTailHasTestSignal(raw_args);
    const lint_signal = sharedTailHasLintSignal(raw_args);
    if (test_signal == lint_signal) {
        return .{
            .test_requested = null,
            .lint_requested = null,
        };
    }

    return .{
        .test_requested = test_signal,
        .lint_requested = lint_signal,
    };
}

fn buildInvocationArgsAllocWindows(allocator: std.mem.Allocator) ![]const []const u8 {
    const raw_items = try std.process.Args.toSlice(
        .{ .vector = std.os.windows.peb().ProcessParameters.CommandLine.slice() },
        allocator,
    );
    const items = try allocator.alloc([]const u8, raw_items.len);
    for (items, raw_items) |*dst, src| {
        dst.* = src;
    }
    return items;
}

// Keep this in sync with Zig 0.16.0's compiler/build_runner.zig argv handling.
// The generated build helper only sees the tokens that survive the parent
// process, so flags such as `--system <pkgdir>` must stay out of this table
// because the helper receives only the bare `--system` token.
fn buildInvocationArgRequiresNextValue(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "-p") or
        std.mem.eql(u8, arg, "--prefix") or
        std.mem.eql(u8, arg, "--prefix-lib-dir") or
        std.mem.eql(u8, arg, "--prefix-exe-dir") or
        std.mem.eql(u8, arg, "--prefix-include-dir") or
        std.mem.eql(u8, arg, "--color") or
        std.mem.eql(u8, arg, "--error-style") or
        std.mem.eql(u8, arg, "--multiline-errors") or
        std.mem.eql(u8, arg, "--summary") or
        std.mem.eql(u8, arg, "--maxrss") or
        std.mem.eql(u8, arg, "--libc-runtimes") or
        std.mem.eql(u8, arg, "--glibc-runtimes") or
        std.mem.eql(u8, arg, "--debounce") or
        std.mem.eql(u8, arg, "--search-prefix") or
        std.mem.eql(u8, arg, "--sysroot") or
        std.mem.eql(u8, arg, "--libc") or
        std.mem.eql(u8, arg, "--build-file") or
        std.mem.eql(u8, arg, "--cache-dir") or
        std.mem.eql(u8, arg, "--global-cache-dir") or
        std.mem.eql(u8, arg, "--zig-lib-dir") or
        std.mem.eql(u8, arg, "--build-runner") or
        std.mem.eql(u8, arg, "--seed") or
        std.mem.eql(u8, arg, "--test-timeout") or
        std.mem.eql(u8, arg, "--debug-log");
}

fn buildInvocationArgOptionallyConsumesNextValue(arg: []const u8, next_arg: []const u8) bool {
    if (std.mem.eql(u8, arg, "--release")) {
        return std.mem.eql(u8, next_arg, "fast") or
            std.mem.eql(u8, next_arg, "safe") or
            std.mem.eql(u8, next_arg, "small");
    }
    if (std.mem.eql(u8, arg, "--fetch")) {
        return std.mem.eql(u8, next_arg, "needed") or
            std.mem.eql(u8, next_arg, "all");
    }
    if (std.mem.eql(u8, arg, "--webui")) {
        return next_arg.len != 0 and
            next_arg[0] != '-' and
            (std.mem.findScalar(u8, next_arg, '.') != null or
                std.mem.findScalar(u8, next_arg, ':') != null);
    }
    return false;
}

fn buildInvocationRequestsStepInArgs(args: []const []const u8, step_name: []const u8) bool {
    var index: usize = @min(args.len, 6);
    while (index < args.len) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--")) break;
        if (arg.len == 0) {
            index += 1;
            continue;
        }
        if (buildInvocationArgRequiresNextValue(arg)) {
            index += @min(@as(usize, 2), args.len - index);
            continue;
        }
        if (index + 1 < args.len and buildInvocationArgOptionallyConsumesNextValue(arg, args[index + 1])) {
            index += @min(@as(usize, 2), args.len - index);
            continue;
        }
        if (arg[0] == '-') {
            index += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, step_name)) return true;
        index += 1;
    }
    return false;
}

fn buildInvocationRequestsOnlyStepInArgs(args: []const []const u8, step_name: []const u8) bool {
    var index: usize = @min(args.len, 6);
    var saw_step = false;
    while (index < args.len) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--")) break;
        if (arg.len == 0) {
            index += 1;
            continue;
        }
        if (buildInvocationArgRequiresNextValue(arg)) {
            index += @min(@as(usize, 2), args.len - index);
            continue;
        }
        if (index + 1 < args.len and buildInvocationArgOptionallyConsumesNextValue(arg, args[index + 1])) {
            index += @min(@as(usize, 2), args.len - index);
            continue;
        }
        if (arg[0] == '-') {
            index += 1;
            continue;
        }
        if (!std.mem.eql(u8, arg, step_name)) return false;
        saw_step = true;
        index += 1;
    }
    return saw_step;
}

fn buildInvocationSkipsStepExecutionInArgs(args: []const []const u8) bool {
    var index: usize = @min(args.len, 6);
    while (index < args.len) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--")) break;
        if (arg.len == 0) {
            index += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "-h") or
            std.mem.eql(u8, arg, "--help") or
            std.mem.eql(u8, arg, "-l") or
            std.mem.eql(u8, arg, "--list-steps") or
            std.mem.eql(u8, arg, "--fetch") or
            std.mem.startsWith(u8, arg, "--fetch="))
        {
            return true;
        }
        if (buildInvocationArgRequiresNextValue(arg)) {
            index += @min(@as(usize, 2), args.len - index);
            continue;
        }
        if (index + 1 < args.len and buildInvocationArgOptionallyConsumesNextValue(arg, args[index + 1])) {
            index += @min(@as(usize, 2), args.len - index);
            continue;
        }
        index += 1;
    }
    return false;
}

fn buildInvocationRequestsRunnableStepInArgs(args: []const []const u8, step_name: []const u8) bool {
    return !buildInvocationSkipsStepExecutionInArgs(args) and
        buildInvocationRequestsStepInArgs(args, step_name);
}

fn buildInvocationRequestsRunnableStep(step_name: []const u8) ?bool {
    return buildInvocationRequestsRunnableStepFromArgsResult(step_name, buildInvocationArgsAlloc());
}

fn buildInvocationSkipsStepExecution() ?bool {
    return buildInvocationSkipsStepExecutionFromArgsResult(buildInvocationArgsAlloc());
}

fn unsupportedSharedTailForNoTailStep(
    shared_tail_args: ?[]const []const u8,
    step_requested: ?bool,
    tail_owner_requested: ?bool,
) bool {
    const args = shared_tail_args orelse return false;
    if (args.len == 0) return false;
    if (tail_owner_requested orelse false) return false;
    return step_requested orelse false;
}

fn rejectUnsupportedSharedTailForNoTailStep(
    b: *std.Build,
    step_requested: ?bool,
    tail_owner_requested: ?bool,
    step_name: []const u8,
) void {
    if (!unsupportedSharedTailForNoTailStep(b.args, step_requested, tail_owner_requested)) return;
    std.process.fatal("`zig build {s}` does not accept post-`--` arguments; remove the shared tail or use a step with documented tail options", .{step_name});
}

fn buildInvocationSharedTailOwnerRequested(step_requests: []const ?bool) ?bool {
    var unknown_request = false;
    for (step_requests) |step_requested| {
        if (step_requested orelse false) return true;
        if (step_requested == null) unknown_request = true;
    }
    if (unknown_request) return null;
    return false;
}

fn hostBuildInvocationArgsSupported() bool {
    return switch (builtin.os.tag) {
        .macos, .ios, .tvos, .watchos, .visionos, .linux, .windows => true,
        else => false,
    };
}

fn compatIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

fn childProcessIo() std.Io {
    return if (builtin.is_test) std.testing.io else compatIo();
}

const PackageManifest = struct {
    version: []const u8,
};

fn packageVersionAlloc(b: *std.Build) []const u8 {
    const bytes = std.Io.Dir.cwd().readFileAlloc(
        compatIo(),
        b.pathFromRoot("build.zig.zon"),
        b.allocator,
        .limited(1 << 20),
    ) catch |err| std.process.fatal("unable to read build.zig.zon for package version: {s}", .{@errorName(err)});
    defer b.allocator.free(bytes);

    const source_z = b.allocator.dupeSentinel(u8, bytes, 0) catch
        std.process.fatal("unable to prepare build.zig.zon for package version parsing", .{});
    defer b.allocator.free(source_z);

    const manifest = std.zon.parse.fromSliceAlloc(
        PackageManifest,
        b.allocator,
        source_z,
        null,
        .{ .ignore_unknown_fields = true },
    ) catch |err| std.process.fatal("unable to parse build.zig.zon package version: {s}", .{@errorName(err)});
    return manifest.version;
}

fn findTestSuiteIndex(id: []const u8, specs: []const TestSuiteSpec) ?usize {
    for (specs, 0..) |spec, index| {
        if (std.mem.eql(u8, spec.suite_id, id)) return index;
    }
    return null;
}

fn parseTestSuiteSelectionAlloc(
    allocator: std.mem.Allocator,
    raw: ?[]const u8,
    specs: []const TestSuiteSpec,
) !TestSuiteSelectionResult {
    const enabled = try allocator.alloc(bool, specs.len);
    errdefer allocator.free(enabled);

    if (raw == null) {
        for (specs, 0..) |spec, index| {
            enabled[index] = spec.default_enabled;
        }
        return .{ .selection = .{
            .allocator = allocator,
            .enabled = enabled,
        } };
    }

    @memset(enabled, false);
    var iter = std.mem.splitScalar(u8, raw.?, ',');
    while (iter.next()) |item| {
        const token = std.mem.trim(u8, item, " \t\r\n");
        if (token.len == 0) {
            allocator.free(enabled);
            return .empty_token;
        }
        const index = findTestSuiteIndex(token, specs) orelse {
            allocator.free(enabled);
            return .{ .unknown = token };
        };
        if (enabled[index]) {
            allocator.free(enabled);
            return .{ .duplicate = specs[index].suite_id };
        }
        enabled[index] = true;
    }

    return .{ .selection = .{
        .allocator = allocator,
        .enabled = enabled,
    } };
}

fn testSuiteIdListAlloc(allocator: std.mem.Allocator, specs: []const TestSuiteSpec) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    for (specs) |spec| {
        try out.appendSlice(allocator, "\n  - ");
        try out.appendSlice(allocator, spec.suite_id);
    }

    return try out.toOwnedSlice(allocator);
}

fn parseRequestedTestSuiteSelectionAlloc(
    allocator: std.mem.Allocator,
    raw: ?[]const u8,
    specs: []const TestSuiteSpec,
    test_requested: bool,
) !TestSuiteSelectionResult {
    _ = test_requested;
    return parseTestSuiteSelectionAlloc(allocator, raw, specs);
}

fn testSuiteSelectionRawForValidation(
    raw: ?[]const u8,
    test_requested: bool,
    skip_execution: bool,
) ?[]const u8 {
    if (!test_requested and skip_execution) return null;
    return raw;
}

fn resolveTestSuiteSelection(
    b: *std.Build,
    raw: ?[]const u8,
    specs: []const TestSuiteSpec,
    test_requested: bool,
    skip_execution: bool,
) ?TestSuiteSelection {
    const selection_result = parseRequestedTestSuiteSelectionAlloc(
        b.allocator,
        testSuiteSelectionRawForValidation(raw, test_requested, skip_execution),
        specs,
        test_requested,
    ) catch |err|
        std.process.fatal("unable to parse -Dtest-suites: {s}", .{@errorName(err)});

    if (!test_requested and raw != null and !skip_execution) {
        switch (selection_result) {
            .selection => |selection| selection.deinit(),
            else => {},
        }
        std.log.err(
            "`-Dtest-suites` only applies to `zig build test`; use `zig build test -Dtest-suites=<ids>`.",
            .{},
        );
        b.invalid_user_input = true;
        return null;
    }

    if (!test_requested) {
        return switch (selection_result) {
            .selection => |selection| selection,
            else => unreachable,
        };
    }

    switch (selection_result) {
        .selection => |selection| return selection,
        .empty_token => {
            const supported = testSuiteIdListAlloc(b.allocator, specs) catch |err|
                std.process.fatal("unable to list supported test suite ids: {s}", .{@errorName(err)});
            std.log.err(
                "Expected -Dtest-suites to be a comma-separated list of exact suite ids without empty entries. Supported ids:{s}",
                .{supported},
            );
        },
        .duplicate => |id| {
            const supported = testSuiteIdListAlloc(b.allocator, specs) catch |err|
                std.process.fatal("unable to list supported test suite ids: {s}", .{@errorName(err)});
            std.log.err(
                "Duplicate test suite id in -Dtest-suites: '{s}'. Supported ids:{s}",
                .{ id, supported },
            );
        },
        .unknown => |id| {
            const supported = testSuiteIdListAlloc(b.allocator, specs) catch |err|
                std.process.fatal("unable to list supported test suite ids: {s}", .{@errorName(err)});
            std.log.err(
                "Unknown test suite id in -Dtest-suites: '{s}'. Supported ids:{s}",
                .{ id, supported },
            );
        },
    }
    b.invalid_user_input = true;
    return null;
}

fn addSelectedTestSuites(
    test_step: *std.Build.Step,
    specs: []const TestSuiteSpec,
    selection: TestSuiteSelection,
) void {
    for (specs, 0..) |spec, index| {
        if (!selection.isEnabled(index)) continue;
        test_step.dependOn(spec.run_step.?);
    }
}

fn testRunnerArgCanPassThrough(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "--listen=-") or
        std.mem.startsWith(u8, arg, "--cache-dir=");
}

fn testRunnerArgRequiresValue(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "--seed") or
        std.mem.eql(u8, arg, "--cache-dir");
}

fn testRunnerBuildOnlyArgCanPassThrough(arg: []const u8) bool {
    return std.mem.startsWith(u8, arg, "--test-timeout=");
}

fn testRunnerBuildOnlyArgRequiresValue(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "--test-timeout");
}

fn testRunnerAttachedSeedValue(arg: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, arg, "--seed=")) return null;
    return arg["--seed=".len..];
}

fn testRunnerSeedValueIsValid(value: []const u8) bool {
    _ = std.fmt.parseUnsigned(u32, value, 0) catch return false;
    return true;
}

fn testRunnerValueStartsNewArg(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "--test-filter") or
        std.mem.startsWith(u8, arg, "--test-filter=") or
        std.mem.eql(u8, arg, "--seed") or
        std.mem.startsWith(u8, arg, "--seed=") or
        std.mem.eql(u8, arg, "--test-timeout") or
        std.mem.startsWith(u8, arg, "--test-timeout=") or
        std.mem.eql(u8, arg, "--cache-dir") or
        std.mem.startsWith(u8, arg, "--cache-dir=") or
        std.mem.startsWith(u8, arg, "--");
}

fn parseTestRunnerArgsAlloc(
    allocator: std.mem.Allocator,
    args: ?[]const []const u8,
    mode: TestRunnerArgParseMode,
) !TestRunnerArgParseResult {
    const raw_args = args orelse &.{};
    var filter_count: usize = 0;
    var passthrough_count: usize = 0;
    var owned_passthrough_count: usize = 0;
    var index: usize = 0;
    while (index < raw_args.len) {
        const arg = raw_args[index];
        if (std.mem.eql(u8, arg, "--test-filter")) {
            if (index + 1 >= raw_args.len) return .missing_pattern;
            if (raw_args[index + 1].len == 0) return .empty_pattern;
            if (testRunnerValueStartsNewArg(raw_args[index + 1])) return .missing_pattern;
            filter_count += 1;
            index += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--test-filter=")) {
            if (arg["--test-filter=".len..].len == 0) return .empty_pattern;
            filter_count += 1;
            index += 1;
            continue;
        }
        if (testRunnerAttachedSeedValue(arg)) |seed_value| {
            if (!testRunnerSeedValueIsValid(seed_value)) return .{ .invalid_seed_value = seed_value };
            passthrough_count += 1;
            index += 1;
            continue;
        }
        if (testRunnerBuildOnlyArgCanPassThrough(arg)) {
            index += 1;
            continue;
        }
        if (testRunnerArgCanPassThrough(arg)) {
            passthrough_count += 1;
            index += 1;
            continue;
        }
        if (testRunnerBuildOnlyArgRequiresValue(arg)) {
            if (index + 1 >= raw_args.len or testRunnerValueStartsNewArg(raw_args[index + 1])) {
                return .{ .missing_passthrough_value = arg };
            }
            index += 2;
            continue;
        }
        if (testRunnerArgRequiresValue(arg)) {
            if (index + 1 >= raw_args.len or testRunnerValueStartsNewArg(raw_args[index + 1])) {
                return .{ .missing_passthrough_value = arg };
            }
            if (std.mem.eql(u8, arg, "--seed") and !testRunnerSeedValueIsValid(raw_args[index + 1])) {
                return .{ .invalid_seed_value = raw_args[index + 1] };
            }
            passthrough_count += 1;
            owned_passthrough_count += 1;
            index += 2;
            continue;
        }
        if (mode == .allow_unknown_args) {
            index += 1;
            continue;
        }
        return .{ .unknown_arg = arg };
    }

    const filters = try allocator.alloc([]const u8, filter_count);
    errdefer allocator.free(filters);
    const passthrough = try allocator.alloc([]const u8, passthrough_count);
    errdefer allocator.free(passthrough);
    const owned_passthrough = try allocator.alloc([]const u8, owned_passthrough_count);
    var owned_passthrough_allocated: usize = 0;
    errdefer {
        for (owned_passthrough[0..owned_passthrough_allocated]) |arg| allocator.free(arg);
        allocator.free(owned_passthrough);
    }
    index = 0;
    var filter_index: usize = 0;
    var passthrough_index: usize = 0;
    var owned_passthrough_index: usize = 0;
    while (index < raw_args.len) {
        const arg = raw_args[index];
        if (std.mem.eql(u8, arg, "--test-filter")) {
            filters[filter_index] = raw_args[index + 1];
            filter_index += 1;
            index += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--test-filter=")) {
            filters[filter_index] = arg["--test-filter=".len..];
            filter_index += 1;
            index += 1;
            continue;
        }
        if (testRunnerAttachedSeedValue(arg) != null) {
            passthrough[passthrough_index] = arg;
            passthrough_index += 1;
            index += 1;
            continue;
        }
        if (testRunnerBuildOnlyArgCanPassThrough(arg)) {
            index += 1;
            continue;
        }
        if (testRunnerArgCanPassThrough(arg)) {
            passthrough[passthrough_index] = arg;
            passthrough_index += 1;
            index += 1;
            continue;
        }
        if (testRunnerBuildOnlyArgRequiresValue(arg) and index + 1 < raw_args.len and !testRunnerValueStartsNewArg(raw_args[index + 1])) {
            index += 2;
            continue;
        }
        if (testRunnerArgRequiresValue(arg) and index + 1 < raw_args.len and !testRunnerValueStartsNewArg(raw_args[index + 1])) {
            const normalized_arg = try std.fmt.allocPrint(allocator, "{s}={s}", .{ arg, raw_args[index + 1] });
            owned_passthrough[owned_passthrough_index] = normalized_arg;
            owned_passthrough_index += 1;
            owned_passthrough_allocated += 1;
            passthrough[passthrough_index] = normalized_arg;
            passthrough_index += 1;
            index += 2;
            continue;
        }
        index += 1;
    }

    return .{ .args = .{
        .filters = .{
            .allocator = allocator,
            .items = filters,
        },
        .passthrough = .{
            .allocator = allocator,
            .items = passthrough,
        },
        .owned_passthrough = .{
            .allocator = allocator,
            .items = owned_passthrough,
        },
    } };
}

fn recognizedTestRunnerArgSpan(args: []const []const u8, index: usize) ?usize {
    const arg = args[index];
    if (std.mem.eql(u8, arg, "--test-filter")) {
        if (index + 1 >= args.len) return null;
        if (args[index + 1].len == 0) return null;
        if (testRunnerValueStartsNewArg(args[index + 1])) return null;
        return 2;
    }
    if (std.mem.startsWith(u8, arg, "--test-filter=")) {
        if (arg["--test-filter=".len..].len == 0) return null;
        return 1;
    }
    if (testRunnerAttachedSeedValue(arg)) |seed_value| {
        if (!testRunnerSeedValueIsValid(seed_value)) return null;
        return 1;
    }
    if (testRunnerBuildOnlyArgCanPassThrough(arg)) return 1;
    if (testRunnerArgCanPassThrough(arg)) return 1;
    if (testRunnerBuildOnlyArgRequiresValue(arg)) {
        if (index + 1 >= args.len or testRunnerValueStartsNewArg(args[index + 1])) return null;
        return 2;
    }
    if (testRunnerArgRequiresValue(arg)) {
        if (index + 1 >= args.len or testRunnerValueStartsNewArg(args[index + 1])) return null;
        if (std.mem.eql(u8, arg, "--seed") and !testRunnerSeedValueIsValid(args[index + 1])) return null;
        return 2;
    }
    return null;
}

fn lintSharedTailArgsAlloc(
    allocator: std.mem.Allocator,
    args: ?[]const []const u8,
    strip_test_runner_args: bool,
) ![]const []const u8 {
    const raw_args = args orelse &.{};
    if (!strip_test_runner_args) return allocator.dupe([]const u8, raw_args);

    var filtered_count: usize = 0;
    var index: usize = 0;
    while (index < raw_args.len) {
        if (recognizedTestRunnerArgSpan(raw_args, index)) |span| {
            index += span;
            continue;
        }
        filtered_count += 1;
        index += 1;
    }

    const filtered_args = try allocator.alloc([]const u8, filtered_count);
    index = 0;
    var filtered_index: usize = 0;
    while (index < raw_args.len) {
        if (recognizedTestRunnerArgSpan(raw_args, index)) |span| {
            index += span;
            continue;
        }
        filtered_args[filtered_index] = raw_args[index];
        filtered_index += 1;
        index += 1;
    }
    return filtered_args;
}

fn recognizedLintArgSpan(args: []const []const u8, index: usize) ?usize {
    const arg = args[index];
    if (std.mem.startsWith(u8, arg, "--max-warnings=")) return 1;
    if (std.mem.eql(u8, arg, "--max-warnings")) {
        if (index + 1 >= args.len) return 1;
        if (std.mem.startsWith(u8, args[index + 1], "--")) return 1;
        return 2;
    }
    return null;
}

fn fixtureGeneratorSharedTailArgsAlloc(
    allocator: std.mem.Allocator,
    args: ?[]const []const u8,
    strip_test_runner_args: bool,
    strip_lint_args: bool,
) ![]const []const u8 {
    const raw_args = args orelse &.{};

    var filtered_args = std.ArrayList([]const u8).empty;
    errdefer filtered_args.deinit(allocator);

    var index: usize = 0;
    while (index < raw_args.len) {
        if (strip_test_runner_args) {
            if (recognizedTestRunnerArgSpan(raw_args, index)) |span| {
                index += span;
                continue;
            }
        }
        if (strip_lint_args) {
            if (recognizedLintArgSpan(raw_args, index)) |span| {
                index += span;
                continue;
            }
        }
        try filtered_args.append(allocator, raw_args[index]);
        index += 1;
    }
    return filtered_args.toOwnedSlice(allocator);
}

fn requireTestRunnerArgs(
    b: *std.Build,
    args: ?[]const []const u8,
    test_requested: bool,
    allow_unknown_args: bool,
) ?TestRunnerArgs {
    if (!test_requested) {
        return emptyTestRunnerArgs(b.allocator) catch |err|
            std.process.fatal("unable to initialize empty test runner args: {s}", .{@errorName(err)});
    }
    const parse_result = parseTestRunnerArgsAlloc(b.allocator, args, if (test_requested and allow_unknown_args) .allow_unknown_args else .strict) catch |err|
        std.process.fatal("unable to parse test runner args: {s}", .{@errorName(err)});

    switch (parse_result) {
        .args => |test_runner_args| return test_runner_args,
        .missing_pattern => std.log.err(
            "Expected a pattern after '--test-filter' in `zig build test -- ...`.",
            .{},
        ),
        .empty_pattern => std.log.err(
            "Expected '--test-filter' to contain a non-empty pattern in `zig build test -- ...`.",
            .{},
        ),
        .invalid_seed_value => |value| std.log.err(
            "Expected '--seed' to contain an unsigned 32-bit integer in `zig build test -- ...`; got '{s}'.",
            .{value},
        ),
        .missing_passthrough_value => |arg| std.log.err(
            "Expected a value after '{s}' in `zig build test -- ...`.",
            .{arg},
        ),
        .unknown_arg => |arg| std.log.err(
            "Unsupported `zig build test --` argument: '{s}'. Supported forms are '--test-filter[=pattern]', '--listen=-', '--seed[=value]', '--cache-dir[=path]', and the build-only '--test-timeout[=value]'.",
            .{arg},
        ),
    }
    b.invalid_user_input = true;
    return null;
}

fn addFilteredTest(
    b: *std.Build,
    root_module: *std.Build.Module,
    filters: []const []const u8,
) *std.Build.Step.Compile {
    return b.addTest(.{
        .root_module = root_module,
        .filters = filters,
    });
}

fn testFilterCouldMatchSuiteDefault(user_filter: []const u8, default_filter: []const u8) bool {
    return std.mem.find(u8, default_filter, user_filter) != null or
        std.mem.find(u8, user_filter, default_filter) != null;
}

fn defaultSuiteFiltersForUserFiltersAlloc(
    allocator: std.mem.Allocator,
    user_filters: []const []const u8,
    default_filters: []const []const u8,
    no_match_filters: []const []const u8,
) ![]const []const u8 {
    if (user_filters.len == 0) return try allocator.dupe([]const u8, default_filters);

    var match_count: usize = 0;
    for (default_filters) |default_filter| {
        for (user_filters) |user_filter| {
            if (testFilterCouldMatchSuiteDefault(user_filter, default_filter)) {
                match_count += 1;
                break;
            }
        }
    }
    if (match_count == 0) return try allocator.dupe([]const u8, no_match_filters);

    const selected = try allocator.alloc([]const u8, match_count);
    var selected_index: usize = 0;
    for (default_filters) |default_filter| {
        for (user_filters) |user_filter| {
            if (testFilterCouldMatchSuiteDefault(user_filter, default_filter)) {
                selected[selected_index] = default_filter;
                selected_index += 1;
                break;
            }
        }
    }
    return selected;
}

fn addRunArtifactWithArgs(
    b: *std.Build,
    artifact: *std.Build.Step.Compile,
    args: []const []const u8,
) *std.Build.Step.Run {
    const run_step = b.addRunArtifact(artifact);
    if (args.len != 0) run_step.addArgs(args);
    return run_step;
}

fn absolutizeGraphDirPath(b: *std.Build, maybe_path: ?[]const u8) ?[]const u8 {
    const path = maybe_path orelse return null;
    if (std.Io.Dir.path.isAbsolute(path)) return path;
    const cwd = std.process.currentPathAlloc(b.graph.io, b.allocator) catch |err|
        std.process.fatal("failed to resolve build cwd for graph path '{s}': {s}", .{ path, @errorName(err) });
    return std.Io.Dir.path.resolve(b.allocator, &.{ cwd, path }) catch |err|
        std.process.fatal("failed to resolve build graph path '{s}': {s}", .{ path, @errorName(err) });
}

fn absolutizeZlinterRuntimePaths(b: *std.Build) void {
    b.graph.global_cache_root.path = absolutizeGraphDirPath(b, b.graph.global_cache_root.path);
    b.graph.zig_lib_directory.path = absolutizeGraphDirPath(b, b.graph.zig_lib_directory.path);
}

fn tempRootPath(b: *std.Build) []const u8 {
    const env_names = switch (builtin.os.tag) {
        .windows => &[_][]const u8{ "TMP", "TEMP" },
        else => &[_][]const u8{ "TMPDIR", "TMP", "TEMP" },
    };
    for (env_names) |name| {
        const value = b.graph.environ_map.get(name) orelse continue;
        if (value.len != 0) return value;
    }
    return switch (builtin.os.tag) {
        .windows => "C:\\Temp",
        else => "/tmp",
    };
}

fn createShiftConsumerModule(
    b: *std.Build,
    path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    deps: ShiftConsumerDeps,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = lazyPathForSourceFile(b, path),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("ability", deps.ability_mod);
    if (deps.ability_compile_mod) |ability_compile_mod| mod.addImport("ability_compile", ability_compile_mod);
    if (deps.ability_agent_vm_mod) |ability_agent_vm_mod| mod.addImport("ability_agent_vm", ability_agent_vm_mod);
    if (deps.lowered_runtime_mod) |runtime_mod| mod.addImport("private_lowered_runtime", runtime_mod);
    return mod;
}

fn createPlainModule(
    b: *std.Build,
    path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = lazyPathForSourceFile(b, path),
        .target = target,
        .optimize = optimize,
    });
}

fn lazyPathForSourceFile(b: *std.Build, path: []const u8) std.Build.LazyPath {
    if (std.Io.Dir.path.isAbsolute(path)) return .{ .cwd_relative = path };
    return b.path(path);
}

fn canonicalSourceHash(b: *std.Build, path: []const u8) [32]u8 {
    const bytes = std.Io.Dir.cwd().readFileAlloc(b.graph.io, b.pathFromRoot(path), b.allocator, .limited(1 << 20)) catch |err| switch (err) {
        // Archive/registry package paths intentionally exclude proof-only corpora.
        error.FileNotFound => return std.mem.zeroes([32]u8),
        else => std.process.fatal("unable to read canonical source-lowering source", .{}),
    };
    defer b.allocator.free(bytes);

    const normalized = normalizeSourceForHashAlloc(b.allocator, bytes) catch
        std.process.fatal("unable to normalize canonical source-lowering source", .{});
    defer b.allocator.free(normalized);

    var digest = std.mem.zeroes([32]u8);
    std.crypto.hash.Blake3.hash(normalized, &digest, .{});
    return digest;
}

fn hashBuildIdentityU64(hasher: *std.crypto.hash.Blake3, value: u64) void {
    var buffer: [8]u8 = undefined;
    std.mem.writeInt(u64, &buffer, value, .little);
    hasher.update(&buffer);
}

fn hashBuildIdentityField(
    hasher: *std.crypto.hash.Blake3,
    label: []const u8,
    value: []const u8,
) void {
    hasher.update(label);
    hashBuildIdentityU64(hasher, @as(u64, @intCast(value.len)));
    hasher.update(value);
}

fn pathExistsAtRoot(root_dir: std.Io.Dir, io: std.Io, path: []const u8) bool {
    const file = root_dir.openFile(io, path, .{}) catch return false;
    file.close(io);
    return true;
}

fn repoRootContainsGitMetadata(root_dir: std.Io.Dir, io: std.Io) bool {
    if (pathExistsAtRoot(root_dir, io, ".git")) return true;
    var git_dir = root_dir.openDir(io, ".git", .{}) catch return false;
    git_dir.close(io);
    return true;
}

fn hashBuildIdentityFileAtRoot(
    hasher: *std.crypto.hash.Blake3,
    repo_root: []const u8,
    path: []const u8,
) void {
    const io = childProcessIo();
    var root_dir = std.Io.Dir.openDirAbsolute(io, repo_root, .{}) catch |err|
        std.process.fatal("unable to open build identity root '{s}': {s}", .{ repo_root, @errorName(err) });
    defer root_dir.close(io);

    var file = root_dir.openFile(io, path, .{}) catch |err|
        std.process.fatal("unable to open build identity file '{s}': {s}", .{ path, @errorName(err) });
    defer file.close(io);

    const stat = file.stat(io) catch |err|
        std.process.fatal("unable to stat build identity file '{s}': {s}", .{ path, @errorName(err) });

    hashBuildIdentityField(hasher, "build-input-path", path);
    hasher.update("build-input-bytes");
    hashBuildIdentityU64(hasher, stat.size);

    var chunk = std.mem.zeroes([16 * 1024]u8);
    var reader = file.reader(io, &.{});
    while (true) {
        const read_len = reader.interface.readSliceShort(&chunk) catch |err| switch (err) {
            error.ReadFailed => std.process.fatal("unable to read build identity file '{s}': {s}", .{ path, @errorName(reader.err.?) }),
        };
        if (read_len == 0) break;
        hasher.update(chunk[0..read_len]);
    }
}

fn appendOwnedPathIfMissing(
    allocator: std.mem.Allocator,
    paths: *std.ArrayList([]const u8),
    path_set: *std.StringHashMap(void),
    path: []const u8,
) !void {
    const owned = try allocator.dupe(u8, path);
    errdefer allocator.free(owned);

    const gop = try path_set.getOrPut(owned);
    if (gop.found_existing) return allocator.free(owned);
    try paths.append(allocator, owned);
}

fn sortOwnedPaths(paths: [][]const u8) void {
    std.mem.sort([]const u8, paths, {}, struct {
        fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lessThan);
}

fn freeOwnedPathList(allocator: std.mem.Allocator, paths: []const []const u8) void {
    for (paths) |path| allocator.free(path);
    allocator.free(paths);
}

fn stringLiteralInner(literal: []const u8) ?[]const u8 {
    if (literal.len < 2) return null;
    if (literal[0] != '"' or literal[literal.len - 1] != '"') return null;
    return literal[1 .. literal.len - 1];
}

fn decodeStringLiteralAlloc(allocator: std.mem.Allocator, literal: []const u8) !?[]u8 {
    const inner = stringLiteralInner(literal) orelse return null;
    if (std.mem.findScalar(u8, inner, '\\') == null) {
        if (std.mem.findAny(u8, inner, "\"\n") != null) return null;
        return try allocator.dupe(u8, inner);
    }

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var index: usize = 0;
    while (index < inner.len) {
        switch (inner[index]) {
            '\\' => {
                const escape_char_index = index + 1;
                const parsed = std.zig.string_literal.parseEscapeSequence(inner, &index);
                const codepoint = switch (parsed) {
                    .success => |value| value,
                    .failure => return null,
                };
                if (escape_char_index >= inner.len) return null;
                if (inner[escape_char_index] == 'u') {
                    var utf8_buffer: [4]u8 = undefined;
                    const utf8_len = std.unicode.utf8Encode(codepoint, &utf8_buffer) catch return null;
                    try out.appendSlice(allocator, utf8_buffer[0..utf8_len]);
                } else {
                    try out.append(allocator, @as(u8, @intCast(codepoint)));
                }
            },
            '"' => return null,
            '\n' => return null,
            else => {
                try out.append(allocator, inner[index]);
            },
        }
        index += 1;
    }

    return try out.toOwnedSlice(allocator);
}

const BuildInputToken = struct {
    tag: std.zig.Token.Tag,
    lexeme: []const u8,
};

const BuildInputTokenWindow = struct {
    items: [8]BuildInputToken = [_]BuildInputToken{.{
        .tag = .invalid,
        .lexeme = "",
    }} ** 8,
    count: usize = 0,

    fn push(self: *@This(), item: BuildInputToken) void {
        if (self.count < self.items.len) {
            self.items[self.count] = item;
            self.count += 1;
            return;
        }
        var index: usize = 1;
        while (index < self.items.len) : (index += 1) {
            self.items[index - 1] = self.items[index];
        }
        self.items[self.items.len - 1] = item;
    }
};

fn tokenSlice(source: [:0]const u8, token: anytype) []const u8 {
    return source[token.loc.start..token.loc.end];
}

fn maybeEmbedFileLiteralPath(window: *const BuildInputTokenWindow) ?[]const u8 {
    if (window.count < 4) return null;
    const tail = window.items[window.count - 4 .. window.count];
    if (!(tail[0].tag == .builtin and
        std.mem.eql(u8, tail[0].lexeme, "@embedFile") and
        tail[1].tag == .l_paren and
        tail[2].tag == .string_literal and
        tail[3].tag == .r_paren))
    {
        return null;
    }
    return tail[2].lexeme;
}

fn maybeEmbedFileIdentifierPath(window: *const BuildInputTokenWindow) ?[]const u8 {
    if (window.count < 4) return null;
    const tail = window.items[window.count - 4 .. window.count];
    if (!(tail[0].tag == .builtin and
        std.mem.eql(u8, tail[0].lexeme, "@embedFile") and
        tail[1].tag == .l_paren and
        tail[2].tag == .identifier and
        tail[3].tag == .r_paren))
    {
        return null;
    }
    return tail[2].lexeme;
}

fn maybeImportLiteralPath(window: *const BuildInputTokenWindow) ?[]const u8 {
    if (window.count < 4) return null;
    const tail = window.items[window.count - 4 .. window.count];
    if (!(tail[0].tag == .builtin and
        std.mem.eql(u8, tail[0].lexeme, "@import") and
        tail[1].tag == .l_paren and
        tail[2].tag == .string_literal and
        tail[3].tag == .r_paren))
    {
        return null;
    }
    return tail[2].lexeme;
}

fn windowMatchesEmbedFileSelf(window: *const BuildInputTokenWindow) bool {
    if (window.count < 8) return false;
    const tail = window.items[window.count - 8 .. window.count];
    return tail[0].tag == .builtin and
        std.mem.eql(u8, tail[0].lexeme, "@embedFile") and
        tail[1].tag == .l_paren and
        tail[2].tag == .builtin and
        std.mem.eql(u8, tail[2].lexeme, "@src") and
        tail[3].tag == .l_paren and
        tail[4].tag == .r_paren and
        tail[5].tag == .period and
        tail[6].tag == .identifier and
        std.mem.eql(u8, tail[6].lexeme, "file") and
        tail[7].tag == .r_paren;
}

fn tryRepoRelativePathFromAbsoluteAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    absolute_path: []const u8,
) !?[]u8 {
    if (!std.mem.startsWith(u8, absolute_path, repo_root)) return null;
    if (absolute_path.len == repo_root.len) return null;
    if (absolute_path[repo_root.len] != std.Io.Dir.path.sep) return null;
    return try allocator.dupe(u8, absolute_path[repo_root.len + 1 ..]);
}

const EmbedFileFunctionPattern = struct {
    fn_name: []const u8,
    path_param_indexes: []const usize,

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.fn_name);
        allocator.free(self.path_param_indexes);
        self.* = undefined;
    }
};

const ImportedEmbedFnPattern = struct {
    module_binding: []const u8,
    source_dir: []const u8,
    pattern: EmbedFileFunctionPattern,

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.module_binding);
        allocator.free(self.source_dir);
        self.pattern.deinit(allocator);
        self.* = undefined;
    }
};

const BuildModuleBinding = struct {
    alias: []const u8,
    repo_relative_source_path: []const u8,

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.alias);
        allocator.free(self.repo_relative_source_path);
        self.* = undefined;
    }
};

const BuildInputPathCollector = struct {
    paths: *std.ArrayList([]const u8),
    path_set: *std.StringHashMap(void),
};

const BuildInputSourceScan = struct {
    repo_root: []const u8,
    source_path: []const u8,
    source: [:0]const u8,
    tokens: []const BuildInputToken,
    collector: BuildInputPathCollector,
    top_bindings: *const std.StringHashMap([]const u8),
};

const TopLevelStringDeclaration = struct {
    name: []const u8,
    value_tokens: []const BuildInputToken,
};

fn resolveStringTokensFromBindingMapAlloc(
    allocator: std.mem.Allocator,
    tokens: []const BuildInputToken,
    bindings: *const std.StringHashMap([]const u8),
) !?[]u8 {
    if (tokens.len != 1) return null;
    const tag = tokens[0].tag;
    if (tag == .string_literal) {
        return try decodeStringLiteralAlloc(allocator, tokens[0].lexeme);
    }
    if (tag == .identifier) {
        if (bindings.get(tokens[0].lexeme)) |bound| {
            return try allocator.dupe(u8, bound);
        }
        return null;
    }
    return null;
}

fn collectTopLevelStringDeclarationsAlloc(
    allocator: std.mem.Allocator,
    tokens: []const BuildInputToken,
) ![]const TopLevelStringDeclaration {
    var declarations = std.ArrayList(TopLevelStringDeclaration).empty;
    errdefer declarations.deinit(allocator);

    var index: usize = 0;
    var scope_depth: usize = 0;
    while (index + 1 < tokens.len) {
        const tag = tokens[index].tag;
        if (tag == .l_brace) {
            scope_depth += 1;
            index += 1;
            continue;
        }
        if (tag == .r_brace) {
            if (scope_depth > 0) scope_depth -= 1;
            index += 1;
            continue;
        }

        if (scope_depth != 0 or tokens[index].tag != .keyword_const or tokens[index + 1].tag != .identifier) {
            index += 1;
            continue;
        }

        var cursor = index + 2;
        var depth: usize = 0;
        var equal_index: ?usize = null;
        var semicolon_index: ?usize = null;
        while (cursor < tokens.len) : (cursor += 1) {
            const cursor_tag = tokens[cursor].tag;
            if (cursor_tag == .l_paren or cursor_tag == .l_brace or cursor_tag == .l_bracket) {
                depth += 1;
            } else if (cursor_tag == .r_paren or cursor_tag == .r_brace or cursor_tag == .r_bracket) {
                if (depth > 0) depth -= 1;
            } else if (cursor_tag == .equal) {
                if (depth == 0 and equal_index == null) equal_index = cursor;
            } else if (cursor_tag == .semicolon and depth == 0) {
                semicolon_index = cursor;
                break;
            }
        }

        const value_start = equal_index orelse {
            index += 1;
            continue;
        };
        const value_end = semicolon_index orelse {
            index += 1;
            continue;
        };
        try declarations.append(allocator, .{
            .name = tokens[index + 1].lexeme,
            .value_tokens = tokens[value_start + 1 .. value_end],
        });
        index = value_end + 1;
    }

    return declarations.toOwnedSlice(allocator);
}

fn populateTopLevelSimpleStringBindings(
    allocator: std.mem.Allocator,
    tokens: []const BuildInputToken,
    top_bindings: *std.StringHashMap([]const u8),
) !void {
    const declarations = try collectTopLevelStringDeclarationsAlloc(allocator, tokens);
    defer allocator.free(declarations);

    while (true) {
        var made_progress = false;
        declaration_loop: for (declarations) |declaration| {
            if (top_bindings.contains(declaration.name)) continue :declaration_loop;
            const value = try resolveStringTokensFromBindingMapAlloc(
                allocator,
                declaration.value_tokens,
                top_bindings,
            ) orelse continue :declaration_loop;
            errdefer allocator.free(value);
            try top_bindings.put(declaration.name, value);
            made_progress = true;
        }
        if (!made_progress) break;
    }
}

fn lookupVisibleStringBinding(
    scopes: []const std.StringHashMap([]const u8),
    top_bindings: *const std.StringHashMap([]const u8),
    identifier: []const u8,
) ?[]const u8 {
    var index = scopes.len;
    while (index > 0) {
        index -= 1;
        if (scopes[index].get(identifier)) |value| return value;
    }
    return top_bindings.get(identifier);
}

fn resolveStringTokensFromVisibleBindingsAlloc(
    allocator: std.mem.Allocator,
    tokens: []const BuildInputToken,
    scopes: []const std.StringHashMap([]const u8),
    top_bindings: *const std.StringHashMap([]const u8),
) !?[]u8 {
    if (tokens.len != 1) return null;
    const tag = tokens[0].tag;
    if (tag == .string_literal) {
        return try decodeStringLiteralAlloc(allocator, tokens[0].lexeme);
    }
    if (tag == .identifier) {
        if (lookupVisibleStringBinding(scopes, top_bindings, tokens[0].lexeme)) |bound| {
            return try allocator.dupe(u8, bound);
        }
        return null;
    }
    return null;
}

fn setScopeBinding(
    allocator: std.mem.Allocator,
    scope: *std.StringHashMap([]const u8),
    identifier: []const u8,
    value: []const u8,
) !void {
    const gop = try scope.getOrPut(identifier);
    if (gop.found_existing) allocator.free(gop.value_ptr.*);
    gop.value_ptr.* = value;
}

fn resolveVisibleStringBindingAlloc(
    allocator: std.mem.Allocator,
    tokens: []const BuildInputToken,
    use_index: usize,
    identifier: []const u8,
    top_bindings: *const std.StringHashMap([]const u8),
) !?[]u8 {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    errdefer scratch.deinit();
    defer scratch.deinit();
    const scratch_allocator = scratch.allocator();

    var scopes = std.ArrayList(std.StringHashMap([]const u8)).empty;
    errdefer scopes.deinit(scratch_allocator);
    try scopes.append(scratch_allocator, std.StringHashMap([]const u8).init(scratch_allocator));
    defer scopes.deinit(scratch_allocator);

    var index: usize = 0;
    while (index < use_index) {
        const tag = tokens[index].tag;
        if (tag == .l_brace) {
            try scopes.append(scratch_allocator, std.StringHashMap([]const u8).init(scratch_allocator));
            index += 1;
            continue;
        }
        if (tag == .r_brace) {
            if (scopes.items.len > 1) {
                _ = scopes.pop();
            }
            index += 1;
            continue;
        }

        if (scopes.items.len == 1 or
            tokens[index].tag != .keyword_const or
            index + 1 >= use_index or
            tokens[index + 1].tag != .identifier)
        {
            index += 1;
            continue;
        }

        var cursor = index + 2;
        var depth: usize = 0;
        var equal_index: ?usize = null;
        var semicolon_index: ?usize = null;
        while (cursor < use_index) : (cursor += 1) {
            const cursor_tag = tokens[cursor].tag;
            if (cursor_tag == .l_paren or cursor_tag == .l_brace or cursor_tag == .l_bracket) {
                depth += 1;
            } else if (cursor_tag == .r_paren or cursor_tag == .r_brace or cursor_tag == .r_bracket) {
                if (depth > 0) depth -= 1;
            } else if (cursor_tag == .equal) {
                if (depth == 0 and equal_index == null) equal_index = cursor;
            } else if (cursor_tag == .semicolon and depth == 0) {
                semicolon_index = cursor;
                break;
            }
        }

        const value_start = equal_index orelse {
            index += 1;
            continue;
        };
        const value_end = semicolon_index orelse break;

        const value = try resolveStringTokensFromVisibleBindingsAlloc(
            scratch_allocator,
            tokens[value_start + 1 .. value_end],
            scopes.items,
            top_bindings,
        ) orelse {
            index = value_end + 1;
            continue;
        };
        try setScopeBinding(
            scratch_allocator,
            &scopes.items[scopes.items.len - 1],
            tokens[index + 1].lexeme,
            value,
        );
        index = value_end + 1;
    }

    if (lookupVisibleStringBinding(scopes.items, top_bindings, identifier)) |value| {
        return try allocator.dupe(u8, value);
    }
    return null;
}

fn resolveBuildInputStringTokensAtUseAlloc(
    allocator: std.mem.Allocator,
    all_tokens: []const BuildInputToken,
    use_index: usize,
    tokens: []const BuildInputToken,
    top_bindings: *const std.StringHashMap([]const u8),
) !?[]u8 {
    if (tokens.len != 1) return null;
    const tag = tokens[0].tag;
    if (tag == .string_literal) {
        return try decodeStringLiteralAlloc(allocator, tokens[0].lexeme);
    }
    if (tag == .identifier) {
        return try resolveVisibleStringBindingAlloc(
            allocator,
            all_tokens,
            use_index,
            tokens[0].lexeme,
            top_bindings,
        );
    }
    return null;
}

fn freeEmbedFileFunctionPatterns(
    allocator: std.mem.Allocator,
    patterns: []EmbedFileFunctionPattern,
) void {
    for (patterns) |*pattern| pattern.deinit(allocator);
    allocator.free(patterns);
}

fn freeImportedEmbedFileFunctionPatterns(
    allocator: std.mem.Allocator,
    patterns: []ImportedEmbedFnPattern,
) void {
    for (patterns) |*pattern| pattern.deinit(allocator);
    allocator.free(patterns);
}

fn freeBuildModuleBindings(
    allocator: std.mem.Allocator,
    bindings: []BuildModuleBinding,
) void {
    for (bindings) |*binding| binding.deinit(allocator);
    allocator.free(bindings);
}

fn appendUniqueIndex(indexes: *std.ArrayList(usize), allocator: std.mem.Allocator, value: usize) !void {
    for (indexes.items) |existing| {
        if (existing == value) return;
    }
    try indexes.append(allocator, value);
}

fn appendResolvedEmbedPathIfPresent(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    source_dir: []const u8,
    decoded: []const u8,
    collector: BuildInputPathCollector,
) !void {
    const resolved = try std.Io.Dir.path.resolve(allocator, &.{ repo_root, source_dir, decoded });
    defer allocator.free(resolved);

    const repo_relative = try tryRepoRelativePathFromAbsoluteAlloc(allocator, repo_root, resolved) orelse return;
    defer allocator.free(repo_relative);
    if (pathIsGeneratedArtifactBuildOutput(repo_relative)) return;

    const io = compatIo();
    var root_dir = std.Io.Dir.openDirAbsolute(io, repo_root, .{}) catch |err|
        std.process.fatal("unable to open repo root for embed input scan '{s}': {s}", .{ repo_root, @errorName(err) });
    defer root_dir.close(io);
    if (!pathExistsAtRoot(root_dir, io, repo_relative)) return;
    try appendOwnedPathIfMissing(allocator, collector.paths, collector.path_set, repo_relative);
}

const agent_vm_artifact_path = "test/fixtures/ability_agent_vm_smoke.artifact";

fn repoRelativePathEqlWithSeparator(
    path: []const u8,
    expected_posix: []const u8,
    separator: u8,
) bool {
    if (path.len != expected_posix.len) return false;
    for (expected_posix, 0..) |expected_byte, index| {
        const path_byte = path[index];
        if (expected_byte == '/') {
            if (path_byte != '/' and path_byte != separator) return false;
            continue;
        }
        if (path_byte != expected_byte) return false;
    }
    return true;
}

fn pathIsGeneratedArtifactBuildOutput(path: []const u8) bool {
    return repoRelativePathEqlWithSeparator(
        path,
        agent_vm_artifact_path,
        std.Io.Dir.path.sep,
    );
}

fn resolveRepoRelativeImportPathAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    source_dir: []const u8,
    decoded: []const u8,
) !?[]u8 {
    if (!std.mem.endsWith(u8, decoded, ".zig")) return null;

    const resolved = try std.Io.Dir.path.resolve(allocator, &.{ repo_root, source_dir, decoded });
    defer allocator.free(resolved);
    return try tryRepoRelativePathFromAbsoluteAlloc(allocator, repo_root, resolved);
}

fn appendResolvedImportPathIfPresent(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    source_dir: []const u8,
    decoded: []const u8,
    collector: BuildInputPathCollector,
) !void {
    const repo_relative = try resolveRepoRelativeImportPathAlloc(allocator, repo_root, source_dir, decoded) orelse return;
    defer allocator.free(repo_relative);
    try appendResolvedEmbedPathIfPresent(allocator, repo_root, ".", repo_relative, collector);
}

fn functionSourceSlice(
    tree: std.zig.Ast,
    source: [:0]const u8,
    member: std.zig.Ast.Node.Index,
    fn_proto: std.zig.Ast.full.FnProto,
) []const u8 {
    const start = tree.tokenStart(fn_proto.firstToken());
    const last = tree.lastToken(member);
    const end = tree.tokenStart(last) + @as(u32, @intCast(tree.tokenSlice(last).len));
    return source[start..end];
}

fn collectSameFileEmbedFunctionPatternsAlloc(
    allocator: std.mem.Allocator,
    source: [:0]const u8,
) ![]EmbedFileFunctionPattern {
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);

    var root_buffer: [2]std.zig.Ast.Node.Index = undefined;
    const root = tree.fullContainerDecl(&root_buffer, .root) orelse return allocator.alloc(EmbedFileFunctionPattern, 0);

    var patterns = std.ArrayList(EmbedFileFunctionPattern).empty;
    errdefer {
        for (patterns.items) |*pattern| {
            pattern.deinit(allocator);
        }
        patterns.deinit(allocator);
    }

    for (root.ast.members) |member| {
        var fn_buffer: [1]std.zig.Ast.Node.Index = undefined;
        const fn_proto = tree.fullFnProto(&fn_buffer, member) orelse continue;
        const fn_name_token = fn_proto.name_token orelse continue;

        var comptime_params = std.ArrayList(struct {
            name: []const u8,
            index: usize,
        }).empty;
        defer {
            for (comptime_params.items) |param| allocator.free(param.name);
            comptime_params.deinit(allocator);
        }

        var iter = fn_proto.iterate(&tree);
        var param_index: usize = 0;
        param_decl_loop: while (iter.next()) |param| : (param_index += 1) {
            if (param.comptime_noalias == null) continue :param_decl_loop;
            const name_token = param.name_token orelse continue :param_decl_loop;
            try comptime_params.append(allocator, .{
                .name = try allocator.dupe(u8, tree.tokenSlice(name_token)),
                .index = param_index,
            });
        }
        if (comptime_params.items.len == 0) continue;

        const fn_source = functionSourceSlice(tree, source, member, fn_proto);
        const fn_source_z = try allocator.dupeSentinel(u8, fn_source, 0);
        defer allocator.free(fn_source_z);

        var tokenizer = std.zig.Tokenizer.init(fn_source_z);
        var window: BuildInputTokenWindow = .{};
        var matched_indexes = std.ArrayList(usize).empty;
        defer matched_indexes.deinit(allocator);

        token_loop: while (true) {
            const token = tokenizer.next();
            if (token.tag == .eof) break;
            window.push(.{
                .tag = token.tag,
                .lexeme = tokenSlice(fn_source_z, token),
            });

            const identifier = maybeEmbedFileIdentifierPath(&window) orelse continue :token_loop;
            param_match_loop: for (comptime_params.items) |param| {
                if (!std.mem.eql(u8, identifier, param.name)) continue :param_match_loop;
                try appendUniqueIndex(&matched_indexes, allocator, param.index);
            }
        }

        if (matched_indexes.items.len == 0) continue;

        try patterns.append(allocator, .{
            .fn_name = try allocator.dupe(u8, tree.tokenSlice(fn_name_token)),
            .path_param_indexes = try matched_indexes.toOwnedSlice(allocator),
        });
    }

    return try patterns.toOwnedSlice(allocator);
}

fn patternUsesParamIndex(pattern: *const EmbedFileFunctionPattern, index: usize) bool {
    for (pattern.path_param_indexes) |existing| {
        if (existing == index) return true;
    }
    return false;
}

fn importPathFromValueTokensAlloc(
    allocator: std.mem.Allocator,
    value_tokens: []const BuildInputToken,
) !?[]u8 {
    if (value_tokens.len != 4) return null;
    if (value_tokens[0].tag != .builtin or !std.mem.eql(u8, value_tokens[0].lexeme, "@import")) return null;
    if (value_tokens[1].tag != .l_paren or value_tokens[2].tag != .string_literal or value_tokens[3].tag != .r_paren) {
        return null;
    }
    return try decodeStringLiteralAlloc(allocator, value_tokens[2].lexeme);
}

fn moduleRootSourcePathFromExprTokensAlloc(
    allocator: std.mem.Allocator,
    expr_tokens: []const BuildInputToken,
) !?[]u8 {
    if (expr_tokens.len == 1 and expr_tokens[0].tag == .string_literal) {
        return try decodeStringLiteralAlloc(allocator, expr_tokens[0].lexeme);
    }
    if (expr_tokens.len == 6 and
        expr_tokens[0].tag == .identifier and
        expr_tokens[1].tag == .period and
        expr_tokens[2].tag == .identifier and
        std.mem.eql(u8, expr_tokens[2].lexeme, "path") and
        expr_tokens[3].tag == .l_paren and
        expr_tokens[4].tag == .string_literal and
        expr_tokens[5].tag == .r_paren)
    {
        return try decodeStringLiteralAlloc(allocator, expr_tokens[4].lexeme);
    }
    return null;
}

fn moduleRootSourcePathFromValueTokensAlloc(
    allocator: std.mem.Allocator,
    value_tokens: []const BuildInputToken,
) !?[]u8 {
    var index: usize = 0;
    while (index + 2 < value_tokens.len) : (index += 1) {
        if (value_tokens[index].tag != .period or
            value_tokens[index + 1].tag != .identifier or
            !std.mem.eql(u8, value_tokens[index + 1].lexeme, "root_source_file") or
            value_tokens[index + 2].tag != .equal)
        {
            continue;
        }

        const value_start = index + 3;
        var cursor = value_start;
        var depth: usize = 0;
        while (cursor < value_tokens.len) : (cursor += 1) {
            const tag = value_tokens[cursor].tag;
            if (tag == .l_paren or tag == .l_brace or tag == .l_bracket) {
                depth += 1;
            } else if (tag == .r_paren or tag == .r_brace or tag == .r_bracket) {
                if (depth == 0) break;
                depth -= 1;
            } else if (tag == .comma and depth == 0) {
                break;
            }
        }
        return try moduleRootSourcePathFromExprTokensAlloc(allocator, value_tokens[value_start..cursor]);
    }
    return null;
}

fn appendOwnedBuildModuleBinding(
    allocator: std.mem.Allocator,
    bindings: *std.ArrayList(BuildModuleBinding),
    alias: []const u8,
    repo_relative_source_path: []const u8,
) !void {
    for (bindings.items) |existing| {
        if (std.mem.eql(u8, existing.alias, alias)) return;
    }
    try bindings.append(allocator, .{
        .alias = try allocator.dupe(u8, alias),
        .repo_relative_source_path = try allocator.dupe(u8, repo_relative_source_path),
    });
}

fn collectBuildModuleBindingsAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
) ![]BuildModuleBinding {
    const io = compatIo();
    var root_dir = std.Io.Dir.openDirAbsolute(io, repo_root, .{}) catch return allocator.alloc(BuildModuleBinding, 0);
    defer root_dir.close(io);

    const source = root_dir.readFileAlloc(io, "build.zig", allocator, .limited(4 * 1024 * 1024)) catch return allocator.alloc(BuildModuleBinding, 0);
    defer allocator.free(source);
    const source_z = try allocator.dupeSentinel(u8, source, 0);
    defer allocator.free(source_z);

    var tree = try std.zig.Ast.parse(allocator, source_z, .zig);
    defer tree.deinit(allocator);

    var root_buffer: [2]std.zig.Ast.Node.Index = undefined;
    const root = tree.fullContainerDecl(&root_buffer, .root) orelse return allocator.alloc(BuildModuleBinding, 0);

    var build_fn_source: ?[]const u8 = null;
    for (root.ast.members) |member| {
        var fn_buffer: [1]std.zig.Ast.Node.Index = undefined;
        const fn_proto = tree.fullFnProto(&fn_buffer, member) orelse continue;
        const fn_name_token = fn_proto.name_token orelse continue;
        if (!std.mem.eql(u8, tree.tokenSlice(fn_name_token), "build")) continue;
        build_fn_source = functionSourceSlice(tree, source_z, member, fn_proto);
        break;
    }

    const build_source = build_fn_source orelse return allocator.alloc(BuildModuleBinding, 0);
    const build_source_z = try allocator.dupeSentinel(u8, build_source, 0);
    defer allocator.free(build_source_z);
    const tokens = try collectBuildInputTokensAlloc(allocator, build_source_z);
    defer allocator.free(tokens);

    var bindings = std.ArrayList(BuildModuleBinding).empty;
    errdefer {
        for (bindings.items) |*binding| binding.deinit(allocator);
        bindings.deinit(allocator);
    }

    var module_vars = std.StringHashMap([]const u8).init(allocator);
    defer {
        var iter = module_vars.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        module_vars.deinit();
    }

    var index: usize = 0;
    var scope_depth: usize = 0;
    while (index < tokens.len) : (index += 1) {
        const tag = tokens[index].tag;
        if (tag == .l_brace) {
            scope_depth += 1;
            continue;
        }
        if (tag == .r_brace) {
            if (scope_depth > 0) scope_depth -= 1;
            continue;
        }

        if (scope_depth == 1 and
            index + 1 < tokens.len and
            tokens[index].tag == .keyword_const and
            tokens[index + 1].tag == .identifier)
        {
            var cursor = index + 2;
            var depth: usize = 0;
            var equal_index: ?usize = null;
            var semicolon_index: ?usize = null;
            while (cursor < tokens.len) : (cursor += 1) {
                const cursor_tag = tokens[cursor].tag;
                if (cursor_tag == .l_paren or cursor_tag == .l_brace or cursor_tag == .l_bracket) {
                    depth += 1;
                } else if (cursor_tag == .r_paren or cursor_tag == .r_brace or cursor_tag == .r_bracket) {
                    if (depth > 0) depth -= 1;
                } else if (cursor_tag == .equal) {
                    if (depth == 0 and equal_index == null) equal_index = cursor;
                } else if (cursor_tag == .semicolon and depth == 0) {
                    semicolon_index = cursor;
                    break;
                }
            }

            const value_start = equal_index orelse continue;
            const value_end = semicolon_index orelse continue;
            const value_tokens = tokens[value_start + 1 .. value_end];
            const root_source_path = try moduleRootSourcePathFromValueTokensAlloc(allocator, value_tokens) orelse continue;
            defer allocator.free(root_source_path);
            const repo_relative = try resolveRepoRelativeImportPathAlloc(allocator, repo_root, ".", root_source_path) orelse continue;
            defer allocator.free(repo_relative);

            const module_var = tokens[index + 1].lexeme;
            try module_vars.put(try allocator.dupe(u8, module_var), try allocator.dupe(u8, repo_relative));
            errdefer _ = module_vars.remove(module_var);
            try appendOwnedBuildModuleBinding(allocator, &bindings, module_var, repo_relative);

            if (value_tokens.len >= 6 and
                value_tokens[0].tag == .identifier and
                value_tokens[1].tag == .period and
                value_tokens[2].tag == .identifier and
                std.mem.eql(u8, value_tokens[2].lexeme, "addModule") and
                value_tokens[3].tag == .l_paren and
                value_tokens[4].tag == .string_literal)
            {
                const module_name = try decodeStringLiteralAlloc(allocator, value_tokens[4].lexeme) orelse continue;
                defer allocator.free(module_name);
                try appendOwnedBuildModuleBinding(allocator, &bindings, module_name, repo_relative);
            }
            continue;
        }

        if (scope_depth == 1 and
            index + 6 < tokens.len and
            tokens[index].tag == .identifier and
            tokens[index + 1].tag == .period and
            tokens[index + 2].tag == .identifier and
            std.mem.eql(u8, tokens[index + 2].lexeme, "addImport") and
            tokens[index + 3].tag == .l_paren and
            tokens[index + 4].tag == .string_literal and
            tokens[index + 5].tag == .comma and
            tokens[index + 6].tag == .identifier)
        {
            const import_alias = try decodeStringLiteralAlloc(allocator, tokens[index + 4].lexeme) orelse continue;
            defer allocator.free(import_alias);
            const module_var = tokens[index + 6].lexeme;
            const repo_relative = module_vars.get(module_var) orelse continue;
            try appendOwnedBuildModuleBinding(allocator, &bindings, import_alias, repo_relative);
        }
    }

    return try bindings.toOwnedSlice(allocator);
}

fn resolveBuildModuleImportPathAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    import_alias: []const u8,
) !?[]u8 {
    const bindings = try collectBuildModuleBindingsAlloc(allocator, repo_root);
    defer freeBuildModuleBindings(allocator, bindings);

    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.alias, import_alias)) {
            return try allocator.dupe(u8, binding.repo_relative_source_path);
        }
    }
    return null;
}

fn collectImportedEmbedFileFunctionPatternsAlloc(
    allocator: std.mem.Allocator,
    scan: BuildInputSourceScan,
) ![]ImportedEmbedFnPattern {
    var patterns = std.ArrayList(ImportedEmbedFnPattern).empty;
    errdefer {
        for (patterns.items) |*pattern| pattern.deinit(allocator);
        patterns.deinit(allocator);
    }

    const source_dir = std.Io.Dir.path.dirname(scan.source_path) orelse ".";
    var index: usize = 0;
    var scope_depth: usize = 0;
    while (index + 1 < scan.tokens.len) {
        const scan_tag = scan.tokens[index].tag;
        if (scan_tag == .l_brace) {
            scope_depth += 1;
            index += 1;
            continue;
        }
        if (scan_tag == .r_brace) {
            if (scope_depth > 0) scope_depth -= 1;
            index += 1;
            continue;
        }

        if (scope_depth != 0 or scan.tokens[index].tag != .keyword_const or scan.tokens[index + 1].tag != .identifier) {
            index += 1;
            continue;
        }

        var cursor = index + 2;
        var depth: usize = 0;
        var equal_index: ?usize = null;
        var semicolon_index: ?usize = null;
        while (cursor < scan.tokens.len) : (cursor += 1) {
            const cursor_tag = scan.tokens[cursor].tag;
            if (cursor_tag == .l_paren or cursor_tag == .l_brace or cursor_tag == .l_bracket) {
                depth += 1;
            } else if (cursor_tag == .r_paren or cursor_tag == .r_brace or cursor_tag == .r_bracket) {
                if (depth > 0) depth -= 1;
            } else if (cursor_tag == .equal) {
                if (depth == 0 and equal_index == null) equal_index = cursor;
            } else if (cursor_tag == .semicolon and depth == 0) {
                semicolon_index = cursor;
                break;
            }
        }

        const value_start = equal_index orelse {
            index += 1;
            continue;
        };
        const value_end = semicolon_index orelse {
            index += 1;
            continue;
        };
        const decoded = try importPathFromValueTokensAlloc(allocator, scan.tokens[value_start + 1 .. value_end]) orelse {
            index = value_end + 1;
            continue;
        };
        defer allocator.free(decoded);

        const repo_relative = (try resolveRepoRelativeImportPathAlloc(allocator, scan.repo_root, source_dir, decoded)) orelse
            (try resolveBuildModuleImportPathAlloc(allocator, scan.repo_root, decoded)) orelse
            {
                index = value_end + 1;
                continue;
            };
        defer allocator.free(repo_relative);
        if (!std.mem.endsWith(u8, repo_relative, ".zig")) {
            index = value_end + 1;
            continue;
        }

        const imported_source_full_path = try std.Io.Dir.path.join(allocator, &.{ scan.repo_root, repo_relative });
        defer allocator.free(imported_source_full_path);
        const imported_bytes = std.Io.Dir.cwd().readFileAlloc(compatIo(), imported_source_full_path, allocator, .limited(1 << 20)) catch |err| switch (err) {
            error.FileNotFound => {
                index = value_end + 1;
                continue;
            },
            else => return err,
        };
        defer allocator.free(imported_bytes);
        const imported_source_z = try allocator.dupeSentinel(u8, imported_bytes, 0);
        defer allocator.free(imported_source_z);

        const imported_patterns = try collectSameFileEmbedFunctionPatternsAlloc(allocator, imported_source_z);
        defer allocator.free(imported_patterns);
        const imported_source_dir = std.Io.Dir.path.dirname(repo_relative) orelse ".";
        for (imported_patterns) |pattern| {
            try patterns.append(allocator, .{
                .module_binding = try allocator.dupe(u8, scan.tokens[index + 1].lexeme),
                .source_dir = try allocator.dupe(u8, imported_source_dir),
                .pattern = pattern,
            });
        }
        index = value_end + 1;
    }

    return try patterns.toOwnedSlice(allocator);
}

fn collectBuildInputTokensAlloc(
    allocator: std.mem.Allocator,
    source: [:0]const u8,
) ![]const BuildInputToken {
    var tokens = std.ArrayList(BuildInputToken).empty;
    errdefer tokens.deinit(allocator);

    var tokenizer = std.zig.Tokenizer.init(source);
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) break;
        try tokens.append(allocator, .{
            .tag = token.tag,
            .lexeme = tokenSlice(source, token),
        });
    }
    return try tokens.toOwnedSlice(allocator);
}

fn collectParameterizedEmbedFileBuildInputsForSource(
    allocator: std.mem.Allocator,
    scan: BuildInputSourceScan,
) !void {
    const Match = struct {
        pattern: *const EmbedFileFunctionPattern,
        call_source_dir: []const u8,
        arg_start: usize,
    };

    const patterns = try collectSameFileEmbedFunctionPatternsAlloc(allocator, scan.source);
    defer freeEmbedFileFunctionPatterns(allocator, patterns);
    const imported_patterns = try collectImportedEmbedFileFunctionPatternsAlloc(allocator, scan);
    defer freeImportedEmbedFileFunctionPatterns(allocator, imported_patterns);
    if (patterns.len == 0 and imported_patterns.len == 0) return;

    const source_dir = std.Io.Dir.path.dirname(scan.source_path) orelse ".";
    var index: usize = 0;
    while (index + 1 < scan.tokens.len) : (index += 1) {
        const match = (blk: {
            if (scan.tokens[index].tag == .identifier and scan.tokens[index + 1].tag == .l_paren) {
                if (index > 0 and scan.tokens[index - 1].tag == .keyword_fn) break :blk null;
                for (patterns) |*candidate| {
                    if (std.mem.eql(u8, candidate.fn_name, scan.tokens[index].lexeme)) {
                        break :blk Match{
                            .pattern = candidate,
                            .call_source_dir = source_dir,
                            .arg_start = index + 2,
                        };
                    }
                }
            }
            if (index + 3 < scan.tokens.len and
                scan.tokens[index].tag == .identifier and
                scan.tokens[index + 1].tag == .period and
                scan.tokens[index + 2].tag == .identifier and
                scan.tokens[index + 3].tag == .l_paren)
            {
                pattern_search: for (imported_patterns) |*candidate| {
                    if (!std.mem.eql(u8, candidate.module_binding, scan.tokens[index].lexeme)) continue :pattern_search;
                    if (!std.mem.eql(u8, candidate.pattern.fn_name, scan.tokens[index + 2].lexeme)) continue :pattern_search;
                    break :blk Match{
                        .pattern = &candidate.pattern,
                        .call_source_dir = candidate.source_dir,
                        .arg_start = index + 4,
                    };
                }
            }
            break :blk null;
        }) orelse continue;

        var arg_index: usize = 0;
        var arg_start = match.arg_start;
        var depth: usize = 0;
        var cursor = match.arg_start;
        arg_scan: while (cursor < scan.tokens.len) : (cursor += 1) {
            const tag = scan.tokens[cursor].tag;
            if (tag == .l_paren or tag == .l_brace or tag == .l_bracket) {
                depth += 1;
            } else if (tag == .r_paren) {
                if (depth == 0) {
                    if (patternUsesParamIndex(match.pattern, arg_index)) {
                        const arg_tokens = scan.tokens[arg_start..cursor];
                        const decoded = try resolveBuildInputStringTokensAtUseAlloc(
                            allocator,
                            scan.tokens,
                            arg_start,
                            arg_tokens,
                            scan.top_bindings,
                        ) orelse null;
                        if (decoded) |owned| {
                            defer allocator.free(owned);
                            try appendResolvedEmbedPathIfPresent(
                                allocator,
                                scan.repo_root,
                                match.call_source_dir,
                                owned,
                                scan.collector,
                            );
                        }
                    }
                    index = cursor;
                    break;
                }
                depth -= 1;
            } else if (tag == .r_brace or tag == .r_bracket) {
                if (depth > 0) depth -= 1;
            } else if (tag == .comma) {
                if (depth != 0) continue :arg_scan;
                if (patternUsesParamIndex(match.pattern, arg_index)) {
                    const arg_tokens = scan.tokens[arg_start..cursor];
                    const decoded = try resolveBuildInputStringTokensAtUseAlloc(
                        allocator,
                        scan.tokens,
                        arg_start,
                        arg_tokens,
                        scan.top_bindings,
                    ) orelse null;
                    if (decoded) |owned| {
                        defer allocator.free(owned);
                        try appendResolvedEmbedPathIfPresent(
                            allocator,
                            scan.repo_root,
                            match.call_source_dir,
                            owned,
                            scan.collector,
                        );
                    }
                }
                arg_index += 1;
                arg_start = cursor + 1;
            }
        }
    }
}

fn collectEmbedFileBuildInputsForSource(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    source_path: []const u8,
    paths: *std.ArrayList([]const u8),
    path_set: *std.StringHashMap(void),
) !void {
    const source_full_path = try std.Io.Dir.path.join(allocator, &.{ repo_root, source_path });
    defer allocator.free(source_full_path);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(compatIo(), source_full_path, allocator, .limited(1 << 20));
    defer allocator.free(bytes);
    const source_z = try allocator.dupeSentinel(u8, bytes, 0);
    defer allocator.free(source_z);

    const source_dir = std.Io.Dir.path.dirname(source_path) orelse ".";
    const collector: BuildInputPathCollector = .{
        .paths = paths,
        .path_set = path_set,
    };
    var scratch = std.heap.ArenaAllocator.init(allocator);
    errdefer scratch.deinit();
    defer scratch.deinit();
    const scratch_allocator = scratch.allocator();
    const tokens = try collectBuildInputTokensAlloc(allocator, source_z);
    defer allocator.free(tokens);
    var top_bindings = std.StringHashMap([]const u8).init(scratch_allocator);
    errdefer top_bindings.deinit();
    defer top_bindings.deinit();
    try populateTopLevelSimpleStringBindings(scratch_allocator, tokens, &top_bindings);
    var window: BuildInputTokenWindow = .{};
    var token_index: usize = 0;
    while (token_index < tokens.len) : (token_index += 1) {
        window.push(tokens[token_index]);

        if (windowMatchesEmbedFileSelf(&window)) {
            try appendOwnedPathIfMissing(allocator, paths, path_set, source_path);
            continue;
        }

        if (maybeImportLiteralPath(&window)) |literal| {
            const decoded = try decodeStringLiteralAlloc(allocator, literal) orelse continue;
            defer allocator.free(decoded);
            try appendResolvedImportPathIfPresent(allocator, repo_root, source_dir, decoded, collector);
            continue;
        }

        if (maybeEmbedFileIdentifierPath(&window)) |identifier| {
            const decoded = try resolveVisibleStringBindingAlloc(
                allocator,
                tokens,
                token_index,
                identifier,
                &top_bindings,
            ) orelse null;
            if (decoded) |owned| {
                defer allocator.free(owned);
                try appendResolvedEmbedPathIfPresent(allocator, repo_root, source_dir, owned, collector);
                continue;
            }
        }

        if (maybeEmbedFileLiteralPath(&window)) |literal| {
            const decoded = try decodeStringLiteralAlloc(allocator, literal) orelse continue;
            defer allocator.free(decoded);
            try appendResolvedEmbedPathIfPresent(allocator, repo_root, source_dir, decoded, collector);
        }
    }

    try collectParameterizedEmbedFileBuildInputsForSource(allocator, .{
        .repo_root = repo_root,
        .source_path = source_path,
        .source = source_z,
        .tokens = tokens,
        .collector = collector,
        .top_bindings = &top_bindings,
    });
}

fn pathIsIgnoredBuildInput(path: []const u8) bool {
    return std.mem.eql(u8, path, ".git") or
        std.mem.startsWith(u8, path, ".git/") or
        std.mem.eql(u8, path, ".zig-cache") or
        std.mem.startsWith(u8, path, ".zig-cache/") or
        std.mem.eql(u8, path, "zig-cache") or
        std.mem.startsWith(u8, path, "zig-cache/") or
        std.mem.eql(u8, path, ".zig-global-cache") or
        std.mem.startsWith(u8, path, ".zig-global-cache/") or
        std.mem.eql(u8, path, "zig-global-cache") or
        std.mem.startsWith(u8, path, "zig-global-cache/") or
        std.mem.eql(u8, path, "zig-out") or
        std.mem.startsWith(u8, path, "zig-out/");
}

fn collectFilesystemRepoZigPaths(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    paths: *std.ArrayList([]const u8),
    path_set: *std.StringHashMap(void),
) void {
    const io = compatIo();
    var root_dir = std.Io.Dir.openDirAbsolute(io, repo_root, .{ .iterate = true }) catch |err|
        std.process.fatal("unable to open repo root for build input walk '{s}': {s}", .{ repo_root, @errorName(err) });
    defer root_dir.close(io);

    var walker = root_dir.walkSelectively(allocator) catch
        std.process.fatal("unable to walk repo root for build inputs", .{});
    defer walker.deinit();

    while ((walker.next(io) catch
        std.process.fatal("unable to iterate repo build input walk", .{}))) |entry|
    {
        if (pathIsIgnoredBuildInput(entry.path)) continue;
        if (entry.kind == .directory) {
            walker.enter(io, entry) catch
                std.process.fatal("unable to enter repo build input directory '{s}'", .{entry.path});
            continue;
        }
        if (!(entry.kind == .file or entry.kind == .sym_link)) continue;
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;
        appendOwnedPathIfMissing(allocator, paths, path_set, entry.path) catch
            std.process.fatal("unable to record repo Zig build input path", .{});
    }
}

fn collectBuildZigReferencedRepoZigPaths(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    paths: *std.ArrayList([]const u8),
    path_set: *std.StringHashMap(void),
) void {
    const io = compatIo();
    var root_dir = std.Io.Dir.openDirAbsolute(io, repo_root, .{}) catch return;
    defer root_dir.close(io);

    const source = root_dir.readFileAlloc(io, "build.zig", allocator, .limited(4 * 1024 * 1024)) catch return;
    defer allocator.free(source);
    const source_z = allocator.dupeSentinel(u8, source, 0) catch
        std.process.fatal("unable to duplicate build.zig source for build input scan", .{});
    defer allocator.free(source_z);

    var tree = std.zig.Ast.parse(allocator, source_z, .zig) catch
        std.process.fatal("unable to parse build.zig for build input scan", .{});
    defer tree.deinit(allocator);

    var root_buffer: [2]std.zig.Ast.Node.Index = undefined;
    const root = tree.fullContainerDecl(&root_buffer, .root) orelse return;

    var build_fn_source: ?[]const u8 = null;
    for (root.ast.members) |member| {
        var fn_buffer: [1]std.zig.Ast.Node.Index = undefined;
        const fn_proto = tree.fullFnProto(&fn_buffer, member) orelse continue;
        const fn_name_token = fn_proto.name_token orelse continue;
        if (!std.mem.eql(u8, tree.tokenSlice(fn_name_token), "build")) continue;
        build_fn_source = functionSourceSlice(tree, source_z, member, fn_proto);
        break;
    }

    const build_source = build_fn_source orelse return;
    const build_source_z = allocator.dupeSentinel(u8, build_source, 0) catch
        std.process.fatal("unable to duplicate build() source for build input scan", .{});
    defer allocator.free(build_source_z);
    const tokens = collectBuildInputTokensAlloc(allocator, build_source_z) catch
        std.process.fatal("unable to tokenize build() source for build input scan", .{});
    defer allocator.free(tokens);

    const collector: BuildInputPathCollector = .{
        .paths = paths,
        .path_set = path_set,
    };
    for (tokens) |token| {
        if (token.tag != .string_literal) continue;
        const decoded = decodeStringLiteralAlloc(allocator, token.lexeme) catch
            std.process.fatal("unable to decode build() path literal for build input scan", .{}) orelse continue;
        defer allocator.free(decoded);
        appendResolvedImportPathIfPresent(allocator, repo_root, ".", decoded, collector) catch
            std.process.fatal("unable to record build() referenced repo Zig path", .{});
    }
}

fn collectTrackedRepoZigPathsAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    paths: *std.ArrayList([]const u8),
    path_set: *std.StringHashMap(void),
) bool {
    const io = childProcessIo();
    var root_dir = std.Io.Dir.openDirAbsolute(io, repo_root, .{}) catch return false;
    defer root_dir.close(io);
    if (!repoRootContainsGitMetadata(root_dir, io)) return false;

    const result = std.process.run(allocator, io, .{
        .argv = &.{ "git", "-C", repo_root, "ls-files", "--cached", "--", "*.zig" },
        .stdout_limit = .limited(512 * 1024),
        .stderr_limit = .limited(512 * 1024),
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) return false,
        else => return false,
    }

    var lines = std.mem.tokenizeScalar(u8, result.stdout, '\n');
    while (lines.next()) |line| {
        if (!std.mem.endsWith(u8, line, ".zig")) continue;
        if (!pathExistsAtRoot(root_dir, io, line)) continue;
        appendOwnedPathIfMissing(allocator, paths, path_set, line) catch
            std.process.fatal("unable to record tracked repo Zig path", .{});
    }
    return true;
}

fn collectRepoZigPathsAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    paths: *std.ArrayList([]const u8),
    path_set: *std.StringHashMap(void),
) void {
    const have_tracked = collectTrackedRepoZigPathsAlloc(allocator, repo_root, paths, path_set);
    if (have_tracked) return;
    collectFilesystemRepoZigPaths(allocator, repo_root, paths, path_set);
}

fn artifactBuildInputPathsAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
) []const []const u8 {
    var paths = std.ArrayList([]const u8).empty;
    var path_set = std.StringHashMap(void).init(allocator);
    defer path_set.deinit();

    collectRepoZigPathsAlloc(allocator, repo_root, &paths, &path_set);
    collectBuildZigReferencedRepoZigPaths(allocator, repo_root, &paths, &path_set);

    var index: usize = 0;
    while (index < paths.items.len) : (index += 1) {
        if (!std.mem.endsWith(u8, paths.items[index], ".zig")) continue;
        collectEmbedFileBuildInputsForSource(
            allocator,
            repo_root,
            paths.items[index],
            &paths,
            &path_set,
        ) catch std.process.fatal("unable to collect embedded build inputs from '{s}'", .{paths.items[index]});
    }

    sortOwnedPaths(paths.items);
    return paths.toOwnedSlice(allocator) catch
        std.process.fatal("unable to allocate artifact build input path list", .{});
}

fn hashArtifactBuildInputs(
    hasher: *std.crypto.hash.Blake3,
    allocator: std.mem.Allocator,
    repo_root: []const u8,
) void {
    const input_paths = artifactBuildInputPathsAlloc(allocator, repo_root);
    defer freeOwnedPathList(allocator, input_paths);

    for (input_paths) |path| {
        hashBuildIdentityFileAtRoot(hasher, repo_root, path);
    }

    const io = compatIo();
    var root_dir = std.Io.Dir.openDirAbsolute(io, repo_root, .{}) catch |err|
        std.process.fatal("unable to open repo root for build metadata '{s}': {s}", .{ repo_root, @errorName(err) });
    defer root_dir.close(io);
    if (pathExistsAtRoot(root_dir, io, "build.zig.zon")) {
        hashBuildIdentityFileAtRoot(hasher, repo_root, "build.zig.zon");
    }
}

fn artifactBuildInputFingerprint(allocator: std.mem.Allocator, repo_root: []const u8) [32]u8 {
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update("ability-artifact-build-input-fingerprint-v1");
    hashArtifactBuildInputs(&hasher, allocator, repo_root);
    var digest = std.mem.zeroes([32]u8);
    hasher.final(&digest);
    return digest;
}

fn hashBuildTargetIdentity(
    hasher: *std.crypto.hash.Blake3,
    b: *std.Build,
    target: std.Build.ResolvedTarget,
) void {
    const query_triple = target.query.zigTriple(b.allocator) catch
        std.process.fatal("unable to serialize build target query triple", .{});
    defer b.allocator.free(query_triple);
    const query_cpu = target.query.serializeCpuAlloc(b.allocator) catch
        std.process.fatal("unable to serialize build target query cpu", .{});
    defer b.allocator.free(query_cpu);
    const result_triple = target.result.zigTriple(b.allocator) catch
        std.process.fatal("unable to serialize resolved build target triple", .{});
    defer b.allocator.free(result_triple);
    const result_cpu = std.zig.serializeCpuAlloc(b.allocator, target.result.cpu) catch
        std.process.fatal("unable to serialize resolved build target cpu", .{});
    defer b.allocator.free(result_cpu);

    hasher.update("query-triple");
    hasher.update(query_triple);
    hasher.update("query-cpu");
    hasher.update(query_cpu);
    hasher.update("query-ofmt");
    if (target.query.ofmt) |ofmt| {
        hasher.update(@tagName(ofmt));
    } else {
        hasher.update("default");
    }
    hasher.update("query-dynamic-linker");
    if (target.query.dynamic_linker) |dynamic_linker| {
        if (dynamic_linker.get()) |path| {
            hasher.update(path);
        } else {
            hasher.update("(none)");
        }
    } else {
        hasher.update("(none)");
    }

    hasher.update("resolved-triple");
    hasher.update(result_triple);
    hasher.update("resolved-cpu");
    hasher.update(result_cpu);
    hasher.update("resolved-ofmt");
    hasher.update(@tagName(target.result.ofmt));
    hasher.update("resolved-dynamic-linker");
    if (target.result.dynamic_linker.get()) |dynamic_linker| {
        hasher.update(dynamic_linker);
    } else {
        hasher.update("(none)");
    }
}

fn defaultArtifactBuildFingerprint(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) [32]u8 {
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update("ability-default-artifact-build-fingerprint-v2");
    hasher.update(builtin.zig_version_string);
    hasher.update(@tagName(optimize));
    hashBuildTargetIdentity(&hasher, b, target);
    hashArtifactBuildInputs(&hasher, b.allocator, b.pathFromRoot("."));

    var digest = std.mem.zeroes([32]u8);
    hasher.final(&digest);
    return digest;
}

fn repoZigPathRegistryAlloc(allocator: std.mem.Allocator, repo_root: []const u8) []const u8 {
    var paths = std.ArrayList([]const u8).empty;
    var path_set = std.StringHashMap(void).init(allocator);
    defer path_set.deinit();

    collectRepoZigPathsAlloc(allocator, repo_root, &paths, &path_set);
    defer {
        for (paths.items) |path| allocator.free(path);
        paths.deinit(allocator);
    }

    sortOwnedPaths(paths.items);

    var registry = std.ArrayList(u8).empty;
    for (paths.items) |path| {
        registry.appendSlice(allocator, path) catch
            std.process.fatal("unable to append repo source path", .{});
        registry.append(allocator, '\n') catch
            std.process.fatal("unable to append repo source separator", .{});
    }
    return registry.toOwnedSlice(allocator) catch
        std.process.fatal("unable to allocate repo source path registry", .{});
}

fn repoZigPathRegistry(b: *std.Build) []const u8 {
    return repoZigPathRegistryAlloc(b.allocator, b.pathFromRoot("."));
}

fn zigLintPathExcluded(path: []const u8) bool {
    if (std.mem.startsWith(u8, path, ".zig-cache/")) return true;
    if (std.mem.startsWith(u8, path, "zig-cache/")) return true;
    if (std.mem.startsWith(u8, path, ".zig-global-cache/")) return true;
    if (std.mem.startsWith(u8, path, "zig-global-cache/")) return true;
    if (std.mem.startsWith(u8, path, "tmp.")) return true;
    if (std.mem.startsWith(u8, path, "zig-pkg/")) return true;
    if (std.mem.eql(u8, path, "src/error_witness.zig")) return true;
    if (std.mem.eql(u8, path, "src/ir_api.zig")) return true;
    if (std.mem.eql(u8, path, "src/lowering_api.zig")) return true;
    if (std.mem.eql(u8, path, "src/root.zig")) return true;
    return false;
}

fn repoZigLintIncludePaths(b: *std.Build) []const std.Build.LazyPath {
    const registry = repoZigPathRegistry(b);
    var includes = std.ArrayList(std.Build.LazyPath).empty;
    var lines = std.mem.tokenizeScalar(u8, registry, '\n');
    while (lines.next()) |line| {
        if (!std.mem.endsWith(u8, line, ".zig")) continue;
        if (zigLintPathExcluded(line)) continue;
        includes.append(b.allocator, b.path(line)) catch
            std.process.fatal("unable to record repo Zig lint path", .{});
    }
    return includes.toOwnedSlice(b.allocator) catch
        std.process.fatal("unable to allocate repo Zig lint path list", .{});
}

fn repoZigLintCliArgsFromRegistryAlloc(
    allocator: std.mem.Allocator,
    registry: []const u8,
    tail_args: []const []const u8,
) ![]const []const u8 {
    var args = std.ArrayList([]const u8).empty;
    errdefer args.deinit(allocator);
    var lines = std.mem.tokenizeScalar(u8, registry, '\n');
    while (lines.next()) |line| {
        if (!std.mem.endsWith(u8, line, ".zig")) continue;
        if (zigLintPathExcluded(line)) continue;
        try args.append(allocator, "--include");
        try args.append(allocator, line);
    }
    for (tail_args) |arg| try args.append(allocator, arg);
    return args.toOwnedSlice(allocator);
}

fn repoZigLintCliArgsAlloc(b: *std.Build, tail_args: []const []const u8) []const []const u8 {
    return repoZigLintCliArgsFromRegistryAlloc(b.allocator, repoZigPathRegistry(b), tail_args) catch
        std.process.fatal("unable to allocate repo Zig lint command args", .{});
}

const PackageRootAlias = struct {
    path: []const u8,
    available: bool,
};

fn scratchRootPath(b: *std.Build, leaf: []const u8) []const u8 {
    return std.Io.Dir.path.join(b.allocator, &.{ tempRootPath(b), leaf }) catch
        std.process.fatal("unable to allocate scratch root path", .{});
}

fn boundaryAliasRoot(b: *std.Build) []const u8 {
    return scratchRootPath(b, ".ability_aliases");
}

fn clearAliasPath(alias_path: []const u8, dir_error: []const u8, path_error: []const u8) void {
    const io = compatIo();
    std.Io.Dir.deleteFileAbsolute(io, alias_path) catch |err| switch (err) {
        error.FileNotFound => {},
        error.IsDir => std.Io.Dir.cwd().deleteTree(io, alias_path) catch
            std.process.fatal("{s}", .{dir_error}),
        else => std.process.fatal("{s}", .{path_error}),
    };
}

fn packageRootAlias(b: *std.Build) PackageRootAlias {
    const repo_root = b.pathFromRoot(".");
    const alias_root = boundaryAliasRoot(b);
    std.Io.Dir.createDirAbsolute(b.graph.io, alias_root, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return .{ .path = repo_root, .available = false },
    };
    const alias_leaf = std.fmt.allocPrint(
        b.allocator,
        "ability_repo_alias_{x}",
        .{std.hash.Wyhash.hash(0, repo_root)},
    ) catch std.process.fatal("unable to allocate package-root alias leaf", .{});
    const alias_path = std.Io.Dir.path.join(b.allocator, &.{ alias_root, alias_leaf }) catch
        std.process.fatal("unable to allocate package-root alias path", .{});

    var link_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const existing_target_len = std.Io.Dir.readLinkAbsolute(b.graph.io, alias_path, &link_buffer) catch |err| switch (err) {
        error.FileNotFound => null,
        else => blk: {
            clearAliasPath(alias_path, "unable to clear package-root alias directory", "unable to clear package-root alias path");
            break :blk null;
        },
    };
    const existing_target = if (existing_target_len) |len| link_buffer[0..len] else null;
    if (existing_target) |target| {
        if (std.mem.eql(u8, target, repo_root)) return .{
            .path = alias_path,
            .available = true,
        };
    }

    clearAliasPath(alias_path, "unable to clear package-root alias directory", "unable to clear package-root alias path");
    std.Io.Dir.symLinkAbsolute(b.graph.io, repo_root, alias_path, .{}) catch
        return .{ .path = repo_root, .available = false };
    return .{
        .path = alias_path,
        .available = true,
    };
}

fn zigStringLiteralEscapeAlloc(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var escaped = std.ArrayList(u8).empty;
    defer escaped.deinit(allocator);

    for (value) |byte| switch (byte) {
        '\\' => try escaped.appendSlice(allocator, "\\\\"),
        '"' => try escaped.appendSlice(allocator, "\\\""),
        '\n' => try escaped.appendSlice(allocator, "\\n"),
        '\r' => try escaped.appendSlice(allocator, "\\r"),
        '\t' => try escaped.appendSlice(allocator, "\\t"),
        else => try escaped.append(allocator, byte),
    };

    return try escaped.toOwnedSlice(allocator);
}

fn normalizeSourceForHashAlloc(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var in_string = false;
    var escaped = false;
    var idx: usize = 0;
    while (idx < source.len) : (idx += 1) {
        const byte = source[idx];
        if (in_string) {
            try out.append(allocator, byte);
            if (escaped) {
                escaped = false;
            } else if (byte == '\\') {
                escaped = true;
            } else if (byte == '"') {
                in_string = false;
            }
            continue;
        }

        if (byte == '"') {
            in_string = true;
            try out.append(allocator, byte);
            continue;
        }
        if (byte == '/' and idx + 1 < source.len and source[idx + 1] == '/') {
            idx += 2;
            while (idx < source.len and source[idx] != '\n') : (idx += 1) {}
            continue;
        }
        if (std.ascii.isWhitespace(byte)) continue;
        try out.append(allocator, byte);
    }

    return try out.toOwnedSlice(allocator);
}

test "zigStringLiteralEscapeAlloc escapes path bytes for generated fixture source" {
    const escaped = try zigStringLiteralEscapeAlloc(
        std.testing.allocator,
        "C:\\Users\\\"tk\"\\ability\\downstream_lowering_api_test.zig",
    );
    defer std.testing.allocator.free(escaped);

    try std.testing.expectEqualStrings(
        "C:\\\\Users\\\\\\\"tk\\\"\\\\ability\\\\downstream_lowering_api_test.zig",
        escaped,
    );
}

fn writeTmpFile(dir: std.Io.Dir, path: []const u8, contents: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |dir_name| {
        try dir.createDirPath(std.testing.io, dir_name);
    }
    try dir.writeFile(std.testing.io, .{
        .sub_path = path,
        .data = contents,
        .flags = .{ .truncate = true },
    });
}

fn writeTmpFileRepeatedByte(dir: std.Io.Dir, path: []const u8, byte: u8, len: usize) !void {
    if (std.Io.Dir.path.dirname(path)) |dir_name| {
        try dir.createDirPath(std.testing.io, dir_name);
    }

    var file = try dir.createFile(std.testing.io, path, .{});
    defer file.close(std.testing.io);

    var writer_buffer = std.mem.zeroes([1024]u8);
    var writer = file.writer(std.testing.io, &writer_buffer);
    var chunk = std.mem.zeroes([4096]u8);
    @memset(&chunk, byte);

    var remaining = len;
    while (remaining > 0) {
        const write_len = @min(remaining, chunk.len);
        try writer.interface.writeAll(chunk[0..write_len]);
        remaining -= write_len;
    }
    try writer.interface.flush();
}

fn runChildExpectSuccess(_: std.mem.Allocator, argv: []const []const u8) !void {
    var child = try std.process.spawn(std.testing.io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const term = try child.wait(std.testing.io);

    switch (term) {
        .exited => |code| if (code == 0) return,
        else => {},
    }
    std.debug.print("child command failed: {s}\n", .{argv[0]});
    return error.UnexpectedChildCommandFailure;
}

test "artifact build fingerprint changes on raw-byte-only Zig edits" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realPathFileAlloc(compatIo(), ".", std.testing.allocator);
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\pub fn main() void {
        \\    const self = @embedFile(@src().file);
        \\    _ = self;
        \\}
        \\
    );
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "probe.zig", "build.zig.zon" });

    const before = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "probe.zig",
        \\// whitespace/comment-only edit must still perturb exact-build identity
        \\pub fn main() void {
        \\    const self = @embedFile(@src().file);
        \\    _ = self;
        \\}
        \\
    );
    const after = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before, &after));
}

test "artifact build fingerprint includes embedded non-Zig inputs and excludes untracked Zig scratch" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realPathFileAlloc(compatIo(), ".", std.testing.allocator);
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\pub fn main() void {
        \\    const schema = @embedFile("schema.json");
        \\    _ = schema;
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "schema.json", "{ \"version\": 1 }\n");
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "probe.zig", "build.zig.zon" });

    const before_asset = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "schema.json", "{ \"version\": 2 }\n");
    const after_asset = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before_asset, &after_asset));

    const before_untracked_zig = after_asset;
    try writeTmpFile(tmp.dir, "helper.zig",
        \\pub fn helper() void {}
        \\
    );
    const after_untracked_zig = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expectEqualSlices(u8, &before_untracked_zig, &after_untracked_zig);
}

test "artifact build fingerprint excludes generated ability_agent_vm artifact self-input" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realPathFileAlloc(compatIo(), ".", std.testing.allocator);
    defer std.testing.allocator.free(repo_root);

    try tmp.dir.createDirPath(compatIo(), "test/fixtures");
    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\pub fn main() void {
        \\    const artifact = @embedFile("test/fixtures/ability_agent_vm_smoke.artifact");
        \\    _ = artifact;
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "test/fixtures/ability_agent_vm_smoke.artifact", "artifact-v1\n");
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "probe.zig", "build.zig.zon" });

    const before = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "test/fixtures/ability_agent_vm_smoke.artifact", "artifact-v2\n");
    const after = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expectEqualSlices(u8, &before, &after);
}

test "generated ability_agent_vm artifact exclusion matches native separator spelling" {
    try std.testing.expect(repoRelativePathEqlWithSeparator(
        "test\\fixtures\\ability_agent_vm_smoke.artifact",
        agent_vm_artifact_path,
        '\\',
    ));
    try std.testing.expect(!repoRelativePathEqlWithSeparator(
        "test\\fixtures\\other.artifact",
        agent_vm_artifact_path,
        '\\',
    ));
}

test "artifact build fingerprint includes embedded inputs larger than 16 MiB" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realPathFileAlloc(compatIo(), ".", std.testing.allocator);
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\pub fn main() void {
        \\    const blob = @embedFile("large.bin");
        \\    _ = blob;
        \\}
        \\
    );
    try writeTmpFileRepeatedByte(tmp.dir, "large.bin", 'a', 16 * 1024 * 1024 + 1);
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "probe.zig", "build.zig.zon" });

    const before = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFileRepeatedByte(tmp.dir, "large.bin", 'b', 16 * 1024 * 1024 + 1);
    const after = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before, &after));
}

test "artifact build fingerprint excludes non-dotted Zig cache roots" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realPathFileAlloc(compatIo(), ".", std.testing.allocator);
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\pub fn main() void {
        \\    const self = @embedFile(@src().file);
        \\    _ = self;
        \\}
        \\
    );
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "probe.zig", "build.zig.zon" });

    const before = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "zig-cache/generated.zig",
        \\pub fn ignored() void {}
        \\
    );
    try writeTmpFile(tmp.dir, "zig-global-cache/generated.zig",
        \\pub fn ignored() void {}
        \\
    );
    const after = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expectEqualSlices(u8, &before, &after);
}

test "artifact build fingerprint includes imported untracked Zig inputs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realPathFileAlloc(compatIo(), ".", std.testing.allocator);
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\const helper = @import("helper.zig");
        \\
        \\pub fn main() void {
        \\    helper.touch();
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "helper.zig",
        \\pub fn touch() void {}
        \\
    );
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "probe.zig", "build.zig.zon" });

    const before = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "helper.zig",
        \\pub fn touch() void {
        \\    _ = 1;
        \\}
        \\
    );
    const after = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before, &after));
}

test "artifact build fingerprint includes build.zig-wired untracked Zig modules" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realPathFileAlloc(compatIo(), ".", std.testing.allocator);
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const helper = b.addModule("helper", .{
        \\        .root_source_file = b.path("helper.zig"),
        \\    });
        \\    const probe = b.addModule("probe", .{
        \\        .root_source_file = b.path("probe.zig"),
        \\    });
        \\    probe.addImport("helper", helper);
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\const helper = @import("helper");
        \\
        \\pub fn main() void {
        \\    helper.touch();
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "helper.zig",
        \\pub fn touch() void {}
        \\
    );
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "build.zig", "build.zig.zon", "probe.zig" });

    const before = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "helper.zig",
        \\pub fn touch() void {
        \\    _ = 1;
        \\}
        \\
    );
    const after = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before, &after));
}

test "artifact build fingerprint includes build.zig-wired module-name helper wrapper embed inputs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realPathFileAlloc(compatIo(), ".", std.testing.allocator);
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const helper = b.addModule("helper", .{
        \\        .root_source_file = b.path("helpers/helper.zig"),
        \\    });
        \\    const probe = b.addModule("probe", .{
        \\        .root_source_file = b.path("probe.zig"),
        \\    });
        \\    probe.addImport("helper", helper);
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\const helper = @import("helper");
        \\
        \\pub fn main() void {
        \\    const schema = helper.fixture("schema.json");
        \\    _ = schema;
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "helpers/helper.zig",
        \\pub fn fixture(comptime rel: []const u8) []const u8 {
        \\    return @embedFile(rel);
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "helpers/schema.json", "{ \"version\": 1 }\n");
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "build.zig", "build.zig.zon", "probe.zig" });

    const before = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "helpers/schema.json", "{ \"version\": 2 }\n");
    const after = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before, &after));
}

test "artifact build fingerprint includes same-file comptime parameter embed inputs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realPathFileAlloc(compatIo(), ".", std.testing.allocator);
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\fn fixture(comptime rel: []const u8) []const u8 {
        \\    return @embedFile(rel);
        \\}
        \\
        \\pub fn main() void {
        \\    const schema = fixture("schema.json");
        \\    _ = schema;
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "schema.json", "{ \"version\": 1 }\n");
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "probe.zig", "build.zig.zon" });

    const before = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "schema.json", "{ \"version\": 2 }\n");
    const after = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before, &after));
}

test "artifact build fingerprint includes imported helper wrapper embed inputs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realPathFileAlloc(compatIo(), ".", std.testing.allocator);
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\const helper = @import("helpers/helper.zig");
        \\
        \\pub fn main() void {
        \\    const schema = helper.fixture("schema.json");
        \\    _ = schema;
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "helpers/helper.zig",
        \\pub fn fixture(comptime rel: []const u8) []const u8 {
        \\    return @embedFile(rel);
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "helpers/schema.json", "{ \"version\": 1 }\n");
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "probe.zig", "build.zig.zon" });

    const before = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "helpers/schema.json", "{ \"version\": 2 }\n");
    const after = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before, &after));
}

test "artifact build fingerprint includes identifier-backed embed inputs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realPathFileAlloc(compatIo(), ".", std.testing.allocator);
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\const direct_path = "direct.json";
        \\const wrapped_path = "wrapped.json";
        \\
        \\fn fixture(comptime rel: []const u8) []const u8 {
        \\    return @embedFile(rel);
        \\}
        \\
        \\pub fn main() void {
        \\    const direct = @embedFile(direct_path);
        \\    const wrapped = fixture(wrapped_path);
        \\    _ = direct;
        \\    _ = wrapped;
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "direct.json", "{ \"version\": 1 }\n");
    try writeTmpFile(tmp.dir, "wrapped.json", "{ \"version\": 1 }\n");
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "probe.zig", "build.zig.zon" });

    const before_direct = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "direct.json", "{ \"version\": 2 }\n");
    const after_direct = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before_direct, &after_direct));

    const before_wrapped = after_direct;
    try writeTmpFile(tmp.dir, "wrapped.json", "{ \"version\": 2 }\n");
    const after_wrapped = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before_wrapped, &after_wrapped));
}

test "artifact build fingerprint prefers the nearest visible identifier-backed embed binding" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realPathFileAlloc(compatIo(), ".", std.testing.allocator);
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\const fixture_path = "outer.json";
        \\
        \\fn fixture(comptime rel: []const u8) []const u8 {
        \\    return @embedFile(rel);
        \\}
        \\
        \\pub fn main() void {
        \\    const fixture_path = "inner.json";
        \\    const direct = @embedFile(fixture_path);
        \\    const wrapped = fixture(fixture_path);
        \\    _ = direct;
        \\    _ = wrapped;
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "outer.json", "{ \"version\": 1 }\n");
    try writeTmpFile(tmp.dir, "inner.json", "{ \"version\": 1 }\n");
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "probe.zig", "build.zig.zon" });

    const before_outer = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "outer.json", "{ \"version\": 2 }\n");
    const after_outer = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expectEqualSlices(u8, &before_outer, &after_outer);

    try writeTmpFile(tmp.dir, "inner.json", "{ \"version\": 2 }\n");
    const after_inner = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &after_outer, &after_inner));
}

test "artifact build fingerprint includes top-level forward alias embed inputs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realPathFileAlloc(compatIo(), ".", std.testing.allocator);
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\const direct_path = schema_path;
        \\const schema_path = "schema.json";
        \\
        \\pub fn main() void {
        \\    const schema = @embedFile(direct_path);
        \\    _ = schema;
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "schema.json", "{ \"version\": 1 }\n");
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "probe.zig", "build.zig.zon" });

    const before = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "schema.json", "{ \"version\": 2 }\n");
    const after = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before, &after));
}

test "repo Zig path registry falls back to filesystem when git metadata is unavailable" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realPathFileAlloc(compatIo(), ".", std.testing.allocator);
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(_: *std.Build) void {}
        \\
    );
    try writeTmpFile(tmp.dir, "src/probe.zig",
        \\pub fn touch() void {}
        \\
    );

    const registry = repoZigPathRegistryAlloc(std.testing.allocator, repo_root);
    defer std.testing.allocator.free(registry);

    try std.testing.expectEqualStrings(
        \\build.zig
        \\src/probe.zig
        \\
    , registry);
}

test "repo Zig path registry prefers tracked git paths over filesystem backup" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realPathFileAlloc(compatIo(), ".", std.testing.allocator);
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(_: *std.Build) void {}
        \\
    );
    try writeTmpFile(tmp.dir, "live.zig",
        \\pub fn live() void {}
        \\
    );
    try writeTmpFile(tmp.dir, "deleted.zig",
        \\pub fn deleted() void {}
        \\
    );
    try writeTmpFile(tmp.dir, "scratch.zig",
        \\pub fn scratch() void {}
        \\
    );

    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "build.zig", "live.zig", "deleted.zig" });
    try tmp.dir.deleteFile(compatIo(), "deleted.zig");

    const registry = repoZigPathRegistryAlloc(std.testing.allocator, repo_root);
    defer std.testing.allocator.free(registry);

    try std.testing.expectEqualStrings(
        \\build.zig
        \\live.zig
        \\
    , registry);
}

test "repo Zig path registry matches tracked Zig files in the working checkout" {
    const repo_root = try std.process.currentPathAlloc(compatIo(), std.testing.allocator);
    defer std.testing.allocator.free(repo_root);

    const tracked_registry = repoZigPathRegistryAlloc(std.testing.allocator, repo_root);
    defer std.testing.allocator.free(tracked_registry);

    const tracked = try std.process.run(std.testing.allocator, childProcessIo(), .{
        .argv = &.{ "git", "-C", repo_root, "ls-files", "--cached", "--", "*.zig" },
        .stdout_limit = .limited(512 * 1024),
        .stderr_limit = .limited(512 * 1024),
    });
    defer std.testing.allocator.free(tracked.stdout);
    defer std.testing.allocator.free(tracked.stderr);

    switch (tracked.term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.GitLsFilesFailed,
    }

    try std.testing.expect(tracked_registry.len != 0);
    try std.testing.expect(std.mem.find(u8, tracked_registry, "build.zig\n") != null);
    try std.testing.expect(std.mem.find(u8, tracked_registry, "source_graph_embed.zig\n") != null);
    var registry_lines = std.mem.tokenizeScalar(u8, tracked_registry, '\n');
    while (registry_lines.next()) |line| {
        try std.testing.expect(std.mem.findScalar(u8, line, '\n') == null);
        try std.testing.expect(std.mem.findScalar(u8, line, '\r') == null);
        const line_with_separator = try std.mem.concat(std.testing.allocator, u8, &.{ line, "\n" });
        defer std.testing.allocator.free(line_with_separator);
        try std.testing.expect(std.mem.find(u8, tracked.stdout, line_with_separator) != null);
    }
}

test "repo Zig lint CLI args include tracked files explicitly" {
    const args = try repoZigLintCliArgsFromRegistryAlloc(
        std.testing.allocator,
        \\build.zig
        \\src/error_witness.zig
        \\src/with_api.zig
        \\tmp.scratch/main.zig
        \\
    ,
        &.{ "--max-warnings", "0" },
    );
    defer std.testing.allocator.free(args);

    try std.testing.expectEqual(@as(usize, 6), args.len);
    try std.testing.expectEqualStrings("--include", args[0]);
    try std.testing.expectEqualStrings("build.zig", args[1]);
    try std.testing.expectEqualStrings("--include", args[2]);
    try std.testing.expectEqualStrings("src/with_api.zig", args[3]);
    try std.testing.expectEqualStrings("--max-warnings", args[4]);
    try std.testing.expectEqualStrings("0", args[5]);
}

test "test suite selection accepts trimmed multi-suite lists" {
    const specs = [_]TestSuiteSpec{
        .{ .suite_id = "alpha", .description = "alpha suite" },
        .{ .suite_id = "beta", .description = "beta suite" },
        .{ .suite_id = "gamma", .description = "gamma suite" },
    };
    const result = try parseTestSuiteSelectionAlloc(std.testing.allocator, " alpha, gamma ", &specs);
    switch (result) {
        .selection => |selection| {
            defer selection.deinit();
            try std.testing.expect(selection.isEnabled(0));
            try std.testing.expect(!selection.isEnabled(1));
            try std.testing.expect(selection.isEnabled(2));
        },
        else => return error.UnexpectedSelectionParseResult,
    }
}

test "test suite selection defaults to all suites when unspecified" {
    const specs = [_]TestSuiteSpec{
        .{ .suite_id = "alpha", .description = "alpha suite" },
        .{ .suite_id = "beta", .description = "beta suite" },
    };
    const result = try parseTestSuiteSelectionAlloc(std.testing.allocator, null, &specs);
    switch (result) {
        .selection => |selection| {
            defer selection.deinit();
            try std.testing.expect(selection.isEnabled(0));
            try std.testing.expect(selection.isEnabled(1));
        },
        else => return error.UnexpectedSelectionParseResult,
    }
}

test "test suite selection respects default_enabled when unspecified" {
    const specs = [_]TestSuiteSpec{
        .{ .suite_id = "alpha", .description = "alpha suite" },
        .{ .suite_id = "beta", .description = "beta suite", .default_enabled = false },
        .{ .suite_id = "gamma", .description = "gamma suite" },
    };
    const result = try parseTestSuiteSelectionAlloc(std.testing.allocator, null, &specs);
    switch (result) {
        .selection => |selection| {
            defer selection.deinit();
            try std.testing.expect(selection.isEnabled(0));
            try std.testing.expect(!selection.isEnabled(1));
            try std.testing.expect(selection.isEnabled(2));
        },
        else => return error.UnexpectedSelectionParseResult,
    }
}

test "test suite selection rejects empty tokens" {
    const specs = [_]TestSuiteSpec{
        .{ .suite_id = "alpha", .description = "alpha suite" },
        .{ .suite_id = "beta", .description = "beta suite" },
    };
    const result = try parseTestSuiteSelectionAlloc(std.testing.allocator, "alpha,,beta", &specs);
    try std.testing.expect(result == .empty_token);
}

test "test suite selection rejects duplicate suite ids" {
    const specs = [_]TestSuiteSpec{
        .{ .suite_id = "alpha", .description = "alpha suite" },
        .{ .suite_id = "beta", .description = "beta suite" },
    };
    const result = try parseTestSuiteSelectionAlloc(std.testing.allocator, "alpha, alpha", &specs);
    switch (result) {
        .duplicate => |id| try std.testing.expectEqualStrings("alpha", id),
        else => return error.UnexpectedSelectionParseResult,
    }
}

test "test suite selection rejects unknown suite ids" {
    const specs = [_]TestSuiteSpec{
        .{ .suite_id = "alpha", .description = "alpha suite" },
        .{ .suite_id = "beta", .description = "beta suite" },
    };
    const result = try parseTestSuiteSelectionAlloc(std.testing.allocator, "alpha, gamma", &specs);
    switch (result) {
        .unknown => |id| try std.testing.expectEqualStrings("gamma", id),
        else => return error.UnexpectedSelectionParseResult,
    }
}

test "test suite selection still validates raw option when test step not requested" {
    const specs = [_]TestSuiteSpec{
        .{ .suite_id = "alpha", .description = "alpha suite" },
        .{ .suite_id = "beta", .description = "beta suite" },
    };
    const result = try parseRequestedTestSuiteSelectionAlloc(
        std.testing.allocator,
        "does-not-exist",
        &specs,
        false,
    );
    switch (result) {
        .unknown => |id| try std.testing.expectEqualStrings("does-not-exist", id),
        else => return error.UnexpectedSelectionParseResult,
    }
}

test "test suite selection ignores raw option during discovery without test execution" {
    try std.testing.expectEqual(
        @as(?[]const u8, null),
        testSuiteSelectionRawForValidation("does-not-exist", false, true),
    );
    try std.testing.expectEqualStrings(
        "alpha",
        testSuiteSelectionRawForValidation("alpha", false, false).?,
    );
    try std.testing.expectEqualStrings(
        "alpha",
        testSuiteSelectionRawForValidation("alpha", true, true).?,
    );
}

test "test runner args accept split and equals filter forms" {
    const result = try parseTestRunnerArgsAlloc(
        std.testing.allocator,
        &.{ "--test-filter", "alpha beta", "--test-filter=gamma" },
        .strict,
    );
    switch (result) {
        .args => |test_runner_args| {
            defer test_runner_args.deinit();
            try std.testing.expectEqual(@as(usize, 2), test_runner_args.filters.items.len);
            try std.testing.expectEqualStrings("alpha beta", test_runner_args.filters.items[0]);
            try std.testing.expectEqualStrings("gamma", test_runner_args.filters.items[1]);
            try std.testing.expectEqual(@as(usize, 0), test_runner_args.passthrough.items.len);
        },
        else => return error.UnexpectedFilterParseResult,
    }
}

test "test runner args normalize supported runner passthrough args while consuming build-only timeout args" {
    const result = try parseTestRunnerArgsAlloc(
        std.testing.allocator,
        &.{ "--seed", "123", "--cache-dir", "zig-cache", "--test-timeout", "10", "--test-timeout=500ms" },
        .strict,
    );
    switch (result) {
        .args => |test_runner_args| {
            defer test_runner_args.deinit();
            try std.testing.expectEqual(@as(usize, 0), test_runner_args.filters.items.len);
            try std.testing.expectEqual(@as(usize, 2), test_runner_args.passthrough.items.len);
            try std.testing.expectEqualStrings("--seed=123", test_runner_args.passthrough.items[0]);
            try std.testing.expectEqualStrings("--cache-dir=zig-cache", test_runner_args.passthrough.items[1]);
        },
        else => return error.UnexpectedFilterParseResult,
    }
}

test "test runner args accept supported runner passthrough flags without values" {
    const result = try parseTestRunnerArgsAlloc(std.testing.allocator, &.{"--listen=-"}, .strict);
    switch (result) {
        .args => |test_runner_args| {
            defer test_runner_args.deinit();
            try std.testing.expectEqual(@as(usize, 0), test_runner_args.filters.items.len);
            try std.testing.expectEqual(@as(usize, 1), test_runner_args.passthrough.items.len);
            try std.testing.expectEqualStrings("--listen=-", test_runner_args.passthrough.items[0]);
        },
        else => return error.UnexpectedFilterParseResult,
    }
}

test "test runner args split filters from passthrough args" {
    const result = try parseTestRunnerArgsAlloc(
        std.testing.allocator,
        &.{ "--seed", "123", "--test-filter", "alpha beta", "--test-filter=gamma" },
        .strict,
    );
    switch (result) {
        .args => |test_runner_args| {
            defer test_runner_args.deinit();
            try std.testing.expectEqual(@as(usize, 2), test_runner_args.filters.items.len);
            try std.testing.expectEqualStrings("alpha beta", test_runner_args.filters.items[0]);
            try std.testing.expectEqualStrings("gamma", test_runner_args.filters.items[1]);
            try std.testing.expectEqual(@as(usize, 1), test_runner_args.passthrough.items.len);
            try std.testing.expectEqualStrings("--seed=123", test_runner_args.passthrough.items[0]);
        },
        else => return error.UnexpectedFilterParseResult,
    }
}

test "test runner args reject missing patterns" {
    const result = try parseTestRunnerArgsAlloc(std.testing.allocator, &.{"--test-filter"}, .strict);
    try std.testing.expect(result == .missing_pattern);
}

test "test runner args reject split filter when next token is another flag" {
    const result = try parseTestRunnerArgsAlloc(
        std.testing.allocator,
        &.{ "--test-filter", "--seed=123" },
        .strict,
    );
    try std.testing.expect(result == .missing_pattern);
}

test "test runner args reject split passthrough args without values" {
    const args = [_][]const u8{ "--seed", "--test-filter", "alpha", "--cache-dir", "--test-filter=beta" };
    const seed_result = try parseTestRunnerArgsAlloc(std.testing.allocator, args[0..3], .strict);
    switch (seed_result) {
        .missing_passthrough_value => |arg| try std.testing.expectEqualStrings("--seed", arg),
        else => return error.UnexpectedFilterParseResult,
    }

    const cache_dir_result = try parseTestRunnerArgsAlloc(
        std.testing.allocator,
        &.{ "--test-filter", "alpha", "--cache-dir", "--test-filter=beta" },
        .strict,
    );
    switch (cache_dir_result) {
        .missing_passthrough_value => |arg| try std.testing.expectEqualStrings("--cache-dir", arg),
        else => return error.UnexpectedFilterParseResult,
    }
}

test "test runner args reject split passthrough args with omitted trailing values" {
    const seed_result = try parseTestRunnerArgsAlloc(std.testing.allocator, &.{"--seed"}, .strict);
    switch (seed_result) {
        .missing_passthrough_value => |arg| try std.testing.expectEqualStrings("--seed", arg),
        else => return error.UnexpectedFilterParseResult,
    }

    const cache_dir_result = try parseTestRunnerArgsAlloc(std.testing.allocator, &.{"--cache-dir"}, .strict);
    switch (cache_dir_result) {
        .missing_passthrough_value => |arg| try std.testing.expectEqualStrings("--cache-dir", arg),
        else => return error.UnexpectedFilterParseResult,
    }
}

test "test runner args reject invalid seed values in both supported forms" {
    const split_result = try parseTestRunnerArgsAlloc(std.testing.allocator, &.{ "--seed", "abc" }, .strict);
    switch (split_result) {
        .invalid_seed_value => |value| try std.testing.expectEqualStrings("abc", value),
        else => return error.UnexpectedFilterParseResult,
    }

    const attached_result = try parseTestRunnerArgsAlloc(std.testing.allocator, &.{"--seed=abc"}, .strict);
    switch (attached_result) {
        .invalid_seed_value => |value| try std.testing.expectEqualStrings("abc", value),
        else => return error.UnexpectedFilterParseResult,
    }
}

test "test runner args reject unsupported post-double-dash args" {
    const result = try parseTestRunnerArgsAlloc(std.testing.allocator, &.{"--test-filtre=foo"}, .strict);
    switch (result) {
        .unknown_arg => |arg| try std.testing.expectEqualStrings("--test-filtre=foo", arg),
        else => return error.UnexpectedFilterParseResult,
    }
}

test "test runner args allow dash-prefixed split values" {
    const result = try parseTestRunnerArgsAlloc(
        std.testing.allocator,
        &.{ "--test-filter", "-foo", "--cache-dir", "-tmp" },
        .strict,
    );
    switch (result) {
        .args => |test_runner_args| {
            defer test_runner_args.deinit();
            try std.testing.expectEqual(@as(usize, 1), test_runner_args.filters.items.len);
            try std.testing.expectEqualStrings("-foo", test_runner_args.filters.items[0]);
            try std.testing.expectEqual(@as(usize, 1), test_runner_args.passthrough.items.len);
            try std.testing.expectEqualStrings("--cache-dir=-tmp", test_runner_args.passthrough.items[0]);
        },
        else => return error.UnexpectedFilterParseResult,
    }
}

test "test runner args can ignore foreign shared-tail args while still applying recognized test args" {
    const result = try parseTestRunnerArgsAlloc(
        std.testing.allocator,
        &.{ "--max-warnings", "0", "--seed", "123", "--test-filter=alpha" },
        .allow_unknown_args,
    );
    switch (result) {
        .args => |test_runner_args| {
            defer test_runner_args.deinit();
            try std.testing.expectEqual(@as(usize, 1), test_runner_args.filters.items.len);
            try std.testing.expectEqualStrings("alpha", test_runner_args.filters.items[0]);
            try std.testing.expectEqual(@as(usize, 1), test_runner_args.passthrough.items.len);
            try std.testing.expectEqualStrings("--seed=123", test_runner_args.passthrough.items[0]);
        },
        else => return error.UnexpectedFilterParseResult,
    }
}

test "test runner args still reject malformed recognized args when foreign shared-tail args are present" {
    const result = try parseTestRunnerArgsAlloc(
        std.testing.allocator,
        &.{ "--max-warnings", "0", "--seed", "abc" },
        .allow_unknown_args,
    );
    switch (result) {
        .invalid_seed_value => |value| try std.testing.expectEqualStrings("abc", value),
        else => return error.UnexpectedFilterParseResult,
    }
}

test "suite default filters are narrowed by explicit user test filters" {
    const default_filters = [_][]const u8{
        "private regression alpha",
        "private regression beta",
    };
    const no_match_filters = [_][]const u8{"private regression no-match sentinel"};

    const no_user_filters = try defaultSuiteFiltersForUserFiltersAlloc(
        std.testing.allocator,
        &.{},
        &default_filters,
        &no_match_filters,
    );
    defer std.testing.allocator.free(no_user_filters);
    try std.testing.expectEqual(@as(usize, 2), no_user_filters.len);
    try std.testing.expectEqualStrings("private regression alpha", no_user_filters[0]);
    try std.testing.expectEqualStrings("private regression beta", no_user_filters[1]);

    const user_filters = [_][]const u8{"alpha"};
    const selected_filters = try defaultSuiteFiltersForUserFiltersAlloc(
        std.testing.allocator,
        &user_filters,
        &default_filters,
        &no_match_filters,
    );
    defer std.testing.allocator.free(selected_filters);
    try std.testing.expectEqual(@as(usize, 1), selected_filters.len);
    try std.testing.expectEqualStrings("private regression alpha", selected_filters[0]);

    const full_name_filters = [_][]const u8{"prefix private regression beta suffix"};
    const full_name_selected_filters = try defaultSuiteFiltersForUserFiltersAlloc(
        std.testing.allocator,
        &full_name_filters,
        &default_filters,
        &no_match_filters,
    );
    defer std.testing.allocator.free(full_name_selected_filters);
    try std.testing.expectEqual(@as(usize, 1), full_name_selected_filters.len);
    try std.testing.expectEqualStrings("private regression beta", full_name_selected_filters[0]);
}

test "suite default filters use no-match sentinel when user filters miss bounded defaults" {
    const default_filters = [_][]const u8{
        "private regression alpha",
        "private regression beta",
    };
    const no_match_filters = [_][]const u8{"private regression no-match sentinel"};
    const user_filters = [_][]const u8{"broad private regression"};
    const selected_filters = try defaultSuiteFiltersForUserFiltersAlloc(
        std.testing.allocator,
        &user_filters,
        &default_filters,
        &no_match_filters,
    );
    defer std.testing.allocator.free(selected_filters);
    try std.testing.expectEqual(@as(usize, 1), selected_filters.len);
    try std.testing.expectEqualStrings("private regression no-match sentinel", selected_filters[0]);
}

test "lint shared-tail args keep lint-owned flags while stripping recognized test args" {
    const filtered_args = try lintSharedTailArgsAlloc(
        std.testing.allocator,
        &.{ "--max-warnings", "0", "--test-filter=alpha", "--seed", "123", "--listen=-", "--cache-dir", "zig-cache", "--test-timeout", "10", "--test-timeout=500ms" },
        true,
    );
    defer std.testing.allocator.free(filtered_args);

    try std.testing.expectEqual(@as(usize, 2), filtered_args.len);
    try std.testing.expectEqualStrings("--max-warnings", filtered_args[0]);
    try std.testing.expectEqualStrings("0", filtered_args[1]);
}

test "lint shared-tail args preserve unknown args for fail-closed mixed-step validation" {
    const filtered_args = try lintSharedTailArgsAlloc(
        std.testing.allocator,
        &.{ "--max-warnings", "0", "--bogus", "--test-filter=alpha" },
        true,
    );
    defer std.testing.allocator.free(filtered_args);

    try std.testing.expectEqual(@as(usize, 3), filtered_args.len);
    try std.testing.expectEqualStrings("--max-warnings", filtered_args[0]);
    try std.testing.expectEqualStrings("0", filtered_args[1]);
    try std.testing.expectEqualStrings("--bogus", filtered_args[2]);
}

test "fixture generator shared-tail args strip sibling test args in mixed invocations" {
    const filtered_args = try fixtureGeneratorSharedTailArgsAlloc(
        std.testing.allocator,
        &.{ "--test-filter", "host-log", "--seed=123", "--check" },
        true,
        false,
    );
    defer std.testing.allocator.free(filtered_args);

    try std.testing.expectEqual(@as(usize, 1), filtered_args.len);
    try std.testing.expectEqualStrings("--check", filtered_args[0]);
}

test "fixture generator shared-tail args strip sibling lint and test args while preserving unknowns" {
    const filtered_args = try fixtureGeneratorSharedTailArgsAlloc(
        std.testing.allocator,
        &.{ "--max-warnings", "0", "--test-filter=host-log", "--bogus" },
        true,
        true,
    );
    defer std.testing.allocator.free(filtered_args);

    try std.testing.expectEqual(@as(usize, 1), filtered_args.len);
    try std.testing.expectEqualStrings("--bogus", filtered_args[0]);
}

test "build invocation step detection ignores option values" {
    const prefix_args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "-p",
        "test",
        "source-lower",
        "--",
        "--bogus",
    };
    try std.testing.expect(!buildInvocationRequestsStepInArgs(&prefix_args, "test"));
    try std.testing.expect(buildInvocationRequestsStepInArgs(&prefix_args, "source-lower"));

    const maxrss_args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "--maxrss",
        "test",
        "source-lower",
    };
    try std.testing.expect(!buildInvocationRequestsStepInArgs(&maxrss_args, "test"));
    try std.testing.expect(buildInvocationRequestsStepInArgs(&maxrss_args, "source-lower"));
}

test "build invocation step detection ignores long prefix values before non-test steps" {
    const args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "--prefix",
        "test",
        "lint",
        "--",
        "--max-warnings",
        "0",
    };
    try std.testing.expect(!buildInvocationRequestsStepInArgs(&args, "test"));
    try std.testing.expect(buildInvocationRequestsStepInArgs(&args, "lint"));
}

test "build invocation step detection finds explicit test step after options" {
    const args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "--summary",
        "none",
        "test",
        "--",
        "--test-filter=alpha",
    };
    try std.testing.expect(buildInvocationRequestsStepInArgs(&args, "test"));
}

test "build invocation step detection does not skip test after bare optional-value flags" {
    const args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "--release",
        "test",
        "-Dtest-suites=root",
    };
    try std.testing.expect(buildInvocationRequestsStepInArgs(&args, "test"));
}

test "build invocation step detection skips optional-value arguments when present" {
    const release_args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "--release",
        "fast",
        "test",
    };
    try std.testing.expect(buildInvocationRequestsStepInArgs(&release_args, "test"));

    const fetch_args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "--fetch",
        "all",
        "test",
    };
    try std.testing.expect(buildInvocationRequestsStepInArgs(&fetch_args, "test"));

    const reference_trace_args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "-freference-trace",
        "7",
        "test",
    };
    try std.testing.expect(buildInvocationRequestsStepInArgs(&reference_trace_args, "test"));

    const build_id_args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "--build-id",
        "uuid",
        "test",
    };
    try std.testing.expect(buildInvocationRequestsStepInArgs(&build_id_args, "test"));
}

test "build invocation step detection does not skip test after flags without values" {
    const args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "--verbose-llvm-bc",
        "test",
    };
    try std.testing.expect(buildInvocationRequestsStepInArgs(&args, "test"));
}

test "build invocation step detection consumes the --debug-log scope" {
    const args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "--debug-log",
        "scope",
        "test",
        "--",
        "--seed=123",
    };
    try std.testing.expect(buildInvocationRequestsStepInArgs(&args, "test"));
}

test "build invocation step detection keeps build-runner-visible --system from swallowing the test step" {
    const args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "--system",
        "test",
        "--",
        "--seed=123",
    };
    try std.testing.expect(buildInvocationRequestsStepInArgs(&args, "test"));
}

test "build invocation Linux cmdline read limit stays explicit and bounded" {
    try std.testing.expect(max_cmdline_bytes >= 4096);
    try std.testing.expect(max_cmdline_bytes > 4 * 1024 * 1024);
    try std.testing.expect(max_cmdline_bytes > linux_max_argv_env_bytes);
    try std.testing.expect(max_cmdline_bytes < std.math.maxInt(usize));
}

test "build invocation step detection still finds test in mixed-step invocations" {
    const args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "test",
        "source-lower",
        "--",
        "--seed=123",
    };
    try std.testing.expect(buildInvocationRequestsStepInArgs(&args, "test"));
    try std.testing.expect(buildInvocationRequestsStepInArgs(&args, "source-lower"));
}

test "build invocation runnable step detection still finds mixed-step test invocations" {
    const args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "test",
        "source-lower",
        "--",
        "--seed=123",
    };
    try std.testing.expect(buildInvocationRequestsRunnableStepInArgs(&args, "test"));
}

test "build invocation runnable step detection skips discovery and fetch exit modes" {
    const help_args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "-h",
        "test",
        "--",
        "--test-filtre=foo",
    };
    try std.testing.expect(buildInvocationRequestsStepInArgs(&help_args, "test"));
    try std.testing.expect(!buildInvocationRequestsRunnableStepInArgs(&help_args, "test"));

    const list_args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "--list-steps",
        "test",
        "-Dtest-suites=does-not-exist",
    };
    try std.testing.expect(buildInvocationRequestsStepInArgs(&list_args, "test"));
    try std.testing.expect(!buildInvocationRequestsRunnableStepInArgs(&list_args, "test"));

    const fetch_args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "--fetch=all",
        "test",
        "-Dtest-suites=does-not-exist",
    };
    try std.testing.expect(buildInvocationRequestsStepInArgs(&fetch_args, "test"));
    try std.testing.expect(!buildInvocationRequestsRunnableStepInArgs(&fetch_args, "test"));
}

test "build invocation skip-step-execution ignores consumed option values" {
    const args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "-p",
        "-h",
        "test",
        "--",
        "--seed=123",
    };
    try std.testing.expect(!buildInvocationSkipsStepExecutionInArgs(&args));
    try std.testing.expect(buildInvocationRequestsRunnableStepInArgs(&args, "test"));
}

test "build invocation exclusive test detection rejects mixed-step invocations" {
    const args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "lint",
        "test",
        "--",
        "--max-warnings",
        "0",
    };
    try std.testing.expect(!buildInvocationRequestsOnlyStepInArgs(&args, "test"));
}

test "build invocation mixed-step test keeps runnable detection without claiming the shared tail" {
    const args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "lint",
        "test",
        "--",
        "--max-warnings",
        "0",
    };
    try std.testing.expect(buildInvocationRequestsRunnableStepInArgs(&args, "test"));
    try std.testing.expect(!buildInvocationRequestsOnlyStepInArgs(&args, "test"));
}

test "build invocation detection reports unavailable when argv inspection is unavailable" {
    try std.testing.expect(buildInvocationRequestsStepFromArgsResult(
        "test",
        error.UnsupportedHostBuildInvocationArgs,
    ) == null);
    try std.testing.expect(buildInvocationRequestsRunnableStepFromArgsResult(
        "test",
        error.UnsupportedHostBuildInvocationArgs,
    ) == null);
}

test "shared-tail invocation inference stays unknown when no shared-tail args are visible" {
    const inference = inferBuildInvocationFromSharedTail(null);
    try std.testing.expectEqual(@as(?bool, null), inference.test_requested);
    try std.testing.expectEqual(@as(?bool, null), inference.lint_requested);
}

test "shared-tail invocation inference recovers documented test args without argv inspection" {
    const inference = inferBuildInvocationFromSharedTail(&.{ "--seed", "123", "--test-filter=alpha" });
    try std.testing.expectEqual(@as(?bool, true), inference.test_requested);
    try std.testing.expectEqual(@as(?bool, false), inference.lint_requested);
}

test "shared-tail invocation inference recovers test timeout without argv inspection" {
    const inference = inferBuildInvocationFromSharedTail(&.{ "--test-timeout", "10" });
    try std.testing.expectEqual(@as(?bool, true), inference.test_requested);
    try std.testing.expectEqual(@as(?bool, false), inference.lint_requested);
}

test "shared-tail invocation inference recovers documented lint args without argv inspection" {
    const inference = inferBuildInvocationFromSharedTail(&.{ "--max-warnings", "0" });
    try std.testing.expectEqual(@as(?bool, false), inference.test_requested);
    try std.testing.expectEqual(@as(?bool, true), inference.lint_requested);
}

test "shared-tail invocation inference stays fail-closed on ambiguous unknown tails" {
    const inference = inferBuildInvocationFromSharedTail(&.{"--bogus"});
    try std.testing.expectEqual(@as(?bool, null), inference.test_requested);
    try std.testing.expectEqual(@as(?bool, null), inference.lint_requested);
}

test "shared-tail invocation inference stays fail-closed on mixed step signals" {
    const inference = inferBuildInvocationFromSharedTail(&.{ "--max-warnings", "0", "--seed", "123" });
    try std.testing.expectEqual(@as(?bool, null), inference.test_requested);
    try std.testing.expectEqual(@as(?bool, null), inference.lint_requested);
}

test "shared-tail no-tail guard defers unavailable argv when documented test tail owns the args" {
    const inference = inferBuildInvocationFromSharedTail(&.{ "--seed", "123" });
    const tail_owner_requested = buildInvocationSharedTailOwnerRequested(&.{ inference.test_requested, inference.lint_requested });

    try std.testing.expect(!unsupportedSharedTailForNoTailStep(
        &.{ "--seed", "123" },
        null,
        tail_owner_requested,
    ));
}

test "shared-tail no-tail guard rejects mixed no-tail steps without a tail owner" {
    const args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "source-lower",
        "check-ability-agent-vm-fixture",
        "--",
        "--bad",
    };
    const source_lower_requested: ?bool = buildInvocationRequestsStepInArgs(&args, "source-lower");
    const fixture_check_requested: ?bool = buildInvocationRequestsStepInArgs(&args, "check-ability-agent-vm-fixture");
    const tail_owner_requested = buildInvocationSharedTailOwnerRequested(&.{ false, false });

    try std.testing.expect(!buildInvocationRequestsOnlyStepInArgs(&args, "source-lower"));
    try std.testing.expect(!buildInvocationRequestsOnlyStepInArgs(&args, "check-ability-agent-vm-fixture"));
    try std.testing.expect(unsupportedSharedTailForNoTailStep(
        &.{"--bad"},
        source_lower_requested,
        tail_owner_requested,
    ));
    try std.testing.expect(unsupportedSharedTailForNoTailStep(
        &.{"--bad"},
        fixture_check_requested,
        tail_owner_requested,
    ));
}

test "shared-tail no-tail guard ignores discovery-mode no-tail steps" {
    const args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "--help",
        "source-lower",
        "--",
        "--bad",
    };
    const source_lower_requested: ?bool = buildInvocationRequestsRunnableStepInArgs(&args, "source-lower");
    const tail_owner_requested = buildInvocationSharedTailOwnerRequested(&.{ false, false });

    try std.testing.expect(buildInvocationSkipsStepExecutionInArgs(&args));
    try std.testing.expect(buildInvocationRequestsStepInArgs(&args, "source-lower"));
    try std.testing.expectEqual(@as(?bool, false), source_lower_requested);
    try std.testing.expect(!unsupportedSharedTailForNoTailStep(
        &.{"--bad"},
        source_lower_requested,
        tail_owner_requested,
    ));
}

test "shared-tail no-tail guard allows selected no-tail steps when a documented test step owns the args" {
    const args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "source-lower",
        "test",
        "--",
        "--seed",
        "123",
    };
    const source_lower_requested: ?bool = buildInvocationRequestsStepInArgs(&args, "source-lower");
    const test_requested: ?bool = buildInvocationRequestsRunnableStepInArgs(&args, "test");
    const tail_owner_requested = buildInvocationSharedTailOwnerRequested(&.{ test_requested, false });

    try std.testing.expectEqual(@as(?bool, true), source_lower_requested);
    try std.testing.expect(!unsupportedSharedTailForNoTailStep(
        &.{ "--seed", "123" },
        source_lower_requested,
        tail_owner_requested,
    ));
}

test "shared-tail no-tail guard allows selected no-tail steps when the fixture generator owns the args" {
    const args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "generate-ability-agent-vm-fixture",
        "source-lower",
        "--",
        "--help",
    };
    const fixture_generator_requested: ?bool = buildInvocationRequestsStepInArgs(&args, "generate-ability-agent-vm-fixture");
    const source_lower_requested: ?bool = buildInvocationRequestsStepInArgs(&args, "source-lower");
    const tail_owner_requested = buildInvocationSharedTailOwnerRequested(&.{ false, false, fixture_generator_requested });

    try std.testing.expectEqual(@as(?bool, true), fixture_generator_requested);
    try std.testing.expectEqual(@as(?bool, true), source_lower_requested);
    try std.testing.expect(!unsupportedSharedTailForNoTailStep(
        &.{"--help"},
        source_lower_requested,
        tail_owner_requested,
    ));
}

test "build invocation exclusive test detection accepts pure test invocations" {
    const args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "--summary",
        "none",
        "test",
        "--",
        "--test-filter=alpha",
    };
    try std.testing.expect(buildInvocationRequestsOnlyStepInArgs(&args, "test"));
}

test "build invocation exclusive test detection consumes the --debug-log scope" {
    const args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "--debug-log",
        "scope",
        "test",
        "--",
        "--seed=123",
    };
    try std.testing.expect(buildInvocationRequestsOnlyStepInArgs(&args, "test"));
}

test "build invocation exclusive test detection keeps build-runner-visible --system from swallowing the test step" {
    const args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "--system",
        "test",
        "--",
        "--seed=123",
    };
    try std.testing.expect(buildInvocationRequestsOnlyStepInArgs(&args, "test"));
}

test "build invocation exclusive test detection consumes the --glibc-runtimes alias value" {
    const args = [_][]const u8{
        "build-helper",
        "zig",
        "lib-dir",
        "build-root",
        "local-cache",
        "global-cache",
        "--glibc-runtimes",
        "runtimes-dir",
        "test",
        "--",
        "--seed=123",
    };
    try std.testing.expect(buildInvocationRequestsOnlyStepInArgs(&args, "test"));
}

/// Configure build, test, lint, example, and benchmark entrypoints for ability.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_suites_raw = b.option(
        []const u8,
        "test-suites",
        "Restrict `zig build test` to exact suite ids; README lists ids and invalid ids print them.",
    );
    const agent_vm_artifact_report_path = b.option(
        []const u8,
        "agent-vm-artifact",
        "ArtifactV1 payload to classify with `zig build run-agent-vm-artifact-report`.",
    );
    const artifact_report_format = b.option(
        []const u8,
        "agent-vm-artifact-format",
        "Output format for `zig build run-agent-vm-artifact-report`: text or json.",
    );
    const lint_verbose = b.option(
        bool,
        "lint-verbose",
        "Print verbose zlinter command output during `zig build lint`.",
    ) orelse false;
    const skip_execution = buildInvocationSkipsStepExecution();
    const test_requested_from_argv = buildInvocationRequestsRunnableStep("test");
    const lint_requested_from_argv = buildInvocationRequestsRunnableStep("lint");
    const source_lower_requested = buildInvocationRequestsRunnableStep("source-lower");
    const agent_vm_report_run_requested = buildInvocationRequestsRunnableStep("run-agent-vm-artifact-report");
    const fixture_check_requested = buildInvocationRequestsRunnableStep("check-ability-agent-vm-fixture");
    const fixture_generator_requested = buildInvocationRequestsRunnableStep("generate-ability-agent-vm-fixture");
    const bench_requested = buildInvocationRequestsRunnableStep("bench");
    const bench_first_requested = buildInvocationRequestsRunnableStep("bench-first-suspend");
    const bench_state_requested = buildInvocationRequestsRunnableStep("bench-state-effect");
    const bench_matrix_requested = buildInvocationRequestsRunnableStep("bench-family-matrix");
    const bench_backends_requested = buildInvocationRequestsRunnableStep("bench-runtime-backends");
    const zprof_hotspots_requested = buildInvocationRequestsRunnableStep("zprof-hotspots");
    const inferred_shared_tail = inferBuildInvocationFromSharedTail(b.args);
    const test_requested_opt = test_requested_from_argv orelse inferred_shared_tail.test_requested;
    const lint_requested_opt = lint_requested_from_argv orelse inferred_shared_tail.lint_requested;
    const shared_tail_owner_requested = buildInvocationSharedTailOwnerRequested(&.{ test_requested_opt, lint_requested_opt, fixture_generator_requested });
    rejectUnsupportedSharedTailForNoTailStep(b, source_lower_requested, shared_tail_owner_requested, "source-lower");
    rejectUnsupportedSharedTailForNoTailStep(b, agent_vm_report_run_requested, shared_tail_owner_requested, "run-agent-vm-artifact-report");
    rejectUnsupportedSharedTailForNoTailStep(b, fixture_check_requested, shared_tail_owner_requested, "check-ability-agent-vm-fixture");
    rejectUnsupportedSharedTailForNoTailStep(b, bench_requested, shared_tail_owner_requested, "bench");
    rejectUnsupportedSharedTailForNoTailStep(b, bench_first_requested, shared_tail_owner_requested, "bench-first-suspend");
    rejectUnsupportedSharedTailForNoTailStep(b, bench_state_requested, shared_tail_owner_requested, "bench-state-effect");
    rejectUnsupportedSharedTailForNoTailStep(b, bench_matrix_requested, shared_tail_owner_requested, "bench-family-matrix");
    rejectUnsupportedSharedTailForNoTailStep(b, bench_backends_requested, shared_tail_owner_requested, "bench-runtime-backends");
    rejectUnsupportedSharedTailForNoTailStep(b, zprof_hotspots_requested, shared_tail_owner_requested, "zprof-hotspots");
    if (agent_vm_report_run_requested == true and agent_vm_artifact_report_path == null) {
        std.log.err(
            "`zig build run-agent-vm-artifact-report` requires -Dagent-vm-artifact=<path>.",
            .{},
        );
        b.invalid_user_input = true;
        return;
    }
    if (agent_vm_report_run_requested == true) {
        if (artifact_report_format) |format| {
            if (!std.mem.eql(u8, format, "text") and !std.mem.eql(u8, format, "json")) {
                std.log.err(
                    "`-Dagent-vm-artifact-format` must be `text` or `json`; got `{s}`.",
                    .{format},
                );
                b.invalid_user_input = true;
                return;
            }
        }
    }
    const invocation_args_unknown = skip_execution != true and
        (test_requested_opt == null or lint_requested_opt == null);
    if (invocation_args_unknown and (b.args != null or hostBuildInvocationArgsSupported())) {
        std.process.fatal(
            "unable to attribute requested build steps or build runner post-`--` args on this host; rerun without shared-tail args or use a supported host",
            .{},
        );
    }
    const test_requested = test_requested_opt orelse (test_suites_raw != null);
    // Mixed `lint test -- ...` invocations must ignore unknown args while still honoring test flags.
    const strip_test_args_from_lint = test_requested and
        ((lint_requested_opt orelse false) or
            (lint_requested_from_argv == null and inferred_shared_tail.test_requested == true));
    const allow_foreign_shared_tail_args = test_requested and (lint_requested_opt orelse false);
    const lint_shared_tail_args = lintSharedTailArgsAlloc(b.allocator, b.args, strip_test_args_from_lint) catch |err|
        std.process.fatal("unable to prepare lint shared-tail args: {s}", .{@errorName(err)});
    defer b.allocator.free(lint_shared_tail_args);
    const test_runner_args = requireTestRunnerArgs(
        b,
        b.args,
        test_requested,
        allow_foreign_shared_tail_args,
    ) orelse return;
    const fixture_tail_args = fixtureGeneratorSharedTailArgsAlloc(
        b.allocator,
        b.args,
        test_requested,
        lint_requested_opt orelse false,
    ) catch |err|
        std.process.fatal("unable to prepare fixture generator shared-tail args: {s}", .{@errorName(err)});
    defer b.allocator.free(fixture_tail_args);
    // Compile and run steps retain these slices by reference, so they must live for the build graph lifetime.
    const bench_optimize: std.builtin.OptimizeMode = .ReleaseFast;

    absolutizeZlinterRuntimePaths(b);

    const ability_mod = b.addModule("ability", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ability_compile_mod = b.createModule(.{
        .root_source_file = b.path("src/private_modules/ability_compile.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ability_agent_vm_mod = b.addModule("ability_agent_vm", .{
        .root_source_file = b.path("src/ability_agent_vm.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ability_shared_mod = b.createModule(.{
        .root_source_file = b.path("src/ability_shared.zig"),
        .target = target,
        .optimize = optimize,
    });
    const synthetic_ability_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/synthetic_ability_root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const synthetic_lowering_host_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/synthetic_lowering_host.zig"),
        .target = target,
        .optimize = optimize,
    });
    const artifact_api_mod = b.createModule(.{
        .root_source_file = b.path("src/private_modules/agent_vm_artifact_build.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ir_api_mod = b.createModule(.{
        .root_source_file = b.path("src/ir_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lowering_api_mod = b.createModule(.{
        .root_source_file = b.path("src/lowering_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ability_compile_api_mod = b.createModule(.{
        .root_source_file = b.path("src/ability_compile_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    const private_host_adapter_v1_mod = b.createModule(.{
        .root_source_file = b.path("src/host_adapter_v1.zig"),
        .target = target,
        .optimize = optimize,
    });
    const private_artifact_vm_core_mod = b.createModule(.{
        .root_source_file = b.path("src/private_modules/artifact_vm_runtime_build.zig"),
        .target = target,
        .optimize = optimize,
    });
    const artifact_build_options = b.addOptions();
    artifact_build_options.addOption(
        [32]u8,
        "default_artifact_build_fingerprint",
        defaultArtifactBuildFingerprint(b, target, optimize),
    );
    artifact_api_mod.addOptions("artifact_build_options", artifact_build_options);
    const portable_core_mod = b.createModule(.{
        .root_source_file = b.path("src/portable_core.zig"),
        .target = target,
        .optimize = optimize,
    });
    const error_witness_mod = b.createModule(.{
        .root_source_file = b.path("src/error_witness.zig"),
        .target = target,
        .optimize = optimize,
    });
    const prompt_contract_support_mod = b.createModule(.{
        .root_source_file = b.path("src/prompt_contract.zig"),
        .target = target,
        .optimize = optimize,
    });
    const frontend_support_mod = b.createModule(.{
        .root_source_file = b.path("src/frontend.zig"),
        .target = target,
        .optimize = optimize,
    });
    prompt_contract_support_mod.addImport("portable_core", portable_core_mod);
    frontend_support_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    frontend_support_mod.addImport("portable_core", portable_core_mod);
    ability_mod.addImport("ability_shared", ability_shared_mod);
    ability_mod.addImport("portable_core", portable_core_mod);
    ability_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    ability_mod.addImport("frontend_support", frontend_support_mod);
    ability_mod.addImport("error_witness", error_witness_mod);
    const witnesses_mod = b.createModule(.{
        .root_source_file = b.path("src/witnesses.zig"),
        .target = target,
        .optimize = optimize,
    });
    const parity_scenarios_mod = b.createModule(.{
        .root_source_file = b.path("src/parity_scenarios.zig"),
        .target = target,
        .optimize = optimize,
    });
    ability_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const lowered_machine_mod = b.createModule(.{
        .root_source_file = b.path("src/private_modules/lowered_machine_build.zig"),
        .target = target,
        .optimize = optimize,
    });
    lowered_machine_mod.addImport("portable_core", portable_core_mod);
    synthetic_ability_mod.addImport("lowered_machine", lowered_machine_mod);
    synthetic_ability_mod.addImport("ability_shared", ability_shared_mod);
    synthetic_lowering_host_mod.addImport("synthetic_ability", synthetic_ability_mod);
    const effect_ir_mod = b.createModule(.{
        .root_source_file = b.path("src/effect_ir.zig"),
        .target = target,
        .optimize = optimize,
    });
    synthetic_lowering_host_mod.addImport("effect_ir", effect_ir_mod);
    const helper_body_ir_mod = b.createModule(.{
        .root_source_file = b.path("src/private_modules/helper_body_ir_build.zig"),
        .target = target,
        .optimize = optimize,
    });
    const admitted_body_v1_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/admitted_body_v1.zig"),
        .target = target,
        .optimize = optimize,
    });
    const source_graph_engine_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/source_graph_engine.zig"),
        .target = target,
        .optimize = optimize,
    });
    const internal_program_plan_mod = b.createModule(.{
        .root_source_file = b.path("src/private_modules/internal_program_plan_build.zig"),
        .target = target,
        .optimize = optimize,
    });
    internal_program_plan_mod.addImport("effect_ir", effect_ir_mod);
    helper_body_ir_mod.addImport("internal_program_plan", internal_program_plan_mod);
    helper_body_ir_mod.addImport("effect_ir", effect_ir_mod);
    const source_graph_comptime_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/source_graph_comptime.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_graph_comptime_mod.addImport("source_graph_engine", source_graph_engine_mod);
    source_graph_engine_mod.addImport("admitted_body_v1", admitted_body_v1_mod);
    const source_graph_embed_mod = b.createModule(.{
        .root_source_file = b.path("source_graph_embed.zig"),
        .target = target,
        .optimize = optimize,
    });
    const internal_kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/private_modules/internal_kernel_build.zig"),
        .target = target,
        .optimize = optimize,
    });
    internal_kernel_mod.addImport("parity_scenarios", parity_scenarios_mod);
    internal_kernel_mod.addImport("internal_program_plan", internal_program_plan_mod);
    const interpreter_mod = b.createModule(.{
        .root_source_file = b.path("src/interpreter.zig"),
        .target = target,
        .optimize = optimize,
    });
    interpreter_mod.addImport("parity_scenarios", parity_scenarios_mod);
    interpreter_mod.addImport("internal_kernel", internal_kernel_mod);
    ability_mod.addImport("effect_ir", effect_ir_mod);
    ability_mod.addImport("internal_kernel", internal_kernel_mod);
    ability_mod.addImport("internal_program_plan", internal_program_plan_mod);
    ability_mod.addImport("interpreter", interpreter_mod);
    ability_mod.addImport("source_graph_engine", source_graph_engine_mod);
    ability_mod.addImport("source_graph_comptime", source_graph_comptime_mod);
    artifact_api_mod.addImport("internal_program_plan", internal_program_plan_mod);
    ability_compile_api_mod.addImport("artifact_api", artifact_api_mod);
    ability_compile_mod.addImport("ability_shared", ability_shared_mod);
    ability_compile_mod.addImport("ability_compile_api", ability_compile_api_mod);
    private_artifact_vm_core_mod.addImport("artifact_api", artifact_api_mod);
    private_artifact_vm_core_mod.addImport("host_adapter_v1", private_host_adapter_v1_mod);
    private_artifact_vm_core_mod.addImport("internal_program_plan", internal_program_plan_mod);
    private_artifact_vm_core_mod.addImport("lowered_machine", lowered_machine_mod);
    private_artifact_vm_core_mod.addImport("internal_kernel", internal_kernel_mod);
    ability_agent_vm_mod.addImport("host_adapter_v1", private_host_adapter_v1_mod);
    ability_agent_vm_mod.addImport("artifact_vm_runtime", private_artifact_vm_core_mod);
    ability_agent_vm_mod.addImport("artifact_api", artifact_api_mod);
    ability_agent_vm_mod.addImport("internal_program_plan", internal_program_plan_mod);
    ability_agent_vm_mod.addImport("lowered_machine", lowered_machine_mod);
    ability_agent_vm_mod.addImport("internal_kernel", internal_kernel_mod);
    lowered_machine_mod.addImport("parity_scenarios", parity_scenarios_mod);
    lowered_machine_mod.addImport("internal_kernel", internal_kernel_mod);
    lowered_machine_mod.addImport("interpreter", interpreter_mod);
    const authoring_lowerer_options = b.addOptions();
    const package_root_alias = packageRootAlias(b);
    const lowerer_opts_marker = true;
    authoring_lowerer_options.addOption([]const u8, "package_root", b.pathFromRoot("."));
    authoring_lowerer_options.addOption([]const u8, "package_root_alias", package_root_alias.path);
    authoring_lowerer_options.addOption(bool, "package_root_alias_available", package_root_alias.available);
    authoring_lowerer_options.addOption([]const u8, "repo_zig_paths", repoZigPathRegistry(b));
    authoring_lowerer_options.addOption(bool, "authoring_lowerer_options_marker", lowerer_opts_marker);
    authoring_lowerer_options.addOption([32]u8, "hash_local_mutation_resume", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/local_mutation_resume.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_branch_resume", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/branch_resume.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_loop_resume", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/loop_resume.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_helper_call_resume", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/helper_call_resume.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_nested_prompt_static_redelim", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/nested_prompt_static_redelim.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_typed_error_try", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/typed_error_try.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_defer_resume", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/defer_resume.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_errdefer_error", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/errdefer_error.zig"));
    inline for (shipped_open_row_corpus.custom_examples) |row| {
        switch (row.kind) {
            .transform_basic => authoring_lowerer_options.addOption([32]u8, "hash_define_basic", canonicalSourceHash(b, row.source_path)),
            .choice_basic => authoring_lowerer_options.addOption([32]u8, "hash_define_choice_basic", canonicalSourceHash(b, row.source_path)),
            .abort_basic => authoring_lowerer_options.addOption([32]u8, "hash_define_abort_basic", canonicalSourceHash(b, row.source_path)),
            .workflow => authoring_lowerer_options.addOption([32]u8, "hash_front_door_workflow", canonicalSourceHash(b, row.source_path)),
            .abortive_validation => authoring_lowerer_options.addOption([32]u8, "hash_algebraic_abortive_validation", canonicalSourceHash(b, row.source_path)),
            .artifact_search => authoring_lowerer_options.addOption([32]u8, "hash_algebraic_artifact_search", canonicalSourceHash(b, row.source_path)),
            .generator => authoring_lowerer_options.addOption([32]u8, "hash_generator", canonicalSourceHash(b, row.source_path)),
        }
    }
    authoring_lowerer_options.addOption([32]u8, "hash_early_exit", canonicalSourceHash(b, "examples/early_exit.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_resume_or_return", canonicalSourceHash(b, "examples/resume_or_return.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_nested_workflow", canonicalSourceHash(b, "examples/nested_workflow.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_state_basic", canonicalSourceHash(b, "examples/state_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_reader_basic", canonicalSourceHash(b, "examples/reader_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_optional_basic", canonicalSourceHash(b, "examples/optional_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_exception_basic", canonicalSourceHash(b, "examples/exception_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_resource_basic", canonicalSourceHash(b, "examples/resource_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_writer_basic", canonicalSourceHash(b, "examples/writer_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_witness_sources", canonicalSourceHash(b, "src/witness_sources.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_witnesses", canonicalSourceHash(b, "src/witnesses.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_algebraic_abortive_validation", canonicalSourceHash(b, "test/direct_style_bridge/open_row_abortive_validation.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_algebraic_artifact_search", canonicalSourceHash(b, "test/direct_style_bridge/open_row_artifact_search.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_atm_resume_transform", canonicalSourceHash(b, "test/direct_style_bridge/atm_resume_transform.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_direct_return", canonicalSourceHash(b, "test/direct_style_bridge/direct_return.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_early_exit", canonicalSourceHash(b, "test/direct_style_bridge/early_exit.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_exception_basic", canonicalSourceHash(b, "test/direct_style_bridge/exception_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_generator", canonicalSourceHash(b, "test/direct_style_bridge/open_row_generator.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_multi_prompt", canonicalSourceHash(b, "test/direct_style_bridge/multi_prompt.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_nested_workflow", canonicalSourceHash(b, "test/direct_style_bridge/nested_workflow.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_optional_basic", canonicalSourceHash(b, "test/direct_style_bridge/optional_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_reader_basic", canonicalSourceHash(b, "test/direct_style_bridge/reader_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_resource_basic", canonicalSourceHash(b, "test/direct_style_bridge/resource_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_resume_or_return", canonicalSourceHash(b, "test/direct_style_bridge/resume_or_return.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_resume_or_return_resume", canonicalSourceHash(b, "test/direct_style_bridge/resume_or_return_resume.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_resume_or_return_return_now", canonicalSourceHash(b, "test/direct_style_bridge/resume_or_return_return_now.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_state_basic", canonicalSourceHash(b, "test/direct_style_bridge/state_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_static_redelim", canonicalSourceHash(b, "test/direct_style_bridge/static_redelim.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_writer_basic", canonicalSourceHash(b, "test/direct_style_bridge/writer_basic.zig"));
    const authoring_build_options_mod = authoring_lowerer_options.createModule();
    source_graph_embed_mod.addImport("authoring_build_options", authoring_build_options_mod);
    source_graph_embed_mod.addImport("source_graph_engine", source_graph_engine_mod);
    source_graph_embed_mod.addImport("source_graph_comptime", source_graph_comptime_mod);
    const authoring_lowerer_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/authoring_lowerer.zig"),
        .target = target,
        .optimize = optimize,
    });
    authoring_lowerer_mod.addImport("authoring_build_options", authoring_build_options_mod);
    authoring_lowerer_mod.addImport("effect_ir", effect_ir_mod);
    authoring_lowerer_mod.addImport("lowered_machine", lowered_machine_mod);
    authoring_lowerer_mod.addImport("parity_scenarios", parity_scenarios_mod);
    authoring_lowerer_mod.addImport("source_graph_engine", source_graph_engine_mod);
    frontend_support_mod.addImport("lowered_machine", lowered_machine_mod);
    ability_mod.addImport("effect_ir", effect_ir_mod);
    ability_mod.addImport("lowered_machine", lowered_machine_mod);
    const prompt_support_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/prompt_support.zig"),
        .target = target,
        .optimize = optimize,
    });
    prompt_support_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    prompt_support_mod.addImport("frontend_support", frontend_support_mod);
    const with_api_mod = b.createModule(.{
        .root_source_file = b.path("src/with_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    with_api_mod.addImport("portable_core", portable_core_mod);
    with_api_mod.addImport("synthetic_ability", synthetic_ability_mod);
    with_api_mod.addImport("synthetic_lowering_host", synthetic_lowering_host_mod);
    with_api_mod.addImport("frontend_support", frontend_support_mod);
    with_api_mod.addImport("lowered_machine", lowered_machine_mod);
    with_api_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    with_api_mod.addImport("authoring_build_options", authoring_build_options_mod);
    with_api_mod.addImport("source_graph_embed", source_graph_embed_mod);
    with_api_mod.addImport("source_graph_engine", source_graph_engine_mod);
    const program_frontend_mod = b.createModule(.{
        .root_source_file = b.path("src/private_modules/program_frontend_build.zig"),
        .target = target,
        .optimize = optimize,
    });
    program_frontend_mod.addImport("effect_ir", effect_ir_mod);
    program_frontend_mod.addImport("helper_body_ir", helper_body_ir_mod);
    program_frontend_mod.addImport("parity_scenarios", parity_scenarios_mod);
    internal_program_plan_mod.addImport("program_frontend", program_frontend_mod);
    internal_program_plan_mod.addImport("helper_body_ir", helper_body_ir_mod);
    ability_mod.addImport("program_frontend", program_frontend_mod);
    ability_mod.addImport("authoring_build_options", authoring_build_options_mod);
    ability_mod.addImport("source_graph_embed", source_graph_embed_mod);
    authoring_lowerer_mod.addImport("program_frontend", program_frontend_mod);
    ability_mod.addImport("authoring_lowerer", authoring_lowerer_mod);
    const witness_sources_mod = b.createModule(.{
        .root_source_file = b.path("src/witness_sources.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge_multi_mod = b.createModule(.{
        .root_source_file = b.path("test/direct_style_bridge/multi_prompt.zig"),
        .target = target,
        .optimize = optimize,
    });
    bridge_multi_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const bridge_redelim_mod = b.createModule(.{
        .root_source_file = b.path("test/direct_style_bridge/static_redelim.zig"),
        .target = target,
        .optimize = optimize,
    });
    bridge_redelim_mod.addImport("parity_scenarios", parity_scenarios_mod);
    witness_sources_mod.addImport("lowered_machine", lowered_machine_mod);
    witness_sources_mod.addImport("ability", ability_mod);
    witness_sources_mod.addImport("bridge_fixture_multi_prompt", bridge_multi_mod);
    witness_sources_mod.addImport("bridge_fixture_static_redelim", bridge_redelim_mod);
    witness_sources_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    witness_sources_mod.addImport("frontend_support", frontend_support_mod);
    witnesses_mod.addImport("witness_sources", witness_sources_mod);
    const bridge_manifest_mod = b.createModule(.{
        .root_source_file = b.path("src/direct_style_bridge_manifest.zig"),
        .target = target,
        .optimize = optimize,
    });
    bridge_manifest_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const program_bridge_mod = b.createModule(.{
        .root_source_file = b.path("src/program_bridge.zig"),
        .target = target,
        .optimize = optimize,
    });
    program_bridge_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    program_bridge_mod.addImport("parity_scenarios", parity_scenarios_mod);
    program_bridge_mod.addImport("program_frontend", program_frontend_mod);
    program_bridge_mod.addImport("authoring_lowerer", authoring_lowerer_mod);
    const private_lowered_runtime_mod = b.createModule(.{
        .root_source_file = b.path("src/private_lowered_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    private_lowered_runtime_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    private_lowered_runtime_mod.addImport("lowered_machine", lowered_machine_mod);
    private_lowered_runtime_mod.addImport("parity_scenarios", parity_scenarios_mod);
    private_lowered_runtime_mod.addImport("program_bridge", program_bridge_mod);
    const source_lowering_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/source_lowering_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_registry_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const shipped_open_row_corpus_mod = b.createModule(.{
        .root_source_file = b.path("src/shipped_open_row_corpus_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    const source_lowering_mod = b.createModule(.{
        .root_source_file = b.path("src/source_lowering.zig"),
        .target = target,
        .optimize = optimize,
    });
    const source_lowering_options = b.addOptions();
    source_lowering_options.addOption([]const u8, "package_root", b.pathFromRoot("."));
    source_lowering_mod.addOptions("build_options", source_lowering_options);
    source_lowering_mod.addImport("effect_ir", effect_ir_mod);
    source_lowering_mod.addImport("program_frontend", program_frontend_mod);
    source_lowering_mod.addImport("source_lowering_registry", source_lowering_registry_mod);
    source_lowering_mod.addImport("parity_scenarios", parity_scenarios_mod);
    source_lowering_mod.addImport("lowered_machine", lowered_machine_mod);
    source_lowering_mod.addImport("error_witness", error_witness_mod);
    source_lowering_mod.addImport("authoring_lowerer", authoring_lowerer_mod);
    source_lowering_mod.addImport("shipped_open_row_corpus_registry", shipped_open_row_corpus_mod);
    synthetic_lowering_host_mod.addImport("lowering_api", lowering_api_mod);
    synthetic_lowering_host_mod.addImport("source_lowering", source_lowering_mod);
    lowering_api_mod.addImport("authoring_build_options", authoring_build_options_mod);
    lowering_api_mod.addImport("effect_ir", effect_ir_mod);
    lowering_api_mod.addImport("lowered_machine", lowered_machine_mod);
    lowering_api_mod.addImport("program_frontend", program_frontend_mod);
    lowering_api_mod.addImport("internal_program_plan", internal_program_plan_mod);
    lowering_api_mod.addImport("source_graph_embed", source_graph_embed_mod);
    lowering_api_mod.addImport("source_graph_comptime", source_graph_comptime_mod);
    lowering_api_mod.addImport("source_graph_engine", source_graph_engine_mod);
    lowering_api_mod.addImport("admitted_body_v1", admitted_body_v1_mod);
    lowering_api_mod.addImport("source_lowering", source_lowering_mod);
    ir_api_mod.addImport("effect_ir", effect_ir_mod);
    ir_api_mod.addImport("lowering_api", lowering_api_mod);
    ability_compile_api_mod.addImport("lowering_api", lowering_api_mod);
    ability_mod.addImport("source_lowering", source_lowering_mod);
    ability_shared_mod.addImport("artifact_api", artifact_api_mod);
    ability_shared_mod.addImport("synthetic_ability", synthetic_ability_mod);
    ability_shared_mod.addImport("synthetic_lowering_host", synthetic_lowering_host_mod);
    ability_shared_mod.addImport("portable_core", portable_core_mod);
    ability_shared_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    ability_shared_mod.addImport("frontend_support", frontend_support_mod);
    ability_shared_mod.addImport("error_witness", error_witness_mod);
    ability_shared_mod.addImport("parity_scenarios", parity_scenarios_mod);
    ability_shared_mod.addImport("effect_ir", effect_ir_mod);
    ability_shared_mod.addImport("internal_kernel", internal_kernel_mod);
    ability_shared_mod.addImport("internal_program_plan", internal_program_plan_mod);
    ability_shared_mod.addImport("interpreter", interpreter_mod);
    ability_shared_mod.addImport("source_graph_engine", source_graph_engine_mod);
    ability_shared_mod.addImport("source_graph_comptime", source_graph_comptime_mod);
    ability_shared_mod.addImport("lowered_machine", lowered_machine_mod);
    ability_shared_mod.addImport("program_frontend", program_frontend_mod);
    ability_shared_mod.addImport("authoring_build_options", authoring_build_options_mod);
    ability_shared_mod.addImport("source_graph_embed", source_graph_embed_mod);
    ability_shared_mod.addImport("authoring_lowerer", authoring_lowerer_mod);
    ability_shared_mod.addImport("source_lowering", source_lowering_mod);
    ability_shared_mod.addImport("ir_api", ir_api_mod);
    ability_shared_mod.addImport("lowering_api", lowering_api_mod);
    witnesses_mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);
    const reference_eval_mod = b.createModule(.{
        .root_source_file = b.path("src/reference_eval.zig"),
        .target = target,
        .optimize = optimize,
    });
    reference_eval_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const reference_machine_mod = b.createModule(.{
        .root_source_file = b.path("src/reference_machine.zig"),
        .target = target,
        .optimize = optimize,
    });
    reference_machine_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const parity_kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/parity_kernel.zig"),
        .target = target,
        .optimize = optimize,
    });
    parity_kernel_mod.addImport("internal_kernel", internal_kernel_mod);
    parity_kernel_mod.addImport("interpreter", interpreter_mod);
    parity_kernel_mod.addImport("lowered_machine", lowered_machine_mod);
    parity_kernel_mod.addImport("parity_scenarios", parity_scenarios_mod);
    reference_machine_mod.addImport("parity_kernel", parity_kernel_mod);

    const check_step = b.default_step;

    const lib_check = b.addObject(.{
        .name = "ability",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lib_check.root_module.addImport("ability_shared", ability_shared_mod);
    lib_check.root_module.addImport("effect_ir", effect_ir_mod);
    lib_check.root_module.addImport("interpreter", interpreter_mod);
    lib_check.root_module.addImport("lowered_machine", lowered_machine_mod);
    lib_check.root_module.addImport("portable_core", portable_core_mod);
    lib_check.root_module.addImport("parity_scenarios", parity_scenarios_mod);
    lib_check.root_module.addImport("internal_kernel", internal_kernel_mod);
    lib_check.root_module.addImport("internal_program_plan", internal_program_plan_mod);
    lib_check.root_module.addImport("authoring_lowerer", authoring_lowerer_mod);
    lib_check.root_module.addImport("authoring_build_options", authoring_build_options_mod);
    lib_check.root_module.addImport("program_frontend", program_frontend_mod);
    lib_check.root_module.addImport("source_graph_engine", source_graph_engine_mod);
    lib_check.root_module.addImport("source_graph_comptime", source_graph_comptime_mod);
    lib_check.root_module.addImport("source_graph_embed", source_graph_embed_mod);
    lib_check.root_module.addImport("source_lowering", source_lowering_mod);
    lib_check.root_module.addImport("error_witness", error_witness_mod);
    check_step.dependOn(&lib_check.step);

    const root_tests = addFilteredTest(
        b,
        b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
        test_runner_args.filters.items,
    );
    root_tests.root_module.addImport("ability_shared", ability_shared_mod);
    root_tests.root_module.addImport("effect_ir", effect_ir_mod);
    root_tests.root_module.addImport("interpreter", interpreter_mod);
    root_tests.root_module.addImport("lowered_machine", lowered_machine_mod);
    root_tests.root_module.addImport("portable_core", portable_core_mod);
    root_tests.root_module.addImport("parity_scenarios", parity_scenarios_mod);
    root_tests.root_module.addImport("internal_kernel", internal_kernel_mod);
    root_tests.root_module.addImport("internal_program_plan", internal_program_plan_mod);
    root_tests.root_module.addImport("authoring_lowerer", authoring_lowerer_mod);
    root_tests.root_module.addImport("authoring_build_options", authoring_build_options_mod);
    root_tests.root_module.addImport("program_frontend", program_frontend_mod);
    root_tests.root_module.addImport("source_graph_engine", source_graph_engine_mod);
    root_tests.root_module.addImport("source_graph_comptime", source_graph_comptime_mod);
    root_tests.root_module.addImport("source_graph_embed", source_graph_embed_mod);
    root_tests.root_module.addImport("source_lowering", source_lowering_mod);
    root_tests.root_module.addImport("error_witness", error_witness_mod);
    root_tests.root_module.addImport("prompt_contract_support", prompt_contract_support_mod);
    root_tests.root_module.addImport("frontend_support", frontend_support_mod);
    const run_root_tests = addRunArtifactWithArgs(b, root_tests, test_runner_args.passthrough.items);
    const test_step = b.step("test", "Run the default ability proof surface.");

    const ability_agent_vm_consumer_mod = b.createModule(.{
        .root_source_file = b.path("ability_agent_vm_source_path_consumer.zig"),
        .target = target,
        .optimize = optimize,
    });
    ability_agent_vm_consumer_mod.addImport("host_adapter_v1", private_host_adapter_v1_mod);
    ability_agent_vm_consumer_mod.addImport("artifact_vm_runtime", private_artifact_vm_core_mod);
    const ability_agent_vm_consumer_exe = b.addExecutable(.{
        .name = "ability-agent-vm-source-path-consumer",
        .root_module = ability_agent_vm_consumer_mod,
    });

    const ability_agent_vm_fixture_mod = b.createModule(.{
        .root_source_file = b.path("test/generate_ability_agent_vm_fixture.zig"),
        .target = target,
        .optimize = optimize,
    });
    const fixture_gen_options = b.addOptions();
    fixture_gen_options.addOption([]const u8, "version", packageVersionAlloc(b));
    ability_agent_vm_fixture_mod.addOptions("fixture_generator_options", fixture_gen_options);
    ability_agent_vm_fixture_mod.addImport("ability_compile", ability_compile_mod);
    const ability_agent_vm_fixture_exe = b.addExecutable(.{
        .name = "generate-ability-agent-vm-fixture",
        .root_module = ability_agent_vm_fixture_mod,
    });
    const run_ability_agent_vm_fixture = b.addRunArtifact(ability_agent_vm_fixture_exe);
    if (fixture_tail_args.len != 0) {
        run_ability_agent_vm_fixture.addArgs(fixture_tail_args);
    } else {
        run_ability_agent_vm_fixture.addArg("--write");
    }
    const ability_agent_vm_fixture_step = b.step(
        "generate-ability-agent-vm-fixture",
        "Generate the committed ability_agent_vm compatibility artifact fixture.",
    );
    ability_agent_vm_fixture_step.dependOn(&run_ability_agent_vm_fixture.step);
    const ability_agent_vm_fixture_tests = addFilteredTest(
        b,
        ability_agent_vm_fixture_mod,
        test_runner_args.filters.items,
    );
    const run_agent_vm_fixture_tests = addRunArtifactWithArgs(
        b,
        ability_agent_vm_fixture_tests,
        test_runner_args.passthrough.items,
    );
    const run_fixture_check = b.addRunArtifact(ability_agent_vm_fixture_exe);
    run_fixture_check.addArg("--check");
    const fixture_check_step = b.step(
        "check-ability-agent-vm-fixture",
        "Verify the committed ability_agent_vm compatibility artifact fixture is current.",
    );
    fixture_check_step.dependOn(&run_fixture_check.step);

    const ability_agent_vm_smoke_mod = b.createModule(.{
        .root_source_file = b.path("test/ability_agent_vm_public_smoke_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    ability_agent_vm_smoke_mod.addImport("ability_agent_vm", ability_agent_vm_mod);
    const ability_agent_vm_smoke_tests = addFilteredTest(
        b,
        ability_agent_vm_smoke_mod,
        test_runner_args.filters.items,
    );
    const run_ability_agent_vm_smoke = addRunArtifactWithArgs(
        b,
        ability_agent_vm_smoke_tests,
        test_runner_args.passthrough.items,
    );
    const avm_fixture_mod = b.createModule(.{
        .root_source_file = b.path("tools/generate_agent_vm_conformance_fixtures.zig"),
        .target = target,
        .optimize = optimize,
    });
    avm_fixture_mod.addImport("artifact_api", artifact_api_mod);
    avm_fixture_mod.addImport("internal_program_plan", internal_program_plan_mod);
    const avm_fixture_exe = b.addExecutable(.{
        .name = "generate-agent-vm-conformance-fixtures",
        .root_module = avm_fixture_mod,
    });
    const run_avm_fixture_gen = b.addRunArtifact(avm_fixture_exe);
    const no_host_artifact = run_avm_fixture_gen.addOutputFileArg("agent-vm-no-host.artifact");
    const host_call_artifact = run_avm_fixture_gen.addOutputFileArg("agent-vm-host-call.artifact");
    const output_snapshot_artifact = run_avm_fixture_gen.addOutputFileArg("agent-vm-output-snapshot.artifact");
    const oversized_return_artifact = run_avm_fixture_gen.addOutputFileArg("agent-vm-oversized-return.artifact");
    const avm_fixture_options = b.addOptions();
    avm_fixture_options.addOptionPath("no_host_artifact_path", no_host_artifact);
    avm_fixture_options.addOptionPath("host_call_artifact_path", host_call_artifact);
    avm_fixture_options.addOptionPath("output_snapshot_artifact_path", output_snapshot_artifact);
    avm_fixture_options.addOptionPath("oversized_return_artifact_path", oversized_return_artifact);
    const avm_conformance_mod = b.createModule(.{
        .root_source_file = b.path("test/ability_agent_vm_conformance_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    avm_conformance_mod.addOptions("agent_vm_conformance_fixture_options", avm_fixture_options);
    avm_conformance_mod.addImport("ability_agent_vm", ability_agent_vm_mod);
    const avm_conformance_tests = addFilteredTest(
        b,
        avm_conformance_mod,
        test_runner_args.filters.items,
    );
    const run_avm_conformance = addRunArtifactWithArgs(
        b,
        avm_conformance_tests,
        test_runner_args.passthrough.items,
    );
    const vm_build_filters = [_][]const u8{
        "raised artifact byte budget",
        "host-log response budget",
        "bounds completed value",
        "completed value budget failure cleans",
    };
    const vm_build_no_match_filters = [_][]const u8{
        "__ability_vm_build_suite_no_user_filter_match__",
    };
    const vm_build_effective_filters = defaultSuiteFiltersForUserFiltersAlloc(
        b.allocator,
        test_runner_args.filters.items,
        &vm_build_filters,
        &vm_build_no_match_filters,
    ) catch |err| std.process.fatal("unable to prepare VM build test filters: {s}", .{@errorName(err)});
    const vm_build_tests = addFilteredTest(
        b,
        private_artifact_vm_core_mod,
        vm_build_effective_filters,
    );
    const run_vm_build_tests = addRunArtifactWithArgs(
        b,
        vm_build_tests,
        test_runner_args.passthrough.items,
    );

    const frontend_internal_tests = addFilteredTest(
        b,
        b.createModule(.{
            .root_source_file = b.path("src/frontend.zig"),
            .target = target,
            .optimize = optimize,
        }),
        test_runner_args.filters.items,
    );
    frontend_internal_tests.root_module.addImport("lowered_machine", lowered_machine_mod);
    frontend_internal_tests.root_module.addImport("portable_core", portable_core_mod);
    frontend_internal_tests.root_module.addImport("prompt_contract_support", prompt_contract_support_mod);
    const run_frontend_internal_tests = addRunArtifactWithArgs(b, frontend_internal_tests, test_runner_args.passthrough.items);

    const admitted_body_v1_tests = addFilteredTest(b, admitted_body_v1_mod, test_runner_args.filters.items);
    const run_admitted_body_v1_tests = addRunArtifactWithArgs(b, admitted_body_v1_tests, test_runner_args.passthrough.items);

    const internal_program_plan_tests = addFilteredTest(
        b,
        b.createModule(.{
            .root_source_file = b.path("test/program_plan_review_regression_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
        test_runner_args.filters.items,
    );
    internal_program_plan_tests.root_module.addImport("internal_program_plan", internal_program_plan_mod);
    internal_program_plan_tests.root_module.addImport("effect_ir", effect_ir_mod);
    internal_program_plan_tests.root_module.addImport("lowered_machine", lowered_machine_mod);
    internal_program_plan_tests.root_module.addImport("lowering_api", lowering_api_mod);
    const run_plan_review_tests = addRunArtifactWithArgs(b, internal_program_plan_tests, test_runner_args.passthrough.items);

    const witness_mod = b.createModule(.{
        .root_source_file = b.path("test/witness_corpus_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    witness_mod.addImport("reference_eval", reference_eval_mod);
    witness_mod.addImport("reference_machine", reference_machine_mod);
    witness_mod.addImport("witnesses", witnesses_mod);
    witness_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const witness_tests = addFilteredTest(b, witness_mod, test_runner_args.filters.items);
    const run_witness_tests = addRunArtifactWithArgs(b, witness_tests, test_runner_args.passthrough.items);

    const runtime_contract_mod = b.createModule(.{
        .root_source_file = b.path("test/runtime_contract_suite.zig"),
        .target = target,
        .optimize = optimize,
    });
    runtime_contract_mod.addImport("ability", ability_mod);
    runtime_contract_mod.addImport("prompt_support", prompt_support_mod);
    runtime_contract_mod.addImport("runtime_contract_registry", b.createModule(.{
        .root_source_file = b.path("src/runtime_contract_registry.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const runtime_contract_tests = addFilteredTest(b, runtime_contract_mod, test_runner_args.filters.items);
    const run_runtime_contract_tests = addRunArtifactWithArgs(b, runtime_contract_tests, test_runner_args.passthrough.items);

    const prompt_token_contract_mod = b.createModule(.{
        .root_source_file = b.path("test/prompt_token_contract_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    prompt_token_contract_mod.addImport("portable_core", portable_core_mod);
    prompt_token_contract_mod.addImport("prompt_support", prompt_support_mod);
    const prompt_token_tests = addFilteredTest(b, prompt_token_contract_mod, test_runner_args.filters.items);
    const run_prompt_token_tests = addRunArtifactWithArgs(b, prompt_token_tests, test_runner_args.passthrough.items);
    const portability_contract_mod = b.createModule(.{
        .root_source_file = b.path("test/portability_contract_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const portability_contract_tests = addFilteredTest(b, portability_contract_mod, test_runner_args.filters.items);
    const run_portability_contract_tests = addRunArtifactWithArgs(b, portability_contract_tests, test_runner_args.passthrough.items);
    const boundary_mod = b.createModule(.{
        .root_source_file = b.path("test/program_frontend_boundary_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    boundary_mod.addImport("effect_ir", effect_ir_mod);
    boundary_mod.addImport("program_frontend", program_frontend_mod);
    const runtime_stack_baseline_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime_stack_baseline.zig"),
        .target = target,
        .optimize = optimize,
    });
    runtime_stack_baseline_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    runtime_stack_baseline_mod.addImport("example_open_row_abortive_validation", createShiftConsumerModule(b, "examples/open_row_abortive_validation.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_open_row_artifact_search", createShiftConsumerModule(b, "examples/open_row_artifact_search.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_open_row_generator", createShiftConsumerModule(b, "examples/open_row_generator.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("parity_scenarios", parity_scenarios_mod);
    runtime_stack_baseline_mod.addImport("example_early_exit", createShiftConsumerModule(b, "examples/early_exit.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_exception_basic", createShiftConsumerModule(b, "examples/exception_basic.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_nested_workflow", createShiftConsumerModule(b, "examples/nested_workflow.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_optional_basic", createShiftConsumerModule(b, "examples/optional_basic.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_reader_basic", createShiftConsumerModule(b, "examples/reader_basic.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_resource_basic", createShiftConsumerModule(b, "examples/resource_basic.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_resume_or_return", createShiftConsumerModule(b, "examples/resume_or_return.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_state_basic", createShiftConsumerModule(b, "examples/state_basic.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_writer_basic", createShiftConsumerModule(b, "examples/writer_basic.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    const boundary_tests = addFilteredTest(b, boundary_mod, test_runner_args.filters.items);
    const run_boundary_tests = addRunArtifactWithArgs(b, boundary_tests, test_runner_args.passthrough.items);

    const source_lowering_corpus_mod = b.createModule(.{
        .root_source_file = b.path("test/source_lowering_corpus_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_corpus_mod.addImport("source_lowering_registry", source_lowering_registry_mod);
    source_lowering_corpus_mod.addImport("source_lowering", source_lowering_mod);
    source_lowering_corpus_mod.addImport("lowered_machine", lowered_machine_mod);
    source_lowering_corpus_mod.addImport("parity_scenarios", parity_scenarios_mod);
    source_lowering_corpus_mod.addImport("source_fixture_branch_resume", createPlainModule(b, "test/source_lowering_corpus/fixtures/branch_resume.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_defer_resume", createPlainModule(b, "test/source_lowering_corpus/fixtures/defer_resume.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_errdefer_error", createPlainModule(b, "test/source_lowering_corpus/fixtures/errdefer_error.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_helper_call_resume", createPlainModule(b, "test/source_lowering_corpus/fixtures/helper_call_resume.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_local_mutation_resume", createPlainModule(b, "test/source_lowering_corpus/fixtures/local_mutation_resume.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_loop_resume", createPlainModule(b, "test/source_lowering_corpus/fixtures/loop_resume.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_nested_prompt_static_redelim", createPlainModule(b, "test/source_lowering_corpus/fixtures/nested_prompt_static_redelim.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_typed_error_try", createPlainModule(b, "test/source_lowering_corpus/fixtures/typed_error_try.zig", target, optimize));
    const src_lower_corpus_tests = addFilteredTest(b, source_lowering_corpus_mod, test_runner_args.filters.items);
    const run_src_lower_corpus_tests = addRunArtifactWithArgs(b, src_lower_corpus_tests, test_runner_args.passthrough.items);

    const source_lowering_boundary_mod = b.createModule(.{
        .root_source_file = b.path("test/source_lowering_boundary_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_boundary_mod.addImport("source_lowering_registry", source_lowering_registry_mod);
    source_lowering_boundary_mod.addImport("source_lowering", source_lowering_mod);
    source_lowering_boundary_mod.addImport("ability", ability_mod);
    const src_lower_boundary_tests = addFilteredTest(b, source_lowering_boundary_mod, test_runner_args.filters.items);
    const run_src_lower_boundary_tests = addRunArtifactWithArgs(b, src_lower_boundary_tests, test_runner_args.passthrough.items);

    const src_lower_promoted_mod = b.createModule(.{
        .root_source_file = b.path("test/source_lowering_promoted_examples_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    src_lower_promoted_mod.addImport("source_lowering", source_lowering_mod);
    src_lower_promoted_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const src_lower_promoted_tests = addFilteredTest(b, src_lower_promoted_mod, test_runner_args.filters.items);
    const run_src_lower_promoted_tests = addRunArtifactWithArgs(b, src_lower_promoted_tests, test_runner_args.passthrough.items);

    const source_lowering_completion_mod = b.createModule(.{
        .root_source_file = b.path("test/source_lowering_completion_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_completion_mod.addImport("source_lowering", source_lowering_mod);
    source_lowering_completion_mod.addImport("parity_scenarios", parity_scenarios_mod);
    source_lowering_completion_mod.addImport("example_resource_basic", createShiftConsumerModule(b, "examples/resource_basic.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = null }));
    source_lowering_completion_mod.addImport("example_writer_basic", createShiftConsumerModule(b, "examples/writer_basic.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = null }));
    const src_lower_completion_tests = addFilteredTest(b, source_lowering_completion_mod, test_runner_args.filters.items);
    const run_src_lower_completion_tests = addRunArtifactWithArgs(b, src_lower_completion_tests, test_runner_args.passthrough.items);

    const open_row_lowering_mod = b.createModule(.{
        .root_source_file = b.path("test/open_row_lowering_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    open_row_lowering_mod.addImport("authoring_build_options", authoring_build_options_mod);
    open_row_lowering_mod.addImport("effect_ir", effect_ir_mod);
    open_row_lowering_mod.addImport("source_lowering", source_lowering_mod);
    open_row_lowering_mod.addImport("program_frontend", program_frontend_mod);
    open_row_lowering_mod.addImport("ability", ability_mod);
    open_row_lowering_mod.addImport("ability_compile", ability_compile_mod);
    open_row_lowering_mod.addImport("example_open_row_escaped_string_helper_body", createShiftConsumerModule(b, "examples/open_row_escaped_string_helper_body.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_linear_helper_body", createShiftConsumerModule(b, "examples/open_row_linear_helper_body.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_branching_helper_body", createShiftConsumerModule(b, "examples/open_row_branching_helper_body.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_cross_file_writer", createShiftConsumerModule(b, "examples/open_row_cross_file_writer.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_helper_bool_flow", createShiftConsumerModule(b, "examples/open_row_helper_bool_flow.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_helper_value_flow", createShiftConsumerModule(b, "examples/open_row_helper_value_flow.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_helper_value_flow_cross", createShiftConsumerModule(b, "examples/open_row_helper_value_flow_cross.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_state_writer", createShiftConsumerModule(b, "examples/open_row_state_writer.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_recursive_writer", createShiftConsumerModule(b, "examples/open_row_recursive_writer.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_recursive_cross_writer", createShiftConsumerModule(b, "examples/open_row_recursive_cross_writer.zig", target, optimize, .{ .ability_mod = ability_mod, .ability_compile_mod = ability_compile_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    const open_row_lowering_tests = addFilteredTest(b, open_row_lowering_mod, test_runner_args.filters.items);
    const run_open_row_lowering_tests = addRunArtifactWithArgs(b, open_row_lowering_tests, test_runner_args.passthrough.items);

    const source_ownership_probe_mod = b.createModule(.{
        .root_source_file = b.path("test/source_ownership_probe_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_ownership_probe_mod.addImport("ability", ability_mod);
    source_ownership_probe_mod.addImport("ability_compile", ability_compile_mod);
    const source_ownership_probe_tests = addFilteredTest(b, source_ownership_probe_mod, test_runner_args.filters.items);
    const run_src_ownership_probe_tests = addRunArtifactWithArgs(b, source_ownership_probe_tests, test_runner_args.passthrough.items);

    const custom_effect_workflow_mod = b.createModule(.{
        .root_source_file = b.path("test/custom_effect_workflow_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    custom_effect_workflow_mod.addImport("ability", ability_mod);
    custom_effect_workflow_mod.addImport("ability_compile", ability_compile_mod);
    custom_effect_workflow_mod.addImport("example_custom_approval_workflow", createShiftConsumerModule(b, "examples/custom_approval_workflow.zig", target, optimize, .{
        .ability_mod = ability_mod,
        .ability_compile_mod = null,
        .lowered_runtime_mod = null,
    }));
    const custom_effect_workflow_tests = addFilteredTest(b, custom_effect_workflow_mod, test_runner_args.filters.items);
    const run_custom_effect_tests = addRunArtifactWithArgs(b, custom_effect_workflow_tests, test_runner_args.passthrough.items);

    const custom_effect_bad_choice_mod = b.createModule(.{
        .root_source_file = b.path("test/custom_effect_bad_choice_handler_negative.zig"),
        .target = target,
        .optimize = optimize,
    });
    custom_effect_bad_choice_mod.addImport("ability", ability_mod);
    const custom_effect_bad_choice_tests = b.addTest(.{
        .root_module = custom_effect_bad_choice_mod,
    });
    custom_effect_bad_choice_tests.expect_errors = .{ .contains = "switch on type '[]const u8'" };
    run_custom_effect_tests.step.dependOn(&custom_effect_bad_choice_tests.step);

    const custom_effect_bad_after_mod = b.createModule(.{
        .root_source_file = b.path("test/custom_effect_bad_after_negative.zig"),
        .target = target,
        .optimize = optimize,
    });
    custom_effect_bad_after_mod.addImport("ability", ability_mod);
    const custom_effect_bad_after_tests = b.addTest(.{
        .root_module = custom_effect_bad_after_mod,
    });
    custom_effect_bad_after_tests.expect_errors = .{ .contains = "expected type '[]const u8', found 'bool'" };
    run_custom_effect_tests.step.dependOn(&custom_effect_bad_after_tests.step);

    const bad_mixed_after_mod = b.createModule(.{
        .root_source_file = b.path("test/custom_effect_bad_mixed_same_function_after_negative.zig"),
        .target = target,
        .optimize = optimize,
    });
    bad_mixed_after_mod.addImport("ability", ability_mod);
    bad_mixed_after_mod.addImport("ability_compile", ability_compile_mod);
    const bad_mixed_after_tests = b.addTest(.{
        .root_module = bad_mixed_after_mod,
    });
    bad_mixed_after_tests.expect_errors = .{ .contains = "public lowering rejected mixed direct and explicit-continuation uses of picker.pick in source function body; use one call style for this operation in that function, or move one form into a separate helper" };
    run_custom_effect_tests.step.dependOn(&bad_mixed_after_tests.step);

    const comptime_contract_mod = b.createModule(.{
        .root_source_file = b.path("test/comptime_contract_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    comptime_contract_mod.addImport("ability", ability_mod);
    comptime_contract_mod.addImport("ability_compile", ability_compile_mod);
    const comptime_contract_tests = addFilteredTest(b, comptime_contract_mod, test_runner_args.filters.items);
    const run_comptime_contract_tests = addRunArtifactWithArgs(b, comptime_contract_tests, test_runner_args.passthrough.items);

    const src_lower_witness_mod = b.createModule(.{
        .root_source_file = b.path("test/source_lowering_witness_completion_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    src_lower_witness_mod.addImport("source_lowering", source_lowering_mod);
    src_lower_witness_mod.addImport("parity_scenarios", parity_scenarios_mod);
    src_lower_witness_mod.addImport("witness_sources", witness_sources_mod);
    const src_lower_witness_tests = addFilteredTest(b, src_lower_witness_mod, test_runner_args.filters.items);
    const run_src_lower_witness_tests = addRunArtifactWithArgs(b, src_lower_witness_tests, test_runner_args.passthrough.items);

    const source_lowering_tool_mod = b.createModule(.{
        .root_source_file = b.path("tools/ability_source_lower.zig"),
        .target = target,
        .optimize = optimize,
    });
    const source_lowering_tool_options = b.addOptions();
    source_lowering_tool_options.addOption([]const u8, "package_root", b.pathFromRoot("."));
    source_lowering_tool_options.addOption([]const u8, "version", packageVersionAlloc(b));
    source_lowering_tool_mod.addOptions("tool_build_options", source_lowering_tool_options);
    source_lowering_tool_mod.addImport("source_lowering", source_lowering_mod);
    source_lowering_tool_mod.addImport("lowered_machine", lowered_machine_mod);
    source_lowering_tool_mod.addImport("error_witness", error_witness_mod);
    const source_lowering_tool_exe = b.addExecutable(.{
        .name = "ability-source-lower",
        .root_module = source_lowering_tool_mod,
    });
    const source_lowering_tool_install = b.addInstallArtifact(source_lowering_tool_exe, .{});
    const source_lowering_tool_step = b.step("source-lower", "Build the source-lowering inspection tool.");
    source_lowering_tool_step.dependOn(&source_lowering_tool_exe.step);
    source_lowering_tool_step.dependOn(&source_lowering_tool_install.step);
    const source_lowering_tool_tests = addFilteredTest(b, source_lowering_tool_mod, test_runner_args.filters.items);
    const run_source_lowering_tool_tests = addRunArtifactWithArgs(
        b,
        source_lowering_tool_tests,
        test_runner_args.passthrough.items,
    );
    const agent_vm_report_mod = b.createModule(.{
        .root_source_file = b.path("tools/agent_vm_artifact_report.zig"),
        .target = target,
        .optimize = optimize,
    });
    const agent_vm_report_options = b.addOptions();
    agent_vm_report_options.addOption([]const u8, "version", packageVersionAlloc(b));
    agent_vm_report_mod.addOptions("tool_build_options", agent_vm_report_options);
    agent_vm_report_mod.addImport("ability_agent_vm", ability_agent_vm_mod);
    const agent_vm_report_exe = b.addExecutable(.{
        .name = "agent-vm-artifact-report",
        .root_module = agent_vm_report_mod,
    });
    const agent_vm_report_install = b.addInstallArtifact(agent_vm_report_exe, .{});
    const run_agent_vm_report = b.addRunArtifact(agent_vm_report_exe);
    if (agent_vm_artifact_report_path) |artifact_path| {
        if (artifact_report_format) |format| {
            run_agent_vm_report.addArgs(&.{ "--format", format });
        }
        run_agent_vm_report.addArgs(&.{ "--artifact", artifact_path });
    }
    const agent_vm_report_step = b.step(
        "agent-vm-artifact-report",
        "Build the Agent VM ArtifactV1 conformance report tool.",
    );
    agent_vm_report_step.dependOn(&agent_vm_report_exe.step);
    agent_vm_report_step.dependOn(&agent_vm_report_install.step);
    const run_agent_vm_report_step = b.step(
        "run-agent-vm-artifact-report",
        "Classify one ArtifactV1 payload under the fixed no-host conformance profile.",
    );
    run_agent_vm_report_step.dependOn(&run_agent_vm_report.step);
    const agent_vm_report_test_mod = b.createModule(.{
        .root_source_file = b.path("test/agent_vm_artifact_report_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    agent_vm_report_test_mod.addOptions("agent_vm_conformance_fixture_options", avm_fixture_options);
    agent_vm_report_test_mod.addImport("agent_vm_artifact_report", agent_vm_report_mod);
    const agent_vm_report_tests = addFilteredTest(b, agent_vm_report_test_mod, test_runner_args.filters.items);
    const run_agent_vm_report_tests = addRunArtifactWithArgs(
        b,
        agent_vm_report_tests,
        test_runner_args.passthrough.items,
    );

    // zlinter-disable declaration_naming - lexical witness module/test handles mirror suite ids for traceable proof receipts.
    const lexical_witness_direct_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_witness/direct_return_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_witness_direct_mod.addImport("ability", ability_mod);
    lexical_witness_direct_mod.addImport("synthetic_ability", synthetic_ability_mod);
    lexical_witness_direct_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const lexical_witness_direct_tests = addFilteredTest(b, lexical_witness_direct_mod, test_runner_args.filters.items);
    const run_lexical_witness_direct = addRunArtifactWithArgs(b, lexical_witness_direct_tests, test_runner_args.passthrough.items);

    const lexical_witness_return_now_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_witness/resume_or_return_return_now_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_witness_return_now_mod.addImport("ability", ability_mod);
    lexical_witness_return_now_mod.addImport("synthetic_ability", synthetic_ability_mod);
    lexical_witness_return_now_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const lexical_witness_return_now_tests = addFilteredTest(b, lexical_witness_return_now_mod, test_runner_args.filters.items);
    const run_lexical_witness_return_now = addRunArtifactWithArgs(b, lexical_witness_return_now_tests, test_runner_args.passthrough.items);

    const lexical_witness_resume_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_witness/resume_or_return_resume_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_witness_resume_mod.addImport("ability", ability_mod);
    lexical_witness_resume_mod.addImport("synthetic_ability", synthetic_ability_mod);
    lexical_witness_resume_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const lexical_witness_resume_tests = addFilteredTest(b, lexical_witness_resume_mod, test_runner_args.filters.items);
    const run_lexical_witness_resume = addRunArtifactWithArgs(b, lexical_witness_resume_tests, test_runner_args.passthrough.items);

    const lexical_witness_generator_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_witness/generator_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_witness_generator_mod.addImport("ability", ability_mod);
    lexical_witness_generator_mod.addImport("synthetic_ability", synthetic_ability_mod);
    lexical_witness_generator_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const lexical_witness_generator_tests = addFilteredTest(b, lexical_witness_generator_mod, test_runner_args.filters.items);
    const run_lexical_witness_generator = addRunArtifactWithArgs(b, lexical_witness_generator_tests, test_runner_args.passthrough.items);

    const lexical_witness_atm_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_witness/atm_resume_transform_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_witness_atm_mod.addImport("ability", ability_mod);
    lexical_witness_atm_mod.addImport("synthetic_ability", synthetic_ability_mod);
    lexical_witness_atm_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const lexical_witness_atm_tests = addFilteredTest(b, lexical_witness_atm_mod, test_runner_args.filters.items);
    const run_lexical_witness_atm = addRunArtifactWithArgs(b, lexical_witness_atm_tests, test_runner_args.passthrough.items);

    const lexical_witness_static_redelim_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_witness/static_redelim_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_witness_static_redelim_mod.addImport("ability", ability_mod);
    lexical_witness_static_redelim_mod.addImport("synthetic_ability", synthetic_ability_mod);
    lexical_witness_static_redelim_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const lexical_witness_static_redelim_tests = addFilteredTest(b, lexical_witness_static_redelim_mod, test_runner_args.filters.items);
    const run_lexical_witness_static_redelim = addRunArtifactWithArgs(b, lexical_witness_static_redelim_tests, test_runner_args.passthrough.items);

    const lexical_witness_multi_prompt_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_witness/multi_prompt_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_witness_multi_prompt_mod.addImport("ability", ability_mod);
    lexical_witness_multi_prompt_mod.addImport("synthetic_ability", synthetic_ability_mod);
    lexical_witness_multi_prompt_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const lexical_witness_multi_prompt_tests = addFilteredTest(b, lexical_witness_multi_prompt_mod, test_runner_args.filters.items);
    const run_lexical_witness_multi_prompt = addRunArtifactWithArgs(b, lexical_witness_multi_prompt_tests, test_runner_args.passthrough.items);

    const run_lexical_witness_tests = b.step("lexical-witness", "Run the lexical witness suite.");
    run_lexical_witness_tests.dependOn(&run_lexical_witness_atm.step);
    run_lexical_witness_tests.dependOn(&run_lexical_witness_direct.step);
    run_lexical_witness_tests.dependOn(&run_lexical_witness_multi_prompt.step);
    run_lexical_witness_tests.dependOn(&run_lexical_witness_return_now.step);
    run_lexical_witness_tests.dependOn(&run_lexical_witness_resume.step);
    run_lexical_witness_tests.dependOn(&run_lexical_witness_static_redelim.step);
    run_lexical_witness_tests.dependOn(&run_lexical_witness_generator.step);

    const lexical_with_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_with_mod.addImport("ability", ability_mod);
    const lexical_with_tests = addFilteredTest(b, lexical_with_mod, test_runner_args.filters.items);
    const run_lexical_with_tests_core = addRunArtifactWithArgs(b, lexical_with_tests, test_runner_args.passthrough.items);

    const lexical_with_preview_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_preview_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_with_preview_mod.addImport("ability", ability_mod);
    lexical_with_preview_mod.addImport("ability_shared", ability_shared_mod);
    const lexical_with_preview_tests = addFilteredTest(b, lexical_with_preview_mod, test_runner_args.filters.items);
    const run_lexical_with_preview_tests = addRunArtifactWithArgs(b, lexical_with_preview_tests, test_runner_args.passthrough.items);

    const lexical_with_fixture_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_fixture_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_with_fixture_mod.addImport("ability", ability_mod);
    const lexical_with_fixture_tests = addFilteredTest(b, lexical_with_fixture_mod, test_runner_args.filters.items);
    const run_lexical_with_fixture_tests = addRunArtifactWithArgs(b, lexical_with_fixture_tests, test_runner_args.passthrough.items);

    const lex_fix_ctl_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_fixture_control_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lex_fix_ctl_mod.addImport("ability", ability_mod);
    const lex_fix_ctl_tests = addFilteredTest(b, lex_fix_ctl_mod, test_runner_args.filters.items);
    const run_lex_fix_ctl = addRunArtifactWithArgs(b, lex_fix_ctl_tests, test_runner_args.passthrough.items);

    const lex_fix_res_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_fixture_resource_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lex_fix_res_mod.addImport("ability", ability_mod);
    const lex_fix_res_tests = addFilteredTest(b, lex_fix_res_mod, test_runner_args.filters.items);
    const run_lex_fix_res = addRunArtifactWithArgs(b, lex_fix_res_tests, test_runner_args.passthrough.items);

    const lex_fix_opt_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_fixture_optional_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lex_fix_opt_mod.addImport("ability", ability_mod);
    const lex_fix_opt_tests = addFilteredTest(b, lex_fix_opt_mod, test_runner_args.filters.items);
    const run_lex_fix_opt = addRunArtifactWithArgs(b, lex_fix_opt_tests, test_runner_args.passthrough.items);

    const lexical_with_runtime_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_runtime_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_with_runtime_mod.addImport("ability", ability_mod);
    const lexical_with_runtime_tests = addFilteredTest(b, lexical_with_runtime_mod, test_runner_args.filters.items);

    lexical_with_preview_tests.step.dependOn(&run_lexical_with_tests_core.step);
    lexical_with_fixture_tests.step.dependOn(&run_lexical_with_preview_tests.step);
    lex_fix_opt_tests.step.dependOn(&run_lexical_with_fixture_tests.step);
    lex_fix_ctl_tests.step.dependOn(&run_lex_fix_opt.step);
    lex_fix_res_tests.step.dependOn(&run_lex_fix_ctl.step);
    lexical_with_runtime_tests.step.dependOn(&run_lex_fix_res.step);

    const run_lexical_with_tests = b.step("lexical-with", "Run the lexical-with suite.");
    run_lexical_with_tests.dependOn(&lexical_with_runtime_tests.step);

    const run_lexical_with_all = b.step("lexical-with-all", "Run the full lexical-with suite.");
    run_lexical_with_all.dependOn(run_lexical_with_tests);

    const program_bridge_test_mod = b.createModule(.{
        .root_source_file = b.path("test/program_bridge_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    program_bridge_test_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    program_bridge_test_mod.addImport("lowered_machine", lowered_machine_mod);
    program_bridge_test_mod.addImport("parity_scenarios", parity_scenarios_mod);
    program_bridge_test_mod.addImport("program_bridge", program_bridge_mod);
    const program_bridge_tests = addFilteredTest(b, program_bridge_test_mod, test_runner_args.filters.items);
    const run_program_bridge_tests = addRunArtifactWithArgs(b, program_bridge_tests, test_runner_args.passthrough.items);
    const test_suites = [_]TestSuiteSpec{
        .{ .suite_id = "root", .description = "Root lexical surface", .run_step = &run_root_tests.step },
        .{ .suite_id = "ability-agent-vm-consumer", .description = "ability_agent_vm source-path consumer compile witness", .run_step = &ability_agent_vm_consumer_exe.step },
        .{ .suite_id = "ability-agent-vm-freshness", .description = "ability_agent_vm fixture freshness check", .run_step = &run_agent_vm_fixture_tests.step },
        .{ .suite_id = "ability-agent-vm-smoke", .description = "ability_agent_vm public runtime smoke", .run_step = &run_ability_agent_vm_smoke.step },
        .{ .suite_id = "ability-agent-vm-conformance", .description = "ability_agent_vm no-host budget conformance and report", .run_step = &run_avm_conformance.step },
        .{ .suite_id = "artifact-vm-runtime-build-host-log-budget", .description = "Private artifact VM runtime host-log budget regression", .run_step = &run_vm_build_tests.step },
        .{ .suite_id = "frontend", .description = "Frontend internal module", .run_step = &run_frontend_internal_tests.step },
        .{ .suite_id = "admitted-body-v1", .description = "Admitted body parser suite", .run_step = &run_admitted_body_v1_tests.step },
        .{ .suite_id = "program-plan-review", .description = "ProgramPlan regression suite", .run_step = &run_plan_review_tests.step },
        .{ .suite_id = "program-bridge", .description = "Program bridge suite", .run_step = &run_program_bridge_tests.step },
        .{ .suite_id = "witness-corpus", .description = "Core witness corpus", .run_step = &run_witness_tests.step },
        .{ .suite_id = "runtime-contract", .description = "Runtime contract suite", .run_step = &run_runtime_contract_tests.step },
        .{ .suite_id = "prompt-token", .description = "Prompt token contract suite", .run_step = &run_prompt_token_tests.step },
        .{ .suite_id = "portability-contract", .description = "Portability contract suite", .run_step = &run_portability_contract_tests.step },
        .{ .suite_id = "program-frontend-boundary", .description = "Program frontend boundary suite", .run_step = &run_boundary_tests.step },
        .{ .suite_id = "source-lowering-corpus", .description = "Source lowering corpus suite", .run_step = &run_src_lower_corpus_tests.step },
        .{ .suite_id = "source-lowering-boundary", .description = "Source lowering boundary suite", .run_step = &run_src_lower_boundary_tests.step },
        .{ .suite_id = "source-lowering-promoted", .description = "Promoted source lowering cohort", .run_step = &run_src_lower_promoted_tests.step },
        .{ .suite_id = "source-lowering-completion", .description = "Source lowering completion suite", .run_step = &run_src_lower_completion_tests.step },
        .{ .suite_id = "source-lowering-tool", .description = "Source lowering CLI tool suite", .run_step = &run_source_lowering_tool_tests.step },
        .{ .suite_id = "agent-vm-artifact-report", .description = "Agent VM artifact report CLI suite", .run_step = &run_agent_vm_report_tests.step },
        .{ .suite_id = "open-row-lowering", .description = "Open-row lowering suite", .run_step = &run_open_row_lowering_tests.step },
        .{ .suite_id = "source-ownership-probe", .description = "Source ownership probe suite", .run_step = &run_src_ownership_probe_tests.step },
        .{ .suite_id = "custom-effect-workflow", .description = "Root-public custom effect workflow proof", .run_step = &run_custom_effect_tests.step },
        .{ .suite_id = "comptime-contract", .description = "Public comptime contract suite", .run_step = &run_comptime_contract_tests.step },
        .{ .suite_id = "source-lowering-witness", .description = "Source lowering witness completion suite", .run_step = &run_src_lower_witness_tests.step },
        .{ .suite_id = "lexical-witness", .description = "Lexical witness suite", .run_step = run_lexical_witness_tests },
        .{ .suite_id = "lexical-with", .description = "Lexical with suite", .run_step = run_lexical_with_tests },
    };
    const test_suite_selection = resolveTestSuiteSelection(
        b,
        test_suites_raw,
        &test_suites,
        test_requested,
        skip_execution orelse false,
    ) orelse return;
    defer test_suite_selection.deinit();
    addSelectedTestSuites(test_step, &test_suites, test_suite_selection);

    const examples = [_]struct {
        name: []const u8,
        src: []const u8,
        step_name: []const u8,
        step_desc: []const u8,
    }{
        .{
            .name = "exception_basic",
            .src = "examples/exception_basic.zig",
            .step_name = "run-exception-basic",
            .step_desc = "Run the direct-return exception effect example.",
        },
        .{
            .name = "optional_basic",
            .src = "examples/optional_basic.zig",
            .step_name = "run-optional-basic",
            .step_desc = "Run the optional-resumption effect example.",
        },
        .{
            .name = "reader_basic",
            .src = "examples/reader_basic.zig",
            .step_name = "run-reader-basic",
            .step_desc = "Run the reader-effect example.",
        },
        .{
            .name = "resource_basic",
            .src = "examples/resource_basic.zig",
            .step_name = "run-resource-basic",
            .step_desc = "Run the bracketed resource effect example.",
        },
        .{
            .name = "state_basic",
            .src = "examples/state_basic.zig",
            .step_name = "run-state-basic",
            .step_desc = "Run the additive state-effect example.",
        },
        .{
            .name = "writer_basic",
            .src = "examples/writer_basic.zig",
            .step_name = "run-writer-basic",
            .step_desc = "Run the writer-effect example.",
        },
        .{
            .name = "custom_approval_workflow",
            .src = "examples/custom_approval_workflow.zig",
            .step_name = "run-custom-approval-workflow",
            .step_desc = "Run the custom approval workflow example.",
        },
    };

    inline for (examples) |example| {
        const mod = b.createModule(.{
            .root_source_file = b.path(example.src),
            .target = target,
            .optimize = optimize,
        });
        mod.addImport("ability", ability_mod);
        mod.addImport("ability_compile", ability_compile_mod);
        mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);

        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = mod,
        });
        check_step.dependOn(&exe.step);

        const run = b.addRunArtifact(exe);
        const run_step = b.step(example.step_name, example.step_desc);
        run_step.dependOn(&run.step);
    }

    inline for (shipped_open_row_corpus.custom_examples) |example| {
        const mod = b.createModule(.{
            .root_source_file = b.path(example.source_path),
            .target = target,
            .optimize = optimize,
        });
        mod.addImport("ability", ability_mod);
        mod.addImport("ability_compile", ability_compile_mod);
        mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);

        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = mod,
        });
        check_step.dependOn(&exe.step);

        const run = b.addRunArtifact(exe);
        const run_step = b.step(example.run_step_name, example.run_step_desc);
        run_step.dependOn(&run.step);
    }

    const ability_bench_mod = b.createModule(.{
        .root_source_file = b.path("src/bench_support.zig"),
        .target = target,
        .optimize = bench_optimize,
    });
    ability_bench_mod.addImport("portable_core", portable_core_mod);
    ability_bench_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    ability_bench_mod.addImport("frontend_support", frontend_support_mod);
    ability_bench_mod.addImport("error_witness", error_witness_mod);
    ability_bench_mod.addImport("parity_scenarios", parity_scenarios_mod);
    ability_bench_mod.addImport("effect_ir", effect_ir_mod);
    ability_bench_mod.addImport("internal_kernel", internal_kernel_mod);
    ability_bench_mod.addImport("internal_program_plan", internal_program_plan_mod);
    ability_bench_mod.addImport("interpreter", interpreter_mod);
    ability_bench_mod.addImport("source_graph_engine", source_graph_engine_mod);
    ability_bench_mod.addImport("source_graph_comptime", source_graph_comptime_mod);
    ability_bench_mod.addImport("lowered_machine", lowered_machine_mod);
    ability_bench_mod.addImport("program_frontend", program_frontend_mod);
    ability_bench_mod.addImport("authoring_build_options", authoring_build_options_mod);
    ability_bench_mod.addImport("source_graph_embed", source_graph_embed_mod);
    ability_bench_mod.addImport("authoring_lowerer", authoring_lowerer_mod);
    ability_bench_mod.addImport("source_lowering", source_lowering_mod);
    ability_bench_mod.addImport("lowering_api", lowering_api_mod);
    const bench_specs = [_]struct {
        name: []const u8,
        src: []const u8,
        step_name: []const u8,
        step_desc: []const u8,
    }{
        .{
            .name = "ability-direct-no-capture-bench",
            .src = "bench/no_capture_bench.zig",
            .step_name = "bench",
            .step_desc = "Run the direct-style no-capture benchmark.",
        },
        .{
            .name = "ability-direct-first-suspend-bench",
            .src = "bench/direct_first_suspend_bench.zig",
            .step_name = "bench-first-suspend",
            .step_desc = "Run the direct-style first-suspend benchmark.",
        },
        .{
            .name = "ability-state-effect-bench",
            .src = "bench/state_effect_bench.zig",
            .step_name = "bench-state-effect",
            .step_desc = "Compare the additive state effect against the raw prompt baseline.",
        },
        .{
            .name = "ability-effect-family-matrix-bench",
            .src = "bench/effect_family_matrix_bench.zig",
            .step_name = "bench-family-matrix",
            .step_desc = "Compare every shipped declaration family against its chosen comparator lane.",
        },
    };

    inline for (bench_specs) |bench_spec| {
        const bench_mod = b.createModule(.{
            .root_source_file = b.path(bench_spec.src),
            .target = target,
            .optimize = bench_optimize,
        });
        bench_mod.addImport("ability", ability_bench_mod);
        bench_mod.addImport("lowered_machine", lowered_machine_mod);
        const bench_exe = b.addExecutable(.{
            .name = bench_spec.name,
            .root_module = bench_mod,
        });
        const bench_step = b.step(bench_spec.step_name, bench_spec.step_desc);
        if (target.query.isNative()) {
            const bench_run = b.addRunArtifact(bench_exe);
            bench_step.dependOn(&bench_run.step);
        } else {
            bench_step.dependOn(&bench_exe.step);
        }
    }

    const runtime_backend_bench_mod = b.createModule(.{
        .root_source_file = b.path("bench/runtime_backend_matrix_bench.zig"),
        .target = target,
        .optimize = bench_optimize,
    });
    runtime_backend_bench_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    runtime_backend_bench_mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);
    runtime_backend_bench_mod.addImport("runtime_stack_baseline", runtime_stack_baseline_mod);
    const runtime_backend_bench_exe = b.addExecutable(.{
        .name = "ability-runtime-backend-matrix-bench",
        .root_module = runtime_backend_bench_mod,
    });
    const runtime_backend_bench_step = b.step("bench-runtime-backends", "Compare the current stack runtime against the lowered runtime over the supported bridge corpus.");
    if (target.query.isNative()) {
        const runtime_backend_bench_run = b.addRunArtifact(runtime_backend_bench_exe);
        runtime_backend_bench_step.dependOn(&runtime_backend_bench_run.step);
    } else {
        runtime_backend_bench_step.dependOn(&runtime_backend_bench_exe.step);
    }

    const zprof_hotspots_step = b.step("zprof-hotspots", "Profile writer/resource allocator hotspots with zprof.");
    if (b.lazyDependency("zprof", .{
        .target = target,
        .optimize = bench_optimize,
    })) |zprof_dep| {
        const zprof_hotspots_mod = b.createModule(.{
            .root_source_file = b.path("bench/zprof_hotspots.zig"),
            .target = target,
            .optimize = bench_optimize,
        });
        zprof_hotspots_mod.addImport("ability", ability_bench_mod);
        zprof_hotspots_mod.addImport("zprof", zprof_dep.module("zprof"));
        const zprof_hotspots_exe = b.addExecutable(.{
            .name = "ability-zprof-hotspots",
            .root_module = zprof_hotspots_mod,
        });
        const zprof_hotspots_run = b.addRunArtifact(zprof_hotspots_exe);
        zprof_hotspots_step.dependOn(&zprof_hotspots_run.step);
    }

    const lint_step = b.step("lint", "Lint source code.");
    lint_step.dependOn(step: {
        const saved_verbose = b.verbose;
        const saved_args = b.args;
        const lint_args = repoZigLintCliArgsAlloc(b, lint_shared_tail_args);
        defer b.allocator.free(lint_args);
        b.verbose = saved_verbose or lint_verbose;
        b.args = lint_args;
        defer {
            b.verbose = saved_verbose;
            b.args = saved_args;
        }
        var builder = zlinter.builder(b, .{});
        builder.addPaths(.{
            // Feed zlinter the explicit repo path registry so lint stays fail-closed
            // without relying on recursive cwd walking or exclude-index construction.
            .include = repoZigLintIncludePaths(b),
            .exclude = &.{
                b.path("zig-pkg"),
            },
        });
        inline for (@typeInfo(zlinter.BuiltinLintRule).@"enum".fields) |field| {
            const rule: zlinter.BuiltinLintRule = @enumFromInt(field.value);
            builder.addRule(.{ .builtin = rule }, .{});
        }
        break :step builder.build();
    });
}
