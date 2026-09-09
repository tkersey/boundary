// Copyright (c) 2026 Boundary contributors. MIT license.
//! Staged effect declarations. A finite index selects a concrete payload/result
//! signature before emission; there is no unchecked runtime result cast.
const std = @import("std");
const source = @import("source.zig");
const p = @import("boundary_data_v2").program;
pub const Signature = p.Effect;
pub const Row = source.Row;
pub const declare = source.Builder.effect;
pub const Operation = struct { effect: p.Id, capability: p.Id, payload: p.Id, result: p.Id };
pub const Indexed = struct {
    operations: []const Operation,
    pub fn at(self: Indexed, index: usize) source.Error!Operation {
        if (index >= self.operations.len) return error.InvalidReference;
        return self.operations[index];
    }
};

/// Case identities are the finite family indices. Ordinary Zig helpers can
/// abstract over the family and retain each selected index's result schema.
pub fn indexed(b: *source.Builder, identity: []const u8, cases: []const Signature) source.Error!Indexed {
    if (identity.len == 0 or cases.len == 0) return error.InvalidEffect;
    const operations = try b.allocator().alloc(Operation, cases.len);
    for (cases, operations, 0..) |signature, *operation, index| {
        if (signature.identity.len == 0) return error.InvalidEffect;
        for (cases[0..index]) |previous| if (std.mem.eql(u8, previous.identity, signature.identity)) return error.InvalidEffect;
        var instance = signature;
        instance.identity = try std.fmt.allocPrint(b.allocator(), "{s}/{s}", .{ identity, signature.identity });
        const id = try b.effect(instance);
        operation.* = .{ .effect = id, .capability = try b.schema(.{ .internal = .{ .capability = id } }), .payload = signature.payload, .result = signature.result };
    }
    return .{ .operations = operations };
}
