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
const affine = @import("affine_state.zig");
const pre = @import("partial_redundancy.zig");
const patterns = @import("call_patterns.zig");
const leaves = @import("leaf_inlining.zig");
const unpack = @import("capture_unpack.zig");
pub const Contract = enum { structural, semantic };
pub const Objective = enum { size, balanced, speed };
pub const Stage = enum { p01, branch, applications, aggregates, expressions, cells, dead_computation, dead_arguments, dead_captures, capture_projection, capture_summary, affine_state, capture_unpack, partial_redundancy, call_patterns, leaf_inlining };
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
    selected_candidate: enum { baseline, shrinking, full } = .baseline,
    admission_guard_rejections: usize = 0,
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

    /// Begin an invocation before any producer can reject its input.
    pub fn resetObservations(self: Options) void {
        self.coalescing.resetObservations();
        if (self.statistics) |stats| stats.* = .{};
    }
};
pub const Error = branch.Error || applications.Error || aggregates.Error || expressions.Error || cells.Error || dead.Error || arguments.Error || captures.Error || projections.Error || summaries.Error || affine.Error || unpack.Error || pre.Error || patterns.Error || leaves.Error;
const schedule = [_]Stage{ .branch, .capture_unpack, .aggregates, .dead_computation, .affine_state, .call_patterns, .applications, .leaf_inlining, .aggregates, .expressions, .partial_redundancy, .cells, .dead_computation, .dead_arguments, .dead_captures, .capture_projection, .capture_summary, .dead_computation, .dead_arguments, .applications, .dead_computation };
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
        .call_patterns, .leaf_inlining => std.math.mul(u64, try sumWork(&.{ program.functions.len, max_inputs, instructions, program.blocks.len, 1 }), shape.records) catch return error.Capacity,
        .applications => std.math.mul(u64, try sumWork(&.{ applications_count, 1 }), shape.records) catch return error.Capacity,
        .aggregates => block_squares,
        .expressions => 0,
        .partial_redundancy => std.math.mul(u64, try sumWork(&.{ instructions, program.blocks.len, 1 }), shape.records) catch return error.Capacity,
        .cells => std.math.mul(u64, try sumWork(&.{ cells_count, 1 }), shape.records) catch return error.Capacity,
        .dead_computation => std.math.mul(u64, try sumWork(&.{ instructions, max_slots, program.blocks.len, 1 }), shape.records) catch return error.Capacity,
        .dead_arguments => std.math.mul(u64, try sumWork(&.{ program.functions.len, max_inputs, 1 }), shape.records) catch return error.Capacity,
        .affine_state => std.math.mul(u64, try sumWork(&.{ program.constructors.len, program.functions.len, constructions, 1 }), shape.records) catch return error.Capacity,
        .dead_captures, .capture_projection, .capture_summary, .capture_unpack => std.math.mul(u64, try sumWork(&.{ program.constructors.len, constructions, 1 }), shape.records) catch return error.Capacity,
        .p01 => 0,
    };
    const scans = std.math.mul(u64, std.math.add(u64, comparisons, shape.records) catch return error.Capacity, 64) catch return error.Capacity;
    const byte_work = std.math.mul(u64, shape.bytes, 16) catch return error.Capacity;
    const facts: u64 = switch (stage) {
        .branch, .applications, .aggregates, .call_patterns => 22_000_000,
        .expressions, .partial_redundancy => 1_000_000,
        .affine_state => std.math.mul(u64, try sumWork(&.{ program.constructors.len, program.functions.len }), 6_000_000) catch return error.Capacity,
        else => 0,
    };
    return std.math.add(u64, std.math.add(u64, scans, byte_work) catch return error.Capacity, facts) catch return error.Capacity;
}
const Cost = struct { bytes: usize, work: u64, path_work: ?u64 = null, retention: u64, admission_sets: [4]u64 };
// Zig 0.16's geometric growth starts with cache_line / node_size. Cover
// 64/128-byte cache lines and 16/24-byte nodes without querying the build host.
const node_growth_starts = [_]u64{ 2, 4, 5, 8 };
fn nodeCapacityEstimate(count: usize, start: u64) Error!u64 {
    var capacity: u64 = 0;
    while (capacity < count) {
        const minimum = std.math.add(u64, capacity, 1) catch return error.Capacity;
        capacity = try sumWork(&.{ minimum, minimum / 2, start });
    }
    return capacity;
}
fn admissionSetCost(nodes: usize, table_capacity: usize) Error![4]u64 {
    var result: [4]u64 = undefined;
    for (node_growth_starts, &result) |start, *score| score.* = try sumWork(&.{
        std.math.mul(u64, try nodeCapacityEstimate(nodes, start), 24) catch return error.Capacity,
        std.math.mul(u64, table_capacity, 12) catch return error.Capacity,
    });
    return result;
}
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
// A bounded acyclic entry-path estimate exposes PRE and specialization work
// savings that static sums miss. Known direct callees are expanded; applications
// retain their opaque dispatch weight. Cycles/depth exhaustion yield unknown.
// This is a selection heuristic, not a whole-program runtime bound.
fn blockWork(block: ir.Block) u64 {
    var work: u64 = if (block.terminator == .apply) 4 else 1;
    for (block.instructions) |op| work +|= switch (op.opcode) {
        .move => 0,
        .cell_new => 8,
        .cell_get, .cell_set => 3,
        else => 1,
    };
    return work;
}
fn pathSuccessor(term: ir.Terminator, index: usize) ?ir.Edge {
    return switch (term) {
        .return_value, .fail => null,
        .jump => |v| if (index == 0) v else null,
        .branch => |v| if (index == 0) v.when_true else if (index == 1) v.when_false else null,
        .switch_variant => |v| if (index < v.cases.len) v.cases[index] else null,
        .yield_value => |v| if (index == 0) v else null,
        inline else => |v| if (index == 0) v.next else null,
    };
}
fn pathAt(program: ir.Program, block: usize, marks: []u8, memo: []u64, depth: usize) ?u64 {
    if (depth >= 512 or marks[block] == 1) return null;
    if (marks[block] == 2) return memo[block];
    marks[block] = 1;
    var following: u64 = 0;
    var index: usize = 0;
    while (pathSuccessor(program.blocks[block].terminator, index)) |edge| : (index += 1)
        following = @max(following, pathAt(program, @intCast(edge.block), marks, memo, depth + 1) orelse return null);
    const nested: u64 = if (program.blocks[block].terminator == .call)
        pathAt(program, @intCast(program.functions[@intCast(program.blocks[block].terminator.call.function)].entry), marks, memo, depth + 1) orelse return null
    else
        0;
    memo[block] = blockWork(program.blocks[block]) +| following +| nested;
    marks[block] = 2;
    return memo[block];
}
fn pathWork(allocator: std.mem.Allocator, program: ir.Program) Error!?u64 {
    const marks = try allocator.alloc(u8, program.blocks.len);
    defer allocator.free(marks);
    @memset(marks, 0);
    const memo = try allocator.alloc(u64, program.blocks.len);
    defer allocator.free(memo);
    var work: u64 = 0;
    for (program.functions, 0..) |function, id| {
        if (!@import("call_contexts.zig").unknownEntry(program, id)) continue;
        work = @max(work, pathAt(program, @intCast(function.entry), marks, memo, 0) orelse return null);
    }
    return work;
}
fn cost(allocator: std.mem.Allocator, owned: *const p01.Owned) Error!Cost {
    const program = owned.program;
    const memo = try allocator.alloc(?u64, program.schemas.len);
    defer allocator.free(memo);
    const active = try allocator.alloc(bool, program.schemas.len);
    defer allocator.free(active);
    @memset(memo, null);
    @memset(active, false);
    // Fixed logical weights avoid making selection depend on host pointers,
    // allocator resize success, or native versus wasm node representation.
    // This models the retained analysis containers, not World runtime memory.
    const admission_sets = try admissionSetCost(owned.flow.pool.nodeCount(), owned.flow.pool.interned.capacity());
    var result: Cost = .{ .bytes = try image.encodedLength(program), .work = 0, .path_work = try pathWork(allocator, program), .retention = 0, .admission_sets = admission_sets };
    for (program.blocks) |block| {
        result.work +|= blockWork(block);
        for (block.instructions) |op| {
            if (op.opcode == .computation) {
                const capture = program.scopes.captures[@intCast(program.constructors[@intCast(op.immediate)].capture)];
                for (capture.fields) |field| result.retention +|= payloadEstimate(program, field, 0, memo, active);
            }
        }
    }
    return result;
}
fn admissionGrowthAllowed(candidate: Cost, baseline: Cost) bool {
    for (candidate.admission_sets, baseline.admission_sets) |after, before| {
        const allowance = @max(1024, before / 100);
        if (after > before and after - before > allowance) return false;
    }
    return true;
}
fn allowBaseline(options: Options, bytes: usize) Error!void {
    if (options.max_image_bytes) |limit| if (bytes > limit) return error.Capacity;
}
fn better(candidate: Cost, baseline: Cost, objective: Objective) bool {
    // Deterministic, explicitly heuristic estimates; never runtime measurements.
    if (objective == .size) return candidate.bytes < baseline.bytes or (candidate.bytes == baseline.bytes and candidate.work < baseline.work);
    return candidate.retention < baseline.retention or candidate.work < baseline.work or candidate.bytes < baseline.bytes or
        (candidate.path_work != null and baseline.path_work != null and candidate.path_work.? < baseline.path_work.?);
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
        .capture_unpack => for (program.constructors) |constructor| {
            const capture = program.scopes.captures[@intCast(constructor.capture)];
            if (capture.fields.len != 1 or program.schemas[@intCast(capture.fields[0])] != .product) continue;
            for (program.blocks) |block| if (block.function == constructor.function and block.terminator == .call and block.terminator.call.function == constructor.function) return true;
        },
        .affine_state => {
            for (program.constructors) |constructor| {
                const capture = program.scopes.captures[@intCast(constructor.capture)];
                if (capture.fields.len == 0 or capture.fields.len > 128) continue;
                for (program.blocks) |block| {
                    if (block.function != constructor.function) continue;
                    switch (block.terminator) {
                        .call => |call| if (call.function == constructor.function) return true,
                        .jump => |edge| if (edge.assignments.len != 0) return true,
                        .branch => |choice| if (choice.when_true.assignments.len != 0 or choice.when_false.assignments.len != 0) return true,
                        else => {},
                    }
                }
            }
            for (program.functions, 0..) |_, id| if (affine.directTarget(program, id) != null) return true;
        },
        .partial_redundancy => return pre.possible(program),
        .call_patterns => return patterns.possible(program),
        .leaf_inlining => return leaves.possible(program),
        .p01 => return true,
    }
    return false;
}

pub fn run(allocator: std.mem.Allocator, original: ir.Program, options: Options) Error!p01.Owned {
    options.resetObservations();
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
    const baseline_cost = try cost(allocator, &baseline);
    const limit = std.math.add(usize, stats.baseline_bytes, growth(options, stats.baseline_bytes)) catch return error.Capacity;
    const quiet: p01.Options = .{ .work_limit = options.coalescing.work_limit };
    // A small independent shrinking candidate keeps useful dead-work removal
    // available when a later reuse combination is uneconomical. It is an
    // internal candidate, never an alternative production compilation route.
    var shrinking: ?p01.Owned = null;
    defer if (shrinking) |*owner| owner.deinit();
    if (try possible(allocator, &baseline, .dead_computation)) {
        const charge = try reservation(baseline.program, .dead_computation);
        if (charge > options.work_limit - stats.work_reserved) {
            try allowBaseline(options, stats.baseline_bytes);
            stats.outcome = .work_limit;
            stats.stopped_stage = .dead_computation;
            keep_baseline = true;
            return baseline;
        }
        stats.work_reserved += charge;
        stage = .dead_computation;
        notify(options, stage);
        var exhausted = false;
        shrinking = try apply(allocator, baseline.program, stage, quiet, &exhausted);
        stats.stages_run += 1;
    }
    var stable = false;
    var generation: usize = 0;
    var no_change_generation: [std.meta.fields(Stage).len]?usize = @splat(null);
    if (shrinking) |owner| {
        if (@import("record_equal.zig").equal(ir.Program, baseline.program, owner.program))
            no_change_generation[@intFromEnum(Stage.dead_computation)] = generation;
    }
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
    var selected: *const p01.Owned = &baseline;
    var selected_cost = baseline_cost;
    const hard_limit = options.max_image_bytes orelse std.math.maxInt(usize);
    var size_rejected = false;
    const candidates = [_]?*const p01.Owned{ if (shrinking) |*owner| owner else null, if (current) |*owner| owner else null };
    for (candidates, 0..) |candidate, index| {
        const owner = candidate orelse continue;
        const candidate_cost = try cost(allocator, owner);
        if (candidate_cost.bytes > limit or candidate_cost.bytes > hard_limit) {
            size_rejected = true;
            continue;
        }
        if (!admissionGrowthAllowed(candidate_cost, baseline_cost)) {
            stats.admission_guard_rejections += 1;
            continue;
        }
        if (better(candidate_cost, selected_cost, options.objective)) {
            selected = owner;
            selected_cost = candidate_cost;
            stats.selected_candidate = if (index == 0) .shrinking else .full;
        }
    }
    if (stats.selected_candidate == .baseline) {
        if (stats.baseline_bytes > hard_limit) return error.Capacity;
        stats.outcome = if (size_rejected) .size_guard else .no_change;
        keep_baseline = true;
        return baseline;
    }
    stage = .p01;
    notify(options, .p01);
    var result = try p01.run(allocator, selected.program, options.coalescing);
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
        .leaf_inlining => blk: {
            var stats: leaves.Statistics = .{};
            const result = try leaves.run(a, program, &stats, .{ .coalescing = options });
            exhausted.* = stats.work_limit;
            break :blk result;
        },
        .call_patterns => blk: {
            var stats: patterns.Statistics = .{};
            const result = try patterns.run(a, program, &stats, .{ .coalescing = options });
            exhausted.* = stats.work_limit;
            break :blk result;
        },
        .partial_redundancy => blk: {
            var stats: pre.Statistics = .{};
            const result = try pre.run(a, program, &stats, .{ .coalescing = options });
            exhausted.* = stats.work_limit;
            break :blk result;
        },
        .cells => cells.run(a, program, null, options),
        .dead_computation => dead.run(a, program, null, .{ .coalescing = options }),
        .dead_arguments => arguments.run(a, program, null, options),
        .dead_captures => captures.run(a, program, null, options),
        .capture_projection => projections.run(a, program, null, options),
        .capture_summary => summaries.run(a, program, null, options),
        .capture_unpack => unpack.run(a, program, options),
        .affine_state => blk: {
            for (program.constructors, 0..) |_, id| {
                var stats: affine.Statistics = .{};
                var result = try affine.run(a, program, id, &stats, 1_000_000, options);
                if (stats.outcome == .work_limit) {
                    exhausted.* = true;
                    break :blk result;
                }
                if (stats.outcome == .applied) break :blk result;
                result.deinit();
            }
            for (program.functions, 0..) |_, id| {
                const target = affine.directTarget(program, id) orelse continue;
                var stats: affine.Statistics = .{};
                var result = try affine.runTarget(a, program, target, &stats, 1_000_000, options);
                if (stats.outcome == .work_limit) {
                    exhausted.* = true;
                    break :blk result;
                }
                if (stats.outcome == .applied) break :blk result;
                result.deinit();
            }
            break :blk try p01.run(a, program, options);
        },
    };
}

test "admission-set cost guard bounds growth without host allocator capacities" {
    const baseline: Cost = .{ .bytes = 100, .work = 20, .retention = 0, .admission_sets = @splat(10_000) };
    var candidate = baseline;
    candidate.admission_sets[0] += 1024;
    try std.testing.expect(admissionGrowthAllowed(candidate, baseline));
    candidate.admission_sets[0] += 1;
    try std.testing.expect(!admissionGrowthAllowed(candidate, baseline));
    // A smaller image or less estimated work cannot erase this dimension.
    candidate.bytes = 1;
    candidate.work = 0;
    try std.testing.expect(!admissionGrowthAllowed(candidate, baseline));
    candidate.admission_sets = @splat(0);
    try std.testing.expect(admissionGrowthAllowed(candidate, baseline));
    const largest: Cost = .{ .bytes = 100, .work = 20, .retention = 0, .admission_sets = @splat(std.math.maxInt(u64)) };
    try std.testing.expect(admissionGrowthAllowed(largest, largest));
}

test "candidate admission cost accounts for a wasm growth cliff hidden by native capacity" {
    try std.testing.expectEqual(@as(u64, 692), try nodeCapacityEstimate(536, 8));
    try std.testing.expectEqual(@as(u64, 692), try nodeCapacityEstimate(553, 8));
    try std.testing.expectEqual(@as(u64, 542), try nodeCapacityEstimate(536, 2));
    try std.testing.expectEqual(@as(u64, 816), try nodeCapacityEstimate(553, 2));
    const before: Cost = .{ .bytes = 3064, .work = 200, .retention = 0, .admission_sets = try admissionSetCost(536, 1024) };
    const after: Cost = .{ .bytes = 3047, .work = 190, .retention = 0, .admission_sets = try admissionSetCost(553, 1024) };
    try std.testing.expect(!admissionGrowthAllowed(after, before));
}

test "activation path cost is exact for a simple chain and unknown for a CFG cycle" {
    const a = std.testing.allocator;
    var blocks = [_]ir.Block{
        .{ .function = 0, .instructions = &.{.{ .destination = 0, .opcode = .constant }}, .terminator = .{ .jump = .{ .block = 1 } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
    };
    const program: ir.Program = .{ .roots = .{ .entry = 0, .result = 0, .failure = 0 }, .schemas = &.{.unit}, .constants = &.{.{ .schema = 0, .bytes = &.{} }}, .effects = &.{}, .functions = &.{.{ .entry = 0, .inputs = &.{}, .layout = .{ .slots = &.{0} }, .result = 0 }}, .blocks = &blocks };
    try std.testing.expectEqual(@as(?u64, 3), try pathWork(a, program));
    blocks[1].terminator = .{ .jump = .{ .block = 0 } };
    try std.testing.expectEqual(@as(?u64, null), try pathWork(a, program));
}

test "entry-path estimate expands known direct calls and declines recursion" {
    const a = std.testing.allocator;
    var blocks = [_]ir.Block{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 0, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 0, .opcode = .constant }}, .terminator = .{ .return_value = 0 } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
    };
    const program: ir.Program = .{ .roots = .{ .entry = 0, .result = 0, .failure = 0 }, .schemas = &.{.unit}, .constants = &.{.{ .schema = 0, .bytes = &.{} }}, .effects = &.{}, .functions = &.{ .{ .entry = 0, .inputs = &.{}, .layout = .{ .slots = &.{0} }, .result = 0 }, .{ .entry = 2, .inputs = &.{}, .layout = .{ .slots = &.{0} }, .result = 0 } }, .blocks = &blocks };
    try std.testing.expectEqual(@as(?u64, 4), try pathWork(a, program));
    blocks[2].terminator = .{ .call = .{ .function = 0, .arguments = &.{}, .next = .{ .block = 3, .assignments = &.{.{ .destination = 0, .source = .returned }} } } };
    try std.testing.expectEqual(@as(?u64, null), try pathWork(a, program));
}
