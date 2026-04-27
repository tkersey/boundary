const ability_compile = @import("ability_compile");
const fixture = @import("ability_agent_vm_fixture_spec.zig");
const std = @import("std");

const Mode = enum {
    check,
    write,
};

fn modeFromArgs(args: []const [:0]const u8) !Mode {
    if (args.len == 1) return .write;
    if (args.len == 2 and std.mem.eql(u8, args[1], "--check")) return .check;
    return error.InvalidAbilityAgentVmFixtureGeneratorArgs;
}

/// Regenerate the committed public agent-vm artifact fixture.
pub fn main(init: std.process.Init) anyerror!void {
    var arena_buffer: [1 << 20]u8 = undefined;
    var fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(&arena_buffer);
    const allocator = fixed_buffer_allocator.allocator();

    const mode = try modeFromArgs(try init.minimal.args.toSlice(allocator));
    const bytes = try ability_compile.compileAndEncode(
        allocator,
        fixture.source_path,
        fixture.FixtureSpec,
        .{},
    );

    switch (mode) {
        .write => try std.Io.Dir.cwd().writeFile(init.io, .{
            .sub_path = fixture.artifact_path,
            .data = bytes,
            .flags = .{ .truncate = true },
        }),
        .check => {
            const fixture_bytes = try std.Io.Dir.cwd().readFileAlloc(
                init.io,
                fixture.artifact_path,
                allocator,
                .limited(1 << 20),
            );
            if (!std.mem.eql(u8, bytes, fixture_bytes)) {
                std.log.err(
                    "stale {s}; regenerate with `zig build generate-ability-agent-vm-fixture`",
                    .{fixture.artifact_path},
                );
                return error.StaleAbilityAgentVmFixture;
            }
        },
    }
}
