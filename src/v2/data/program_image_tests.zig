const std = @import("std");
const image = @import("program_image.zig");
const ir = @import("activation.zig");
const p = @import("program.zig");
const testing = std.testing;

const example: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit },
    .constants = &.{.{ .schema = 0, .bytes = &.{ 42, 0, 0, 0, 0, 0, 0, 0 } }},
    .effects = &.{},
    .functions = &.{.{ .entry = 0, .inputs = &.{}, .layout = .{ .slots = &.{0} }, .result = 0 }},
    .blocks = &.{.{ .function = 0, .instructions = &.{.{ .destination = 0, .opcode = .constant }}, .terminator = .{ .return_value = 0 } }},
};

// Independently transcribed from the documented grammar, not encoder output.
const golden = "ABL_BPI3".* ++ [_]u8{
    3, 0, 0, 0, 32, 0, 0, 0, 0, 0, 0, 0, // framing
    1, 0, 0, 1, // roots
    2, 9, 0, // schemas: u64, unit
    1, 0, 8, 1, 42, // literal: u64 42
    0, // effects
    1, 0, 0, 0, 1, 0, 0, // one function, one slot
    1, 0, 1, 0, 0, 0, 0, // one block: constant to slot 0, return 0
    0, 0, 0, 0, 0, // handlers, captures, regions, resources, constructors
};

test "immutable admitted images share facts without accepting mutable lookalikes" {
    var bytes = golden;
    const admitted = try image.Admitted.decode(testing.allocator, &bytes);
    defer admitted.deinit();
    @memset(&bytes, 0xff);
    try testing.expectEqualDeep(example, admitted.program());
    const retained = admitted.storageBytes();
    var first = try admitted.analysis(testing.allocator);
    defer first.deinit();
    var second = try admitted.analysis(testing.allocator);
    defer second.deinit();
    try testing.expect(first.facts.live.ptr == second.facts.live.ptr);
    try testing.expect(first.facts.pool != second.facts.pool);
    const root = first.facts.live[0][1];
    try testing.expect(first.facts.pool.contains(root, 0));
    try testing.expectEqual(@import("analysis_sets.zig").empty, try first.facts.pool.remove(root, 0));
    try testing.expect(second.facts.pool.contains(root, 0));
    try testing.expectEqual(retained, admitted.storageBytes());
    const state: @import("process_state.zig").State = .{
        .program_identity = admitted.identity(),
        .status = .active,
        .roots = .{ .current = .{ .id = 0 } },
        .nodes = &.{.{ .record = .{ .control = .{ .block = 0, .arguments = &.{} } }, .activation = .{
            .position = 1,
            .scope = 0,
            .owners = &.{},
            .bindings = &.{.{ .slot = 0, .value = .{ .schema = 0, .body = .{ .scalar = .{ 42, 0, 0, 0, 0, 0, 0, 0 } } } }},
        } }},
    };
    try @import("state_admission.zig").validateAdmitted(testing.allocator, admitted, state);
    var lookalike = admitted.program();
    lookalike.roots.entry = 999;
    try testing.expectError(error.InvalidReference, @import("state_admission.zig").validateStable(testing.allocator, lookalike, state));
    try @import("state_admission.zig").validateAdmitted(testing.allocator, admitted, state);
}

fn admittedFailure(allocator: std.mem.Allocator) !void {
    const owner = try image.Admitted.decode(allocator, &golden);
    defer owner.deinit();
    var analysis = try owner.analysis(allocator);
    defer analysis.deinit();
    try testing.expectEqualDeep(example, owner.program());
}
test "immutable admitted image allocation failures release records and facts" {
    try testing.checkAllAllocationFailures(testing.allocator, admittedFailure, .{});
}

test "BPI3 scalar and unit golden encodings" {
    var bytes: [256]u8 = undefined;
    try testing.expectEqualSlices(u8, &golden, try image.encode(testing.allocator, example, &bytes));
    var decoded = try image.decode(testing.allocator, &golden);
    defer decoded.deinit();
    try testing.expectEqualDeep(example, decoded.program);
    var unit = example;
    unit.roots.failure = 0;
    unit.schemas = &.{.unit};
    unit.constants = &.{.{ .schema = 0, .bytes = &.{} }};
    const unit_golden = "ABL_BPI3".* ++ [_]u8{
        3, 0, 0, 0, 29, 0, 0, 0, 0, 0, 0, 0,
        1, 0, 0, 0, 1,  0, 1, 0, 0, 0, 1, 0,
        0, 0, 1, 0, 0,  1, 0, 1, 0, 0, 0, 0,
        0, 0, 0, 0, 0,
    };
    try testing.expectEqualSlices(u8, &unit_golden, try image.encode(testing.allocator, unit, &bytes));
    var decoded_unit = try image.decode(testing.allocator, &unit_golden);
    defer decoded_unit.deinit();
    try testing.expectEqualDeep(unit, decoded_unit.program);
}

test "BPI3 rejects redundant defaults and compressed expansion bombs" {
    var noncanonical: [golden.len + 1]u8 = undefined;
    @memcpy(noncanonical[0..45], golden[0..45]);
    noncanonical[12] += 1;
    noncanonical[43] = 64; // Explicit zero immediate must be omitted.
    noncanonical[45] = 0;
    @memcpy(noncanonical[46..], golden[45..]);
    try testing.expectError(error.NonCanonical, image.decode(testing.allocator, &noncanonical));

    // Replace the one-slot layout with a short repeated-ID descriptor for 2^30 slots.
    const bomb = golden[0..37].* ++ [_]u8{ 128, 128, 128, 128, 4, 1, 1, 128, 128, 128, 128, 4, 0 } ++ golden[39..].*;
    var framed = bomb;
    std.mem.writeInt(u64, framed[12..20], framed.len - 20, .little);
    try testing.expectError(error.Capacity, image.decode(testing.allocator, &framed));
}

test "BPI3 owns decoded records and binds identity to its canonical bytes" {
    var bytes: [256]u8 = undefined;
    const encoded = try image.encode(testing.allocator, example, &bytes);
    var decoded = try image.decode(testing.allocator, encoded);
    defer decoded.deinit();
    @memset(&bytes, 0xff);
    try testing.expectEqualDeep(example, decoded.program);
    try testing.expectEqual(try image.identity(testing.allocator, example), decoded.identity);
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(image.identity_domain);
    hash.update(decoded.bytes);
    try testing.expectEqual(hash.finalResult(), decoded.identity);
}

test "BPI3 rejects output overlap and capacity without mutation" {
    var bytes = [_]u8{0} ** 256;
    const constants = [_]p.Literal{.{ .schema = 0, .bytes = bytes[0..8] }};
    var program = example;
    program.constants = &constants;
    try testing.expectError(error.InvalidBuffers, image.encode(testing.allocator, program, &bytes));
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 256), &bytes);
    @memset(&bytes, 0xa5);
    try testing.expectError(error.Capacity, image.encode(testing.allocator, example, bytes[0..1]));
    try testing.expectEqualSlices(u8, &([_]u8{0xa5} ** 256), &bytes);
    program = example;
    program.roots.entry = 999;
    try testing.expectError(error.InvalidReference, image.encode(testing.allocator, program, &bytes));
    try testing.expectEqualSlices(u8, &([_]u8{0xa5} ** 256), &bytes);
}

test "BPI3 single-bit mutations either reject or remain admitted canonical owners" {
    for (0..golden.len) |position| {
        for (0..8) |bit| {
            var mutated = golden;
            mutated[position] ^= @as(u8, 1) << @intCast(bit);
            if (image.decode(testing.allocator, &mutated)) |value| {
                var decoded = value;
                defer decoded.deinit();
                var output: [256]u8 = undefined;
                try testing.expectEqualSlices(u8, &mutated, try image.encode(testing.allocator, decoded.program, &output));
                try testing.expectEqual(try image.identity(testing.allocator, decoded.program), decoded.identity);
            } else |_| {}
        }
    }
}

fn allocationFailure(allocator: std.mem.Allocator) !void {
    var bytes = [_]u8{0xa5} ** 256;
    const encoded = image.encode(allocator, example, &bytes) catch |err| {
        for (bytes) |byte| try testing.expectEqual(@as(u8, 0xa5), byte);
        return err;
    };
    var decoded = try image.decode(allocator, encoded);
    defer decoded.deinit();
    try testing.expectEqualDeep(example, decoded.program);
}

test "BPI3 allocation failures release owners and leave uncommitted output intact" {
    try testing.checkAllAllocationFailures(testing.allocator, allocationFailure, .{});
}

test "BPI3 framing rejects truncation, old families, flags and trailing input" {
    var bytes: [256]u8 = undefined;
    const encoded = try image.encode(testing.allocator, example, &bytes);
    for (0..encoded.len) |length| {
        if (image.decode(testing.allocator, encoded[0..length])) |value| {
            var owner = value;
            owner.deinit();
            return error.AcceptedTruncation;
        } else |_| {}
    }
    for ([_][]const u8{ "ABL_BPI1", "ABL_BPI2", "ABL_BPC1", "ABL_PST1", "ABL_PST2" }) |family| {
        @memcpy(bytes[0..8], family);
        try testing.expectError(error.InvalidFamily, image.decode(testing.allocator, encoded));
    }
    @memcpy(bytes[0..8], "ABL_BPI3");
    bytes[8] = 2;
    try testing.expectError(error.UnsupportedVersion, image.decode(testing.allocator, encoded));
    bytes[8] = 3;
    bytes[10] = 1;
    try testing.expectError(error.InvalidFlags, image.decode(testing.allocator, encoded));
    bytes[10] = 0;
    try testing.expectError(error.InvalidLength, image.decode(testing.allocator, bytes[0 .. encoded.len + 1]));
    try testing.expectError(error.Capacity, image.decodeLimited(testing.allocator, encoded, .{ .max_decoded_bytes = encoded.len }));
}
