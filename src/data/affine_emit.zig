// Copyright (c) 2026 Boundary contributors. MIT license.
//! Untrusted affine candidate construction; never a production acceptance gate.
const std = @import("std");
const ir = @import("activation.zig");
const p = @import("program.zig");
const census = @import("affine_capture.zig");
const extract = @import("affine_extract.zig");
const space = @import("affine_space.zig");
pub const Error = census.Error || error{UnrepresentableAffineObservation};
pub const Candidate = struct {
    arena: std.heap.ArenaAllocator,
    program: ir.Program,
    constructor: usize,
    basis: []const space.Row,
    pub fn deinit(self: *Candidate) void {
        self.arena.deinit();
        self.* = undefined;
    }
};
const Builder = struct {
    a: std.mem.Allocator,
    schema: p.Id,
    width: usize,
    slots: *std.ArrayList(p.Id),
    literals: *std.ArrayList(p.Literal),
    operations: std.ArrayList(ir.Instruction) = .empty,
    budget: *space.Budget,
    fn append(self: *Builder, opcode: p.Opcode, operands: []const p.Id, immediate: p.Id) Error!p.Id {
        try self.budget.charge();
        const destination = self.slots.items.len;
        try self.slots.append(self.a, self.schema);
        try self.operations.append(self.a, .{ .destination = destination, .opcode = opcode, .operands = try self.a.dupe(p.Id, operands), .immediate = immediate });
        return destination;
    }
    fn constant(self: *Builder, value: u64) Error!p.Id {
        const bytes = try self.a.alloc(u8, self.width);
        for (bytes, 0..) |*byte, i| byte.* = @truncate(value >> @intCast(8 * i));
        const id = self.literals.items.len;
        try self.literals.append(self.a, .{ .schema = self.schema, .bytes = bytes });
        return self.append(.constant, &.{}, id);
    }
    fn combine(self: *Builder, accumulator: ?p.Id, value: p.Id) Error!p.Id {
        return if (accumulator) |previous| self.append(.integer_bit_xor, &.{ previous, value }, 0) else value;
    }
    fn expression(self: *Builder, value: extract.Expression, basis: *const space.Space, summary: []const p.Id, inputs: []const p.Id) Error!p.Id {
        const coefficients = (try basis.coefficients(value.state, self.budget)) orelse return error.UnrepresentableAffineObservation;
        var result: ?p.Id = null;
        for (summary, 0..) |slot, i| if (coefficients & space.coordinate(i) != 0) {
            result = try self.combine(result, slot);
        };
        for (inputs, 0..) |slot, i| if (value.input & space.coordinate(i) != 0) {
            result = try self.combine(result, slot);
        };
        if (value.constant != 0) result = try self.combine(result, try self.constant(value.constant));
        return result orelse try self.constant(0);
    }
    fn original(self: *Builder, row: space.Row, operands: []const p.Id) Error!p.Id {
        var result: ?p.Id = null;
        for (operands, 0..) |slot, i| if (row & space.coordinate(i) != 0) {
            result = try self.combine(result, slot);
        };
        return result orelse try self.constant(0);
    }
};
fn remap(builder: *Builder, slot: p.Id, values: []const ?extract.Expression, basis: *const space.Space, summary: []const p.Id, inputs: []const p.Id) Error!p.Id {
    return if (values[@intCast(slot)]) |value| builder.expression(value, basis, summary, inputs) else slot;
}

pub fn construct(allocator: std.mem.Allocator, original: ir.Program, constructor_id: usize, work_limit: u64) Error!?Candidate {
    var plan = (try census.analyze(allocator, original, constructor_id, work_limit)) orelse return null;
    defer plan.deinit();
    if (plan.basis.len == plan.dimension) return null;
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const a = arena.allocator();
    var budget: space.Budget = .{ .remaining = work_limit };
    var basis = try space.Space.init(plan.dimension);
    for (plan.basis) |row| _ = try basis.insert(row, &budget);
    const functions = try a.dupe(ir.Function, original.functions);
    const blocks = try a.dupe(ir.Block, original.blocks);
    const constructors = try a.dupe(p.Constructor, original.constructors);
    const captures = try a.alloc(p.Capture, original.scopes.captures.len + 1);
    @memcpy(captures[0..original.scopes.captures.len], original.scopes.captures);
    const ctor = &constructors[constructor_id];
    var capture = original.scopes.captures[@intCast(ctor.capture)];
    const fields = try a.alloc(p.Id, plan.basis.len);
    @memset(fields, plan.schema);
    capture.fields = fields;
    captures[original.scopes.captures.len] = capture;
    ctor.capture = original.scopes.captures.len;
    const worker = original.functions[@intCast(plan.worker)];
    const input_slots = try a.alloc(p.Id, worker.inputs.len - plan.dimension + plan.basis.len);
    @memcpy(input_slots[0..plan.basis.len], worker.inputs[0..plan.basis.len]);
    @memcpy(input_slots[plan.basis.len..], worker.inputs[plan.dimension..]);
    functions[@intCast(plan.worker)].inputs = input_slots;
    const layouts = try a.alloc(std.ArrayList(p.Id), functions.len);
    for (layouts, original.functions) |*layout, function| {
        layout.* = .empty;
        try layout.appendSlice(a, function.layout.slots);
    }
    var literals: std.ArrayList(p.Literal) = .empty;
    try literals.appendSlice(a, original.constants);
    for (original.blocks, blocks) |block, *out| {
        var builder: Builder = .{ .a = a, .schema = plan.schema, .width = extract.unsignedWidth(original.schemas[@intCast(plan.schema)]).?, .slots = &layouts[@intCast(block.function)], .literals = &literals, .budget = &budget };
        if (block.function != plan.worker) {
            for (block.instructions) |op| {
                var replacement = op;
                if (op.opcode == .computation and op.immediate == constructor_id) {
                    const operands = try a.alloc(p.Id, plan.basis.len);
                    for (plan.basis, operands) |row, *operand| operand.* = try builder.original(row, op.operands);
                    replacement.operands = operands;
                }
                try builder.operations.append(a, replacement);
            }
            if (block.terminator == .call and block.terminator.call.function == plan.worker) {
                const call = block.terminator.call;
                const arguments = try a.alloc(p.Id, input_slots.len);
                for (plan.basis, arguments[0..plan.basis.len]) |row, *argument| argument.* = try builder.original(row, call.arguments[0..plan.dimension]);
                @memcpy(arguments[plan.basis.len..], call.arguments[plan.dimension..]);
                out.terminator.call.arguments = arguments;
            }
        } else {
            const values = try a.alloc(?extract.Expression, worker.layout.slots.len);
            @memset(values, null);
            for (worker.inputs, 0..) |slot, index| {
                if (index < plan.dimension) values[@intCast(slot)] = .{ .state = space.coordinate(index) } else if (worker.layout.slots[@intCast(slot)] == plan.schema) values[@intCast(slot)] = .{ .input = space.coordinate(index - plan.dimension) };
            }
            const summary = input_slots[0..plan.basis.len];
            const dynamic = worker.inputs[plan.dimension..];
            for (block.instructions) |op| {
                const value = try extract.instruction(original, worker, op, values, plan.schema, &budget);
                if (value == null) {
                    var replacement = op;
                    const operands = try a.dupe(p.Id, op.operands);
                    for (operands) |*operand| operand.* = try remap(&builder, operand.*, values, &basis, summary, dynamic);
                    replacement.operands = operands;
                    try builder.operations.append(a, replacement);
                }
                values[@intCast(op.destination)] = value;
            }
            switch (block.terminator) {
                .return_value => |slot| out.terminator.return_value = try remap(&builder, slot, values, &basis, summary, dynamic),
                .branch => |branch| out.terminator.branch.condition = try remap(&builder, branch.condition, values, &basis, summary, dynamic),
                .call => |call| {
                    if (call.function == plan.worker) {
                        const arguments = try a.alloc(p.Id, input_slots.len);
                        for (plan.basis, arguments[0..plan.basis.len]) |row, *argument| {
                            var value: extract.Expression = .{};
                            for (call.arguments[0..plan.dimension], 0..) |slot, i| if (row & space.coordinate(i) != 0) {
                                value = value.xor(values[@intCast(slot)].?);
                            };
                            argument.* = try builder.expression(value, &basis, summary, dynamic);
                        }
                        for (call.arguments[plan.dimension..], arguments[plan.basis.len..]) |slot, *argument| argument.* = try remap(&builder, slot, values, &basis, summary, dynamic);
                        out.terminator.call.arguments = arguments;
                    } else {
                        const arguments = try a.dupe(p.Id, call.arguments);
                        for (arguments) |*argument| argument.* = try remap(&builder, argument.*, values, &basis, summary, dynamic);
                        out.terminator.call.arguments = arguments;
                    }
                },
                .jump => {},
                else => unreachable,
            }
        }
        out.instructions = try builder.operations.toOwnedSlice(a);
    }
    for (functions, layouts) |*function, layout| function.layout.slots = layout.items;
    var program = original;
    program.functions = functions;
    program.blocks = blocks;
    program.constructors = constructors;
    program.scopes.captures = captures;
    program.constants = try literals.toOwnedSlice(a);
    return .{ .arena = arena, .program = program, .constructor = constructor_id, .basis = try a.dupe(space.Row, plan.basis) };
}
