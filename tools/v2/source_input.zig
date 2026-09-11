//! Exact, data-only reader for the staged Module JSON emitted by emit_source.
//! All metadata numbers remain decimal token strings until checked conversion.
const std = @import("std");
const boundary = @import("boundary");
const ast = boundary.source.ast;
const ParseError = error{ InvalidSource, InvalidNumber, UnknownField, MissingField };

pub const Decoded = struct {
    arena: std.heap.ArenaAllocator,
    module: ast.Module,

    pub fn deinit(self: *Decoded) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !Decoded {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const storage = arena.allocator();
    const json = try std.json.parseFromSliceLeaky(std.json.Value, storage, bytes, .{
        .parse_numbers = false,
        .allocate = .alloc_always,
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = false,
    });
    const module = try value(ast.Module, storage, json);
    return .{ .arena = arena, .module = module };
}

fn value(comptime T: type, a: std.mem.Allocator, input: std.json.Value) (ParseError || std.mem.Allocator.Error)!T {
    return switch (@typeInfo(T)) {
        .int => blk: {
            if (input != .number_string or input.number_string.len == 0) return error.InvalidNumber;
            const token = input.number_string;
            for (token) |byte| if (byte < '0' or byte > '9') return error.InvalidNumber;
            if (token.len > 1 and token[0] == '0') return error.InvalidNumber;
            break :blk std.fmt.parseInt(T, token, 10) catch return error.InvalidNumber;
        },
        .bool => if (input == .bool) input.bool else error.InvalidSource,
        .void => if (input == .object and input.object.count() == 0) {} else error.InvalidSource,
        .optional => |info| if (input == .null) null else try value(info.child, a, input),
        .@"enum" => if (input == .string)
            std.meta.stringToEnum(T, input.string) orelse error.InvalidSource
        else
            error.InvalidSource,
        .pointer => |info| blk: {
            if (info.size != .slice) @compileError("staged source contains a non-slice pointer");
            if (input != .array) return error.InvalidSource;
            const output = try a.alloc(info.child, input.array.items.len);
            for (output, input.array.items) |*to, from| to.* = try value(info.child, a, from);
            break :blk output;
        },
        .@"struct" => try record(T, a, input),
        .@"union" => |info| blk: {
            if (input != .object or input.object.count() != 1) return error.InvalidSource;
            const tag = input.object.keys()[0];
            inline for (info.fields) |field| {
                if (std.mem.eql(u8, tag, field.name)) {
                    break :blk @unionInit(T, field.name, try value(field.type, a, input.object.values()[0]));
                }
            }
            return error.UnknownField;
        },
        else => @compileError("classify the new staged-source field type"),
    };
}

fn record(comptime T: type, a: std.mem.Allocator, input: std.json.Value) (ParseError || std.mem.Allocator.Error)!T {
    if (input != .object) return error.InvalidSource;
    var output: T = undefined;
    inline for (@typeInfo(T).@"struct".fields) |field| {
        @field(output, field.name) = if (input.object.get(field.name)) |item|
            try value(field.type, a, item)
        else if (field.defaultValue()) |default|
            default
        else
            return error.MissingField;
    }
    for (input.object.keys()) |key| {
        var known = false;
        inline for (@typeInfo(T).@"struct".fields) |field| {
            known = known or std.mem.eql(u8, key, field.name);
        }
        if (!known) return error.UnknownField;
    }
    return output;
}

test "metadata integers never pass through a floating-point value" {
    const a = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(std.json.Value, a, "18446744073709551615", .{ .parse_numbers = false });
    defer parsed.deinit();
    try std.testing.expectEqual(std.math.maxInt(u64), try value(u64, a, parsed.value));
    for ([_][]const u8{ "\"1\"", "1e0", "1.0", "-1", "18446744073709551616" }) |text| {
        var bad = try std.json.parseFromSlice(std.json.Value, a, text, .{ .parse_numbers = false });
        defer bad.deinit();
        try std.testing.expectError(error.InvalidNumber, value(u64, a, bad.value));
    }
}

test "duplicate fields and ambiguous union tags reject" {
    const a = std.testing.allocator;
    try std.testing.expectError(error.DuplicateField, decode(a, "{\"entry\":0,\"entry\":1}"));
    var bad = try std.json.parseFromSlice(std.json.Value, a, "{\"u64\":{},\"unit\":{}}", .{});
    defer bad.deinit();
    try std.testing.expectError(error.InvalidSource, value(@import("boundary_data_v2").program.Schema, a, bad.value));
}

test "decoded arena custody includes buffers allocated by the final typed traversal" {
    const a = std.testing.allocator;
    const schemas: [129]@import("boundary_data_v2").program.Schema = @splat(.unit);
    for (1..130) |count| {
        const source: ast.Module = .{
            .entry = 0,
            .failure = 0,
            .schemas = schemas[0..count],
            .constants = &.{},
            .effects = &.{},
            .handlers = &.{},
            .region_count = 0,
            .variables = &.{},
            .values = &.{},
            .terms = &.{},
            .functions = &.{},
        };
        const bytes = try std.json.Stringify.valueAlloc(a, source, .{ .emit_strings_as_arrays = true });
        defer a.free(bytes);
        var decoded = try decode(a, bytes);
        defer decoded.deinit();
        try std.testing.expectEqual(count, decoded.module.schemas.len);
        for (decoded.module.schemas) |schema| try std.testing.expect(schema == .unit);
    }
}
