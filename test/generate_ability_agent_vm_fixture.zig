const ability_compile = @import("ability_compile");
const fixture = @import("ability_agent_vm_fixture_spec.zig");
const fixture_generator_options = @import("fixture_generator_options");
const std = @import("std");

const max_fixture_bytes = 1 << 20;

const Mode = enum {
    check,
    help,
    version,
    write,
};

fn isModeArg(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "--help") or
        std.mem.eql(u8, arg, "-h") or
        std.mem.eql(u8, arg, "--check") or
        std.mem.eql(u8, arg, "--write") or
        std.mem.eql(u8, arg, "--version");
}

fn modeFromArgs(args: []const [:0]const u8) !Mode {
    if (args.len == 1) return .check;
    if (args.len == 2 and isModeArg(args[1])) {
        if (std.mem.eql(u8, args[1], "--check")) return .check;
        if (std.mem.eql(u8, args[1], "--write")) return .write;
        if (std.mem.eql(u8, args[1], "--version")) return .version;
        return .help;
    }
    return error.InvalidAbilityAgentVmFixtureGeneratorArgs;
}

fn invalidArg(args: []const [:0]const u8) ?[]const u8 {
    if (args.len == 2) return args[1];
    if (args.len > 2) {
        return if (isModeArg(args[1])) args[2] else args[1];
    }
    return null;
}

fn writeUsage(writer: anytype) !void {
    try writer.writeAll(
        "usage: generate-ability-agent-vm-fixture [--check|--write|--version|--help]\n" ++
            "\n" ++
            "flags:\n" ++
            "  --check        verify the committed fixture is current\n" ++
            "  --write        regenerate the committed fixture\n" ++
            "  --version      print the tool version\n" ++
            "  --help, -h     print this help\n",
    );
}

fn compatIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

fn generateFixtureBytes(allocator: std.mem.Allocator) ![]u8 {
    return try ability_compile.compileAndEncode(
        allocator,
        fixture.source_path,
        fixture.FixtureSpec,
        .{ .stable_build_fingerprint_seed = "ability-agent-vm-smoke-fixture-v1" },
    );
}

fn readCommittedFixtureBytes(io: std.Io, allocator: std.mem.Allocator) ![]u8 {
    return try std.Io.Dir.cwd().readFileAlloc(
        io,
        fixture.artifact_path,
        allocator,
        .limited(max_fixture_bytes),
    );
}

fn checkCommittedFixtureFreshness(
    io: std.Io,
    generated_allocator: std.mem.Allocator,
    committed_allocator: std.mem.Allocator,
) !void {
    const bytes = try generateFixtureBytes(generated_allocator);
    defer generated_allocator.free(bytes);

    const fixture_bytes = try readCommittedFixtureBytes(io, committed_allocator);
    defer committed_allocator.free(fixture_bytes);

    if (!std.mem.eql(u8, bytes, fixture_bytes)) {
        std.log.err(
            "stale {s}; regenerate with `zig build generate-ability-agent-vm-fixture`",
            .{fixture.artifact_path},
        );
        return error.StaleAbilityAgentVmFixture;
    }
}

/// Regenerate the committed public agent-vm artifact fixture.
pub fn main(init: std.process.Init) anyerror!void {
    var arena_buffer: [1 << 20]u8 = undefined;
    var fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(&arena_buffer);
    const allocator = fixed_buffer_allocator.allocator();

    const args = try init.minimal.args.toSlice(allocator);
    const mode = modeFromArgs(args) catch {
        var stderr_buffer: [256]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writerStreaming(init.io, &stderr_buffer);
        const stderr = &stderr_writer.interface;
        if (invalidArg(args)) |arg| {
            try stderr.print("generate-ability-agent-vm-fixture: invalid argument '{s}'\n", .{arg});
        } else {
            try stderr.writeAll("generate-ability-agent-vm-fixture: invalid arguments\n");
        }
        try writeUsage(stderr);
        try stderr.flush();
        std.process.exit(1);
    };

    switch (mode) {
        .help => {
            var stdout_buffer: [128]u8 = undefined;
            var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
            const stdout = &stdout_writer.interface;
            try writeUsage(stdout);
            try stdout.flush();
        },
        .version => {
            var stdout_buffer: [64]u8 = undefined;
            var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
            const stdout = &stdout_writer.interface;
            try stdout.print("generate-ability-agent-vm-fixture {s}\n", .{fixture_generator_options.version});
            try stdout.flush();
        },
        .write => {
            const bytes = try generateFixtureBytes(allocator);
            try std.Io.Dir.cwd().writeFile(init.io, .{
                .sub_path = fixture.artifact_path,
                .data = bytes,
                .flags = .{ .truncate = true },
            });
        },
        .check => try checkCommittedFixtureFreshness(init.io, allocator, std.heap.page_allocator),
    }
}

test "ability_agent_vm fixture generator args expose help and reject unknowns" {
    try std.testing.expectEqual(Mode.check, try modeFromArgs(&.{"generate-ability-agent-vm-fixture"}));
    try std.testing.expectEqual(Mode.check, try modeFromArgs(&.{ "generate-ability-agent-vm-fixture", "--check" }));
    try std.testing.expectEqual(Mode.write, try modeFromArgs(&.{ "generate-ability-agent-vm-fixture", "--write" }));
    try std.testing.expectEqual(Mode.version, try modeFromArgs(&.{ "generate-ability-agent-vm-fixture", "--version" }));
    try std.testing.expectEqual(Mode.help, try modeFromArgs(&.{ "generate-ability-agent-vm-fixture", "--help" }));
    try std.testing.expectEqual(Mode.help, try modeFromArgs(&.{ "generate-ability-agent-vm-fixture", "-h" }));
    try std.testing.expectError(
        error.InvalidAbilityAgentVmFixtureGeneratorArgs,
        modeFromArgs(&.{ "generate-ability-agent-vm-fixture", "--bad" }),
    );
    try std.testing.expectEqualStrings("--bad", invalidArg(&.{ "generate-ability-agent-vm-fixture", "--bad" }).?);
    try std.testing.expectEqualStrings("--bad", invalidArg(&.{ "generate-ability-agent-vm-fixture", "--bad", "extra" }).?);
    try std.testing.expectEqualStrings("extra", invalidArg(&.{ "generate-ability-agent-vm-fixture", "--check", "extra" }).?);
    try std.testing.expectEqualStrings("extra", invalidArg(&.{ "generate-ability-agent-vm-fixture", "--version", "extra" }).?);
    try std.testing.expectEqualStrings("extra", invalidArg(&.{ "generate-ability-agent-vm-fixture", "--help", "extra" }).?);
}

test "ability_agent_vm fixture freshness check matches committed artifact" {
    try checkCommittedFixtureFreshness(
        compatIo(),
        std.testing.allocator,
        std.testing.allocator,
    );
}
