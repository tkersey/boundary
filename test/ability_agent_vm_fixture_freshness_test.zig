const ability_compile = @import("ability_compile");
const fixture = @import("ability_agent_vm_fixture_spec.zig");
const std = @import("std");

fn loadFixtureBytes(allocator: std.mem.Allocator) ![]u8 {
    return try std.Io.Dir.cwd().readFileAlloc(
        std.Io.Threaded.global_single_threaded.io(),
        fixture.artifact_path,
        allocator,
        .limited(1 << 20),
    );
}

test "ability_agent_vm smoke fixture matches current compiler output" {
    const allocator = std.testing.allocator;
    const bytes = try loadFixtureBytes(allocator);
    defer allocator.free(bytes);

    const generated = try ability_compile.compileAndEncode(
        allocator,
        fixture.source_path,
        fixture.FixtureSpec,
        .{},
    );
    defer allocator.free(generated);

    const fixture_disasm = try ability_compile.artifact.disasmAlloc(allocator, bytes);
    defer allocator.free(fixture_disasm);
    const generated_disasm = try ability_compile.artifact.disasmAlloc(allocator, generated);
    defer allocator.free(generated_disasm);

    try std.testing.expectEqualStrings(generated_disasm, fixture_disasm);
}
