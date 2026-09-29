// Copyright (c) 2026 Boundary contributors. MIT license.
//! Offline-only extraction from checked BPI3 records. No solver is imported.
const std = @import("std");
const data = @import("boundary_data");
const Node = struct { opcode: []const u8, schema: u64, bits: u8, slot: u64, instruction: ?usize = null, input: ?usize = null, value: u64 = 0, operands: []const usize = &.{} };
fn width(schema: data.program.Schema) !u8 {
    return switch (schema) {
        .u8 => 8,
        .u16 => 16,
        .u32 => 32,
        .u64 => 64,
        else => error.UnsupportedFragment,
    };
}
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const path = args.next() orelse return error.ExpectedImage;
    if (args.next() != null) return error.UnexpectedArgument;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(1 << 20));
    var decoded = try data.program_image.decodeLimited(a, bytes, .{ .max_decoded_bytes = 8 << 20 });
    defer decoded.deinit();
    const program = decoded.program;
    if (program.functions.len != 1 or program.blocks.len != 1) return error.UnsupportedFragment;
    const f = program.functions[0];
    const block = program.blocks[0];
    if (f.entry != 0 or f.effects.len != 0 or f.regions.len != 0 or f.custody.len != 1 or block.custody != 0 or block.terminator != .return_value) return error.UnsupportedFragment;
    if (f.inputs.len > 8 or f.layout.slots.len > 4096 or block.instructions.len > 128) return error.ExtractionLimit;
    const slots = try a.alloc(?usize, f.layout.slots.len);
    @memset(slots, null);
    var nodes: std.ArrayList(Node) = .empty;
    for (f.inputs, 0..) |slot, index| {
        const schema = f.layout.slots[@intCast(slot)];
        const bits = try width(program.schemas[@intCast(schema)]);
        slots[@intCast(slot)] = nodes.items.len;
        try nodes.append(a, .{ .opcode = "input", .schema = schema, .bits = bits, .slot = slot, .input = index });
    }
    for (block.instructions, 0..) |op, index| {
        if (op.failures.len != 0) return error.UnsupportedFragment;
        const schema = f.layout.slots[@intCast(op.destination)];
        const bits = try width(program.schemas[@intCast(schema)]);
        if (op.opcode == .move) {
            if (op.operands.len != 1) return error.UnsupportedFragment;
            slots[@intCast(op.destination)] = slots[@intCast(op.operands[0])] orelse return error.UnsupportedFragment;
            continue;
        }
        var node: Node = .{ .opcode = @tagName(op.opcode), .schema = schema, .bits = bits, .slot = op.destination, .instruction = index };
        switch (op.opcode) {
            .constant => {
                const value = program.constants[@intCast(op.immediate)];
                if (value.schema != schema or value.bytes.len != bits / 8) return error.UnsupportedFragment;
                for (value.bytes, 0..) |byte, i| node.value |= @as(u64, byte) << @as(u6, @intCast(i * 8));
            },
            .integer_bit_xor, .integer_bit_and, .integer_bit_or, .integer_bit_not => {
                const arity: usize = if (op.opcode == .integer_bit_not) 1 else 2;
                if (op.operands.len != arity) return error.UnsupportedFragment;
                const operands = try a.alloc(usize, arity);
                for (op.operands, operands) |slot, *operand| {
                    operand.* = slots[@intCast(slot)] orelse return error.UnsupportedFragment;
                    if (nodes.items[operand.*].schema != schema or nodes.items[operand.*].bits != bits) return error.UnsupportedFragment;
                }
                node.operands = operands;
            },
            else => return error.UnsupportedFragment,
        }
        slots[@intCast(op.destination)] = nodes.items.len;
        try nodes.append(a, node);
    }
    const result = slots[@intCast(block.terminator.return_value)] orelse return error.UnsupportedFragment;
    const identity = std.fmt.bytesToHex(decoded.identity, .lower);
    var raw_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &raw_digest, .{});
    const raw_identity = std.fmt.bytesToHex(raw_digest, .lower);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{ .format = "boundary-bitvectors/v1", .image_identity = identity[0..], .image_sha256 = raw_identity[0..], .encoding_complete = true, .evaluation = "total-straight-line-eager", .input_domain = "all-bit-patterns", .nodes = nodes.items, .result = result }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
