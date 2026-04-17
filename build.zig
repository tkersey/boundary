const builtin = @import("builtin");
const shipped_open_row_corpus = @import("src/shipped_open_row_corpus_registry.zig");
const std = @import("std");
const zlinter = @import("zlinter");

const ShiftConsumerDeps = struct {
    lowered_runtime_mod: ?*std.Build.Module,
    shift_mod: *std.Build.Module,
    shift_compile_mod: ?*std.Build.Module = null,
    shift_vm_mod: ?*std.Build.Module = null,
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

// Keep this in sync with Zig 0.15.2's compiler/build_runner.zig argv handling.
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
            (std.mem.indexOfScalar(u8, next_arg, '.') != null or
                std.mem.indexOfScalar(u8, next_arg, ':') != null);
    }
    if (std.mem.eql(u8, arg, "-freference-trace")) {
        _ = std.fmt.parseUnsigned(usize, next_arg, 10) catch return false;
        return true;
    }
    if (std.mem.eql(u8, arg, "--build-id")) {
        if (std.mem.eql(u8, next_arg, "fast") or
            std.mem.eql(u8, next_arg, "sha1") or
            std.mem.eql(u8, next_arg, "tree") or
            std.mem.eql(u8, next_arg, "md5") or
            std.mem.eql(u8, next_arg, "uuid") or
            std.mem.eql(u8, next_arg, "none"))
        {
            return true;
        }
        if (!std.mem.startsWith(u8, next_arg, "0x") or next_arg.len == 2) return false;
        for (next_arg["0x".len..]) |char| {
            if (std.ascii.isHex(char)) continue;
            return false;
        }
        return true;
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

fn buildInvocationRequestsRunnableStep(step_name: []const u8) bool {
    const args = std.process.argsAlloc(std.heap.page_allocator) catch
        std.process.fatal("unable to inspect build invocation args", .{});
    defer std.process.argsFree(std.heap.page_allocator, args);

    // The generated build executable receives:
    // argv[0] = build helper exe
    // argv[1..6] = zig_exe, zig_lib_dir, build_root, local_cache_root, global_cache_root
    return buildInvocationRequestsRunnableStepInArgs(args, step_name);
}

fn buildInvocationRequestsStep(step_name: []const u8) bool {
    const args = std.process.argsAlloc(std.heap.page_allocator) catch
        std.process.fatal("unable to inspect build invocation args", .{});
    defer std.process.argsFree(std.heap.page_allocator, args);

    // The generated build executable receives:
    // argv[0] = build helper exe
    // argv[1..6] = zig_exe, zig_lib_dir, build_root, local_cache_root, global_cache_root
    return buildInvocationRequestsStepInArgs(args, step_name);
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

    for (specs, 0..) |spec, index| {
        if (index != 0) try out.appendSlice(allocator, ", ");
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
    return parseTestSuiteSelectionAlloc(allocator, if (test_requested) raw else null, specs);
}

fn resolveTestSuiteSelection(
    b: *std.Build,
    raw: ?[]const u8,
    specs: []const TestSuiteSpec,
    test_requested: bool,
) ?TestSuiteSelection {
    const selection_result = parseRequestedTestSuiteSelectionAlloc(
        b.allocator,
        raw,
        specs,
        test_requested,
    ) catch |err|
        std.process.fatal("unable to parse -Dtest-suites: {s}", .{@errorName(err)});

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
                "Expected -Dtest-suites to be a comma-separated list of exact suite ids without empty entries. Supported ids: {s}",
                .{supported},
            );
        },
        .duplicate => |id| {
            const supported = testSuiteIdListAlloc(b.allocator, specs) catch |err|
                std.process.fatal("unable to list supported test suite ids: {s}", .{@errorName(err)});
            std.log.err(
                "Duplicate test suite id in -Dtest-suites: '{s}'. Supported ids: {s}",
                .{ id, supported },
            );
        },
        .unknown => |id| {
            const supported = testSuiteIdListAlloc(b.allocator, specs) catch |err|
                std.process.fatal("unable to list supported test suite ids: {s}", .{@errorName(err)});
            std.log.err(
                "Unknown test suite id in -Dtest-suites: '{s}'. Supported ids: {s}",
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
    return std.mem.eql(u8, arg, "--seed") or std.mem.eql(u8, arg, "--cache-dir");
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
        if (testRunnerArgCanPassThrough(arg)) {
            passthrough_count += 1;
            index += 1;
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
        if (testRunnerArgCanPassThrough(arg)) {
            passthrough[passthrough_index] = arg;
            passthrough_index += 1;
            index += 1;
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
    if (testRunnerArgCanPassThrough(arg)) return 1;
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
            "Unsupported `zig build test --` argument: '{s}'. Supported forms are '--test-filter[=pattern]', '--listen=-', '--seed[=value]', and '--cache-dir[=path]'.",
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
    if (std.fs.path.isAbsolute(path)) return path;
    const cwd = std.fs.cwd().realpathAlloc(b.allocator, ".") catch |err|
        std.process.fatal("failed to resolve build cwd for graph path '{s}': {s}", .{ path, @errorName(err) });
    return std.fs.path.resolve(b.allocator, &.{ cwd, path }) catch |err|
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
        const value = std.process.getEnvVarOwned(b.allocator, name) catch |err| switch (err) {
            error.EnvironmentVariableNotFound => continue,
            else => continue,
        };
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
    mod.addImport("shift", deps.shift_mod);
    if (deps.shift_compile_mod) |shift_compile_mod| mod.addImport("shift_compile", shift_compile_mod);
    if (deps.shift_vm_mod) |shift_vm_mod| mod.addImport("shift_vm", shift_vm_mod);
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
    if (std.fs.path.isAbsolute(path)) return .{ .cwd_relative = path };
    return b.path(path);
}

fn canonicalSourceHash(b: *std.Build, path: []const u8) [32]u8 {
    const bytes = std.fs.cwd().readFileAlloc(b.allocator, b.pathFromRoot(path), 1 << 20) catch |err| switch (err) {
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

fn pathExistsAtRoot(root_dir: std.fs.Dir, path: []const u8) bool {
    const file = root_dir.openFile(path, .{}) catch return false;
    file.close();
    return true;
}

fn repoRootContainsGitMetadata(root_dir: std.fs.Dir) bool {
    root_dir.access(".git", .{}) catch return false;
    return true;
}

fn hashBuildIdentityFileAtRoot(
    hasher: *std.crypto.hash.Blake3,
    repo_root: []const u8,
    path: []const u8,
) void {
    var root_dir = std.fs.openDirAbsolute(repo_root, .{}) catch |err|
        std.process.fatal("unable to open build identity root '{s}': {s}", .{ repo_root, @errorName(err) });
    defer root_dir.close();

    var file = root_dir.openFile(path, .{}) catch |err|
        std.process.fatal("unable to open build identity file '{s}': {s}", .{ path, @errorName(err) });
    defer file.close();

    const stat = file.stat() catch |err|
        std.process.fatal("unable to stat build identity file '{s}': {s}", .{ path, @errorName(err) });

    hashBuildIdentityField(hasher, "build-input-path", path);
    hasher.update("build-input-bytes");
    hashBuildIdentityU64(hasher, stat.size);

    var buffer: [4096]u8 = undefined;
    while (true) {
        const read_len = file.read(&buffer) catch |err|
            std.process.fatal("unable to read build identity file '{s}': {s}", .{ path, @errorName(err) });
        if (read_len == 0) break;
        hasher.update(buffer[0..read_len]);
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
    var left: usize = 0;
    while (left < paths.len) : (left += 1) {
        var right = left + 1;
        while (right < paths.len) : (right += 1) {
            if (std.mem.order(u8, paths[right], paths[left]) == .lt) {
                const tmp = paths[left];
                paths[left] = paths[right];
                paths[right] = tmp;
            }
        }
    }
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
    if (std.mem.indexOfScalar(u8, inner, '\\') == null) {
        if (std.mem.indexOfAny(u8, inner, "\"\n") != null) return null;
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
    if (absolute_path[repo_root.len] != std.fs.path.sep) return null;
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
    return switch (tokens[0].tag) {
        .string_literal => try decodeStringLiteralAlloc(allocator, tokens[0].lexeme),
        .identifier => if (bindings.get(tokens[0].lexeme)) |bound|
            try allocator.dupe(u8, bound)
        else
            null,
        else => null,
    };
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
        switch (tokens[index].tag) {
            .l_brace => {
                scope_depth += 1;
                index += 1;
                continue;
            },
            .r_brace => {
                if (scope_depth > 0) scope_depth -= 1;
                index += 1;
                continue;
            },
            else => {},
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
            switch (tokens[cursor].tag) {
                .l_paren, .l_brace, .l_bracket => depth += 1,
                .r_paren, .r_brace, .r_bracket => {
                    if (depth > 0) depth -= 1;
                },
                .equal => {
                    if (depth == 0 and equal_index == null) equal_index = cursor;
                },
                .semicolon => {
                    if (depth == 0) {
                        semicolon_index = cursor;
                        break;
                    }
                },
                else => {},
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
        for (declarations) |declaration| {
            if (top_bindings.contains(declaration.name)) continue;
            const value = try resolveStringTokensFromBindingMapAlloc(
                allocator,
                declaration.value_tokens,
                top_bindings,
            ) orelse continue;
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
    return switch (tokens[0].tag) {
        .string_literal => try decodeStringLiteralAlloc(allocator, tokens[0].lexeme),
        .identifier => if (lookupVisibleStringBinding(scopes, top_bindings, tokens[0].lexeme)) |bound|
            try allocator.dupe(u8, bound)
        else
            null,
        else => null,
    };
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
        switch (tokens[index].tag) {
            .l_brace => {
                try scopes.append(scratch_allocator, std.StringHashMap([]const u8).init(scratch_allocator));
                index += 1;
                continue;
            },
            .r_brace => {
                if (scopes.items.len > 1) {
                    _ = scopes.pop();
                }
                index += 1;
                continue;
            },
            else => {},
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
            switch (tokens[cursor].tag) {
                .l_paren, .l_brace, .l_bracket => depth += 1,
                .r_paren, .r_brace, .r_bracket => {
                    if (depth > 0) depth -= 1;
                },
                .equal => {
                    if (depth == 0 and equal_index == null) equal_index = cursor;
                },
                .semicolon => {
                    if (depth == 0) {
                        semicolon_index = cursor;
                        break;
                    }
                },
                else => {},
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
    return switch (tokens[0].tag) {
        .string_literal => try decodeStringLiteralAlloc(allocator, tokens[0].lexeme),
        .identifier => try resolveVisibleStringBindingAlloc(
            allocator,
            all_tokens,
            use_index,
            tokens[0].lexeme,
            top_bindings,
        ),
        else => null,
    };
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
    const resolved = try std.fs.path.resolve(allocator, &.{ repo_root, source_dir, decoded });
    defer allocator.free(resolved);

    const repo_relative = try tryRepoRelativePathFromAbsoluteAlloc(allocator, repo_root, resolved) orelse return;
    defer allocator.free(repo_relative);

    var root_dir = std.fs.openDirAbsolute(repo_root, .{}) catch |err|
        std.process.fatal("unable to open repo root for embed input scan '{s}': {s}", .{ repo_root, @errorName(err) });
    defer root_dir.close();
    if (!pathExistsAtRoot(root_dir, repo_relative)) return;
    try appendOwnedPathIfMissing(allocator, collector.paths, collector.path_set, repo_relative);
}

fn resolveRepoRelativeImportPathAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    source_dir: []const u8,
    decoded: []const u8,
) !?[]u8 {
    if (!std.mem.endsWith(u8, decoded, ".zig")) return null;

    const resolved = try std.fs.path.resolve(allocator, &.{ repo_root, source_dir, decoded });
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
        while (iter.next()) |param| : (param_index += 1) {
            if (param.comptime_noalias == null) continue;
            const name_token = param.name_token orelse continue;
            try comptime_params.append(allocator, .{
                .name = try allocator.dupe(u8, tree.tokenSlice(name_token)),
                .index = param_index,
            });
        }
        if (comptime_params.items.len == 0) continue;

        const fn_source = functionSourceSlice(tree, source, member, fn_proto);
        const fn_source_z = try allocator.dupeZ(u8, fn_source);
        defer allocator.free(fn_source_z);

        var tokenizer = std.zig.Tokenizer.init(fn_source_z);
        var window: BuildInputTokenWindow = .{};
        var matched_indexes = std.ArrayList(usize).empty;
        defer matched_indexes.deinit(allocator);

        while (true) {
            const token = tokenizer.next();
            if (token.tag == .eof) break;
            window.push(.{
                .tag = token.tag,
                .lexeme = tokenSlice(fn_source_z, token),
            });

            const identifier = maybeEmbedFileIdentifierPath(&window) orelse continue;
            for (comptime_params.items) |param| {
                if (!std.mem.eql(u8, identifier, param.name)) continue;
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
            switch (value_tokens[cursor].tag) {
                .l_paren, .l_brace, .l_bracket => depth += 1,
                .r_paren, .r_brace, .r_bracket => {
                    if (depth == 0) break;
                    depth -= 1;
                },
                .comma => if (depth == 0) break,
                else => {},
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
    var root_dir = std.fs.openDirAbsolute(repo_root, .{}) catch return allocator.alloc(BuildModuleBinding, 0);
    defer root_dir.close();

    const source = root_dir.readFileAlloc(allocator, "build.zig", 4 * 1024 * 1024) catch return allocator.alloc(BuildModuleBinding, 0);
    defer allocator.free(source);
    const source_z = try allocator.dupeZ(u8, source);
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
    const build_source_z = try allocator.dupeZ(u8, build_source);
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
        switch (tokens[index].tag) {
            .l_brace => {
                scope_depth += 1;
                continue;
            },
            .r_brace => {
                if (scope_depth > 0) scope_depth -= 1;
                continue;
            },
            else => {},
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
                switch (tokens[cursor].tag) {
                    .l_paren, .l_brace, .l_bracket => depth += 1,
                    .r_paren, .r_brace, .r_bracket => {
                        if (depth > 0) depth -= 1;
                    },
                    .equal => {
                        if (depth == 0 and equal_index == null) equal_index = cursor;
                    },
                    .semicolon => {
                        if (depth == 0) {
                            semicolon_index = cursor;
                            break;
                        }
                    },
                    else => {},
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

    const source_dir = std.fs.path.dirname(scan.source_path) orelse ".";
    var index: usize = 0;
    var scope_depth: usize = 0;
    while (index + 1 < scan.tokens.len) {
        switch (scan.tokens[index].tag) {
            .l_brace => {
                scope_depth += 1;
                index += 1;
                continue;
            },
            .r_brace => {
                if (scope_depth > 0) scope_depth -= 1;
                index += 1;
                continue;
            },
            else => {},
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
            switch (scan.tokens[cursor].tag) {
                .l_paren, .l_brace, .l_bracket => depth += 1,
                .r_paren, .r_brace, .r_bracket => {
                    if (depth > 0) depth -= 1;
                },
                .equal => {
                    if (depth == 0 and equal_index == null) equal_index = cursor;
                },
                .semicolon => {
                    if (depth == 0) {
                        semicolon_index = cursor;
                        break;
                    }
                },
                else => {},
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

        const imported_source_full_path = try std.fs.path.join(allocator, &.{ scan.repo_root, repo_relative });
        defer allocator.free(imported_source_full_path);
        const imported_bytes = std.fs.cwd().readFileAlloc(allocator, imported_source_full_path, 1 << 20) catch |err| switch (err) {
            error.FileNotFound => {
                index = value_end + 1;
                continue;
            },
            else => return err,
        };
        defer allocator.free(imported_bytes);
        const imported_source_z = try allocator.dupeZ(u8, imported_bytes);
        defer allocator.free(imported_source_z);

        const imported_patterns = try collectSameFileEmbedFunctionPatternsAlloc(allocator, imported_source_z);
        defer allocator.free(imported_patterns);
        const imported_source_dir = std.fs.path.dirname(repo_relative) orelse ".";
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

    const source_dir = std.fs.path.dirname(scan.source_path) orelse ".";
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
                for (imported_patterns) |*candidate| {
                    if (!std.mem.eql(u8, candidate.module_binding, scan.tokens[index].lexeme)) continue;
                    if (!std.mem.eql(u8, candidate.pattern.fn_name, scan.tokens[index + 2].lexeme)) continue;
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
        while (cursor < scan.tokens.len) : (cursor += 1) {
            switch (scan.tokens[cursor].tag) {
                .l_paren, .l_brace, .l_bracket => depth += 1,
                .r_paren => {
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
                },
                .r_brace, .r_bracket => {
                    if (depth > 0) depth -= 1;
                },
                .comma => {
                    if (depth != 0) continue;
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
                },
                else => {},
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
    const source_full_path = try std.fs.path.join(allocator, &.{ repo_root, source_path });
    defer allocator.free(source_full_path);
    const bytes = try std.fs.cwd().readFileAlloc(allocator, source_full_path, 1 << 20);
    defer allocator.free(bytes);
    const source_z = try allocator.dupeZ(u8, bytes);
    defer allocator.free(source_z);

    const source_dir = std.fs.path.dirname(source_path) orelse ".";
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
        std.mem.eql(u8, path, ".zig-global-cache") or
        std.mem.startsWith(u8, path, ".zig-global-cache/") or
        std.mem.eql(u8, path, "zig-out") or
        std.mem.startsWith(u8, path, "zig-out/");
}

fn collectFilesystemRepoZigPaths(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    paths: *std.ArrayList([]const u8),
    path_set: *std.StringHashMap(void),
) void {
    var root_dir = std.fs.openDirAbsolute(repo_root, .{ .iterate = true }) catch |err|
        std.process.fatal("unable to open repo root for build input walk '{s}': {s}", .{ repo_root, @errorName(err) });
    defer root_dir.close();

    var walker = root_dir.walk(allocator) catch
        std.process.fatal("unable to walk repo root for build inputs", .{});
    defer walker.deinit();

    while (walker.next() catch
        std.process.fatal("unable to iterate repo build input walk", .{})) |entry|
    {
        if (pathIsIgnoredBuildInput(entry.path)) continue;
        switch (entry.kind) {
            .file, .sym_link => {},
            else => continue,
        }
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
    var root_dir = std.fs.openDirAbsolute(repo_root, .{}) catch return;
    defer root_dir.close();

    const source = root_dir.readFileAlloc(allocator, "build.zig", 4 * 1024 * 1024) catch return;
    defer allocator.free(source);
    const source_z = allocator.dupeZ(u8, source) catch
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
    const build_source_z = allocator.dupeZ(u8, build_source) catch
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
    var root_dir = std.fs.openDirAbsolute(repo_root, .{}) catch return false;
    defer root_dir.close();
    if (!repoRootContainsGitMetadata(root_dir)) return false;

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "-C", repo_root, "ls-files", "--cached", "--", "*.zig" },
        .max_output_bytes = 512 * 1024,
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code != 0) return false,
        else => return false,
    }

    var lines = std.mem.tokenizeScalar(u8, result.stdout, '\n');
    while (lines.next()) |line| {
        if (!std.mem.endsWith(u8, line, ".zig")) continue;
        if (!pathExistsAtRoot(root_dir, line)) continue;
        appendOwnedPathIfMissing(allocator, paths, path_set, line) catch
            std.process.fatal("unable to record tracked repo Zig path", .{});
    }
    return true;
}

fn collectRepoZigPathsFromRegistryFile(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    paths: *std.ArrayList([]const u8),
    path_set: *std.StringHashMap(void),
) bool {
    var root_dir = std.fs.openDirAbsolute(repo_root, .{}) catch return false;
    defer root_dir.close();

    const registry = root_dir.readFileAlloc(allocator, "repo_zig_paths.txt", 512 * 1024) catch return false;
    defer allocator.free(registry);

    var lines = std.mem.tokenizeScalar(u8, registry, '\n');
    while (lines.next()) |line| {
        if (!std.mem.endsWith(u8, line, ".zig")) continue;
        if (!pathExistsAtRoot(root_dir, line)) continue;
        appendOwnedPathIfMissing(allocator, paths, path_set, line) catch
            std.process.fatal("unable to record committed repo Zig path", .{});
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
    const have_registry = collectRepoZigPathsFromRegistryFile(allocator, repo_root, paths, path_set);

    if (!have_tracked and !have_registry) {
        collectFilesystemRepoZigPaths(allocator, repo_root, paths, path_set);
    }
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

    var root_dir = std.fs.openDirAbsolute(repo_root, .{}) catch |err|
        std.process.fatal("unable to open repo root for build metadata '{s}': {s}", .{ repo_root, @errorName(err) });
    defer root_dir.close();
    if (pathExistsAtRoot(root_dir, "build.zig.zon")) {
        hashBuildIdentityFileAtRoot(hasher, repo_root, "build.zig.zon");
    }
}

fn artifactBuildInputFingerprint(allocator: std.mem.Allocator, repo_root: []const u8) [32]u8 {
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update("shift-artifact-build-input-fingerprint-v1");
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
    if (target.query.dynamic_linker.get()) |dynamic_linker| {
        hasher.update(dynamic_linker);
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
    hasher.update("shift-default-artifact-build-fingerprint-v2");
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
    if (std.mem.eql(u8, path, "src/error_witness.zig")) return true;
    if (std.mem.eql(u8, path, "src/op_compat.zig")) return true;
    if (std.mem.eql(u8, path, "src/public_ir.zig")) return true;
    if (std.mem.eql(u8, path, "src/public_lowering.zig")) return true;
    if (std.mem.eql(u8, path, "src/program_api_compat.zig")) return true;
    if (std.mem.eql(u8, path, "src/program_api.zig")) return true;
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

const PackageRootAlias = struct {
    path: []const u8,
    available: bool,
};

fn scratchRootPath(b: *std.Build, leaf: []const u8) []const u8 {
    return std.fs.path.join(b.allocator, &.{ tempRootPath(b), leaf }) catch
        std.process.fatal("unable to allocate scratch root path", .{});
}

fn boundaryAliasRoot(b: *std.Build) []const u8 {
    return scratchRootPath(b, ".shift_aliases");
}

fn clearAliasPath(alias_path: []const u8, dir_error: []const u8, path_error: []const u8) void {
    std.fs.deleteFileAbsolute(alias_path) catch |err| switch (err) {
        error.FileNotFound => {},
        error.IsDir => std.fs.deleteTreeAbsolute(alias_path) catch
            std.process.fatal("{s}", .{dir_error}),
        else => std.process.fatal("{s}", .{path_error}),
    };
}

fn packageRootAlias(b: *std.Build) PackageRootAlias {
    const repo_root = b.pathFromRoot(".");
    const alias_root = boundaryAliasRoot(b);
    std.fs.makeDirAbsolute(alias_root) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return .{ .path = repo_root, .available = false },
    };
    const alias_leaf = std.fmt.allocPrint(
        b.allocator,
        "shift_repo_alias_{x}",
        .{std.hash.Wyhash.hash(0, repo_root)},
    ) catch std.process.fatal("unable to allocate package-root alias leaf", .{});
    const alias_path = std.fs.path.join(b.allocator, &.{ alias_root, alias_leaf }) catch
        std.process.fatal("unable to allocate package-root alias path", .{});

    var link_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const existing_target = std.fs.readLinkAbsolute(alias_path, &link_buffer) catch |err| switch (err) {
        error.FileNotFound => null,
        else => blk: {
            clearAliasPath(alias_path, "unable to clear package-root alias directory", "unable to clear package-root alias path");
            break :blk null;
        },
    };
    if (existing_target) |target| {
        if (std.mem.eql(u8, target, repo_root)) return .{
            .path = alias_path,
            .available = true,
        };
    }

    clearAliasPath(alias_path, "unable to clear package-root alias directory", "unable to clear package-root alias path");
    std.fs.symLinkAbsolute(repo_root, alias_path, .{}) catch
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
        "C:\\Users\\\"tk\"\\shift\\downstream_public_lowering_test.zig",
    );
    defer std.testing.allocator.free(escaped);

    try std.testing.expectEqualStrings(
        "C:\\\\Users\\\\\\\"tk\\\"\\\\shift\\\\downstream_public_lowering_test.zig",
        escaped,
    );
}

fn writeTmpFile(dir: std.fs.Dir, path: []const u8, contents: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir_name| {
        try dir.makePath(dir_name);
    }
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [1024]u8 = undefined;
    var writer = file.writer(&buffer);
    try writer.interface.writeAll(contents);
    try writer.interface.flush();
}

fn runChildExpectSuccess(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .max_output_bytes = 32 * 1024,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code == 0) return,
        else => {},
    }
    std.debug.print("child command failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ argv[0], result.stdout, result.stderr });
    return error.UnexpectedChildCommandFailure;
}

fn makeExternalTmpDir(allocator: std.mem.Allocator) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "mktemp", "-d" },
        .max_output_bytes = 1024,
    });
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code != 0) {
            allocator.free(result.stdout);
            return error.UnexpectedChildCommandFailure;
        },
        else => {
            allocator.free(result.stdout);
            return error.UnexpectedChildCommandFailure;
        },
    }

    const trimmed = std.mem.trimEnd(u8, result.stdout, "\r\n");
    const owned = try allocator.dupe(u8, trimmed);
    allocator.free(result.stdout);
    return owned;
}

test "artifact build fingerprint changes on raw-byte-only Zig edits" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
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

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
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

test "artifact build fingerprint includes imported untracked Zig inputs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
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

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
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

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
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

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
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

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
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

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
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

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
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

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
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

test "repo Zig path registry falls back to filesystem when git and committed registry are unavailable" {
    const repo_root = try makeExternalTmpDir(std.testing.allocator);
    defer std.testing.allocator.free(repo_root);
    defer runChildExpectSuccess(std.testing.allocator, &.{ "rm", "-rf", repo_root }) catch unreachable;

    var repo_dir = try std.fs.openDirAbsolute(repo_root, .{});
    defer repo_dir.close();

    try writeTmpFile(repo_dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(_: *std.Build) void {}
        \\
    );
    try writeTmpFile(repo_dir, "src/probe.zig",
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

test "repo Zig path registry ignores deleted tracked files" {
    const repo_root = try makeExternalTmpDir(std.testing.allocator);
    defer std.testing.allocator.free(repo_root);
    defer runChildExpectSuccess(std.testing.allocator, &.{ "rm", "-rf", repo_root }) catch unreachable;

    var repo_dir = try std.fs.openDirAbsolute(repo_root, .{});
    defer repo_dir.close();

    try writeTmpFile(repo_dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(_: *std.Build) void {}
        \\
    );
    try writeTmpFile(repo_dir, "live.zig",
        \\pub fn live() void {}
        \\
    );
    try writeTmpFile(repo_dir, "stale.zig",
        \\pub fn stale() void {}
        \\
    );

    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "build.zig", "live.zig", "stale.zig" });
    try repo_dir.deleteFile("stale.zig");

    const registry = repoZigPathRegistryAlloc(std.testing.allocator, repo_root);
    defer std.testing.allocator.free(registry);

    try std.testing.expectEqualStrings(
        \\build.zig
        \\live.zig
        \\
    , registry);
}

test "checked-in repo Zig path registry stays in parity with tracked Zig files" {
    var repo_dir = try std.fs.cwd().openDir(".", .{});
    defer repo_dir.close();

    const repo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    const tracked_registry = repoZigPathRegistryAlloc(std.testing.allocator, repo_root);
    defer std.testing.allocator.free(tracked_registry);

    const committed_registry_bytes = try repo_dir.readFileAlloc(std.testing.allocator, "repo_zig_paths.txt", 512 * 1024);
    defer std.testing.allocator.free(committed_registry_bytes);
    const committed_registry = std.mem.trimEnd(u8, committed_registry_bytes, "\n\r");

    try std.testing.expectEqualStrings(
        std.mem.trimEnd(u8, tracked_registry, "\n\r"),
        committed_registry,
    );
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

test "test suite selection ignores raw option when test step not requested" {
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
        .selection => |selection| {
            defer selection.deinit();
            try std.testing.expect(selection.isEnabled(0));
            try std.testing.expect(selection.isEnabled(1));
        },
        else => return error.UnexpectedSelectionParseResult,
    }
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

test "test runner args normalize supported runner passthrough args" {
    const result = try parseTestRunnerArgsAlloc(std.testing.allocator, &.{ "--seed", "123", "--cache-dir", "zig-cache" }, .strict);
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

test "lint shared-tail args keep lint-owned flags while stripping recognized test args" {
    const filtered_args = try lintSharedTailArgsAlloc(
        std.testing.allocator,
        &.{ "--max-warnings", "0", "--test-filter=alpha", "--seed", "123", "--listen=-", "--cache-dir", "zig-cache" },
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

/// Configure build, test, lint, example, and benchmark entrypoints for shift.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_suites_raw = b.option(
        []const u8,
        "test-suites",
        "Restrict `zig build test` to a comma-separated list of exact suite ids.",
    );
    const test_requested = buildInvocationRequestsRunnableStep("test");
    // `lint` currently owns the only documented non-test shared-tail CLI surface (`--max-warnings`),
    // so mixed `lint test -- ...` invocations must ignore unknown args while still honoring test flags.
    const allow_foreign_shared_tail_args = test_requested and buildInvocationRequestsStep("lint");
    const lint_shared_tail_args = lintSharedTailArgsAlloc(b.allocator, b.args, allow_foreign_shared_tail_args) catch |err|
        std.process.fatal("unable to prepare lint shared-tail args: {s}", .{@errorName(err)});
    defer b.allocator.free(lint_shared_tail_args);
    const test_runner_args = requireTestRunnerArgs(
        b,
        b.args,
        test_requested,
        allow_foreign_shared_tail_args,
    ) orelse return;
    // Compile and run steps retain these slices by reference, so they must live for the build graph lifetime.
    const bench_optimize: std.builtin.OptimizeMode = .ReleaseFast;

    absolutizeZlinterRuntimePaths(b);

    const shift_mod = b.addModule("shift", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const shift_compile_mod = b.createModule(.{
        .root_source_file = b.path("src/private_modules/shift_compile.zig"),
        .target = target,
        .optimize = optimize,
    });
    const shift_vm_mod = b.createModule(.{
        .root_source_file = b.path("src/private_modules/shift_vm.zig"),
        .target = target,
        .optimize = optimize,
    });
    const shift_shared_mod = b.createModule(.{
        .root_source_file = b.path("src/shift_shared.zig"),
        .target = target,
        .optimize = optimize,
    });
    const artifact_api_mod = b.createModule(.{
        .root_source_file = b.path("src/agent_vm_artifact.zig"),
        .target = target,
        .optimize = optimize,
    });
    const public_ir_mod = b.createModule(.{
        .root_source_file = b.path("src/public_ir.zig"),
        .target = target,
        .optimize = optimize,
    });
    const public_lowering_mod = b.createModule(.{
        .root_source_file = b.path("src/public_lowering.zig"),
        .target = target,
        .optimize = optimize,
    });
    const shift_compile_api_mod = b.createModule(.{
        .root_source_file = b.path("src/shift_compile_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    const private_host_adapter_v1_mod = b.createModule(.{
        .root_source_file = b.path("src/host_adapter_v1.zig"),
        .target = target,
        .optimize = optimize,
    });
    const private_artifact_vm_core_mod = b.createModule(.{
        .root_source_file = b.path("src/artifact_vm_runtime.zig"),
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
    shift_mod.addImport("shift_shared", shift_shared_mod);
    shift_mod.addImport("portable_core", portable_core_mod);
    shift_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    shift_mod.addImport("frontend_support", frontend_support_mod);
    shift_mod.addImport("error_witness", error_witness_mod);
    const witnesses_mod = b.createModule(.{
        .root_source_file = b.path("src/witnesses.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lexical_witness_runners_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_witness_support.zig"),
        .target = target,
        .optimize = optimize,
    });
    const parity_scenarios_mod = b.createModule(.{
        .root_source_file = b.path("src/parity_scenarios.zig"),
        .target = target,
        .optimize = optimize,
    });
    shift_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const lowered_machine_mod = b.createModule(.{
        .root_source_file = b.path("src/lowered_machine.zig"),
        .target = target,
        .optimize = optimize,
    });
    lowered_machine_mod.addImport("portable_core", portable_core_mod);
    const effect_ir_mod = b.createModule(.{
        .root_source_file = b.path("src/effect_ir.zig"),
        .target = target,
        .optimize = optimize,
    });
    const helper_body_ir_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/helper_body_ir.zig"),
        .target = target,
        .optimize = optimize,
    });
    const source_graph_engine_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/source_graph_engine.zig"),
        .target = target,
        .optimize = optimize,
    });
    const internal_program_plan_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/program_plan.zig"),
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
    const source_graph_embed_mod = b.createModule(.{
        .root_source_file = b.path("source_graph_embed.zig"),
        .target = target,
        .optimize = optimize,
    });
    const internal_kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/kernel.zig"),
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
    shift_mod.addImport("effect_ir", effect_ir_mod);
    shift_mod.addImport("internal_kernel", internal_kernel_mod);
    shift_mod.addImport("internal_program_plan", internal_program_plan_mod);
    shift_mod.addImport("interpreter", interpreter_mod);
    shift_mod.addImport("source_graph_engine", source_graph_engine_mod);
    shift_mod.addImport("source_graph_comptime", source_graph_comptime_mod);
    artifact_api_mod.addImport("internal_program_plan", internal_program_plan_mod);
    shift_compile_api_mod.addImport("artifact_api", artifact_api_mod);
    shift_compile_mod.addImport("shift_shared", shift_shared_mod);
    shift_compile_mod.addImport("shift_compile_api", shift_compile_api_mod);
    private_artifact_vm_core_mod.addImport("artifact_api", artifact_api_mod);
    private_artifact_vm_core_mod.addImport("host_adapter_v1", private_host_adapter_v1_mod);
    private_artifact_vm_core_mod.addImport("internal_program_plan", internal_program_plan_mod);
    private_artifact_vm_core_mod.addImport("lowered_machine", lowered_machine_mod);
    shift_vm_mod.addImport("shift_shared", shift_shared_mod);
    shift_vm_mod.addImport("host_adapter_v1", private_host_adapter_v1_mod);
    shift_vm_mod.addImport("artifact_vm_runtime", private_artifact_vm_core_mod);
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
    shift_mod.addImport("effect_ir", effect_ir_mod);
    shift_mod.addImport("lowered_machine", lowered_machine_mod);
    witnesses_mod.addImport("lexical_witness_support", lexical_witness_runners_mod);
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
    with_api_mod.addImport("frontend_support", frontend_support_mod);
    with_api_mod.addImport("lowered_machine", lowered_machine_mod);
    with_api_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    with_api_mod.addImport("authoring_build_options", authoring_build_options_mod);
    with_api_mod.addImport("source_graph_embed", source_graph_embed_mod);
    with_api_mod.addImport("source_graph_engine", source_graph_engine_mod);
    const program_frontend_mod = b.createModule(.{
        .root_source_file = b.path("src/program_frontend.zig"),
        .target = target,
        .optimize = optimize,
    });
    program_frontend_mod.addImport("effect_ir", effect_ir_mod);
    program_frontend_mod.addImport("helper_body_ir", helper_body_ir_mod);
    program_frontend_mod.addImport("parity_scenarios", parity_scenarios_mod);
    internal_program_plan_mod.addImport("program_frontend", program_frontend_mod);
    internal_program_plan_mod.addImport("helper_body_ir", helper_body_ir_mod);
    shift_mod.addImport("program_frontend", program_frontend_mod);
    shift_mod.addImport("authoring_build_options", authoring_build_options_mod);
    shift_mod.addImport("source_graph_embed", source_graph_embed_mod);
    authoring_lowerer_mod.addImport("program_frontend", program_frontend_mod);
    shift_mod.addImport("authoring_lowerer", authoring_lowerer_mod);
    const lexical_runtime_internal_mod = b.createModule(.{
        .root_source_file = b.path("src/lexical_runtime_internal.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_runtime_internal_mod.addImport("portable_core", portable_core_mod);
    lexical_runtime_internal_mod.addImport("frontend_support", frontend_support_mod);
    lexical_runtime_internal_mod.addImport("lowered_machine", lowered_machine_mod);
    lexical_runtime_internal_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    lexical_runtime_internal_mod.addImport("effect_ir", effect_ir_mod);
    lexical_runtime_internal_mod.addImport("public_lowering", public_lowering_mod);
    lexical_runtime_internal_mod.addImport("source_graph_embed", source_graph_embed_mod);
    lexical_runtime_internal_mod.addImport("source_graph_engine", source_graph_engine_mod);
    lexical_runtime_internal_mod.addImport("authoring_build_options", authoring_build_options_mod);
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
    witness_sources_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
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
    public_lowering_mod.addImport("authoring_build_options", authoring_build_options_mod);
    public_lowering_mod.addImport("effect_ir", effect_ir_mod);
    public_lowering_mod.addImport("lowered_machine", lowered_machine_mod);
    public_lowering_mod.addImport("program_frontend", program_frontend_mod);
    public_lowering_mod.addImport("internal_program_plan", internal_program_plan_mod);
    public_lowering_mod.addImport("source_graph_embed", source_graph_embed_mod);
    public_lowering_mod.addImport("source_graph_comptime", source_graph_comptime_mod);
    public_lowering_mod.addImport("source_graph_engine", source_graph_engine_mod);
    public_lowering_mod.addImport("source_lowering", source_lowering_mod);
    public_ir_mod.addImport("effect_ir", effect_ir_mod);
    public_ir_mod.addImport("public_lowering", public_lowering_mod);
    shift_compile_api_mod.addImport("public_lowering", public_lowering_mod);
    shift_mod.addImport("source_lowering", source_lowering_mod);
    shift_shared_mod.addImport("artifact_api", artifact_api_mod);
    shift_shared_mod.addImport("portable_core", portable_core_mod);
    shift_shared_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    shift_shared_mod.addImport("frontend_support", frontend_support_mod);
    shift_shared_mod.addImport("error_witness", error_witness_mod);
    shift_shared_mod.addImport("parity_scenarios", parity_scenarios_mod);
    shift_shared_mod.addImport("effect_ir", effect_ir_mod);
    shift_shared_mod.addImport("internal_kernel", internal_kernel_mod);
    shift_shared_mod.addImport("internal_program_plan", internal_program_plan_mod);
    shift_shared_mod.addImport("interpreter", interpreter_mod);
    shift_shared_mod.addImport("source_graph_engine", source_graph_engine_mod);
    shift_shared_mod.addImport("source_graph_comptime", source_graph_comptime_mod);
    shift_shared_mod.addImport("lowered_machine", lowered_machine_mod);
    shift_shared_mod.addImport("program_frontend", program_frontend_mod);
    shift_shared_mod.addImport("authoring_build_options", authoring_build_options_mod);
    shift_shared_mod.addImport("source_graph_embed", source_graph_embed_mod);
    shift_shared_mod.addImport("authoring_lowerer", authoring_lowerer_mod);
    shift_shared_mod.addImport("source_lowering", source_lowering_mod);
    shift_shared_mod.addImport("public_ir", public_ir_mod);
    shift_shared_mod.addImport("public_lowering", public_lowering_mod);
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
        .name = "shift",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lib_check.root_module.addImport("shift_shared", shift_shared_mod);
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
    root_tests.root_module.addImport("shift_shared", shift_shared_mod);
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
    const test_step = b.step("test", "Run the default shift proof surface.");

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
    runtime_contract_mod.addImport("shift", shift_mod);
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
    const public_root_pkg_contract_mod = b.createModule(.{
        .root_source_file = b.path("test/public_root_package_contract_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const root_pkg_opts = b.addOptions();
    root_pkg_opts.addOption([:0]const u8, "zig_exe", b.graph.zig_exe);
    public_root_pkg_contract_mod.addOptions("build_options", root_pkg_opts);
    const public_root_pkg_contract_tests = addFilteredTest(b, public_root_pkg_contract_mod, test_runner_args.filters.items);
    const run_root_pkg_contract_tests = addRunArtifactWithArgs(b, public_root_pkg_contract_tests, test_runner_args.passthrough.items);

    const root_pkg_smoke_mod = b.createModule(.{
        .root_source_file = b.path("test/public_root_package_contract_smoke_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    root_pkg_smoke_mod.addOptions("build_options", root_pkg_opts);
    const root_pkg_smoke_tests = addFilteredTest(b, root_pkg_smoke_mod, test_runner_args.filters.items);
    const run_root_pkg_smoke = addRunArtifactWithArgs(b, root_pkg_smoke_tests, test_runner_args.passthrough.items);
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
    runtime_stack_baseline_mod.addImport("example_open_row_abortive_validation", createShiftConsumerModule(b, "examples/open_row_abortive_validation.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_open_row_artifact_search", createShiftConsumerModule(b, "examples/open_row_artifact_search.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_open_row_generator", createShiftConsumerModule(b, "examples/open_row_generator.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("witnesses_src", witnesses_mod);
    runtime_stack_baseline_mod.addImport("example_early_exit", createShiftConsumerModule(b, "examples/early_exit.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_exception_basic", createShiftConsumerModule(b, "examples/exception_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_nested_workflow", createShiftConsumerModule(b, "examples/nested_workflow.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_optional_basic", createShiftConsumerModule(b, "examples/optional_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_reader_basic", createShiftConsumerModule(b, "examples/reader_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_resource_basic", createShiftConsumerModule(b, "examples/resource_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_resume_or_return", createShiftConsumerModule(b, "examples/resume_or_return.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_state_basic", createShiftConsumerModule(b, "examples/state_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_writer_basic", createShiftConsumerModule(b, "examples/writer_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
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
    source_lowering_boundary_mod.addImport("shift", shift_mod);
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
    source_lowering_completion_mod.addImport("example_resource_basic", createShiftConsumerModule(b, "examples/resource_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    source_lowering_completion_mod.addImport("example_writer_basic", createShiftConsumerModule(b, "examples/writer_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    const src_lower_completion_tests = addFilteredTest(b, source_lowering_completion_mod, test_runner_args.filters.items);
    const run_src_lower_completion_tests = addRunArtifactWithArgs(b, src_lower_completion_tests, test_runner_args.passthrough.items);

    const src_lower_smoke_mod = b.createModule(.{
        .root_source_file = b.path("test/source_lowering_completion_smoke_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    src_lower_smoke_mod.addImport("source_lowering", source_lowering_mod);
    src_lower_smoke_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const src_lower_smoke_tests = addFilteredTest(b, src_lower_smoke_mod, test_runner_args.filters.items);
    const run_src_lower_smoke = addRunArtifactWithArgs(b, src_lower_smoke_tests, test_runner_args.passthrough.items);

    const open_row_lowering_mod = b.createModule(.{
        .root_source_file = b.path("test/open_row_lowering_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    open_row_lowering_mod.addImport("authoring_build_options", authoring_build_options_mod);
    open_row_lowering_mod.addImport("effect_ir", effect_ir_mod);
    open_row_lowering_mod.addImport("source_lowering", source_lowering_mod);
    open_row_lowering_mod.addImport("program_frontend", program_frontend_mod);
    open_row_lowering_mod.addImport("shift_compile", shift_compile_mod);
    open_row_lowering_mod.addImport("shift_vm", shift_vm_mod);
    open_row_lowering_mod.addImport("example_open_row_escaped_string_helper_body", createShiftConsumerModule(b, "examples/open_row_escaped_string_helper_body.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_linear_helper_body", createShiftConsumerModule(b, "examples/open_row_linear_helper_body.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_branching_helper_body", createShiftConsumerModule(b, "examples/open_row_branching_helper_body.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_cross_file_writer", createShiftConsumerModule(b, "examples/open_row_cross_file_writer.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_helper_bool_flow", createShiftConsumerModule(b, "examples/open_row_helper_bool_flow.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_helper_value_flow", createShiftConsumerModule(b, "examples/open_row_helper_value_flow.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_helper_value_flow_cross", createShiftConsumerModule(b, "examples/open_row_helper_value_flow_cross.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_state_writer", createShiftConsumerModule(b, "examples/open_row_state_writer.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_recursive_writer", createShiftConsumerModule(b, "examples/open_row_recursive_writer.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_recursive_cross_writer", createShiftConsumerModule(b, "examples/open_row_recursive_cross_writer.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    const open_row_lowering_tests = addFilteredTest(b, open_row_lowering_mod, test_runner_args.filters.items);
    const run_open_row_lowering_tests = addRunArtifactWithArgs(b, open_row_lowering_tests, test_runner_args.passthrough.items);

    const open_row_lowering_smoke_mod = b.createModule(.{
        .root_source_file = b.path("test/open_row_lowering_smoke_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    open_row_lowering_smoke_mod.addImport("shift_compile", shift_compile_mod);
    open_row_lowering_smoke_mod.addImport("shift_vm", shift_vm_mod);
    open_row_lowering_smoke_mod.addImport("example_open_row_cross_file_writer", createShiftConsumerModule(b, "examples/open_row_cross_file_writer.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_smoke_mod.addImport("example_open_row_recursive_cross_writer", createShiftConsumerModule(b, "examples/open_row_recursive_cross_writer.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_smoke_mod.addImport("example_open_row_state_writer", createShiftConsumerModule(b, "examples/open_row_state_writer.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    const open_row_lowering_smoke_tests = addFilteredTest(b, open_row_lowering_smoke_mod, test_runner_args.filters.items);
    const run_open_row_smoke = addRunArtifactWithArgs(b, open_row_lowering_smoke_tests, test_runner_args.passthrough.items);

    const source_ownership_probe_mod = b.createModule(.{
        .root_source_file = b.path("test/source_ownership_probe_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_ownership_probe_mod.addImport("shift", shift_mod);
    source_ownership_probe_mod.addImport("shift_compile", shift_compile_mod);
    const source_ownership_probe_tests = addFilteredTest(b, source_ownership_probe_mod, test_runner_args.filters.items);
    const run_src_ownership_probe_tests = addRunArtifactWithArgs(b, source_ownership_probe_tests, test_runner_args.passthrough.items);

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

    const src_lower_reject_mod = b.createModule(.{
        .root_source_file = b.path("test/source_lowering_rejection_corpus_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    src_lower_reject_mod.addImport("source_lowering", source_lowering_mod);
    const src_lower_reject_tests = addFilteredTest(b, src_lower_reject_mod, test_runner_args.filters.items);
    const run_src_lower_reject_tests = addRunArtifactWithArgs(b, src_lower_reject_tests, test_runner_args.passthrough.items);

    const source_lowering_tool_mod = b.createModule(.{
        .root_source_file = b.path("tools/shift_source_lower.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_tool_mod.addImport("source_lowering", source_lowering_mod);
    source_lowering_tool_mod.addImport("lowered_machine", lowered_machine_mod);
    source_lowering_tool_mod.addImport("error_witness", error_witness_mod);
    const source_lowering_tool_exe = b.addExecutable(.{
        .name = "shift-source-lower",
        .root_module = source_lowering_tool_mod,
    });
    const source_lowering_tool_install = b.addInstallArtifact(source_lowering_tool_exe, .{});
    const source_lowering_tool_step = b.step("source-lower", "Build the internal source-lowering tool.");
    source_lowering_tool_step.dependOn(&source_lowering_tool_exe.step);
    source_lowering_tool_step.dependOn(&source_lowering_tool_install.step);

    lexical_witness_runners_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);

    const lexical_witness_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_witness_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_witness_mod.addImport("shift", shift_shared_mod);
    lexical_witness_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
    lexical_witness_mod.addImport("parity_scenarios", parity_scenarios_mod);
    lexical_witness_mod.addImport("lexical_witness_runners", lexical_witness_runners_mod);
    const lexical_witness_tests = addFilteredTest(b, lexical_witness_mod, test_runner_args.filters.items);
    const run_lexical_witness_tests = addRunArtifactWithArgs(b, lexical_witness_tests, test_runner_args.passthrough.items);

    const lexical_with_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_with_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
    const named_basic_support_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_named_body_basic_support.zig"),
        .target = target,
        .optimize = optimize,
    });
    const named_optional_support_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_named_body_optional_support.zig"),
        .target = target,
        .optimize = optimize,
    });
    const named_generated_support_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_named_body_generated_support.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lexical_with_tests = addFilteredTest(b, lexical_with_mod, test_runner_args.filters.items);
    const run_lexical_with_tests_core = addRunArtifactWithArgs(b, lexical_with_tests, test_runner_args.passthrough.items);

    const lexical_with_preview_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_preview_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_with_preview_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
    const lexical_with_preview_tests = addFilteredTest(b, lexical_with_preview_mod, test_runner_args.filters.items);
    const run_lexical_with_preview_tests = addRunArtifactWithArgs(b, lexical_with_preview_tests, test_runner_args.passthrough.items);

    const lexical_with_fixture_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_fixture_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_with_fixture_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
    const lexical_with_fixture_tests = addFilteredTest(b, lexical_with_fixture_mod, test_runner_args.filters.items);
    const run_lexical_with_fixture_tests = addRunArtifactWithArgs(b, lexical_with_fixture_tests, test_runner_args.passthrough.items);

    const lex_fix_ctl_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_fixture_control_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lex_fix_ctl_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
    const lex_fix_ctl_tests = addFilteredTest(b, lex_fix_ctl_mod, test_runner_args.filters.items);
    const run_lex_fix_ctl = addRunArtifactWithArgs(b, lex_fix_ctl_tests, test_runner_args.passthrough.items);

    const lex_fix_res_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_fixture_resource_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lex_fix_res_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
    const lex_fix_res_tests = addFilteredTest(b, lex_fix_res_mod, test_runner_args.filters.items);
    const run_lex_fix_res = addRunArtifactWithArgs(b, lex_fix_res_tests, test_runner_args.passthrough.items);

    const lex_fix_opt_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_fixture_optional_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lex_fix_opt_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
    const lex_fix_opt_tests = addFilteredTest(b, lex_fix_opt_mod, test_runner_args.filters.items);
    const run_lex_fix_opt = addRunArtifactWithArgs(b, lex_fix_opt_tests, test_runner_args.passthrough.items);

    const lexical_with_runtime_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_runtime_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_with_runtime_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
    const lexical_with_runtime_tests = addFilteredTest(b, lexical_with_runtime_mod, test_runner_args.filters.items);
    const run_lexical_with_runtime_tests = addRunArtifactWithArgs(b, lexical_with_runtime_tests, test_runner_args.passthrough.items);

    const lexical_with_named_body_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_named_body_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_with_named_body_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
    lexical_with_named_body_mod.addImport("lexical_with_named_body_basic_support", named_basic_support_mod);
    const lexical_with_named_body_tests = addFilteredTest(b, lexical_with_named_body_mod, test_runner_args.filters.items);
    const run_lexical_with_named_tests = addRunArtifactWithArgs(b, lexical_with_named_body_tests, test_runner_args.passthrough.items);

    const lex_named_opt_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_named_body_optional_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lex_named_opt_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
    lex_named_opt_mod.addImport("lexical_with_named_body_optional_support", named_optional_support_mod);
    const lex_named_opt_tests = addFilteredTest(b, lex_named_opt_mod, test_runner_args.filters.items);
    const run_lex_named_opt = addRunArtifactWithArgs(b, lex_named_opt_tests, test_runner_args.passthrough.items);

    const lex_named_gen_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_named_body_generated_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lex_named_gen_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
    lex_named_gen_mod.addImport("lexical_with_named_body_generated_support", named_generated_support_mod);
    const lex_named_gen_tests = addFilteredTest(b, lex_named_gen_mod, test_runner_args.filters.items);
    _ = addRunArtifactWithArgs(b, lex_named_gen_tests, test_runner_args.passthrough.items);

    const namedbody_conformance_mod = b.createModule(.{
        .root_source_file = b.path("test/namedbody_conformance_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    namedbody_conformance_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
    const namedbody_tests = addFilteredTest(b, namedbody_conformance_mod, test_runner_args.filters.items);
    const run_namedbody = addRunArtifactWithArgs(b, namedbody_tests, test_runner_args.passthrough.items);

    const namedbody_conformance_full_mod = b.createModule(.{
        .root_source_file = b.path("test/namedbody_conformance_full_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    namedbody_conformance_full_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
    const namedbody_full_tests = addFilteredTest(b, namedbody_conformance_full_mod, test_runner_args.filters.items);
    const run_namedbody_full = addRunArtifactWithArgs(b, namedbody_full_tests, test_runner_args.passthrough.items);

    lexical_with_preview_tests.step.dependOn(&run_lexical_with_tests_core.step);
    lexical_with_fixture_tests.step.dependOn(&run_lexical_with_preview_tests.step);
    lex_fix_opt_tests.step.dependOn(&run_lexical_with_fixture_tests.step);
    lex_fix_ctl_tests.step.dependOn(&run_lex_fix_opt.step);
    lex_fix_res_tests.step.dependOn(&run_lex_fix_ctl.step);
    lexical_with_runtime_tests.step.dependOn(&run_lex_fix_res.step);
    lex_named_opt_tests.step.dependOn(&run_lexical_with_named_tests.step);
    lex_named_gen_tests.step.dependOn(&run_lex_named_opt.step);

    const run_lexical_with_tests = b.step("lexical-with-core", "Run the core lexical-with suite.");
    run_lexical_with_tests.dependOn(&run_lexical_with_runtime_tests.step);

    const run_namedbody_step = b.step("lexical-with-namedbody", "Run the NamedBody lexical-with conformance suite.");
    run_namedbody_step.dependOn(&run_namedbody.step);

    const run_namedbody_conformance_full = b.step("namedbody-conformance-full", "Run the full NamedBody conformance registry.");
    run_namedbody_conformance_full.dependOn(&run_namedbody_full.step);

    const run_lexical_with_all = b.step("lexical-with-all", "Run the full lexical-with suite.");
    run_lexical_with_all.dependOn(run_lexical_with_tests);
    run_lexical_with_all.dependOn(run_namedbody_step);

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
        .{ .suite_id = "frontend", .description = "Frontend internal module", .run_step = &run_frontend_internal_tests.step },
        .{ .suite_id = "program-plan-review", .description = "ProgramPlan regression suite", .run_step = &run_plan_review_tests.step },
        .{ .suite_id = "program-bridge", .description = "Program bridge suite", .run_step = &run_program_bridge_tests.step },
        .{ .suite_id = "witness-corpus", .description = "Core witness corpus", .run_step = &run_witness_tests.step },
        .{ .suite_id = "runtime-contract", .description = "Runtime contract suite", .run_step = &run_runtime_contract_tests.step },
        .{ .suite_id = "prompt-token", .description = "Prompt token contract suite", .run_step = &run_prompt_token_tests.step },
        .{ .suite_id = "portability-contract", .description = "Portability contract suite", .run_step = &run_portability_contract_tests.step },
        .{ .suite_id = "public-root-package-contract", .description = "Public root package contract smoke suite", .default_enabled = false, .run_step = &run_root_pkg_smoke.step },
        .{ .suite_id = "public-root-package-contract-full", .description = "Public root package contract suite", .default_enabled = false, .run_step = &run_root_pkg_contract_tests.step },
        .{ .suite_id = "program-frontend-boundary", .description = "Program frontend boundary suite", .run_step = &run_boundary_tests.step },
        .{ .suite_id = "source-lowering-corpus", .description = "Source lowering corpus suite", .run_step = &run_src_lower_corpus_tests.step },
        .{ .suite_id = "source-lowering-boundary", .description = "Source lowering boundary suite", .run_step = &run_src_lower_boundary_tests.step },
        .{ .suite_id = "source-lowering-promoted", .description = "Promoted source lowering cohort", .run_step = &run_src_lower_promoted_tests.step },
        .{ .suite_id = "source-lowering-completion", .description = "Source lowering completion smoke suite", .run_step = &run_src_lower_smoke.step },
        .{ .suite_id = "source-lowering-completion-full", .description = "Source lowering completion suite", .default_enabled = false, .run_step = &run_src_lower_completion_tests.step },
        .{ .suite_id = "open-row-lowering", .description = "Open-row lowering smoke suite", .run_step = &run_open_row_smoke.step },
        .{ .suite_id = "open-row-lowering-full", .description = "Open-row lowering full suite", .default_enabled = false, .run_step = &run_open_row_lowering_tests.step },
        .{ .suite_id = "source-ownership-probe", .description = "Source ownership probe suite", .run_step = &run_src_ownership_probe_tests.step },
        .{ .suite_id = "source-lowering-witness", .description = "Source lowering witness completion suite", .run_step = &run_src_lower_witness_tests.step },
        .{ .suite_id = "source-lowering-reject", .description = "Source lowering rejection corpus suite", .run_step = &run_src_lower_reject_tests.step },
        .{ .suite_id = "lexical-witness", .description = "Lexical witness suite", .run_step = &run_lexical_witness_tests.step },
        .{ .suite_id = "lexical-with", .description = "Core lexical with suite", .run_step = run_lexical_with_tests },
        .{ .suite_id = "lexical-with-namedbody", .description = "NamedBody lexical conformance suite", .default_enabled = false, .run_step = run_namedbody_step },
        .{ .suite_id = "namedbody-conformance-full", .description = "Full NamedBody conformance registry", .default_enabled = false, .run_step = run_namedbody_conformance_full },
    };
    const test_suite_selection = resolveTestSuiteSelection(b, test_suites_raw, &test_suites, test_requested) orelse return;
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
    };

    inline for (examples) |example| {
        const mod = b.createModule(.{
            .root_source_file = b.path(example.src),
            .target = target,
            .optimize = optimize,
        });
        mod.addImport("shift", shift_mod);
        mod.addImport("shift_compile", shift_compile_mod);
        mod.addImport("shift_vm", shift_vm_mod);
        mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);

        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = mod,
        });
        b.installArtifact(exe);
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
        mod.addImport("shift", shift_mod);
        mod.addImport("shift_compile", shift_compile_mod);
        mod.addImport("shift_vm", shift_vm_mod);
        mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);

        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = mod,
        });
        b.installArtifact(exe);
        check_step.dependOn(&exe.step);

        const run = b.addRunArtifact(exe);
        const run_step = b.step(example.run_step_name, example.run_step_desc);
        run_step.dependOn(&run.step);
    }

    const shift_bench_mod = b.createModule(.{
        .root_source_file = b.path("src/bench_support.zig"),
        .target = target,
        .optimize = bench_optimize,
    });
    shift_bench_mod.addImport("portable_core", portable_core_mod);
    shift_bench_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    shift_bench_mod.addImport("frontend_support", frontend_support_mod);
    shift_bench_mod.addImport("error_witness", error_witness_mod);
    shift_bench_mod.addImport("parity_scenarios", parity_scenarios_mod);
    shift_bench_mod.addImport("effect_ir", effect_ir_mod);
    shift_bench_mod.addImport("internal_kernel", internal_kernel_mod);
    shift_bench_mod.addImport("internal_program_plan", internal_program_plan_mod);
    shift_bench_mod.addImport("interpreter", interpreter_mod);
    shift_bench_mod.addImport("source_graph_engine", source_graph_engine_mod);
    shift_bench_mod.addImport("source_graph_comptime", source_graph_comptime_mod);
    shift_bench_mod.addImport("lowered_machine", lowered_machine_mod);
    shift_bench_mod.addImport("program_frontend", program_frontend_mod);
    shift_bench_mod.addImport("authoring_build_options", authoring_build_options_mod);
    shift_bench_mod.addImport("source_graph_embed", source_graph_embed_mod);
    shift_bench_mod.addImport("authoring_lowerer", authoring_lowerer_mod);
    shift_bench_mod.addImport("source_lowering", source_lowering_mod);
    const bench_specs = [_]struct {
        name: []const u8,
        src: []const u8,
        step_name: []const u8,
        step_desc: []const u8,
    }{
        .{
            .name = "shift-direct-no-capture-bench",
            .src = "bench/no_capture_bench.zig",
            .step_name = "bench",
            .step_desc = "Run the direct-style no-capture benchmark.",
        },
        .{
            .name = "shift-direct-first-suspend-bench",
            .src = "bench/direct_first_suspend_bench.zig",
            .step_name = "bench-first-suspend",
            .step_desc = "Run the direct-style first-suspend benchmark.",
        },
        .{
            .name = "shift-state-effect-bench",
            .src = "bench/state_effect_bench.zig",
            .step_name = "bench-state-effect",
            .step_desc = "Compare the additive state effect against the raw prompt baseline.",
        },
        .{
            .name = "shift-effect-family-matrix-bench",
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
        bench_mod.addImport("shift", shift_bench_mod);
        bench_mod.addImport("lowered_machine", lowered_machine_mod);
        const bench_exe = b.addExecutable(.{
            .name = bench_spec.name,
            .root_module = bench_mod,
        });
        const bench_run = b.addRunArtifact(bench_exe);
        const bench_step = b.step(bench_spec.step_name, bench_spec.step_desc);
        bench_step.dependOn(&bench_run.step);
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
        .name = "shift-runtime-backend-matrix-bench",
        .root_module = runtime_backend_bench_mod,
    });
    const runtime_backend_bench_run = b.addRunArtifact(runtime_backend_bench_exe);
    const runtime_backend_bench_step = b.step("bench-runtime-backends", "Compare the current stack runtime against the lowered runtime over the supported bridge corpus.");
    runtime_backend_bench_step.dependOn(&runtime_backend_bench_run.step);

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
        zprof_hotspots_mod.addImport("shift", shift_bench_mod);
        zprof_hotspots_mod.addImport("zprof", zprof_dep.module("zprof"));
        const zprof_hotspots_exe = b.addExecutable(.{
            .name = "shift-zprof-hotspots",
            .root_module = zprof_hotspots_mod,
        });
        const zprof_hotspots_run = b.addRunArtifact(zprof_hotspots_exe);
        zprof_hotspots_step.dependOn(&zprof_hotspots_run.step);
    }

    const lint_step = b.step("lint", "Lint source code.");
    lint_step.dependOn(step: {
        const saved_verbose = b.verbose;
        const saved_args = b.args;
        b.verbose = true;
        b.args = lint_shared_tail_args;
        defer {
            b.verbose = saved_verbose;
            b.args = saved_args;
        }
        var builder = zlinter.builder(b, .{});
        builder.addPaths(.{
            // Feed zlinter the explicit repo path registry so lint stays fail-closed
            // without relying on recursive cwd walking or exclude-index construction.
            .include = repoZigLintIncludePaths(b),
            .exclude = &.{},
        });
        inline for (@typeInfo(zlinter.BuiltinLintRule).@"enum".fields) |field| {
            const rule: zlinter.BuiltinLintRule = @enumFromInt(field.value);
            builder.addRule(.{ .builtin = rule }, .{});
        }
        break :step builder.build();
    });
}
