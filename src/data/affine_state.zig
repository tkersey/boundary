// Copyright (c) 2026 Boundary contributors. MIT license.
//! Checked affine capture-state transformation. P01 always owns final output.
const std = @import("std");
const ir = @import("activation.zig");
const emit = @import("affine_emit.zig");
const check = @import("affine_validate.zig");
const p01 = @import("coalescing.zig");
pub const Error = p01.Error || emit.Error || check.Error;
pub const Statistics = struct {
    outcome: enum { no_change, applied, work_limit } = .no_change,
    original_words: usize = 0,
    reduced_words: usize = 0,
};
pub fn run(allocator: std.mem.Allocator, original: ir.Program, constructor_id: usize, statistics: ?*Statistics, work_limit: u64, options: p01.Options) Error!p01.Owned {
    var stats: Statistics = .{};
    defer if (statistics) |out| {
        out.* = stats;
    };
    var candidate = (emit.construct(allocator, original, constructor_id, work_limit) catch |err| switch (err) {
        error.WorkLimit => {
            stats.outcome = .work_limit;
            return p01.run(allocator, original, options);
        },
        else => return err,
    }) orelse return p01.run(allocator, original, options);
    defer candidate.deinit();
    check.validate(allocator, original, candidate.program, constructor_id, candidate.basis, work_limit) catch |err| switch (err) {
        error.WorkLimit => {
            stats.outcome = .work_limit;
            return p01.run(allocator, original, options);
        },
        else => return err,
    };
    const result = try p01.run(allocator, candidate.program, options);
    stats.outcome = .applied;
    stats.original_words = original.scopes.captures[@intCast(original.constructors[constructor_id].capture)].fields.len;
    stats.reduced_words = candidate.basis.len;
    return result;
}
