// Copyright (c) 2026 Boundary contributors. MIT license.
//! One closed-record compiler for source lowering and final component linking.
//! Both contracts admit originals and always run independently checked P01.
const std = @import("std");
const ir = @import("activation.zig");
const p = @import("program.zig");
const image = @import("program_image.zig");
const p01 = @import("coalescing.zig");
const branch = @import("branch_reduction.zig");
const applications = @import("application_specialization.zig");
const aggregates = @import("aggregate_reduction.zig");
const expressions = @import("expression_reuse.zig");
const cells = @import("cell_reduction.zig");
const dead = @import("dead_computation.zig");
const arguments = @import("dead_arguments.zig");
const captures = @import("capture_reduction.zig");
const projections = @import("capture_projection.zig");
const summaries = @import("capture_summary.zig");
pub const Contract = enum { structural, semantic };
pub const Objective = enum { size, balanced, speed };
pub const Stage = enum { p01, branch, applications, aggregates, expressions, cells, dead_computation, dead_arguments, dead_captures, capture_projection, capture_summary };
pub const default_work_limit: u64 = 100_000_000_000;
pub const Outcome = enum { not_run, structural, deferred_open_component, no_change, applied, work_limit, size_guard };
pub const Statistics = struct {
    outcome: Outcome = .not_run,
    original_bytes: usize = 0,
    baseline_bytes: usize = 0,
    final_bytes: usize = 0,
    rounds: usize = 0,
    stages_run: usize = 0,
    stages_skipped: usize = 0,
    changed_stages: usize = 0,
    work_reserved: u64 = 0,
    stopped_stage: ?Stage = null,
    failed_stage: ?Stage = null,
};
pub const Observer = struct { context: *anyopaque, enter: *const fn (*anyopaque, Stage) void };
pub const Options = struct {
    contract: Contract = .structural,
    objective: Objective = .balanced,
    image_growth_bytes: ?usize = null,
    max_image_bytes: ?usize = null,
    work_limit: u64 = default_work_limit,
    round_limit: usize = 4,
    statistics: ?*Statistics = null,
    observer: ?Observer = null,
    coalescing: p01.Options = .{},
};
pub const Error = branch.Error || applications.Error || aggregates.Error || expressions.Error || cells.Error || dead.Error || arguments.Error || captures.Error || projections.Error || summaries.Error;
const schedule = [_]Stage{ .branch, .applications, .aggregates, .expressions, .cells, .dead_computation, .dead_arguments, .dead_captures, .capture_projection, .capture_summary, .dead_computation, .dead_arguments, .applications, .dead_computation };
fn notify(options: Options, stage: Stage) void {
    if (options.observer) |observer| observer.enter(observer.context, stage);
}
fn growth(options: Options, baseline: usize) usize {
    return options.image_growth_bytes orelse switch (options.objective) {
        .size => 0,
        .balanced => @max(1024, baseline / 20 + @intFromBool(baseline % 20 != 0)),
        .speed => @max(4096, baseline / 4 + @intFromBool(baseline % 4 != 0)),
    };
}

/// Reserve a conservative bound for descriptor/operand comparison scans. Literal
/// bytes are linear, not multiplied into the quadratic descriptor bound. Dynamic
/// fact/proof searches also have counted local caps. Admission and P01 retain
/// their independent mandatory checks and P01's own work accounting.
const Shape = struct { records: u64 = 0, bytes: u64 = 0 };
fn recordShape(comptime T: type, value: T, result: *Shape) Error!void {
    result.records = std.math.add(u64, result.records, 1) catch return error.Capacity;
    switch (@typeInfo(T)) {
        .@"struct" => |info| inline for (info.fields) |field| try recordShape(field.type, @field(value, field.name), result),
        .@"union" => switch (value) {
            inline else => |payload| try recordShape(@TypeOf(payload), payload, result),
        },
        .optional => |info| if (value) |payload| {
            try recordShape(info.child, payload, result);
        },
        .pointer => |info| {
            if (info.child == u8) result.bytes = std.math.add(u64, result.bytes, value.len) catch return error.Capacity else for (value) |item| try recordShape(info.child, item, result);
        },
        .array => |info| for (value) |item| try recordShape(info.child, item, result),
        else => {},
    }
}
fn sumWork(values: []const u64) Error!u64 {
    var result: u64 = 0;
    for (values) |value| result = std.math.add(u64, result, value) catch return error.Capacity;
    return result;
}
fn reservation(program: ir.Program, stage: Stage) Error!u64 {
    // Wire compression is deliberately irrelevant to a scan-work bound.
    var shape: Shape = .{};
    try recordShape(ir.Program, program, &shape);
    var instructions: u64 = 0;
    var block_squares: u64 = 0;
    var applications_count: u64 = 0;
    var cells_count: u64 = 0;
    var constructions: u64 = 0;
    var max_slots: u64 = 0;
    var max_inputs: u64 = 0;
    for (program.functions) |function| {
        max_slots = @max(max_slots, function.layout.slots.len);
        max_inputs = @max(max_inputs, function.inputs.len);
    }
    for (program.blocks) |block| {
        instructions = std.math.add(u64, instructions, block.instructions.len) catch return error.Capacity;
        const square = std.math.mul(u64, block.instructions.len, block.instructions.len) catch return error.Capacity;
        block_squares = std.math.add(u64, block_squares, square) catch return error.Capacity;
        applications_count += @intFromBool(block.terminator == .apply);
        for (block.instructions) |op| {
            cells_count += @intFromBool(op.opcode == .cell_new);
            constructions += @intFromBool(op.opcode == .computation);
        }
    }
    // Count the domain actually scanned by this pass, not a square of unrelated
    // schemas, literals and record wrapper fields. Fixed-point/proof work below
    // is separately capped by its counted allowance.
    const comparisons: u64 = switch (stage) {
        .branch => std.math.mul(u64, program.blocks.len, program.blocks.len) catch return error.Capacity,
        .applications => std.math.mul(u64, try sumWork(&.{ applications_count, 1 }), shape.records) catch return error.Capacity,
        .aggregates => block_squares,
        .expressions => 0,
        .cells => std.math.mul(u64, try sumWork(&.{ cells_count, 1 }), shape.records) catch return error.Capacity,
        .dead_computation => std.math.mul(u64, try sumWork(&.{ instructions, max_slots, program.blocks.len, 1 }), shape.records) catch return error.Capacity,
        .dead_arguments => std.math.mul(u64, try sumWork(&.{ program.functions.len, max_inputs, 1 }), shape.records) catch return error.Capacity,
        .dead_captures, .capture_projection, .capture_summary => std.math.mul(u64, try sumWork(&.{ program.constructors.len, constructions, 1 }), shape.records) catch return error.Capacity,
        .p01 => 0,
    };
    const scans = std.math.mul(u64, std.math.add(u64, comparisons, shape.records) catch return error.Capacity, 64) catch return error.Capacity;
    const byte_work = std.math.mul(u64, shape.bytes, 16) catch return error.Capacity;
    const facts: u64 = switch (stage) {
        .branch, .applications, .aggregates => 22_000_000,
        .expressions => 1_000_000,
        else => 0,
    };
    return std.math.add(u64, std.math.add(u64, scans, byte_work) catch return error.Capacity, facts) catch return error.Capacity;
}
const Cost = struct { bytes: usize, work: u64, retention: u64 };
fn payloadEstimate(program: ir.Program, schema: u64, depth: usize, memo: []?u64, active: []bool) u64 {
    if (depth == 32) return 8;
    const id: usize = @intCast(schema);
    if (memo[id]) |value| return value;
    if (active[id]) return 8;
    active[id] = true;
    defer active[id] = false;
    const result: u64 = switch (program.schemas[id]) {
        .unit => 0,
        .boolean, .u8, .i8 => 1,
        .u16, .i16 => 2,
        .u32, .i32 => 4,
        .u64, .i64 => 8,
        .product => |fields| blk: {
            var size: u64 = 0;
            for (fields) |field| size +|= payloadEstimate(program, field, depth + 1, memo, active);
            break :blk size;
        },
        .array => |array| array.length *| payloadEstimate(program, array.element, depth + 1, memo, active),
        else => 8,
    };
    memo[id] = result;
    return result;
}
fn cost(allocator: std.mem.Allocator, program: ir.Program) Error!Cost {
    const memo = try allocator.alloc(?u64, program.schemas.len);
    defer allocator.free(memo);
    const active = try allocator.alloc(bool, program.schemas.len);
    defer allocator.free(active);
    @memset(memo, null);
    @memset(active, false);
    var result: Cost = .{ .bytes = try image.encodedLength(program), .work = 0, .retention = 0 };
    for (program.blocks) |block| {
        result.work +|= if (block.terminator == .apply) 4 else 1;
        for (block.instructions) |op| {
            result.work +|= switch (op.opcode) {
                .move => 0,
                .cell_new => 8,
                .cell_get, .cell_set => 3,
                else => 1,
            };
            if (op.opcode == .computation) {
                const capture = program.scopes.captures[@intCast(program.constructors[@intCast(op.immediate)].capture)];
                for (capture.fields) |field| result.retention +|= payloadEstimate(program, field, 0, memo, active);
            }
        }
    }
    return result;
}
fn allowBaseline(options: Options, bytes: usize) Error!void {
    if (options.max_image_bytes) |limit| if (bytes > limit) return error.Capacity;
}
fn better(candidate: Cost, baseline: Cost, objective: Objective) bool {
    // Deterministic, explicitly heuristic estimates; never runtime measurements.
    if (objective == .size) return candidate.bytes < baseline.bytes or (candidate.bytes == baseline.bytes and candidate.work < baseline.work);
    return candidate.retention < baseline.retention or candidate.work < baseline.work or candidate.bytes < baseline.bytes;
}
fn possible(allocator: std.mem.Allocator, owned: *const p01.Owned, stage: Stage) Error!bool {
    const program = owned.program;
    switch (stage) {
        .branch => for (program.blocks) |block| {
            if (block.terminator == .branch) return true;
        },
        .applications => for (program.blocks) |block| {
            if (block.terminator == .apply) return true;
        },
        .aggregates, .cells => for (program.blocks) |block| {
            for (block.instructions) |op| if (op.opcode == (if (stage == .aggregates) p.Opcode.field else p.Opcode.cell_new)) return true;
        },
        .expressions => {
            const seen = try allocator.alloc(u64, program.functions.len);
            defer allocator.free(seen);
            @memset(seen, 0);
            for (program.blocks) |block| for (block.instructions) |op| {
                if (!expressions.canNumber(op.opcode)) continue;
                const tag = @intFromEnum(op.opcode);
                if (tag >= 64) return true;
                const bit = @as(u64, 1) << @intCast(tag);
                if (seen[@intCast(block.function)] & bit != 0) return true;
                seen[@intCast(block.function)] |= bit;
            };
        },
        .dead_computation => for (program.blocks, 0..) |block, id| {
            if (owned.flow.live[id].len == 0) continue;
            for (block.instructions, 0..) |op, index| if (!owned.flow.pool.contains(owned.flow.live[id][index + 1], op.destination)) return true;
        },
        .dead_arguments => for (program.blocks) |block| {
            if (block.terminator != .call) continue;
            const id = block.terminator.call.function;
            if (@import("call_contexts.zig").unknownEntry(program, id)) continue;
            const function = program.functions[@intCast(id)];
            for (function.inputs) |slot| if (!owned.flow.pool.contains(owned.flow.live[@intCast(function.entry)][0], slot)) return true;
        },
        .dead_captures, .capture_projection, .capture_summary => for (program.constructors) |constructor| {
            const capture = program.scopes.captures[@intCast(constructor.capture)];
            const function = program.functions[@intCast(constructor.function)];
            if (stage == .dead_captures) {
                for (capture.fields, 0..) |_, index| if (!owned.flow.pool.contains(owned.flow.live[@intCast(function.entry)][0], function.inputs[index])) return true;
            } else if (stage == .capture_projection) {
                if (capture.fields.len == 1 and program.schemas[@intCast(capture.fields[0])] == .product) return true;
            } else if (capture.fields.len == 2 and program.schemas[@intCast(capture.fields[0])] == .u64 and capture.fields[0] == capture.fields[1]) return true;
        },
        .p01 => return true,
    }
    return false;
}

pub fn run(allocator: std.mem.Allocator, original: ir.Program, options: Options) Error!p01.Owned {
    var stats: Statistics = .{};
    var stage: Stage = .p01;
    defer if (options.statistics) |out| {
        out.* = stats;
    };
    errdefer stats.failed_stage = stage;
    notify(options, .p01);
    var baseline = try p01.run(allocator, original, options.coalescing);
    var keep_baseline = false;
    defer if (!keep_baseline) baseline.deinit();
    stats.original_bytes = try image.encodedLength(original);
    stats.baseline_bytes = try image.encodedLength(baseline.program);
    stats.final_bytes = stats.baseline_bytes;
    if (options.contract == .structural) {
        if (options.max_image_bytes) |limit| if (stats.final_bytes > limit) return error.Capacity;
        stats.outcome = .structural;
        keep_baseline = true;
        return baseline;
    }
    if (options.work_limit == 0) {
        try allowBaseline(options, stats.baseline_bytes);
        stats.outcome = .work_limit;
        keep_baseline = true;
        return baseline;
    }
    var current: ?p01.Owned = null;
    defer if (current) |*owner| owner.deinit();
    const baseline_cost = try cost(allocator, baseline.program);
    const limit = std.math.add(usize, stats.baseline_bytes, growth(options, stats.baseline_bytes)) catch return error.Capacity;
    const quiet: p01.Options = .{ .work_limit = options.coalescing.work_limit };
    var stable = false;
    var generation: usize = 0;
    var no_change_generation: [std.meta.fields(Stage).len]?usize = @splat(null);
    var round: usize = 0;
    while (round < options.round_limit) : (round += 1) {
        const before = try image.identity(allocator, if (current) |owner| owner.program else baseline.program);
        for (schedule) |next_stage| {
            stage = next_stage;
            if (no_change_generation[@intFromEnum(stage)] == generation) {
                stats.stages_skipped += 1;
                continue;
            }
            const subject = if (current) |*value| value else &baseline;
            if (!try possible(allocator, subject, stage)) {
                stats.stages_skipped += 1;
                continue;
            }
            const input = if (current) |owner| owner.program else baseline.program;
            const charge = try reservation(input, stage);
            if (charge > options.work_limit - stats.work_reserved) {
                try allowBaseline(options, stats.baseline_bytes);
                stats.outcome = .work_limit;
                stats.stopped_stage = stage;
                keep_baseline = true;
                return baseline;
            }
            stats.work_reserved += charge;
            notify(options, stage);
            var exhausted = false;
            var next = apply(allocator, input, stage, quiet, &exhausted) catch |err| {
                if (err == error.SemanticWorkLimit or err == error.ExpressionWorkLimit) {
                    try allowBaseline(options, stats.baseline_bytes);
                    stats.outcome = .work_limit;
                    stats.stopped_stage = stage;
                    keep_baseline = true;
                    return baseline;
                }
                return err;
            };
            errdefer next.deinit();
            if (exhausted) {
                try allowBaseline(options, stats.baseline_bytes);
                next.deinit();
                stats.outcome = .work_limit;
                stats.stopped_stage = stage;
                keep_baseline = true;
                return baseline;
            }
            stats.stages_run += 1;
            // An unchanged-stage result is reusable only until another stage
            // changes actual records. No hash match authorizes skipping work.
            if (!@import("record_equal.zig").equal(ir.Program, input, next.program)) {
                stats.changed_stages += 1;
                generation += 1;
            } else no_change_generation[@intFromEnum(stage)] = generation;
            if (current) |*owner| owner.deinit();
            current = next;
        }
        stats.rounds += 1;
        if (std.mem.eql(u8, &before, &try image.identity(allocator, if (current) |owner| owner.program else baseline.program))) {
            stable = true;
            break;
        }
    }
    if (!stable) {
        try allowBaseline(options, stats.baseline_bytes);
        stats.outcome = .work_limit;
        keep_baseline = true;
        return baseline;
    }
    const candidate_cost = try cost(allocator, if (current) |owner| owner.program else baseline.program);
    const hard_limit = options.max_image_bytes orelse std.math.maxInt(usize);
    if (candidate_cost.bytes > limit or candidate_cost.bytes > hard_limit or !better(candidate_cost, baseline_cost, options.objective)) {
        if (stats.baseline_bytes > hard_limit) return error.Capacity;
        stats.outcome = if (candidate_cost.bytes > limit or candidate_cost.bytes > hard_limit) .size_guard else .no_change;
        keep_baseline = true;
        return baseline;
    }
    stage = .p01;
    notify(options, .p01);
    var result = try p01.run(allocator, current.?.program, options.coalescing);
    errdefer result.deinit();
    stats.final_bytes = try image.encodedLength(result.program);
    stats.outcome = .applied;
    return result;
}
fn apply(a: std.mem.Allocator, program: ir.Program, stage: Stage, options: p01.Options, exhausted: *bool) Error!p01.Owned {
    return switch (stage) {
        .p01 => unreachable,
        .branch => blk: {
            var stats: branch.Statistics = .{};
            const result = try branch.run(a, program, &stats, options);
            exhausted.* = stats.proof_work_limit;
            break :blk result;
        },
        .applications => blk: {
            var stats: applications.Statistics = .{};
            const result = try applications.run(a, program, &stats, options);
            exhausted.* = stats.proof_work_limit;
            break :blk result;
        },
        .aggregates => aggregates.run(a, program, null, options),
        .expressions => blk: {
            var stats: expressions.Statistics = .{};
            const result = try expressions.run(a, program, &stats, .{ .coalescing = options });
            exhausted.* = stats.work_limit;
            break :blk result;
        },
        .cells => cells.run(a, program, null, options),
        .dead_computation => dead.run(a, program, null, .{ .coalescing = options }),
        .dead_arguments => arguments.run(a, program, null, options),
        .dead_captures => captures.run(a, program, null, options),
        .capture_projection => projections.run(a, program, null, options),
        .capture_summary => summaries.run(a, program, null, options),
    };
}
