const std = @import("std");
const data = @import("root.zig");
const program_record = @import("program_record.zig");
const testing = std.testing;
const example: data.component.Object = .{
    .program = .{
        .roots = .{ .entry = 0, .result = 0, .failure = 1 },
        .schemas = &.{ .u64, .unit },
        .constants = &.{.{ .schema = 0, .bytes = &.{ 42, 0, 0, 0, 0, 0, 0, 0 } }},
        .effects = &.{},
        .functions = &.{.{ .entry = 0, .inputs = &.{}, .layout = .{ .slots = &.{0} }, .result = 0 }},
        .blocks = &.{.{ .function = 0, .instructions = &.{.{ .destination = 0, .opcode = .constant }}, .terminator = .{ .return_value = 0 } }},
    },
    .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }},
};

// Independently transcribed grammar: stable scalar Program, no imports, main export.
const golden = "ABL_BMO1".* ++ [_]u8{
    1,   0,   0,   0, 41, 0, 0, 0, 0, 0, 0, 0,
    1,   0,   0,   1, 2,  9, 0, 1, 0, 8, 1, 42,
    0,   1,   0,   0, 0,  1, 0, 0, 1, 0, 1, 0,
    0,   0,   0,   0, 0,  0, 0, 0, 0, 1, 4, 'm',
    'a', 'i', 'n', 3, 0,
};

test "BMO1 golden framing and canonical owned decode" {
    var buffer: [256]u8 = undefined;
    try testing.expectEqualSlices(u8, &golden, try data.component.encode(testing.allocator, example, &buffer));
    var bytes = golden;
    var decoded = try data.component.decode(testing.allocator, &bytes);
    defer decoded.deinit();
    @memset(&bytes, 0xff);
    try testing.expectEqualDeep(example, decoded.object);
    for (0..golden.len) |length| {
        if (data.component.decode(testing.allocator, golden[0..length])) |owner| {
            var invalid = owner;
            invalid.deinit();
            return error.ExpectedError;
        } else |_| {}
    }
    bytes = golden;
    bytes[8] = 2;
    try testing.expectError(error.UnsupportedVersion, data.component.decode(testing.allocator, &bytes));
    bytes = golden;
    bytes[10] = 1;
    try testing.expectError(error.InvalidFlags, data.component.decode(testing.allocator, &bytes));
    bytes = golden;
    bytes[golden.len - 2] = 10;
    try testing.expectError(error.InvalidTag, data.component.decode(testing.allocator, &bytes));
    bytes[golden.len - 2] = 255;
    try testing.expectError(error.NonCanonical, data.component.decode(testing.allocator, &bytes));
}

// Deliberately bypass the checked emitter to exercise untrusted public admission.
fn forgedObject(object_value: data.component.Object) ![]u8 {
    const bytes = try testing.allocator.alloc(u8, try data.component.encodedLength(object_value));
    errdefer testing.allocator.free(bytes);
    var writer: data.wire.Writer = .{ .output = bytes };
    try writer.put(data.component.magic);
    try writer.fixed(u16, 1);
    try writer.fixed(u16, 0);
    try writer.fixed(u64, bytes.len - data.wire.header_length);
    var context: program_record.Context = .{};
    try program_record.write(data.activation.Program, object_value.program, &writer, &context);
    try @import("record.zig").write([]const data.component.Symbol, object_value.imports, &writer);
    try @import("record.zig").write([]const data.component.Symbol, object_value.exports, &writer);
    return bytes;
}

test "public linker rejects forged resource elimination authority" {
    const bytes = try forgedObject(example);
    defer testing.allocator.free(bytes);
    var decoded = try data.component.decode(testing.allocator, bytes);
    defer decoded.deinit();
    var forged = decoded.object;
    forged.program.scopes.resources = &.{.{ .representation = forged.program.roots.result, .introducers = &.{}, .eliminators = &.{0} }};
    forged.imports = &.{.{ .name = "resource", .reference = .{ .kind = .resource, .id = 0 } }};
    const invalid = try forgedObject(forged);
    defer testing.allocator.free(invalid);
    try testing.expectError(error.InvalidOwnership, data.linker.link(testing.allocator, &.{.{ .key = "forged", .object = invalid }}, &.{}, .{ .instance = "forged", .symbol = "main" }));
}

test "declared region cardinality is bounded before relocation allocation" {
    var excessive = example;
    excessive.program.scopes.region_count = std.math.maxInt(u64);
    const bytes = try forgedObject(excessive);
    defer testing.allocator.free(bytes);
    try testing.expectError(error.Capacity, data.component.decode(testing.allocator, bytes));
}

test "cyclic unresolved aliases reject without recursive linking" {
    var object_value = example;
    object_value.program.functions = &.{ example.program.functions[0], .{
        .entry = data.relocation.missing,
        .inputs = &.{},
        .layout = .{ .slots = &.{} },
        .result = 0,
    } };
    object_value.imports = &.{.{ .name = "need", .reference = .{ .kind = .function, .id = 1 } }};
    object_value.exports = &.{.{ .name = "alias", .reference = .{ .kind = .function, .id = 1 } }};
    var buffer: [256]u8 = undefined;
    const bytes = try data.component.encode(testing.allocator, object_value, &buffer);
    const bindings = [_]data.linker.Binding{
        .{ .required = .{ .instance = "a", .symbol = "need" }, .supplied = .{ .instance = "b", .symbol = "alias" } },
        .{ .required = .{ .instance = "b", .symbol = "need" }, .supplied = .{ .instance = "a", .symbol = "alias" } },
    };
    try testing.expectError(error.UnresolvedImport, data.linker.link(testing.allocator, &.{ .{ .key = "a", .object = bytes }, .{ .key = "b", .object = bytes } }, &bindings, .{ .instance = "a", .symbol = "alias" }));
}
