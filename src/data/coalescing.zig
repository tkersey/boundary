// Copyright (c) 2026 Boundary contributors. MIT license.
//! Closed-program coalescing. Compilation/linking owns when this pass is invoked.
const std = @import("std");
const ir = @import("activation.zig");
const r = @import("relocation.zig");
const image = @import("program_image.zig");
const admission = @import("activation_ownership.zig");
const graph = @import("coalescing_graph.zig");
const discovery = @import("coalescing_discovery.zig");
const candidate = @import("coalescing_candidate.zig");
pub const Mode = enum { off, safe };
pub const Outcome = enum {
    disabled,
    deferred_open_component,
    no_change,
    applied,
    size_guard,
    work_limit,
};
pub const Counts = struct {
    catalogs: [r.kind_count]usize = @splat(0),
    instructions: usize = 0,
    bytes: usize = 0,
    entries: usize = 0,

    pub fn of(program: ir.Program) Error!Counts {
        var result: Counts = .{
            .catalogs = try r.sizes(program),
            .bytes = try image.encodedLength(program),
            .entries = try candidate.count(program),
        };
        for (program.blocks) |block|
            result.instructions = std.math.add(
                usize,
                result.instructions,
                block.instructions.len,
            ) catch return error.InvalidLength;
        return result;
    }
};
pub const Statistics = struct {
    /// Optional caller-owned storage. Short storage reports a truncated trace;
    /// it never changes selection or retains program/scratch references.
    rounds: []Round = &.{},
    round_count: usize = 0,
    rounds_recorded: usize = 0,
    outcome: Outcome = .disabled,
    baseline: Counts = .{},
    full: Counts = .{},
    descriptions: Counts = .{},
    selected: Counts = .{},
    work: graph.Work = .{},
    extraction_rounds: usize = 0,
    attempted_extraction_rounds: usize = 0,
    first_selected_work: u64 = 0,
    selected_profile: ?discovery.Profile = null,
    validator_calls: usize = 0,
    candidate_admissions: usize = 0,
    pinned_functions: usize = 0,
};
pub const Round = struct {
    baseline: Counts,
    full: Counts,
    descriptions: Counts,
    selected: ?discovery.Profile,
    work: u64,
};
pub const Options = struct {
    mode: Mode = .off,
    statistics: ?*Statistics = null,
    /// Deterministic discovery-work units; unlimited unless a caller selects a bound.
    work_limit: u64 = std.math.maxInt(u64),
};
pub const Error = candidate.Error;
pub const Owned = struct {
    arena: std.heap.ArenaAllocator,
    program: ir.Program,
    flow: @import("activation_flow.zig").Facts,

    pub fn deinit(self: *Owned) void {
        self.flow.deinit();
        self.arena.deinit();
        self.* = undefined;
    }
};

/// Raw-record entry point: checks the complete original before projection.
/// Source/component obligations remain the outer compiler/linker's responsibility.
/// Returned records/facts own their storage; statistics retain no record references.
pub fn run(allocator: std.mem.Allocator, original: ir.Program, options: Options) Error!Owned {
    const round_storage: []Round = if (options.statistics) |stats| stats.rounds else &.{};
    if (options.statistics) |stats| stats.* = .{ .rounds = round_storage };
    var checked = try admission.analyze(allocator, original);
    checked.deinit();
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    var baseline_arena = std.heap.ArenaAllocator.init(allocator);
    errdefer baseline_arena.deinit();
    const baseline = try r.ownReachable(baseline_arena.allocator(), scratch.allocator(), original);
    var flow = try admission.analyze(allocator, baseline.program);
    errdefer flow.deinit();
    const counts = try Counts.of(baseline.program);
    var stats: Statistics = .{
        .baseline = counts,
        .selected = counts,
        .rounds = round_storage,
        .work = .{ .limit = options.work_limit },
    };
    defer {
        if (options.statistics) |output| output.* = stats;
    }
    if (options.mode == .safe) {
        const selected = attempt(allocator, baseline.program, &stats) catch |err| switch (err) {
            error.WorkLimit => blk: {
                stats.outcome = .work_limit;
                stats.selected = counts;
                stats.extraction_rounds = 0;
                stats.selected_profile = null;
                break :blk null;
            },
            else => return err,
        };
        if (selected) |result| {
            flow.deinit();
            baseline_arena.deinit();
            return result;
        }
    }
    return .{ .arena = baseline_arena, .program = baseline.program, .flow = flow };
}

fn owned(value: candidate.Candidate) Owned {
    return .{ .arena = value.arena, .program = value.program, .flow = value.flow };
}

fn eligible(value: candidate.Candidate, baseline: Counts) bool {
    if (value.bytes > baseline.bytes or value.entries >= baseline.entries) return false;
    for (value.correspondence.representatives) |map|
        for (map, 0..) |representative, id| if (representative != id) return true;
    return false;
}

const Cost = struct { bytes: usize, entries: usize };
fn choose(full: ?Cost, descriptions: ?Cost) ?discovery.Profile {
    if (full) |left| {
        const right = descriptions orelse return .full;
        return if (left.bytes < right.bytes or
            (left.bytes == right.bytes and left.entries <= right.entries)) .full else .descriptions;
    }
    return if (descriptions != null) .descriptions else null;
}

fn recordRound(stats: *Statistics, selected: ?discovery.Profile) void {
    if (stats.rounds_recorded < stats.rounds.len) {
        stats.rounds[stats.rounds_recorded] = .{
            .baseline = stats.selected,
            .full = stats.full,
            .descriptions = stats.descriptions,
            .selected = selected,
            .work = stats.work.units,
        };
        stats.rounds_recorded += 1;
    }
    stats.round_count += 1;
}

fn attempt(allocator: std.mem.Allocator, baseline: ir.Program, stats: *Statistics) Error!?Owned {
    var selected: ?Owned = null;
    errdefer if (selected) |*value| value.deinit();
    stats.outcome = .no_change;
    var remaining = stats.baseline.entries;
    while (true) {
        var scratch = std.heap.ArenaAllocator.init(allocator);
        defer scratch.deinit();
        const a = scratch.allocator();
        const program = if (selected) |value| value.program else baseline;
        const analysis = try discovery.analyze(a, program, &stats.work);
        if (stats.round_count == 0) for (analysis.nodes[0..program.functions.len]) |node| {
            stats.pinned_functions += @intFromBool(node.pinned);
        };
        var full = try candidate.build(allocator, a, program, analysis, .full, &stats.work);
        var keep_full = false;
        defer if (!keep_full) full.deinit();
        var descriptions = try candidate.build(
            allocator,
            a,
            program,
            analysis,
            .descriptions,
            &stats.work,
        );
        var keep_descriptions = false;
        defer if (!keep_descriptions) descriptions.deinit();
        stats.validator_calls += 4;
        stats.candidate_admissions += 2;
        stats.full = try Counts.of(full.program);
        stats.descriptions = try Counts.of(descriptions.program);
        const full_eligible = eligible(full, stats.selected);
        const description_eligible = eligible(descriptions, stats.selected);
        const selected_profile = choose(
            if (full_eligible) .{ .bytes = full.bytes, .entries = full.entries } else null,
            if (description_eligible)
                .{ .bytes = descriptions.bytes, .entries = descriptions.entries }
            else
                null,
        );
        recordRound(stats, selected_profile);
        if (!full_eligible and !description_eligible) {
            if (selected == null and (full.entries < stats.selected.entries or
                descriptions.entries < stats.selected.entries)) stats.outcome = .size_guard;
            return selected;
        }
        if (remaining == 0) return error.InvalidCorrespondence;
        remaining -= 1;
        if (selected) |*old| old.deinit();
        if (selected_profile.? == .full) {
            keep_full = true;
            selected = owned(full);
            stats.selected = stats.full;
            stats.selected_profile = .full;
        } else {
            keep_descriptions = true;
            selected = owned(descriptions);
            stats.selected = stats.descriptions;
            stats.selected_profile = .descriptions;
        }
        stats.outcome = .applied;
        stats.extraction_rounds += 1;
        stats.attempted_extraction_rounds += 1;
        if (stats.first_selected_work == 0) stats.first_selected_work = stats.work.units;
    }
}

test "coalescing exact portfolio cost seam preserves byte then entry then full ordering" {
    const testing = std.testing;
    try testing.expect(choose(null, null) == null);
    try testing.expectEqual(
        discovery.Profile.full,
        choose(.{ .bytes = 100, .entries = 8 }, .{ .bytes = 101, .entries = 7 }).?,
    );
    try testing.expectEqual(
        discovery.Profile.descriptions,
        choose(.{ .bytes = 102, .entries = 6 }, .{ .bytes = 101, .entries = 7 }).?,
    );
    try testing.expectEqual(
        discovery.Profile.descriptions,
        choose(.{ .bytes = 100, .entries = 8 }, .{ .bytes = 100, .entries = 7 }).?,
    );
    try testing.expectEqual(
        discovery.Profile.full,
        choose(.{ .bytes = 100, .entries = 7 }, .{ .bytes = 100, .entries = 7 }).?,
    );
}
