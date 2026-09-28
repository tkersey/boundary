// Copyright (c) 2026 Boundary contributors. MIT license.
//! Checked affine capture-state transformation. P01 always owns final output.
const std = @import("std");
const ir = @import("activation.zig");
const emit = @import("affine_emit.zig");
const check = @import("affine_validate.zig");
pub const validate = check.validate;
const p01 = @import("coalescing.zig");
pub const Error = p01.Error || emit.Error || check.Error;
pub const Cost = struct { image_bytes: usize, worker_instructions: usize, construction_instructions: usize };
pub const Statistics = struct {
    outcome: enum { no_change, applied, work_limit } = .no_change,
    original_words: usize = 0,
    reduced_words: usize = 0,
    selected_basis: emit.Basis = .observations,
    observation_cost: ?Cost = null,
    canonical_cost: ?Cost = null,
};
fn cost(program: ir.Program, worker: u64) Error!Cost {
    var result: Cost = .{ .image_bytes = try @import("program_image.zig").encodedLength(program), .worker_instructions = 0, .construction_instructions = 0 };
    for (program.blocks) |block| {
        if (block.function == worker) result.worker_instructions += block.instructions.len else result.construction_instructions += block.instructions.len;
    }
    return result;
}
fn cheaper(left: Cost, right: Cost) bool {
    if (left.worker_instructions != right.worker_instructions) return left.worker_instructions < right.worker_instructions;
    if (left.construction_instructions != right.construction_instructions) return left.construction_instructions < right.construction_instructions;
    return left.image_bytes < right.image_bytes;
}
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
    check.validate(allocator, original, candidate.program, constructor_id, candidate.basis, candidate.input_bias, work_limit) catch |err| switch (err) {
        error.WorkLimit => {
            stats.outcome = .work_limit;
            return p01.run(allocator, original, options);
        },
        else => return err,
    };
    stats.observation_cost = try cost(candidate.program, original.constructors[constructor_id].function);
    var canonical = emit.constructBasis(allocator, original, constructor_id, work_limit, .canonical) catch |err| switch (err) {
        error.WorkLimit => {
            stats.outcome = .work_limit;
            return p01.run(allocator, original, options);
        },
        else => return err,
    };
    defer if (canonical) |*other| other.deinit();
    var selected = candidate.program;
    if (canonical) |other| {
        if (!std.mem.eql(u128, candidate.basis, other.basis)) {
            check.validate(allocator, original, other.program, constructor_id, other.basis, other.input_bias, work_limit) catch |err| switch (err) {
                error.WorkLimit => {
                    stats.outcome = .work_limit;
                    return p01.run(allocator, original, options);
                },
                else => return err,
            };
            stats.canonical_cost = try cost(other.program, original.constructors[constructor_id].function);
            if (cheaper(stats.canonical_cost.?, stats.observation_cost.?)) {
                selected = other.program;
                stats.selected_basis = .canonical;
            }
        }
    }
    const result = try p01.run(allocator, selected, options);
    stats.outcome = .applied;
    stats.original_words = original.scopes.captures[@intCast(original.constructors[constructor_id].capture)].fields.len;
    stats.reduced_words = candidate.basis.len;
    return result;
}
