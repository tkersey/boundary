// Copyright (c) 2026 Boundary contributors. MIT license.
//! Read a function's genuine call interface without allocating a schema vector.
const std = @import("std");
const p = @import("program.zig");
const a = @import("admission.zig");

pub const Inputs = struct {
    types: []const p.Id,
    destinations: []const p.Id,
    len: usize,

    pub fn at(self: Inputs, index: usize) p.Id {
        std.debug.assert(index < self.len);
        return self.types[@intCast(self.destinations[index])];
    }

    pub fn matches(self: Inputs, start: usize, schemas: []const p.Id) bool {
        if (start > self.len or schemas.len > self.len - start) return false;
        for (schemas, 0..) |schema, index| if (self.at(start + index) != schema) return false;
        return true;
    }

    pub fn arguments(self: Inputs, slots: []const p.Id, supplied: []const p.Id) a.Error!void {
        if (supplied.len != self.len) return error.TypeMismatch;
        for (supplied, 0..) |slot, index| {
            if (try a.slotType(slots, slot) != self.at(index)) return error.TypeMismatch;
        }
    }
};

pub fn of(function: @import("activation.zig").Function) Inputs {
    return .{
        .types = function.layout.slots,
        .destinations = function.inputs,
        .len = function.inputs.len,
    };
}
