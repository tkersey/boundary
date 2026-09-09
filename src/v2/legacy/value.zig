// Frozen BPI1 data/validation from Boundary 1.8.2, commit
// 999e936c4a865cd31948b52b2af2baeacf84c9f1. MIT license. No evaluator.
const std = @import("std");

pub const Error = error{
    InvalidSchema,
    InvalidUtf8,
    InvalidValue,
    LengthOverflow,
    LimitExceeded,
    TrailingBytes,
};

pub const Kind = enum(u8) {
    unit = 0,
    bool = 1,
    i8 = 2,
    i16 = 3,
    i32 = 4,
    i64 = 5,
    u8 = 6,
    u16 = 7,
    u32 = 8,
    u64 = 9,
    bytes = 10,
    text = 11,
    array = 12,
    vector = 13,
    optional = 14,
    @"enum" = 15,
    product = 16,
    sum = 17,
};

pub const NodeIndex = struct {
    offset: u32,
    length: u32,
    minimum_encoded_size: u64,
    maximum_encoded_size: u64,
    structural_digest: [32]u8,
};

pub const maximum_schema_members: usize = 8192;

pub const Table = struct {
    bytes: []const u8,
    nodes: []const NodeIndex,

    pub fn count(self: Table) u32 {
        return @intCast(self.nodes.len);
    }

    pub fn node(self: Table, id: u32) Error!Node {
        if (id >= self.nodes.len) return error.InvalidSchema;
        const entry = self.nodes[id];
        const start: usize = entry.offset;
        const end = start + entry.length;
        const record = self.bytes[start..end];
        return .{
            .id = id,
            .kind = std.enums.fromInt(Kind, record[4]) orelse
                return error.InvalidSchema,
            .payload = record[8..],
            .minimum_encoded_size = entry.minimum_encoded_size,
            .maximum_encoded_size = entry.maximum_encoded_size,
        };
    }
};

pub const Node = struct {
    id: u32,
    kind: Kind,
    payload: []const u8,
    minimum_encoded_size: u64,
    maximum_encoded_size: u64,
};

pub const ValueTask = union(enum) {
    schema: u32,
    repeat: struct {
        schema: u32,
        remaining: u32,
    },
    product: struct {
        schema: u32,
        field_index: u32,
    },
};

pub const SchemaHashTask = union(enum) {
    schema: u32,
    enum_fields: struct { schema: u32, index: u32 },
    product_fields: struct { schema: u32, index: u32 },
    sum_after_tag: u32,
    sum_cases: struct { schema: u32, index: u32 },
};

/// Validate one complete BPI1 schema-section payload into caller-owned index
/// storage. Children must precede parents, making the structural DAG finite.
pub fn validateSchemaSection(
    bytes: []const u8,
    index_storage: []NodeIndex,
) Error!Table {
    if (bytes.len < 4) return error.InvalidSchema;
    const node_count = readInt(u32, bytes, 0);
    if (node_count > index_storage.len) return error.LimitExceeded;
    var cursor: usize = 4;
    for (0..node_count) |node_id| {
        if (bytes.len - cursor < 8) return error.InvalidSchema;
        const record_length = readInt(u32, bytes, cursor);
        if (record_length < 8) return error.InvalidSchema;
        const record_end = std.math.add(
            usize,
            cursor,
            record_length,
        ) catch return error.LengthOverflow;
        if (record_end > bytes.len) return error.InvalidSchema;
        const kind = std.enums.fromInt(Kind, bytes[cursor + 4]) orelse
            return error.InvalidSchema;
        if (bytes[cursor + 5] != 0 or
            readInt(u16, bytes, cursor + 6) != 0)
        {
            return error.InvalidSchema;
        }
        const payload = bytes[cursor + 8 .. record_end];
        const sizes = try validateNode(
            bytes,
            kind,
            payload,
            index_storage[0..node_id],
        );
        var structural_digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(
            bytes[cursor..record_end],
            &structural_digest,
            .{},
        );
        for (index_storage[0..node_id]) |prior| {
            const prior_start: usize = prior.offset;
            if (prior.length == record_length and
                std.mem.eql(u8, &prior.structural_digest, &structural_digest) and
                std.mem.eql(
                    u8,
                    bytes[prior_start .. prior_start + prior.length],
                    bytes[cursor..record_end],
                ))
            {
                return error.InvalidSchema;
            }
        }
        index_storage[node_id] = .{
            .offset = std.math.cast(u32, cursor) orelse
                return error.LengthOverflow,
            .length = record_length,
            .minimum_encoded_size = sizes.minimum,
            .maximum_encoded_size = sizes.maximum,
            .structural_digest = structural_digest,
        };
        cursor = record_end;
    }
    if (cursor != bytes.len) return error.InvalidSchema;
    return .{
        .bytes = bytes,
        .nodes = index_storage[0..node_count],
    };
}

/// Validate one exact canonical value without constructing a Zig type. The
/// caller owns the bounded traversal stack; no semantic cursor is persisted.
pub fn validateValue(
    table: Table,
    schema_id: u32,
    bytes: []const u8,
    task_storage: []ValueTask,
) Error!void {
    const consumed = try validateValuePrefix(
        table,
        schema_id,
        bytes,
        task_storage,
    );
    if (consumed != bytes.len) return error.TrailingBytes;
}

/// Validate one canonical value prefix and return its exact consumed length.
pub fn validateValuePrefix(
    table: Table,
    schema_id: u32,
    bytes: []const u8,
    task_storage: []ValueTask,
) Error!usize {
    if (schema_id >= table.nodes.len) return error.InvalidSchema;
    if (task_storage.len == 0) return error.LimitExceeded;
    var task_count: usize = 1;
    task_storage[0] = .{ .schema = schema_id };
    var cursor: usize = 0;
    while (task_count != 0) {
        task_count -= 1;
        switch (task_storage[task_count]) {
            .schema => |id| {
                const node = try table.node(id);
                switch (node.kind) {
                    .unit => {},
                    .bool => {
                        const value = try takeByte(bytes, &cursor);
                        if (value > 1) return error.InvalidValue;
                    },
                    .i8, .u8 => try take(bytes, &cursor, 1),
                    .i16, .u16 => try take(bytes, &cursor, 2),
                    .i32, .u32, .i64, .u64 => try take(
                        bytes,
                        &cursor,
                        if (node.kind == .i64 or node.kind == .u64) 8 else 4,
                    ),
                    .bytes, .text => {
                        const length = try readValueLength(bytes, &cursor);
                        const maximum = readInt(u32, node.payload, 0);
                        if (length > maximum) return error.InvalidValue;
                        const value = try takeSlice(bytes, &cursor, length);
                        if (node.kind == .text and
                            !std.unicode.utf8ValidateSlice(value))
                        {
                            return error.InvalidUtf8;
                        }
                    },
                    .array => try pushTask(task_storage, &task_count, .{
                        .repeat = .{
                            .schema = readInt(u32, node.payload, 4),
                            .remaining = readInt(u32, node.payload, 0),
                        },
                    }),
                    .vector => {
                        const length = try readValueLength(bytes, &cursor);
                        if (length > readInt(u32, node.payload, 0)) {
                            return error.InvalidValue;
                        }
                        try pushTask(task_storage, &task_count, .{
                            .repeat = .{
                                .schema = readInt(u32, node.payload, 4),
                                .remaining = length,
                            },
                        });
                    },
                    .optional => {
                        const present = try takeByte(bytes, &cursor);
                        if (present > 1) return error.InvalidValue;
                        if (present == 1) {
                            try pushTask(task_storage, &task_count, .{
                                .schema = readInt(u32, node.payload, 0),
                            });
                        }
                    },
                    .@"enum" => {
                        const tag = try readValueInt(u32, bytes, &cursor);
                        if (!tagInEnum(node, tag)) return error.InvalidValue;
                    },
                    .product => try pushTask(task_storage, &task_count, .{
                        .product = .{ .schema = id, .field_index = 0 },
                    }),
                    .sum => {
                        const tag = try readValueInt(u32, bytes, &cursor);
                        const payload_schema = sumPayloadSchema(node, tag) orelse
                            return error.InvalidValue;
                        try pushTask(task_storage, &task_count, .{
                            .schema = payload_schema,
                        });
                    },
                }
            },
            .repeat => |repeat| {
                if (repeat.remaining == 0) continue;
                const repeated = try table.node(repeat.schema);
                if (repeated.maximum_encoded_size == 0) continue;
                try pushTask(task_storage, &task_count, .{
                    .repeat = .{
                        .schema = repeat.schema,
                        .remaining = repeat.remaining - 1,
                    },
                });
                try pushTask(task_storage, &task_count, .{
                    .schema = repeat.schema,
                });
            },
            .product => |product| {
                const node = try table.node(product.schema);
                const field_count = readInt(u32, node.payload, 0);
                if (product.field_index >= field_count) continue;
                try pushTask(task_storage, &task_count, .{
                    .product = .{
                        .schema = product.schema,
                        .field_index = product.field_index + 1,
                    },
                });
                try pushTask(task_storage, &task_count, .{
                    .schema = readInt(
                        u32,
                        node.payload,
                        4 + @as(usize, product.field_index) * 4,
                    ),
                });
            },
        }
    }
    return cursor;
}

/// Reconstruct the exact `boundary-portable-schema-v2` digest without Zig
/// reflection or recursive descent.
pub fn schemaDigest(
    table: Table,
    schema_id: u32,
    task_storage: []SchemaHashTask,
) Error![32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hashBytes(&hasher, "boundary-portable-schema-v2");
    if (task_storage.len == 0) return error.LimitExceeded;
    var count: usize = 1;
    task_storage[0] = .{ .schema = schema_id };
    while (count != 0) {
        count -= 1;
        switch (task_storage[count]) {
            .schema => |id| try hashSchemaNode(
                table,
                id,
                &hasher,
                task_storage,
                &count,
            ),
            .enum_fields => |fields| {
                const node = try table.node(fields.schema);
                const field_count = readInt(u32, node.payload, 0);
                if (fields.index >= field_count) continue;
                hashU32(
                    &hasher,
                    readInt(u32, node.payload, 4 + @as(usize, fields.index) * 4),
                );
                try pushHashTask(task_storage, &count, .{ .enum_fields = .{
                    .schema = fields.schema,
                    .index = fields.index + 1,
                } });
            },
            .product_fields => |fields| {
                const node = try table.node(fields.schema);
                const field_count = readInt(u32, node.payload, 0);
                if (fields.index >= field_count) continue;
                try pushHashTask(task_storage, &count, .{ .product_fields = .{
                    .schema = fields.schema,
                    .index = fields.index + 1,
                } });
                try pushHashTask(task_storage, &count, .{ .schema = readInt(
                    u32,
                    node.payload,
                    4 + @as(usize, fields.index) * 4,
                ) });
            },
            .sum_after_tag => |sum_schema| {
                const node = try table.node(sum_schema);
                const case_count = readInt(u32, node.payload, 4);
                hashU64(&hasher, case_count);
                try pushHashTask(task_storage, &count, .{ .sum_cases = .{
                    .schema = sum_schema,
                    .index = 0,
                } });
            },
            .sum_cases => |cases| {
                const node = try table.node(cases.schema);
                const case_count = readInt(u32, node.payload, 4);
                if (cases.index >= case_count) continue;
                const offset = 8 + @as(usize, cases.index) * 8;
                hashU32(&hasher, readInt(u32, node.payload, offset));
                try pushHashTask(task_storage, &count, .{ .sum_cases = .{
                    .schema = cases.schema,
                    .index = cases.index + 1,
                } });
                try pushHashTask(task_storage, &count, .{
                    .schema = readInt(u32, node.payload, offset + 4),
                });
            },
        }
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn hashSchemaNode(
    table: Table,
    schema_id: u32,
    hasher: anytype,
    storage: []SchemaHashTask,
    count: *usize,
) Error!void {
    const node = try table.node(schema_id);
    switch (node.kind) {
        .unit => hashBytes(hasher, "unit"),
        .bool => hashBytes(hasher, "bool"),
        .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 => {
            hashBytes(hasher, "int");
            hashU32(hasher, integerBits(node.kind));
            hashBytes(
                hasher,
                if (@intFromEnum(node.kind) <= @intFromEnum(Kind.i64))
                    "signed"
                else
                    "unsigned",
            );
        },
        .bytes, .text => {
            hashBytes(hasher, if (node.kind == .bytes) "bytes" else "text");
            hashU64(hasher, readInt(u32, node.payload, 0));
        },
        .array, .vector => {
            hashBytes(hasher, if (node.kind == .array) "array" else "vector");
            hashU64(hasher, readInt(u32, node.payload, 0));
            try pushHashTask(storage, count, .{
                .schema = readInt(u32, node.payload, 4),
            });
        },
        .optional => {
            hashBytes(hasher, "optional");
            try pushHashTask(storage, count, .{
                .schema = readInt(u32, node.payload, 0),
            });
        },
        .@"enum" => {
            const field_count = readInt(u32, node.payload, 0);
            hashBytes(hasher, "enum");
            hashU64(hasher, field_count);
            try pushHashTask(storage, count, .{ .enum_fields = .{
                .schema = schema_id,
                .index = 0,
            } });
        },
        .product => {
            const field_count = readInt(u32, node.payload, 0);
            hashBytes(hasher, "product");
            hashU64(hasher, field_count);
            try pushHashTask(storage, count, .{ .product_fields = .{
                .schema = schema_id,
                .index = 0,
            } });
        },
        .sum => {
            hashBytes(hasher, "sum");
            try pushHashTask(storage, count, .{ .sum_after_tag = schema_id });
            try pushHashTask(storage, count, .{
                .schema = readInt(u32, node.payload, 0),
            });
        },
    }
}

fn pushHashTask(
    storage: []SchemaHashTask,
    count: *usize,
    task: SchemaHashTask,
) Error!void {
    if (count.* == storage.len) return error.LimitExceeded;
    storage[count.*] = task;
    count.* += 1;
}

fn integerBits(kind: Kind) u32 {
    return switch (kind) {
        .i8, .u8 => 8,
        .i16, .u16 => 16,
        .i32, .u32 => 32,
        .i64, .u64 => 64,
        .unit,
        .bool,
        .bytes,
        .text,
        .array,
        .vector,
        .optional,
        .@"enum",
        .product,
        .sum,
        => unreachable,
    };
}

fn hashU32(hasher: anytype, value: u32) void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    hasher.update(&bytes);
}

fn hashU64(hasher: anytype, value: u64) void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    hasher.update(&bytes);
}

fn hashBytes(hasher: anytype, value: []const u8) void {
    hashU64(hasher, value.len);
    hasher.update(value);
}

fn pushTask(
    storage: []ValueTask,
    count: *usize,
    task: ValueTask,
) Error!void {
    if (count.* == storage.len) return error.LimitExceeded;
    storage[count.*] = task;
    count.* += 1;
}

fn readValueLength(bytes: []const u8, cursor: *usize) Error!u32 {
    return readValueInt(u32, bytes, cursor);
}

fn readValueInt(
    comptime T: type,
    bytes: []const u8,
    cursor: *usize,
) Error!T {
    const slice = try takeSlice(bytes, cursor, @sizeOf(T));
    return std.mem.readInt(T, slice[0..@sizeOf(T)], .little);
}

fn takeByte(bytes: []const u8, cursor: *usize) Error!u8 {
    const result = try takeSlice(bytes, cursor, 1);
    return result[0];
}

fn take(bytes: []const u8, cursor: *usize, length: usize) Error!void {
    _ = try takeSlice(bytes, cursor, length);
}

fn takeSlice(
    bytes: []const u8,
    cursor: *usize,
    length: usize,
) Error![]const u8 {
    const end = std.math.add(usize, cursor.*, length) catch
        return error.InvalidValue;
    if (end > bytes.len) return error.InvalidValue;
    defer cursor.* = end;
    return bytes[cursor.*..end];
}

fn tagInEnum(node: Node, tag: u32) bool {
    const count = readInt(u32, node.payload, 0);
    for (0..count) |index| {
        if (readInt(u32, node.payload, 4 + index * 4) == tag) return true;
    }
    return false;
}

fn sumPayloadSchema(node: Node, tag: u32) ?u32 {
    const count = readInt(u32, node.payload, 4);
    for (0..count) |index| {
        const offset = 8 + index * 8;
        if (readInt(u32, node.payload, offset) == tag) {
            return readInt(u32, node.payload, offset + 4);
        }
    }
    return null;
}

const Sizes = struct {
    minimum: u64,
    maximum: u64,
};

fn validateNode(
    section: []const u8,
    kind: Kind,
    payload: []const u8,
    prior: []const NodeIndex,
) Error!Sizes {
    return switch (kind) {
        .unit => fixed(payload, 0),
        .bool, .i8, .u8 => fixed(payload, 1),
        .i16, .u16 => fixed(payload, 2),
        .i32, .u32, .@"enum" => if (kind == .@"enum")
            validateEnum(payload)
        else
            fixed(payload, 4),
        .i64, .u64 => fixed(payload, 8),
        .bytes, .text => validateBoundedBytes(payload),
        .array => validateRepeated(payload, prior, false),
        .vector => validateRepeated(payload, prior, true),
        .optional => validateOptional(payload, prior),
        .product => validateProduct(payload, prior),
        .sum => validateSum(section, payload, prior),
    };
}

fn fixed(payload: []const u8, size: u64) Error!Sizes {
    if (payload.len != 0) return error.InvalidSchema;
    return .{ .minimum = size, .maximum = size };
}

fn validateBoundedBytes(payload: []const u8) Error!Sizes {
    if (payload.len != 4) return error.InvalidSchema;
    return .{
        .minimum = 4,
        .maximum = try add(4, readInt(u32, payload, 0)),
    };
}

fn validateRepeated(
    payload: []const u8,
    prior: []const NodeIndex,
    variable: bool,
) Error!Sizes {
    if (payload.len != 8) return error.InvalidSchema;
    const count = readInt(u32, payload, 0);
    const child = try priorNode(prior, readInt(u32, payload, 4));
    const minimum = try multiply(count, child.minimum_encoded_size);
    const maximum = try multiply(count, child.maximum_encoded_size);
    if (!variable) return .{ .minimum = minimum, .maximum = maximum };
    return .{ .minimum = 4, .maximum = try add(4, maximum) };
}

fn validateOptional(
    payload: []const u8,
    prior: []const NodeIndex,
) Error!Sizes {
    if (payload.len != 4) return error.InvalidSchema;
    const child = try priorNode(prior, readInt(u32, payload, 0));
    return .{ .minimum = 1, .maximum = try add(1, child.maximum_encoded_size) };
}

fn validateEnum(payload: []const u8) Error!Sizes {
    if (payload.len < 4) return error.InvalidSchema;
    const count = readInt(u32, payload, 0);
    if (count > maximum_schema_members or
        payload.len != try recordArrayLength(4, count, 4))
    {
        return error.InvalidSchema;
    }
    if (count == 0) return .{ .minimum = 4, .maximum = 4 };
    var tags: [maximum_schema_members]u32 = undefined;
    for (0..count) |index| {
        tags[index] = readInt(u32, payload, 4 + index * 4);
    }
    std.mem.sortUnstable(u32, tags[0..count], {}, std.sort.asc(u32));
    if (count > 1) {
        for (tags[1..count], tags[0 .. count - 1]) |current, previous| {
            if (current == previous) return error.InvalidSchema;
        }
    }
    return .{ .minimum = 4, .maximum = 4 };
}

fn validateProduct(
    payload: []const u8,
    prior: []const NodeIndex,
) Error!Sizes {
    if (payload.len < 4) return error.InvalidSchema;
    const count = readInt(u32, payload, 0);
    if (count > maximum_schema_members or
        payload.len != try recordArrayLength(4, count, 4))
    {
        return error.InvalidSchema;
    }
    var sizes: Sizes = .{ .minimum = 0, .maximum = 0 };
    for (0..count) |index| {
        const child = try priorNode(
            prior,
            readInt(u32, payload, 4 + index * 4),
        );
        sizes.minimum = try add(sizes.minimum, child.minimum_encoded_size);
        sizes.maximum = try add(sizes.maximum, child.maximum_encoded_size);
    }
    return sizes;
}

fn validateSum(
    section: []const u8,
    payload: []const u8,
    prior: []const NodeIndex,
) Error!Sizes {
    if (payload.len < 8) return error.InvalidSchema;
    const tag_schema = readInt(u32, payload, 0);
    const tag_node = try priorNodeView(section, prior, tag_schema);
    if (tag_node.kind != .@"enum") return error.InvalidSchema;
    const count = readInt(u32, payload, 4);
    if (count > maximum_schema_members or
        count != readInt(u32, tag_node.payload, 0) or
        payload.len != try recordArrayLength(8, count, 8))
    {
        return error.InvalidSchema;
    }
    if (count == 0) return .{ .minimum = 4, .maximum = 4 };
    var enum_tags: [maximum_schema_members]u32 = undefined;
    var sum_tags: [maximum_schema_members]u32 = undefined;
    for (0..count) |index| {
        enum_tags[index] = readInt(u32, tag_node.payload, 4 + index * 4);
        sum_tags[index] = readInt(u32, payload, 8 + index * 8);
    }
    std.mem.sortUnstable(u32, enum_tags[0..count], {}, std.sort.asc(u32));
    std.mem.sortUnstable(u32, sum_tags[0..count], {}, std.sort.asc(u32));
    if (!std.mem.eql(u32, enum_tags[0..count], sum_tags[0..count])) {
        return error.InvalidSchema;
    }
    var minimum: u64 = std.math.maxInt(u64);
    var maximum: u64 = 0;
    for (0..count) |index| {
        const tag_offset = 8 + index * 8;
        const child = try priorNode(
            prior,
            readInt(u32, payload, tag_offset + 4),
        );
        minimum = @min(minimum, child.minimum_encoded_size);
        maximum = @max(maximum, child.maximum_encoded_size);
    }
    return .{
        .minimum = try add(4, minimum),
        .maximum = try add(4, maximum),
    };
}

fn priorNodeView(
    section: []const u8,
    prior: []const NodeIndex,
    id: u32,
) Error!Node {
    const entry = try priorNode(prior, id);
    const start: usize = entry.offset;
    const record = section[start .. start + entry.length];
    return .{
        .id = id,
        .kind = std.enums.fromInt(Kind, record[4]) orelse
            return error.InvalidSchema,
        .payload = record[8..],
        .minimum_encoded_size = entry.minimum_encoded_size,
        .maximum_encoded_size = entry.maximum_encoded_size,
    };
}

fn recordArrayLength(base: usize, count: u32, stride: usize) Error!usize {
    const entries = std.math.mul(usize, count, stride) catch
        return error.LengthOverflow;
    return std.math.add(usize, base, entries) catch error.LengthOverflow;
}

fn priorNode(prior: []const NodeIndex, id: u32) Error!NodeIndex {
    if (id >= prior.len) return error.InvalidSchema;
    return prior[id];
}

fn add(left: anytype, right: anytype) Error!u64 {
    return std.math.add(u64, @intCast(left), @intCast(right)) catch
        error.LengthOverflow;
}

fn multiply(left: anytype, right: anytype) Error!u64 {
    return std.math.mul(u64, @intCast(left), @intCast(right)) catch
        error.LengthOverflow;
}

fn readInt(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}

test "dynamic schema validation indexes canonical postorder nodes" {
    var bytes = [_]u8{0} ** 32;
    std.mem.writeInt(u32, bytes[0..4], 2, .little);
    std.mem.writeInt(u32, bytes[4..8], 8, .little);
    bytes[8] = @intFromEnum(Kind.u32);
    std.mem.writeInt(u32, bytes[12..16], 16, .little);
    bytes[16] = @intFromEnum(Kind.vector);
    std.mem.writeInt(u32, bytes[20..24], 2, .little);
    std.mem.writeInt(u32, bytes[24..28], 0, .little);
    var storage: [2]NodeIndex = undefined;
    const table = try validateSchemaSection(bytes[0..28], &storage);
    try std.testing.expectEqual(@as(u32, 2), table.count());
    const vector = try table.node(1);
    try std.testing.expectEqual(Kind.vector, vector.kind);
    try std.testing.expectEqual(@as(u64, 4), vector.minimum_encoded_size);
    try std.testing.expectEqual(@as(u64, 12), vector.maximum_encoded_size);

    var value = [_]u8{0} ** 12;
    std.mem.writeInt(u32, value[0..4], 2, .little);
    std.mem.writeInt(u32, value[4..8], 7, .little);
    std.mem.writeInt(u32, value[8..12], 11, .little);
    var tasks: [4]ValueTask = undefined;
    try validateValue(table, 1, &value, &tasks);

    std.mem.writeInt(u32, value[0..4], 3, .little);
    try std.testing.expectError(
        error.InvalidValue,
        validateValue(table, 1, &value, &tasks),
    );
}

test "zero-width arrays and vectors validate without count traversal" {
    var bytes = [_]u8{0} ** 44;
    std.mem.writeInt(u32, bytes[0..4], 3, .little);
    std.mem.writeInt(u32, bytes[4..8], 8, .little);
    bytes[8] = @intFromEnum(Kind.unit);
    std.mem.writeInt(u32, bytes[12..16], 16, .little);
    bytes[16] = @intFromEnum(Kind.array);
    std.mem.writeInt(u32, bytes[20..24], std.math.maxInt(u32), .little);
    std.mem.writeInt(u32, bytes[24..28], 0, .little);
    std.mem.writeInt(u32, bytes[28..32], 16, .little);
    bytes[32] = @intFromEnum(Kind.vector);
    std.mem.writeInt(u32, bytes[36..40], std.math.maxInt(u32), .little);
    std.mem.writeInt(u32, bytes[40..44], 0, .little);
    var nodes: [3]NodeIndex = undefined;
    const table = try validateSchemaSection(&bytes, &nodes);
    var tasks: [1]ValueTask = undefined;
    try validateValue(table, 1, &.{}, &tasks);
    var vector = [_]u8{0xff} ** 4;
    try validateValue(table, 2, &vector, &tasks);
}

test "dynamic schema validation rejects forward references" {
    var bytes = [_]u8{0} ** 16;
    std.mem.writeInt(u32, bytes[0..4], 1, .little);
    std.mem.writeInt(u32, bytes[4..8], 12, .little);
    bytes[8] = @intFromEnum(Kind.optional);
    std.mem.writeInt(u32, bytes[12..16], 0, .little);
    var storage: [1]NodeIndex = undefined;
    try std.testing.expectError(
        error.InvalidSchema,
        validateSchemaSection(&bytes, &storage),
    );
}

test "dynamic schema validation rejects duplicate structural nodes" {
    var bytes = [_]u8{0} ** 20;
    std.mem.writeInt(u32, bytes[0..4], 2, .little);
    std.mem.writeInt(u32, bytes[4..8], 8, .little);
    bytes[8] = @intFromEnum(Kind.u32);
    std.mem.writeInt(u32, bytes[12..16], 8, .little);
    bytes[16] = @intFromEnum(Kind.u32);
    var storage: [2]NodeIndex = undefined;
    try std.testing.expectError(
        error.InvalidSchema,
        validateSchemaSection(&bytes, &storage),
    );
}

test "schema hashing streams wide product fields through bounded tasks" {
    const field_count: u32 = 8191;
    const product_length: u32 = 8 + 4 + field_count * 4;
    var section: [4 + 8 + product_length]u8 = [_]u8{0} **
        (4 + 8 + product_length);
    std.mem.writeInt(u32, section[0..4], 2, .little);
    std.mem.writeInt(u32, section[4..8], 8, .little);
    section[8] = @intFromEnum(Kind.u8);
    const product_start: usize = 12;
    std.mem.writeInt(
        u32,
        section[product_start..][0..4],
        product_length,
        .little,
    );
    section[product_start + 4] = @intFromEnum(Kind.product);
    std.mem.writeInt(
        u32,
        section[product_start + 8 ..][0..4],
        field_count,
        .little,
    );
    var nodes: [2]NodeIndex = undefined;
    const table = try validateSchemaSection(&section, &nodes);
    var tasks: [4]SchemaHashTask = undefined;
    const digest = try schemaDigest(table, 1, &tasks);
    try std.testing.expect(!std.mem.eql(u8, &digest, &([_]u8{0} ** 32)));
}

test "schema validation sorts the maximum enum tag frontier" {
    const field_count: u32 = maximum_schema_members;
    const record_length: u32 = 8 + 4 + field_count * 4;
    var section: [4 + record_length]u8 = [_]u8{0} ** (4 + record_length);
    std.mem.writeInt(u32, section[0..4], 1, .little);
    std.mem.writeInt(u32, section[4..8], record_length, .little);
    section[8] = @intFromEnum(Kind.@"enum");
    std.mem.writeInt(u32, section[12..16], field_count, .little);
    for (0..field_count) |index| {
        std.mem.writeInt(
            u32,
            section[16 + index * 4 ..][0..4],
            @intCast(index),
            .little,
        );
    }
    var nodes: [1]NodeIndex = undefined;
    _ = try validateSchemaSection(&section, &nodes);
    std.mem.writeInt(
        u32,
        section[16 + (@as(usize, field_count) - 1) * 4 ..][0..4],
        0,
        .little,
    );
    try std.testing.expectError(
        error.InvalidSchema,
        validateSchemaSection(&section, &nodes),
    );
}

test "dynamic values reject noncanonical booleans and trailing bytes" {
    var schema = [_]u8{0} ** 12;
    std.mem.writeInt(u32, schema[0..4], 1, .little);
    std.mem.writeInt(u32, schema[4..8], 8, .little);
    schema[8] = @intFromEnum(Kind.bool);
    var nodes: [1]NodeIndex = undefined;
    const table = try validateSchemaSection(&schema, &nodes);
    var tasks: [1]ValueTask = undefined;
    try validateValue(table, 0, &.{1}, &tasks);
    try std.testing.expectError(
        error.InvalidValue,
        validateValue(table, 0, &.{2}, &tasks),
    );
    try std.testing.expectError(
        error.TrailingBytes,
        validateValue(table, 0, &.{ 1, 0 }, &tasks),
    );
}
