const example = @import("example_open_row_state_writer");
const shift_compile = @import("shift_compile");
const shift_vm = @import("shift_vm");
const std = @import("std");

test "CompileSource encodes repo-owned authored programs into ArtifactV1 bytes" {
    const Compiler = shift_compile.CompileSource(
        "examples/open_row_state_writer.zig",
        example.loweringSpec(),
        .{
            .build_fingerprint_seed = "artifact-api-test",
            .capabilities = &.{},
        },
    );

    const bytes = try Compiler.encode(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    var decoded = try shift_vm.artifact.decode(std.testing.allocator, bytes);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqual(Compiler.ir_hash, decoded.semantic_ir_hash64);
    try std.testing.expectEqual(@as(usize, Compiler.runtime_plan.functions.len), decoded.functions.len);
    try std.testing.expectEqual(@as(usize, Compiler.runtime_plan.instructions.len), decoded.instructions.len);
    try std.testing.expectEqual(@as(usize, Compiler.runtime_plan.requirements.len), decoded.requirement_capability_ids.len);
}

test "compileAndEncode produces readable disasm" {
    const bytes = try shift_compile.compileAndEncode(
        std.testing.allocator,
        "examples/open_row_state_writer.zig",
        example.loweringSpec(),
        .{
            .build_fingerprint_seed = "artifact-disasm-test",
            .capabilities = &.{},
        },
    );
    defer std.testing.allocator.free(bytes);

    const disasm = try shift_vm.artifact.disasmAlloc(std.testing.allocator, bytes);
    defer std.testing.allocator.free(disasm);

    try std.testing.expect(std.mem.indexOf(u8, disasm, "ArtifactV1") != null);
    try std.testing.expect(std.mem.indexOf(u8, disasm, "functions=") != null);
}
