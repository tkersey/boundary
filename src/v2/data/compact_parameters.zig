// Copyright (c) 2026 Boundary contributors. MIT license.
//! Economical shared backings for block parameter schema prefixes.
const std = @import("std");
const p = @import("program.zig");
const wire = @import("wire.zig");
const sequence = @import("compact_sequence.zig");
const Error = @import("record.zig").Error;
const Entry = struct { block: usize, values: []const p.Id };

pub const Plan = struct {
    allocator: std.mem.Allocator,
    references: []?usize,
    backings: std.ArrayList([]const p.Id) = .empty,
    from_end: bool = false,

    pub fn deinit(self: *Plan) void {
        self.allocator.free(self.references);
        self.backings.deinit(self.allocator);
    }

    pub fn init(allocator: std.mem.Allocator, program: p.Program) Error!Plan {
        var front = try direction(allocator, program, false);
        errdefer front.deinit();
        // Reversing constant vectors leaves both sorted candidate sets identical.
        if (uniform(program)) return front;
        var back = try direction(allocator, program, true);
        errdefer back.deinit();
        if (try back.cost(program) < try front.cost(program)) {
            front.deinit();
            return back;
        }
        back.deinit();
        return front;
    }

    fn direction(allocator: std.mem.Allocator, program: p.Program, from_end: bool) Error!Plan {
        var self: Plan = .{
            .allocator = allocator,
            .references = try allocator.alloc(?usize, program.blocks.len),
            .from_end = from_end,
        };
        errdefer self.deinit();
        @memset(self.references, null);
        const entries = try allocator.alloc(Entry, program.blocks.len);
        defer allocator.free(entries);
        for (program.blocks, entries, 0..) |block, *entry, index|
            entry.* = .{ .block = index, .values = block.parameters };
        std.mem.sort(Entry, entries, from_end, less);
        var start: usize = 0;
        while (start < entries.len) {
            var end = start + 1;
            while (end < entries.len and
                matches(entries[end - 1].values, entries[end].values, from_end))
                end += 1;
            try self.consider(entries[start..end]);
            start = end;
        }
        return self;
    }

    fn cost(self: Plan, program: p.Program) Error!usize {
        var total = naturalSize(self.backings.items.len);
        for (self.backings.items) |values|
            total = std.math.add(usize, total, try length(values)) catch return error.InvalidLength;
        for (program.blocks, self.references) |block, index| {
            const bytes = if (index) |backing|
                try referenceLength(block.parameters.len, backing)
            else
                try length(block.parameters);
            total = std.math.add(usize, total, bytes) catch return error.InvalidLength;
        }
        return total;
    }

    fn consider(self: *Plan, entries: []const Entry) Error!void {
        if (entries.len < 2) return;
        const longest = entries[entries.len - 1].values;
        if (longest.len <= 2) return;
        const index = self.backings.items.len;
        // Every backing has a complete logical occurrence, so a tiny prefix
        // cannot keep an otherwise dead expanded allocation alive.
        if (try length(longest) <= try referenceLength(longest.len, index)) return;
        var savings: usize = 0;
        for (entries) |entry| {
            if (entry.values.len <= 2) continue;
            const raw = try length(entry.values);
            const referenced = try referenceLength(entry.values.len, index);
            if (raw > referenced)
                savings = std.math.add(usize, savings, raw - referenced) catch
                    return error.InvalidLength;
        }
        // Account for both the backing and any increase in pool-count width.
        const backing_cost = std.math.add(usize, try length(longest), naturalSize(index + 1) - naturalSize(index)) catch return error.InvalidLength;
        if (savings <= backing_cost) return;
        try self.backings.append(self.allocator, longest);
        for (entries) |entry| {
            if (entry.values.len > 2 and
                try length(entry.values) > try referenceLength(entry.values.len, index))
                self.references[entry.block] = index;
        }
    }
};

fn less(from_end: bool, a: Entry, b: Entry) bool {
    if (from_end) {
        for (0..@min(a.values.len, b.values.len)) |index| {
            const left = a.values[a.values.len - index - 1];
            const right = b.values[b.values.len - index - 1];
            if (left != right) return left < right;
        }
        return if (a.values.len == b.values.len) a.block < b.block else a.values.len < b.values.len;
    }
    const order = std.mem.order(p.Id, a.values, b.values);
    return if (order == .eq) a.block < b.block else order == .lt;
}

fn matches(a: []const p.Id, b: []const p.Id, from_end: bool) bool {
    if (a.len > b.len) return false;
    const start = if (from_end) b.len - a.len else 0;
    return std.mem.eql(p.Id, a, b[start..][0..a.len]);
}

fn uniform(program: p.Program) bool {
    for (program.blocks) |block| {
        if (block.parameters.len == 0) continue;
        for (block.parameters[1..]) |value| if (value != block.parameters[0]) return false;
    }
    return true;
}

fn naturalSize(value: usize) usize {
    var writer: wire.Writer = .{};
    writer.natural(value) catch unreachable; // At most ten bytes.
    return writer.position;
}

fn referenceLength(count: usize, index: usize) Error!usize {
    var writer: wire.Writer = .{};
    try reference(count, index, false, &writer);
    return writer.position;
}

pub fn length(values: []const p.Id) Error!usize {
    var writer: wire.Writer = .{};
    try sequence.write(p.Id, values, &writer);
    return writer.position;
}

pub fn reference(count: usize, index: usize, from_end: bool, writer: *wire.Writer) Error!void {
    std.debug.assert(count > 2);
    try writer.natural(count);
    try writer.byte(if (from_end) 3 else 2);
    try writer.natural(index);
}

pub const Writing = struct {
    plan: *const Plan,
    block: usize = 0,

    pub fn parameters(self: *Writing, values: []const p.Id, writer: *wire.Writer) Error!void {
        const index = self.plan.references[self.block];
        self.block += 1;
        if (index) |backing| return reference(values.len, backing, self.plan.from_end, writer);
        return sequence.write(p.Id, values, writer);
    }
};

pub const Reading = struct {
    backings: []const []const p.Id = &.{},
    fully_used: []bool,

    pub fn parameters(
        self: Reading,
        reader: *wire.Reader,
        allocator: std.mem.Allocator,
        requested: *usize,
    ) Error![]const p.Id {
        var probe = reader.*;
        const count = try probe.count();
        const mode = if (count > 2) try probe.byte() else 0;
        if (mode == 2 or mode == 3) {
            const index = try probe.count();
            if (index >= self.backings.len) return error.InvalidLength;
            const backing_length = self.backings[index].len;
            if (count > backing_length) return error.InvalidLength;
            if (count == backing_length) self.fully_used[index] = true;
            reader.* = probe;
            const start = if (mode == 3) backing_length - count else 0;
            return self.backings[index][start..][0..count];
        }
        return sequence.read(p.Id, true, reader, allocator, requested);
    }
};
