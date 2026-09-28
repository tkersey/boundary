// Copyright (c) 2026 Boundary contributors. MIT license.
//! Bounded private worker specialization for a proven closed callable parameter.
const std = @import("std");
const ir = @import("activation.zig");
const p = @import("program.zig");
const facts = @import("value_facts.zig");
const origin = @import("constant_origin.zig");
const contexts = @import("call_contexts.zig");
const privacy = @import("capture_reduction.zig");
const ownership = @import("activation_ownership.zig");
const access = @import("slot_access.zig").terminator;
const equal = @import("record_equal.zig").equal;
const image = @import("program_image.zig");
const p01 = @import("coalescing.zig");
pub const Error = facts.Error || p01.Error || error{ InvalidCallPattern, CallPatternLimit };
pub const Options = struct { work_limit: u64 = 1_000_000, max_variants: usize = 16, max_added_blocks: usize = 256, max_added_bytes: usize = 4096, coalescing: p01.Options = .{} };
pub const Key = struct { epoch: [32]u8, function: p.Id, parameter: usize, schema: p.Id, constructor: p.Id };
pub const Variant = struct { key: Key, function: p.Id, first_block: usize };
pub const Site = struct { block: usize, variant: usize };
pub const Statistics = struct { variants: usize = 0, rewritten_calls: usize = 0, direct_applications: usize = 0, retained_calls: usize = 0, generic_fallback_calls: usize = 0, work_limit: bool = false };
pub const Candidate = struct {
    arena: std.heap.ArenaAllocator,
    program: ir.Program,
    variants: []const Variant,
    sites: []const Site,
    pub fn deinit(self: *Candidate) void {
        self.arena.deinit();
        self.* = undefined;
    }
};
const Budget = struct {
    remaining: u64,
    fn tick(self: *Budget) Error!void {
        if (self.remaining == 0) return error.CallPatternLimit;
        self.remaining -= 1;
    }
};
fn closedLeaf(program: ir.Program, constructor_id: p.Id, budget: *Budget) Error!bool {
    try budget.tick();
    if (constructor_id >= program.constructors.len or !privacy.privateWorker(program, @intCast(constructor_id))) return false;
    const constructor = program.constructors[@intCast(constructor_id)];
    const capture = program.scopes.captures[@intCast(constructor.capture)];
    const callable = program.schemas[@intCast(constructor.schema)].internal.computation;
    const function = program.functions[@intCast(constructor.function)];
    if (capture.fields.len != 0 or capture.owned_regions.len != 0 or capture.borrowed_regions.len != 0 or capture.use != .reusable or callable.use != .reusable or function.regions.len != 0 or function.effects.len != 0) return false;
    for (program.blocks) |block| {
        try budget.tick();
        if (block.function == constructor.function) switch (block.terminator) {
            .return_value, .fail, .jump, .branch => {},
            else => return false,
        };
    }
    return true;
}
fn parameterEligible(program: ir.Program, function_id: p.Id, parameter: usize, budget: *Budget) Error!bool {
    try budget.tick();
    if (function_id >= program.functions.len or contexts.unknownEntry(program, function_id)) return false;
    const function = program.functions[@intCast(function_id)];
    if (parameter >= function.inputs.len or function.effects.len != 0 or function.regions.len != 0) return false;
    const slot = function.inputs[parameter];
    const schema = program.schemas[@intCast(function.layout.slots[@intCast(slot)])];
    if (schema != .internal or schema.internal != .computation or schema.internal.computation.use != .reusable) return false;
    var uses: usize = 0;
    for (program.blocks) |block| {
        try budget.tick();
        if (block.function != function_id) continue;
        for (block.instructions) |op| {
            try budget.tick();
            if (op.destination == slot or std.mem.indexOfScalar(p.Id, op.operands, slot) != null) return false;
        }
        const usage = access(block.terminator, slot);
        if (usage.writes != 0) return false;
        switch (block.terminator) {
            .apply => |apply| {
                if (apply.computation != slot or usage.reads != 1) return false;
                uses += 1;
            },
            .return_value, .fail, .jump, .branch => if (usage.reads != 0) return false,
            else => return false,
        }
    }
    return uses != 0;
}
/// Admitted-program opportunity filter; eligibility is rechecked under budget.
pub fn possible(program: ir.Program) bool {
    for (program.functions) |function| {
        if (function.effects.len != 0 or function.regions.len != 0) continue;
        for (function.inputs) |slot| {
            const schema = program.schemas[@intCast(function.layout.slots[@intCast(slot)])];
            if (schema == .internal and schema.internal == .computation and schema.internal.computation.use == .reusable) return true;
        }
    }
    return false;
}
fn without(a: std.mem.Allocator, values: []const p.Id, index: usize) Error![]const p.Id {
    const result = try a.alloc(p.Id, values.len - 1);
    @memcpy(result[0..index], values[0..index]);
    @memcpy(result[index..], values[index + 1 ..]);
    return result;
}
fn translated(program: ir.Program, variant: Variant, block_id: p.Id) p.Id {
    var index = variant.first_block;
    for (program.blocks, 0..) |block, old| if (block.function == variant.key.function) {
        if (old == block_id) return index;
        index += 1;
    };
    unreachable; // original admission establishes every intra-function target
}
fn translatedEdge(program: ir.Program, variant: Variant, edge: ir.Edge) ir.Edge {
    var result = edge;
    result.block = translated(program, variant, edge.block);
    return result;
}
pub fn construct(allocator: std.mem.Allocator, original: ir.Program, options: Options) Error!?Candidate {
    var discovered = try facts.analyzeWithLimit(allocator, original, options.work_limit);
    defer discovered.deinit();
    var arena = std.heap.ArenaAllocator.init(allocator);
    var keep = false;
    defer if (!keep) arena.deinit();
    const a = arena.allocator();
    var budget: Budget = .{ .remaining = options.work_limit };
    var variants: std.ArrayList(Variant) = .empty;
    var sites: std.ArrayList(Site) = .empty;
    var added_blocks: usize = 0;
    for (original.blocks, discovered.blocks, 0..) |block, block_facts, bid| {
        try budget.tick();
        if (!block_facts.reachable or block.terminator != .call) continue;
        const call = block.terminator.call;
        for (call.arguments, 0..) |argument, parameter| {
            try budget.tick();
            if (!try parameterEligible(original, call.function, parameter, &budget)) continue;
            const value = block_facts.definitions[block_facts.exit[@intCast(argument)]].value;
            const constructor = value.constructor orelse continue;
            if (!try closedLeaf(original, constructor, &budget)) continue;
            const callee = original.functions[@intCast(call.function)];
            const key: Key = .{ .epoch = discovered.epoch, .function = call.function, .parameter = parameter, .schema = callee.layout.slots[@intCast(callee.inputs[parameter])], .constructor = constructor };
            var selected: ?usize = null;
            for (variants.items, 0..) |variant, index| if (std.meta.eql(variant.key, key)) {
                selected = index;
                break;
            };
            if (selected == null) {
                if (variants.items.len >= options.max_variants) return error.CallPatternLimit;
                var count: usize = 0;
                for (original.blocks) |body| if (body.function == call.function) {
                    count += 1;
                };
                if (count > options.max_added_blocks -| added_blocks) return error.CallPatternLimit;
                selected = variants.items.len;
                try variants.append(a, .{ .key = key, .function = original.functions.len + variants.items.len, .first_block = original.blocks.len + added_blocks });
                added_blocks += count;
            }
            try sites.append(a, .{ .block = bid, .variant = selected.? });
            break;
        }
    }
    if (sites.items.len == 0) return null;
    const functions = try a.alloc(ir.Function, original.functions.len + variants.items.len);
    @memcpy(functions[0..original.functions.len], original.functions);
    const blocks = try a.alloc(ir.Block, original.blocks.len + added_blocks);
    @memcpy(blocks[0..original.blocks.len], original.blocks);
    for (variants.items) |variant| {
        try budget.tick();
        const before = original.functions[@intCast(variant.key.function)];
        var worker = before;
        worker.entry = translated(original, variant, before.entry);
        worker.inputs = try without(a, before.inputs, variant.key.parameter);
        functions[@intCast(variant.function)] = worker;
        var next = variant.first_block;
        for (original.blocks) |block| {
            if (block.function != variant.key.function) continue;
            try budget.tick();
            var copy = block;
            copy.function = variant.function;
            switch (block.terminator) {
                .apply => |apply| copy.terminator = .{ .call = .{ .function = original.constructors[@intCast(variant.key.constructor)].function, .arguments = apply.arguments, .next = translatedEdge(original, variant, apply.next) } },
                .jump => |edge| copy.terminator.jump = translatedEdge(original, variant, edge),
                .branch => |branch| {
                    copy.terminator.branch.when_true = translatedEdge(original, variant, branch.when_true);
                    copy.terminator.branch.when_false = translatedEdge(original, variant, branch.when_false);
                },
                .return_value, .fail => {},
                else => unreachable,
            }
            blocks[next] = copy;
            next += 1;
        }
    }
    for (sites.items) |site| {
        try budget.tick();
        const variant = variants.items[site.variant];
        const call = &blocks[site.block].terminator.call;
        call.function = variant.function;
        call.arguments = try without(a, call.arguments, variant.key.parameter);
    }
    var program = original;
    program.functions = functions;
    program.blocks = blocks;
    const before_bytes = try image.encodedLength(original);
    const after_bytes = try image.encodedLength(program);
    if (after_bytes > before_bytes and after_bytes - before_bytes > options.max_added_bytes) return error.CallPatternLimit;
    const owned_variants = try variants.toOwnedSlice(a);
    const owned_sites = try sites.toOwnedSlice(a);
    keep = true;
    return .{ .arena = arena, .program = program, .variants = owned_variants, .sites = owned_sites };
}

fn edgeCorresponds(original: ir.Program, variant: Variant, before: ir.Edge, after: ir.Edge) bool {
    if (!equal([]const ir.Assignment, before.assignments, after.assignments)) return false;
    // Count source-function blocks independently of the emitter's remapping.
    var ordinal: usize = 0;
    for (original.blocks, 0..) |block, id| {
        if (block.function != variant.key.function) continue;
        if (id == before.block) return after.block == variant.first_block + ordinal;
        ordinal += 1;
    }
    return false;
}
pub fn validate(allocator: std.mem.Allocator, original: ir.Program, candidate: ir.Program, variants: []const Variant, sites: []const Site, work_limit: u64) Error!void {
    var before = try ownership.analyze(allocator, original);
    defer before.deinit();
    var after = try ownership.analyze(allocator, candidate);
    defer after.deinit();
    if (variants.len == 0 or sites.len == 0 or candidate.functions.len != original.functions.len + variants.len or candidate.blocks.len < original.blocks.len) return error.InvalidCallPattern;
    var unchanged = candidate;
    unchanged.functions = original.functions;
    unchanged.blocks = original.blocks;
    if (!equal(ir.Program, original, unchanged)) return error.InvalidCallPattern;
    const epoch = try image.identity(allocator, original);
    var budget: Budget = .{ .remaining = work_limit };
    var proof: origin.Prover = .{ .allocator = allocator, .program = original, .work_limit = work_limit };
    defer proof.deinit();
    for (original.functions, candidate.functions[0..original.functions.len]) |old, new| if (!equal(ir.Function, old, new)) return error.InvalidCallPattern;
    var next_block = original.blocks.len;
    for (variants, 0..) |variant, vid| {
        try budget.tick();
        if (!std.mem.eql(u8, &epoch, &variant.key.epoch) or variant.function != original.functions.len + vid or variant.first_block != next_block or !try parameterEligible(original, variant.key.function, variant.key.parameter, &budget) or !try closedLeaf(original, variant.key.constructor, &budget)) return error.InvalidCallPattern;
        for (variants[0..vid]) |previous| if (std.meta.eql(previous.key, variant.key)) return error.InvalidCallPattern;
        const function = original.functions[@intCast(variant.key.function)];
        const slot = function.inputs[variant.key.parameter];
        if (variant.key.schema != function.layout.slots[@intCast(slot)]) return error.InvalidCallPattern;
        const worker = candidate.functions[@intCast(variant.function)];
        var metadata = worker;
        metadata.entry = function.entry;
        metadata.inputs = function.inputs;
        if (!equal(ir.Function, function, metadata) or worker.inputs.len + 1 != function.inputs.len) return error.InvalidCallPattern;
        var index: usize = 0;
        for (function.inputs, 0..) |input, position| {
            if (position == variant.key.parameter) continue;
            if (worker.inputs[index] != input) return error.InvalidCallPattern;
            index += 1;
        }
        var used = false;
        for (sites) |site| if (site.variant == vid) {
            used = true;
        };
        if (!used) return error.InvalidCallPattern;
        for (original.blocks, 0..) |block, bid| {
            if (block.function != variant.key.function) continue;
            try budget.tick();
            if (next_block >= candidate.blocks.len) return error.InvalidCallPattern;
            const replacement = candidate.blocks[next_block];
            if (bid == function.entry and worker.entry != next_block) return error.InvalidCallPattern;
            next_block += 1;
            if (replacement.function != variant.function or replacement.custody != block.custody or !equal([]const ir.Instruction, block.instructions, replacement.instructions)) return error.InvalidCallPattern;
            var term = replacement.terminator;
            switch (block.terminator) {
                .apply => |apply| {
                    if (term != .call or term.call.function != original.constructors[@intCast(variant.key.constructor)].function or !std.mem.eql(p.Id, term.call.arguments, apply.arguments) or !edgeCorresponds(original, variant, apply.next, term.call.next)) return error.InvalidCallPattern;
                    term = block.terminator;
                },
                .jump => |edge| {
                    if (term != .jump or !edgeCorresponds(original, variant, edge, term.jump)) return error.InvalidCallPattern;
                    term = block.terminator;
                },
                .branch => |branch| {
                    if (term != .branch or !edgeCorresponds(original, variant, branch.when_true, term.branch.when_true) or !edgeCorresponds(original, variant, branch.when_false, term.branch.when_false)) return error.InvalidCallPattern;
                    term.branch.when_true = branch.when_true;
                    term.branch.when_false = branch.when_false;
                },
                .return_value, .fail => {},
                else => return error.InvalidCallPattern,
            }
            if (!equal(ir.Terminator, block.terminator, term)) return error.InvalidCallPattern;
        }
    }
    if (next_block != candidate.blocks.len) return error.InvalidCallPattern;
    var seen: usize = 0;
    for (original.blocks, candidate.blocks[0..original.blocks.len], 0..) |old, new, bid| {
        try budget.tick();
        var site: ?Site = null;
        for (sites) |item| if (item.block == bid) {
            if (site != null) return error.InvalidCallPattern;
            site = item;
        };
        if (site) |item| {
            seen += 1;
            if (item.variant >= variants.len or old.terminator != .call or new.terminator != .call) return error.InvalidCallPattern;
            const variant = variants[item.variant];
            const call = old.terminator.call;
            if (call.function != variant.key.function or new.terminator.call.function != variant.function or new.terminator.call.arguments.len + 1 != call.arguments.len) return error.InvalidCallPattern;
            const known = (try proof.resolve(bid, old.instructions.len, call.arguments[variant.key.parameter])) orelse {
                if (proof.exhausted) return error.CallPatternLimit;
                return error.InvalidCallPattern;
            };
            if (known != .constructor or known.constructor != variant.key.constructor) return error.InvalidCallPattern;
            var index: usize = 0;
            for (call.arguments, 0..) |argument, position| {
                if (position == variant.key.parameter) continue;
                if (new.terminator.call.arguments[index] != argument) return error.InvalidCallPattern;
                index += 1;
            }
            var restored = new;
            restored.terminator.call.function = call.function;
            restored.terminator.call.arguments = call.arguments;
            if (!equal(ir.Block, old, restored)) return error.InvalidCallPattern;
        } else if (!equal(ir.Block, old, new)) return error.InvalidCallPattern;
    }
    if (seen != sites.len) return error.InvalidCallPattern;
}
pub fn run(allocator: std.mem.Allocator, original: ir.Program, statistics: ?*Statistics, options: Options) Error!p01.Owned {
    var stats: Statistics = .{};
    for (original.blocks) |block| if (block.terminator == .call) {
        stats.retained_calls += 1;
    };
    defer if (statistics) |out| {
        out.* = stats;
    };
    var candidate = (construct(allocator, original, options) catch |err| switch (err) {
        error.CallPatternLimit, error.SemanticWorkLimit => {
            stats.work_limit = true;
            return p01.run(allocator, original, options.coalescing);
        },
        else => return err,
    }) orelse return p01.run(allocator, original, options.coalescing);
    defer candidate.deinit();
    validate(allocator, original, candidate.program, candidate.variants, candidate.sites, options.work_limit) catch |err| switch (err) {
        error.CallPatternLimit => {
            stats.work_limit = true;
            return p01.run(allocator, original, options.coalescing);
        },
        else => return err,
    };
    stats.variants = candidate.variants.len;
    stats.rewritten_calls = candidate.sites.len;
    for (candidate.variants) |variant| for (original.blocks) |block| if (block.function == variant.key.function and block.terminator == .apply) {
        stats.direct_applications += 1;
    };
    for (original.blocks, 0..) |block, bid| {
        if (block.terminator != .call) continue;
        var specialized = false;
        for (candidate.sites) |site| if (site.block == bid) {
            specialized = true;
        };
        if (specialized) continue;
        for (candidate.variants) |variant| if (variant.key.function == block.terminator.call.function) {
            stats.generic_fallback_calls += 1;
            break;
        };
    }
    stats.retained_calls -= candidate.sites.len;
    return p01.run(allocator, candidate.program, options.coalescing);
}
