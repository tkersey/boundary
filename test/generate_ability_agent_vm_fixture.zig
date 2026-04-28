const ability_compile = @import("ability_compile");
const fixture = @import("ability_agent_vm_fixture_spec.zig");
const std = @import("std");

const max_fixture_bytes = 1 << 20;

const Mode = enum {
    check,
    help,
    write,
};

fn modeFromArgs(args: []const [:0]const u8) !Mode {
    if (args.len == 1) return .write;
    if (args.len == 2 and (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h"))) return .help;
    if (args.len == 2 and std.mem.eql(u8, args[1], "--check")) return .check;
    return error.InvalidAbilityAgentVmFixtureGeneratorArgs;
}

fn writeUsage(writer: anytype) !void {
    try writer.writeAll("usage: generate-ability-agent-vm-fixture [--check]\n");
}

fn compatIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

fn generateFixtureBytes(allocator: std.mem.Allocator) ![]u8 {
    return try ability_compile.compileAndEncode(
        allocator,
        fixture.source_path,
        fixture.FixtureSpec,
        .{},
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
    const mode = modeFromArgs(args) catch |err| {
        var stderr_buffer: [256]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writerStreaming(init.io, &stderr_buffer);
        const stderr = &stderr_writer.interface;
        try stderr.writeAll("generate-ability-agent-vm-fixture: invalid arguments\n");
        try writeUsage(stderr);
        try stderr.flush();
        return err;
    };

    switch (mode) {
        .help => {
            var stdout_buffer: [128]u8 = undefined;
            var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
            const stdout = &stdout_writer.interface;
            try writeUsage(stdout);
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
    try std.testing.expectEqual(Mode.write, try modeFromArgs(&.{"generate-ability-agent-vm-fixture"}));
    try std.testing.expectEqual(Mode.check, try modeFromArgs(&.{ "generate-ability-agent-vm-fixture", "--check" }));
    try std.testing.expectEqual(Mode.help, try modeFromArgs(&.{ "generate-ability-agent-vm-fixture", "--help" }));
    try std.testing.expectEqual(Mode.help, try modeFromArgs(&.{ "generate-ability-agent-vm-fixture", "-h" }));
    try std.testing.expectError(
        error.InvalidAbilityAgentVmFixtureGeneratorArgs,
        modeFromArgs(&.{ "generate-ability-agent-vm-fixture", "--bad" }),
    );
}

test "ability_agent_vm fixture freshness check matches committed artifact" {
    try checkCommittedFixtureFreshness(
        compatIo(),
        std.testing.allocator,
        std.testing.allocator,
    );
}
