const std = @import("std");
const compact = @import("compact_image.zig");
const sequence = @import("compact_sequence.zig");
const wire = @import("wire.zig");
const p = @import("program.zig");
const image = @import("image.zig");
const example = @import("tests.zig").example;

test "admission checks the owned header even when allocation changes caller input" {
    const Mutating = struct {
        child: std.mem.Allocator,
        input: []u8,
        changed: bool = false,

        fn allocate(ptr: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            if (!self.changed) {
                self.changed = true;
                self.input[10] = 1;
            }
            return self.child.rawAlloc(len, alignment, ra);
        }

        fn free(ptr: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, ra: usize) void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.child.rawFree(bytes, alignment, ra);
        }
    };
    var bytes: [256]u8 = undefined;
    const encoded = try compact.encode(std.testing.allocator, example, &bytes);
    var context: Mutating = .{ .child = std.testing.allocator, .input = &bytes };
    const allocator: std.mem.Allocator = .{ .ptr = &context, .vtable = &.{
        .alloc = Mutating.allocate,
        .resize = std.mem.Allocator.noResize,
        .remap = std.mem.Allocator.noRemap,
        .free = Mutating.free,
    } };
    if (compact.decode(allocator, encoded)) |value| {
        var owner = value;
        owner.deinit();
        return error.AcceptedChangedHeader;
    } else |err| try std.testing.expectEqual(error.InvalidFlags, err);
}

test "suffix references retain forward element order and require a full backing use" {
    const parameters = @import("compact_parameters.zig");
    var fully_used = [_]bool{false};
    const context: parameters.Reading = .{
        .backings = &.{&.{ 7, 3, 9, 1 }},
        .fully_used = &fully_used,
    };
    var requested: usize = 0;
    var reader: wire.Reader = .{ .input = &.{ 3, 3, 0 } };
    try std.testing.expectEqualSlices(p.Id, &.{ 3, 9, 1 }, try context.parameters(&reader, std.testing.allocator, &requested));
    try std.testing.expect(!fully_used[0]);
    reader = .{ .input = &.{ 4, 3, 0 } };
    _ = try context.parameters(&reader, std.testing.allocator, &requested);
    try std.testing.expect(fully_used[0]);
}

fn sequenceRoundTrip(comptime T: type, values: []const T) !void {
    const allocator = std.testing.allocator;
    var buffer: [8192]u8 = undefined;
    var writer: wire.Writer = .{ .output = &buffer };
    try sequence.write(T, values, &writer);
    var reader: wire.Reader = .{ .input = buffer[0..writer.position] };
    var requested: usize = 0;
    const decoded = try sequence.read(T, true, &reader, allocator, &requested);
    defer allocator.free(decoded);
    try reader.finish();
    try std.testing.expectEqualDeep(values, decoded);
}

test "typed sequences preserve literals, full-width IDs, and arbitrary returned holes" {
    try sequenceRoundTrip(p.Id, &.{});
    try sequenceRoundTrip(p.Id, &.{std.math.maxInt(u64)});
    try sequenceRoundTrip(p.Id, &.{ 5, 5, 5, 5, 5, 0, 1, 2, 3, 4, 1, 8, 1 });
    try sequenceRoundTrip(p.Argument, &.{ .{ .slot = 8 }, .returned, .{ .slot = 2 }, .{ .slot = 3 }, .{ .slot = 4 }, .returned, .returned, .{ .slot = 0 } });
    var longs: [128]p.Argument = undefined;
    for (&longs, 0..) |*value, index| value.* = .{ .slot = index };
    longs[127] = .returned;
    try sequenceRoundTrip(p.Argument, &longs);
}

fn allocationFailure(allocator: std.mem.Allocator) !void {
    var bytes = [_]u8{0xa5} ** 256;
    const encoded = compact.encode(allocator, example, &bytes) catch |err| {
        for (bytes) |byte| try std.testing.expectEqual(@as(u8, 0xa5), byte);
        return err;
    };
    var decoded = try compact.decode(allocator, encoded);
    defer decoded.deinit();
    try std.testing.expectEqualDeep(example, decoded.program);
}

test "compact output overlapping nested source bytes rejects atomically" {
    var bytes = [_]u8{0} ** 256;
    var constants = [_]p.Literal{.{ .schema = 0, .bytes = bytes[0..8] }};
    var program = example;
    program.constants = &constants;
    try std.testing.expectError(error.InvalidBuffers, compact.encode(std.testing.allocator, program, &bytes));
    for (bytes) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
}

test "distinct legal packed spellings retain the same logical identity" {
    const program: p.Program = .{
        .roots = .{ .entry = 0, .result = 0, .failure = 0 },
        .schemas = &.{.u64},
        .constants = &.{},
        .effects = &.{},
        .functions = &.{.{ .entry = 0, .parameters = &.{ 0, 0, 0 }, .result = 0 }},
        .blocks = &.{.{ .function = 0, .parameters = &.{ 0, 0, 0 }, .instructions = &.{}, .terminator = .{ .return_value = 1 } }},
    };
    var original: [256]u8 = undefined;
    const encoded = try compact.encode(std.testing.allocator, program, &original);
    var alternate: [256]u8 = undefined;
    @memcpy(alternate[0..encoded.len], encoded);
    const index = wire.header_length + std.mem.indexOf(u8, encoded[wire.header_length..], &.{ 3, 0, 0, 0, 0 }).?;
    @memcpy(alternate[index..][0..5], &[_]u8{ 3, 1, 1, 3, 0 });
    var decoded = try compact.decode(std.testing.allocator, alternate[0..encoded.len]);
    defer decoded.deinit();
    try std.testing.expectEqualDeep(program, decoded.program);
    try std.testing.expectEqual(try image.identity(program), try image.identity(decoded.program));
    var normalized: [256]u8 = undefined;
    const repeated = try compact.encode(std.testing.allocator, decoded.program, &normalized);
    try std.testing.expectEqualSlices(u8, encoded, repeated);
}

test "parameter references and returned ranges validate before storage or traversal" {
    const parameters = @import("compact_parameters.zig");
    var fully_used = [_]bool{false};
    const context: parameters.Reading = .{ .backings = &.{&.{ 0, 1 }}, .fully_used = &fully_used };
    var requested: usize = 0;
    var reader: wire.Reader = .{ .input = &.{ 3, 2, 0 } };
    try std.testing.expectError(error.InvalidLength, context.parameters(&reader, std.testing.allocator, &requested));
    reader = .{ .input = &.{ 3, 2, 1 } };
    try std.testing.expectError(error.InvalidLength, context.parameters(&reader, std.testing.allocator, &requested));
    reader = .{ .input = &.{ 3, 1, 2, 3, 1 } };
    try std.testing.expectError(error.InvalidTag, sequence.read(p.Argument, true, &reader, std.testing.allocator, &requested));
}

test "canonical hand-authored continuation keeps a returned hole between slot operands" {
    const program: p.Program = .{
        .roots = .{ .entry = 0, .result = 0, .failure = 0 },
        .schemas = &.{.u64},
        .constants = &.{},
        .effects = &.{.{ .identity = "compact/holes", .payload = 0, .result = 0 }},
        .functions = &.{.{ .entry = 0, .parameters = &.{ 0, 0 }, .result = 0, .effects = &.{0} }},
        .blocks = &.{
            .{ .function = 0, .parameters = &.{ 0, 0 }, .instructions = &.{}, .terminator = .{ .perform = .{ .effect = 0, .payload = 0, .next = .{ .block = 1, .arguments = &.{ .{ .slot = 1 }, .returned, .{ .slot = 0 } } } } } },
            .{ .function = 0, .parameters = &.{ 0, 0, 0 }, .instructions = &.{}, .terminator = .{ .return_value = 1 } },
        },
    };
    var normalized = try @import("canonical.zig").normalize(std.testing.allocator, program);
    defer normalized.deinit();
    var buffer: [1024]u8 = undefined;
    const bytes = try compact.encode(std.testing.allocator, normalized.program, &buffer);
    var decoded = try compact.decode(std.testing.allocator, bytes);
    defer decoded.deinit();
    try std.testing.expectEqualDeep(normalized.program, decoded.program);
    try std.testing.expect(decoded.program.blocks[0].terminator.perform.next.arguments[1] == .returned);
    try std.testing.expectEqual(try image.identity(normalized.program), try image.identity(decoded.program));
}

test "a short prefix cannot retain an otherwise unused expanded parameter backing" {
    var slots: [12]p.Argument = undefined;
    for (&slots, 0..) |*value, index| value.* = .{ .slot = index };
    const schemas = [_]p.Id{0} ** 16;
    const program: p.Program = .{
        .roots = .{ .entry = 0, .result = 0, .failure = 0 },
        .schemas = &.{.u64},
        .constants = &.{},
        .effects = &.{},
        .functions = &.{.{ .entry = 0, .parameters = &schemas, .result = 0 }},
        .blocks = &.{
            .{ .function = 0, .parameters = &schemas, .instructions = &.{}, .terminator = .{ .jump = .{ .block = 1, .arguments = &slots } } },
            .{ .function = 0, .parameters = schemas[0..12], .instructions = &.{}, .terminator = .{ .jump = .{ .block = 2, .arguments = slots[0..8] } } },
            .{ .function = 0, .parameters = schemas[0..8], .instructions = &.{}, .terminator = .{ .jump = .{ .block = 3, .arguments = slots[0..4] } } },
            .{ .function = 0, .parameters = schemas[0..4], .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        },
    };
    var normalized = try @import("canonical.zig").normalize(std.testing.allocator, program);
    defer normalized.deinit();
    var bytes: [1024]u8 = undefined;
    const encoded = try compact.encode(std.testing.allocator, normalized.program, &bytes);
    var reader: wire.Reader = .{ .input = encoded, .position = wire.header_length };
    try std.testing.expectEqual(@as(u64, 1), try reader.natural());
    const length_position = reader.position;
    try std.testing.expectEqual(@as(u64, 16), try reader.natural());
    try std.testing.expectEqual(@as(u8, 1), try reader.byte());
    try std.testing.expectEqual(@as(u8, 1), try reader.byte());
    const run_position = reader.position;
    try std.testing.expectEqual(@as(u64, 16), try reader.natural());
    bytes[length_position] = 17;
    bytes[run_position] = 17;
    try std.testing.expectError(error.NonCanonical, compact.decode(std.testing.allocator, encoded));
}

test "hand-authored compact images free every partial owner on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationFailure, .{});
}

test "malformed compact framing and every truncation reject" {
    var bytes: [256]u8 = undefined;
    const encoded = try compact.encode(std.testing.allocator, example, &bytes);
    try std.testing.expect(compact.isCompact(encoded));
    for (0..encoded.len) |end| {
        if (compact.decode(std.testing.allocator, encoded[0..end])) |value| {
            var owner = value;
            owner.deinit();
            return error.AcceptedTruncation;
        } else |_| {}
    }
    bytes[8] = 2;
    try std.testing.expectError(error.UnsupportedVersion, compact.decode(std.testing.allocator, encoded));
    bytes[8] = 1;
    bytes[10] = 1;
    try std.testing.expectError(error.InvalidFlags, compact.decode(std.testing.allocator, encoded));
}

test "range endpoint and expanded allocation overflow reject before expansion" {
    var reader: wire.Reader = .{ .input = &.{ 3, 1, 2, 3, 255, 255, 255, 255, 255, 255, 255, 255, 255, 1 } };
    var requested: usize = 0;
    try std.testing.expectError(error.InvalidLength, sequence.read(p.Id, false, &reader, std.testing.allocator, &requested));
    reader = .{ .input = &.{ 255, 255, 255, 255, 255, 255, 255, 255, 255, 1 } };
    try std.testing.expectError(error.InvalidLength, sequence.read(p.Argument, false, &reader, std.testing.allocator, &requested));
}

test "compact mutations never bypass canonical admission or escape caller backing" {
    var source: [256]u8 = undefined;
    const encoded = try compact.encode(std.testing.allocator, example, &source);
    var mutated: [256]u8 = undefined;
    var storage: [256 << 10]u8 = undefined;
    for (0..encoded.len) |index| for ([_]u8{ 0, 1, 127, 128, 255 }) |replacement| {
        @memcpy(mutated[0..encoded.len], encoded);
        mutated[index] = replacement;
        var fixed = std.heap.FixedBufferAllocator.init(&storage);
        if (compact.decode(fixed.allocator(), mutated[0..encoded.len])) |value| {
            var owner = value;
            defer owner.deinit();
            try @import("canonical.zig").require(std.testing.allocator, owner.program);
            _ = try image.identity(owner.program);
        } else |_| {}
    };
}
