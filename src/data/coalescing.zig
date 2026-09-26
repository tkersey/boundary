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
const origins = @import("coalescing_origins.zig");
pub const Diagnostic = origins.Diagnostic;
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
    failed_check: ?anyerror = null,
};
pub const Round = struct {
    materialized: bool,
    baseline: Counts,
    full: Counts,
    descriptions: Counts,
    selected: ?discovery.Profile,
    work: u64,
};
pub const Options = struct {
    mode: Mode = .safe,
    statistics: ?*Statistics = null,
    diagnostic: ?*Diagnostic = null,
    /// Deterministic discovery-work units; unlimited unless a caller selects a bound.
    work_limit: u64 = std.math.maxInt(u64),

    pub fn resetObservations(self: Options) void {
        if (self.statistics) |stats| stats.* = .{ .rounds = stats.rounds };
        if (self.diagnostic) |diagnostic| diagnostic.* = .{};
    }
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
    options.resetObservations();
    const result = runInternal(allocator, original, options) catch |err| {
        if (options.diagnostic) |d| d.code = err;
        if (options.statistics) |stats| stats.failed_check = err;
        return err;
    };
    if (options.diagnostic) |d| d.* = .{};
    return result;
}

fn runInternal(allocator: std.mem.Allocator, original: ir.Program, options: Options) Error!Owned {
    const round_storage: []Round = if (options.statistics) |stats| stats.rounds else &.{};
    var checked = admission.analyzeDiagnosed(allocator, original, if (options.diagnostic) |d| &d.target else null) catch |err| {
        if (options.diagnostic) |d| origins.explainOriginal(original, d);
        return err;
    };
    checked.deinit();
    if (options.diagnostic) |d| d.* = .{ .stage = .baseline };
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    var baseline_arena = std.heap.ArenaAllocator.init(allocator);
    errdefer baseline_arena.deinit();
    const baseline = try r.ownReachable(baseline_arena.allocator(), scratch.allocator(), original);
    var trace: ?origins.Trace = if (options.diagnostic != null)
        try origins.Trace.init(allocator, original, baseline)
    else
        null;
    defer if (trace) |*value| value.deinit();
    if (options.diagnostic) |d| d.* = .{ .stage = .baseline };
    var flow = admission.analyzeDiagnosed(allocator, baseline.program, if (options.diagnostic) |d| &d.target else null) catch |err| {
        if (options.diagnostic) |d| if (trace) |*t| t.explain(null, d);
        return err;
    };
    errdefer flow.deinit();
    if (options.diagnostic) |d| d.* = .{ .stage = .cost };
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
        const selected = attempt(allocator, baseline.program, &stats, if (trace) |*t| t else null, options.diagnostic) catch |err| switch (err) {
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

fn recordRound(stats: *Statistics, selected: ?discovery.Profile, materialized: bool) void {
    if (stats.rounds_recorded < stats.rounds.len) {
        stats.rounds[stats.rounds_recorded] = .{
            .materialized = materialized,
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

fn attempt(allocator: std.mem.Allocator, baseline: ir.Program, stats: *Statistics, trace: ?*origins.Trace, diagnostic: ?*Diagnostic) Error!?Owned {
    var selected: ?Owned = null;
    errdefer if (selected) |*value| value.deinit();
    stats.outcome = .no_change;
    var remaining = stats.baseline.entries;
    while (true) {
        if (diagnostic) |d| d.* = .{ .stage = .mapping };
        var scratch = std.heap.ArenaAllocator.init(allocator);
        defer scratch.deinit();
        const a = scratch.allocator();
        const program = if (selected) |value| value.program else baseline;
        const analysis = try discovery.analyze(a, program, &stats.work);
        if (stats.round_count == 0) for (analysis.nodes[0..program.functions.len]) |node| {
            stats.pinned_functions += @intFromBool(node.pinned);
        };
        const full_map = try discovery.correspondence(a, program, analysis, .full, &stats.work);
        // A restricted profile can only split the complete full relation. If
        // that relation has no merge, neither profile can reduce live records.
        if (!hasMerge(full_map.representatives)) {
            stats.full = stats.selected;
            stats.descriptions = stats.selected;
            recordRound(stats, null, false);
            return selected;
        }
        var full = try candidate.materialize(allocator, a, program, full_map, trace, diagnostic);
        var keep_full = false;
        defer if (!keep_full) full.deinit();
        // The description profile adds only singleton function restrictions.
        // When full discovery already has those singletons, both fixed points
        // and materializations are identical. Reuse the independently checked
        // full candidate; the existing tie-break selects it in either case.
        const same_profiles = !mapHasMerge(full_map.representatives[@intFromEnum(r.Kind.function)]);
        var separate_descriptions: ?candidate.Candidate = if (same_profiles) null else try candidate.buildObserved(
            allocator,
            a,
            program,
            analysis,
            .descriptions,
            &stats.work,
            trace,
            diagnostic,
        );
        const descriptions = if (separate_descriptions) |*value| value else &full;
        var keep_descriptions = false;
        defer if (!keep_descriptions) if (separate_descriptions) |*value| value.deinit();
        stats.validator_calls += if (same_profiles) @as(usize, 2) else 4;
        stats.candidate_admissions += if (same_profiles) @as(usize, 1) else 2;
        stats.full = try Counts.of(full.program);
        stats.descriptions = try Counts.of(descriptions.program);
        const full_eligible = eligible(full, stats.selected);
        const description_eligible = eligible(descriptions.*, stats.selected);
        const selected_profile = choose(
            if (full_eligible) .{ .bytes = full.bytes, .entries = full.entries } else null,
            if (description_eligible)
                .{ .bytes = descriptions.bytes, .entries = descriptions.entries }
            else
                null,
        );
        recordRound(stats, selected_profile, true);
        if (!full_eligible and !description_eligible) {
            if (selected == null and (full.entries < stats.selected.entries or
                descriptions.entries < stats.selected.entries)) stats.outcome = .size_guard;
            return selected;
        }
        if (remaining == 0) return error.InvalidCorrespondence;
        remaining -= 1;
        if (diagnostic) |d| d.* = .{ .stage = .mapping };
        if (trace) |t| try t.advance(if (selected_profile.? == .full)
            full.correspondence
        else
            descriptions.correspondence);
        if (selected) |*old| old.deinit();
        if (selected_profile.? == .full) {
            keep_full = true;
            selected = owned(full);
            stats.selected = stats.full;
            stats.selected_profile = .full;
        } else {
            keep_descriptions = true;
            selected = owned(descriptions.*);
            stats.selected = stats.descriptions;
            stats.selected_profile = .descriptions;
        }
        stats.outcome = .applied;
        stats.extraction_rounds += 1;
        stats.attempted_extraction_rounds += 1;
        if (stats.first_selected_work == 0) stats.first_selected_work = stats.work.units;
    }
}

fn hasMerge(maps: r.Maps) bool {
    for (maps) |map| if (mapHasMerge(map)) return true;
    return false;
}

fn mapHasMerge(map: []const @import("program.zig").Id) bool {
    for (map, 0..) |representative, id| if (representative != id) return true;
    return false;
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
