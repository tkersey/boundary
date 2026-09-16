const std = @import("std");
const protocol = @import("invocation.zig");
const testing = std.testing;

fn request() !protocol.Request {
    // Independently encoded canonical descriptors: root 0, one u64 / Boolean.
    return protocol.request(.{
        .program_identity = .{1} ** 32,
        .pending_state_digest = .{2} ** 32,
        .effect = 3,
        .semantic_identity = "operation",
        .payload_schema = &.{ 0, 1, 9 },
        .resume_schema = &.{ 0, 1, 1 },
        .payload = &.{ 42, 0, 0, 0, 0, 0, 0, 0 },
    });
}

test "ERQ3 binds nominal effect and exact state and ERS3 owns its decoded bytes" {
    const expected = try request();
    const bytes = try protocol.encodeOwned(protocol.Request, testing.allocator, expected);
    defer testing.allocator.free(bytes);
    var decoded = try protocol.decode(protocol.Request, testing.allocator, bytes);
    defer decoded.deinit();
    @memset(bytes, 0xff);
    try testing.expectEqualDeep(expected, decoded.value);
    var response: protocol.Result = .{ .request_identity = expected.request_identity, .value = &.{1} };
    try protocol.validateResult(testing.allocator, expected, response);
    var changed = expected;
    changed.binding.effect += 1;
    changed.request_identity = try protocol.requestIdentity(changed.binding);
    try testing.expectError(error.InvalidResult, protocol.validateResult(testing.allocator, changed, response));
    changed = expected;
    changed.binding.pending_state_digest[0] ^= 1;
    changed.request_identity = try protocol.requestIdentity(changed.binding);
    try testing.expectError(error.InvalidResult, protocol.validateResult(testing.allocator, changed, response));
    response.value = &.{2};
    try testing.expectError(error.InvalidValue, protocol.validateResult(testing.allocator, expected, response));
}

test "current envelope golden tags and owned decode" {
    const value: protocol.Input = .{ .image = &.{}, .instance = .{ .initial_args = &.{} }, .quantum = 0 };
    const golden = "ABL_PKI3".* ++ [_]u8{ 3, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0 };
    const bytes = try protocol.encodeOwned(protocol.Input, testing.allocator, value);
    defer testing.allocator.free(bytes);
    try testing.expectEqualSlices(u8, &golden, bytes);
    var decoded = try protocol.decode(protocol.Input, testing.allocator, &golden);
    defer decoded.deinit();
    try testing.expectEqualDeep(value, decoded.value);
    var changed = golden;
    changed[7] = '2';
    try testing.expectError(error.InvalidFamily, protocol.decode(protocol.Input, testing.allocator, &changed));
    changed = golden;
    changed[10] = 1;
    try testing.expectError(error.InvalidFlags, protocol.decode(protocol.Input, testing.allocator, &changed));
}

test "current envelopes reject initial replies and malformed outcomes atomically" {
    var output = [_]u8{0xa5} ** 256;
    const input: protocol.Input = .{ .image = &.{}, .instance = .{ .initial_args = &.{} }, .control = .{ .reply = &.{} } };
    try testing.expectError(error.InvalidControl, protocol.encode(protocol.Input, testing.allocator, input, &output));
    try testing.expectError(error.InvalidUtf8, protocol.encode(protocol.Outcome, testing.allocator, .{ .cancelled = .{ .reason = .{ .text = &.{0xff} } } }, &output));
    try testing.expectError(error.InvalidOutcome, protocol.encode(protocol.Outcome, testing.allocator, .{ .needs_capacity = .{ .arena = .output, .output = .{ .bytes = 4 } } }, &output));
    for (output) |byte| try testing.expectEqual(0xa5, byte);
    const overlapping: protocol.Input = .{ .image = output[0..3], .instance = .{ .initial_args = &.{} } };
    try testing.expectError(error.InvalidBuffers, protocol.encode(protocol.Input, testing.allocator, overlapping, &output));
    for (output) |byte| try testing.expectEqual(0xa5, byte);
}

fn failure(allocator: std.mem.Allocator) !void {
    const value = try request();
    const bytes = try protocol.encodeOwned(protocol.Request, allocator, value);
    defer allocator.free(bytes);
    var decoded = try protocol.decode(protocol.Request, allocator, bytes);
    defer decoded.deinit();
    try testing.expectEqualDeep(value, decoded.value);
}
test "current request allocation failures release schema and envelope owners" {
    try testing.checkAllAllocationFailures(testing.allocator, failure, .{});
}
