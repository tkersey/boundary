// Copyright (c) 2026 Boundary contributors. MIT license.
//! Direct lowering into function-local stable slots. No block-parameter program
//! is built. The returned construction owns admitted records and flow facts;
//! encoding checks the current records again before producing canonical BPI3.
const std = @import("std");
const data = @import("boundary_data_v2");
const p = data.program;
const ir = data.activation;
const ast = @import("ast.zig");
const source = @import("../source.zig");
const check = @import("check.zig");
const Error = source.Error || data.activation_flow.Error || data.activation_types.Error;
const scope = @import("binding_scope.zig");
const none = scope.empty;

pub const Construction = struct {
    arena: std.heap.ArenaAllocator,
    program: ir.Program,
    flow: data.activation_flow.Facts,

    pub fn encode(self: *const Construction, allocator: std.mem.Allocator, output: []u8) data.program_image.Error![]const u8 {
        return data.program_image.encode(allocator, self.program, output);
    }

    pub fn deinit(self: *Construction) void {
        self.flow.deinit();
        self.arena.deinit();
        self.* = undefined;
    }
};

/// Borrow source only during the call; own the resulting records independently.
/// No analysis scratch or authoring AST survives in the result arena. This
/// construction does not grant executable/trusted status.
pub fn lower(allocator: std.mem.Allocator, input: ast.Module) Error!Construction {
    return lowerObserved(allocator, input, .{});
}

pub fn lowerObserved(allocator: std.mem.Allocator, input: ast.Module, options: source.CompileOptions) Error!Construction {
    return lowerInternal(allocator, input, &.{}, false, options);
}

pub fn lowerComponent(allocator: std.mem.Allocator, input: ast.Module, imports: []const p.Id) Error!Construction {
    return lowerInternal(allocator, input, imports, true, .{});
}
fn lowerInternal(allocator: std.mem.Allocator, input: ast.Module, imports: []const p.Id, component: bool, options: source.CompileOptions) Error!Construction {
    if (options.diagnostic) |diagnostic| diagnostic.* = .{};
    errdefer |err| if (options.diagnostic) |diagnostic| {
        diagnostic.code = err;
    };
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const owned = input;
    // The source checker is independent of both lowering representations.
    // Only genuine captures are enumerated; intermediate free sets share roots.
    options.stage(.source_check);
    const facts = try check.analyzeComponent(a, owned, imports, options.diagnostic);
    const traits = try data.traits.derive(a, owned.schemas);
    options.stage(.lowering);
    var compiler: Compiler = .{
        .allocator = a,
        .source = owned,
        .facts = facts,
        .cacheable = try @import("value_cache.zig").derive(a, owned, traits),
        .uses = traits,
    };
    try compiler.constants.appendSlice(a, owned.constants);
    const functions = try a.alloc(ir.Function, owned.functions.len);
    for (functions, 0..) |*function, id| {
        if (options.diagnostic) |diagnostic| diagnostic.function = id;
        var lowering: Function = .{
            .compiler = &compiler,
            .id = id,
            .bindings = .{ .allocator = a, .name_count = owned.variables.len },
        };
        function.* = try lowering.lower();
    }
    const program: ir.Program = .{
        .roots = .{
            .entry = owned.entry,
            .result = owned.functions[@intCast(owned.entry)].result,
            .failure = owned.failure,
        },
        .schemas = owned.schemas,
        .constants = compiler.constants.items,
        .effects = owned.effects,
        .functions = functions,
        .blocks = compiler.blocks.items,
        .handlers = owned.handlers,
        .scopes = .{
            .captures = compiler.captures.items,
            .region_count = owned.region_count,
            .resources = owned.resources,
        },
        .constructors = compiler.constructors.items,
    };
    if (options.diagnostic) |diagnostic| diagnostic.function = null;
    options.stage(.source_copy);
    var output = std.heap.ArenaAllocator.init(allocator);
    errdefer output.deinit();
    const result = try source.own(ir.Program, output.allocator(), program);
    options.stage(.target_check);
    const flow = if (component) try data.activation_ownership.analyzeComponent(allocator, result, imports) else try data.activation_ownership.analyze(allocator, result);
    options.stage(.complete);
    return .{ .arena = output, .program = result, .flow = flow };
}

const ConstructorKey = struct { function: p.Id, schema: p.Id };
const Compiler = struct {
    allocator: std.mem.Allocator,
    source: ast.Module,
    facts: check.Facts,
    cacheable: []const bool,
    uses: data.traits.Facts,
    constants: std.ArrayList(p.Literal) = .empty,
    blocks: std.ArrayList(ir.Block) = .empty,
    captures: std.ArrayList(p.Capture) = .empty,
    constructors: std.ArrayList(p.Constructor) = .empty,
    constructor_ids: std.AutoHashMapUnmanaged(ConstructorKey, p.Id) = .empty,

    fn constructor(self: *Compiler, function: p.Id, schema: p.Id) Error!p.Id {
        const key: ConstructorKey = .{ .function = function, .schema = schema };
        if (self.constructor_ids.get(key)) |id| return id;
        const shape = self.source.schemas[@intCast(schema)];
        if (shape != .internal or shape.internal != .computation) return error.TypeMismatch;
        const free = self.facts.functions[@intCast(function)].items;
        const fields = try self.allocator.alloc(p.Id, free.len);
        for (fields, free) |*field, name| field.* = self.source.variables[@intCast(name)];
        const capture = self.captures.items.len;
        try self.captures.append(self.allocator, .{
            .fields = fields,
            .use = shape.internal.computation.use,
        });
        const id = self.constructors.items.len;
        try self.constructors.append(self.allocator, .{
            .function = function,
            .schema = schema,
            .capture = capture,
        });
        try self.constructor_ids.put(self.allocator, key, id);
        return id;
    }

    fn unit(self: *Compiler) Error!p.Id {
        for (self.constants.items, 0..) |literal, id| {
            if (self.source.schemas[@intCast(literal.schema)] == .unit) return id;
        }
        for (self.source.schemas, 0..) |shape, schema| {
            if (shape != .unit) continue;
            const id = self.constants.items.len;
            try self.constants.append(self.allocator, .{ .schema = schema, .bytes = &.{} });
            return id;
        }
        return error.TypeMismatch;
    }
};

const Continuation = struct { block: p.Id, destination: p.Id };
const Task = struct { block: p.Id, term: p.Id, environment: p.Id, next: ?Continuation, custody: p.Id };
const TaskKey = struct { term: p.Id, environment: p.Id, next: p.Id, destination: p.Id, custody: p.Id };

const Function = struct {
    compiler: *Compiler,
    id: p.Id,
    slots: std.ArrayList(p.Id) = .empty,
    custody: std.ArrayList(ir.CustodyScope) = .empty,
    bindings: scope.Scopes,
    tasks: std.ArrayList(Task) = .empty,
    memo: std.AutoHashMapUnmanaged(TaskKey, p.Id) = .empty,
    returned: ?Continuation = null,

    fn lower(self: *Function) Error!ir.Function {
        const compiler = self.compiler;
        const definition = compiler.source.functions[@intCast(self.id)];
        try self.custody.append(compiler.allocator, .{});
        const free = compiler.facts.functions[@intCast(self.id)].items;
        const inputs = try compiler.allocator.alloc(p.Id, free.len + definition.parameters.len);
        var environment: p.Id = none;
        for (free, 0..) |name, index| {
            environment = try self.bind(environment, name);
            inputs[index] = try self.resolve(environment, name);
        }
        for (definition.parameters, 0..) |name, index| {
            environment = try self.bind(environment, name);
            inputs[free.len + index] = try self.resolve(environment, name);
        }
        const entry = if (definition.body) |body| try self.schedule(body, environment, null, 0) else data.relocation.missing;
        while (self.tasks.pop()) |task| try self.emit(task);
        return .{
            .entry = entry,
            .inputs = inputs,
            .layout = .{ .slots = self.slots.items },
            .custody = self.custody.items,
            .result = definition.result,
            .effects = definition.effects,
            .regions = definition.regions,
        };
    }

    fn slot(self: *Function, schema: p.Id) Error!p.Id {
        const id = self.slots.items.len;
        try self.slots.append(self.compiler.allocator, schema);
        return id;
    }

    fn bind(self: *Function, parent: p.Id, name: p.Id) Error!p.Id {
        const destination = try self.slot(self.compiler.source.variables[@intCast(name)]);
        return self.bindings.bind(parent, name, destination);
    }

    fn bindingCustody(self: *Function, parent: p.Id, names: []const p.Id) Error!p.Id {
        for (names) |name| {
            const schema = self.compiler.source.variables[@intCast(name)];
            if (self.compiler.uses.copy[@intCast(schema)]) continue;
            const id = self.custody.items.len;
            try self.custody.append(self.compiler.allocator, .{ .parent = parent });
            return id;
        }
        return parent;
    }

    fn resolve(self: *const Function, environment: p.Id, name: p.Id) Error!p.Id {
        return self.bindings.resolve(environment, name);
    }

    fn reserveBlock(self: *Function) Error!p.Id {
        const id = self.compiler.blocks.items.len;
        try self.compiler.blocks.append(self.compiler.allocator, .{
            .function = self.id,
            .instructions = &.{},
            .terminator = .{ .return_value = none },
        });
        return id;
    }

    fn schedule(self: *Function, term_id: p.Id, env: p.Id, next: ?Continuation, custody: p.Id) Error!p.Id {
        const key: TaskKey = .{
            .term = term_id,
            .environment = env,
            .custody = custody,
            .next = if (next) |n| n.block else none,
            .destination = if (next) |n| n.destination else none,
        };
        if (self.memo.get(key)) |id| return id;
        const block = try self.reserveBlock();
        try self.memo.put(self.compiler.allocator, key, block);
        try self.tasks.append(self.compiler.allocator, .{
            .block = block,
            .term = term_id,
            .environment = env,
            .custody = custody,
            .next = next,
        });
        return block;
    }

    fn returnSite(self: *Function) Error!Continuation {
        if (self.returned) |next| return next;
        const result = self.compiler.source.functions[@intCast(self.id)].result;
        const destination = try self.slot(result);
        const block = try self.reserveBlock();
        self.compiler.blocks.items[@intCast(block)].terminator = .{ .return_value = destination };
        const next: Continuation = .{ .block = block, .destination = destination };
        self.returned = next;
        return next;
    }

    fn edge(self: *Function, next: Continuation, value: ir.Source) Error!ir.Edge {
        if (value == .slot and value.slot == next.destination) return .{ .block = next.block };
        const assignments = try self.compiler.allocator.alloc(ir.Assignment, 1);
        assignments[0] = .{ .destination = next.destination, .source = value };
        return .{ .block = next.block, .assignments = assignments };
    }

    fn emit(self: *Function, task: Task) Error!void {
        var block: Block = .{ .function = self, .environment = task.environment };
        const terminator = try self.term(&block, task);
        self.compiler.blocks.items[@intCast(task.block)] = .{
            .function = self.id,
            .custody = task.custody,
            .instructions = block.instructions.items,
            .terminator = terminator,
        };
    }

    fn term(self: *Function, block: *Block, task: Task) Error!ir.Terminator {
        const expression = self.compiler.source.terms[@intCast(task.term)];
        switch (expression) {
            .bind => |binding| {
                const env = try self.bind(task.environment, binding.variable);
                const custody = try self.bindingCustody(task.custody, &.{binding.variable});
                const rest = try self.schedule(binding.next, env, task.next, custody);
                const next: Continuation = .{
                    .block = rest,
                    .destination = try self.resolve(env, binding.variable),
                };
                return .{ .jump = .{
                    .block = try self.schedule(binding.value, task.environment, next, task.custody),
                } };
            },
            .value => |value| {
                const result = try block.value(value);
                return if (task.next) |next|
                    .{ .jump = try self.edge(next, .{ .slot = result }) }
                else
                    .{ .return_value = result };
            },
            .fail => |value| return .{ .fail = try block.value(value) },
            .yield_then => |body| return .{ .yield_value = .{
                .block = try self.schedule(body, task.environment, task.next, task.custody),
            } },
            .conditional => |branch| return .{ .branch = .{
                .condition = try block.value(branch.condition),
                .when_true = .{
                    .block = try self.schedule(branch.when_true, task.environment, task.next, task.custody),
                },
                .when_false = .{
                    .block = try self.schedule(branch.when_false, task.environment, task.next, task.custody),
                },
            } },
            .match_sum => return self.match(block, task),
            .unpack_product => return self.unpack(block, task),
            .dispose => return self.dispose(block, task),
            else => return self.control(block, expression, task.next),
        }
    }

    fn match(self: *Function, block: *Block, task: Task) Error!ir.Terminator {
        const selected = self.compiler.source.terms[@intCast(task.term)].match_sum;
        const value = try block.value(selected.value);
        const cases = try self.compiler.allocator.alloc(ir.Edge, selected.cases.len);
        for (cases, selected.cases) |*edge_value, case| {
            const env = try self.bind(task.environment, case.variable);
            const custody = try self.bindingCustody(task.custody, &.{case.variable});
            edge_value.* = try self.edge(.{
                .block = try self.schedule(case.body, env, task.next, custody),
                .destination = try self.resolve(env, case.variable),
            }, .returned);
        }
        return .{ .switch_variant = .{ .value = value, .cases = cases } };
    }

    fn unpack(self: *Function, block: *Block, task: Task) Error!ir.Terminator {
        const unpacking = self.compiler.source.terms[@intCast(task.term)].unpack_product;
        const value = try block.value(unpacking.value);
        const destinations = try self.compiler.allocator.alloc(p.Id, unpacking.variables.len);
        var env = task.environment;
        for (destinations, unpacking.variables) |*destination, name| {
            env = try self.bind(env, name);
            destination.* = try self.resolve(env, name);
        }
        const custody = try self.bindingCustody(task.custody, unpacking.variables);
        return .{ .unpack_product = .{
            .value = value,
            .destinations = destinations,
            .next = .{ .block = try self.schedule(unpacking.body, env, task.next, custody) },
        } };
    }

    fn dispose(self: *Function, block: *Block, task: Task) Error!ir.Terminator {
        const owned = try block.value(self.compiler.source.terms[@intCast(task.term)].dispose);
        const next = task.next orelse try self.returnSite();
        var adapter: Block = .{ .function = self, .environment = task.environment };
        const literal = try self.compiler.unit();
        const schema = self.compiler.constants.items[@intCast(literal)].schema;
        const unit = try adapter.instruction(schema, .{
            .opcode = .constant,
            .immediate = literal,
        });
        const id = try self.reserveBlock();
        self.compiler.blocks.items[@intCast(id)] = .{
            .function = self.id,
            .custody = task.custody,
            .instructions = adapter.instructions.items,
            .terminator = .{ .jump = try self.edge(next, .{ .slot = unit }) },
        };
        return .{ .dispose = .{ .owned = owned, .next = .{ .block = id } } };
    }

    fn control(
        self: *Function,
        block: *Block,
        expression: ast.Term,
        continuation: ?Continuation,
    ) Error!ir.Terminator {
        const next = try self.edge(continuation orelse try self.returnSite(), .returned);
        return switch (expression) {
            .call => |call| .{ .call = .{
                .function = call.function,
                .arguments = try block.callArguments(call.function, call.arguments),
                .next = next,
            } },
            .apply => |apply| .{ .apply = .{
                .computation = try block.value(apply.computation),
                .arguments = try block.values(apply.arguments),
                .next = next,
            } },
            .perform => |perform| .{ .perform = .{
                .effect = perform.effect,
                .capability = try block.optional(perform.capability),
                .payload = try block.value(perform.payload),
                .bodies = try block.values(perform.bodies),
                .use_site_capabilities = try block.values(perform.use_site_capabilities),
                .next = next,
            } },
            .handle => |handle| .{ .handle = .{
                .handler = handle.handler,
                .body = try block.value(handle.body),
                .arguments = try block.values(handle.arguments),
                .state = try block.values(handle.state),
                .next = next,
            } },
            else => return self.retainedControl(block, expression, next),
        };
    }

    fn retainedControl(
        self: *Function,
        block: *Block,
        expression: ast.Term,
        next: ir.Edge,
    ) Error!ir.Terminator {
        _ = self;
        return switch (expression) {
            .resume_value => |resume_value| .{ .resume_value = .{
                .resumption = try block.value(resume_value.resumption),
                .argument = try block.value(resume_value.argument),
                .next = next,
            } },
            .resume_with => |resume_with| .{ .resume_with = .{
                .resumption = try block.value(resume_with.resumption),
                .argument = try block.value(resume_with.argument),
                .handler = resume_with.handler,
                .state = try block.values(resume_with.state),
                .next = next,
            } },
            .resume_computation => |resume_computation| .{ .resume_computation = .{
                .resumption = try block.value(resume_computation.resumption),
                .computation = try block.value(resume_computation.computation),
                .next = next,
            } },
            .protect => |protect| .{ .protect = .{
                .body = try block.value(protect.body),
                .cleanup = try block.value(protect.cleanup),
                .arguments = try block.values(protect.arguments),
                .resource = try block.optional(protect.resource),
                .loan_region = protect.loan_region,
                .next = next,
            } },
            .with_region => |region| .{ .with_region = .{
                .region = region.region,
                .body = try block.value(region.body),
                .arguments = try block.values(region.arguments),
                .next = next,
            } },
            else => return error.InvalidSource,
        };
    }
};

const Block = struct {
    function: *Function,
    environment: p.Id,
    instructions: std.ArrayList(ir.Instruction) = .empty,
    computed: std.AutoHashMapUnmanaged(p.Id, p.Id) = .empty,

    const Operation = struct {
        opcode: p.Opcode,
        operands: []const p.Id = &.{},
        immediate: p.Id = 0,
        failures: []const p.InstructionFailure = &.{},
    };

    fn instruction(self: *Block, schema: p.Id, operation: Operation) Error!p.Id {
        const destination = try self.function.slot(schema);
        try self.instructions.append(self.function.compiler.allocator, .{
            .destination = destination,
            .opcode = operation.opcode,
            .operands = operation.operands,
            .immediate = operation.immediate,
            .failures = operation.failures,
        });
        return destination;
    }

    const ValueTask = struct { id: p.Id, operands: []p.Id, next: usize = 0 };
    fn value(self: *Block, id: p.Id) Error!p.Id {
        if (self.computed.get(id)) |slot| return slot;
        const compiler = self.function.compiler;
        var tasks: std.ArrayList(ValueTask) = .empty;
        defer tasks.deinit(compiler.allocator);
        try tasks.append(compiler.allocator, try self.valueTask(id));
        while (tasks.items.len != 0) {
            const task = &tasks.items[tasks.items.len - 1];
            const expression = compiler.source.values[@intCast(task.id)].expression;
            if (expression == .primitive and task.next < task.operands.len) {
                const child = expression.primitive.operands[task.next];
                if (self.computed.get(child)) |slot| {
                    task.operands[task.next] = slot;
                    task.next += 1;
                } else try tasks.append(compiler.allocator, try self.valueTask(child));
                continue;
            }
            const result = try self.emitValue(task.id, task.operands);
            if (compiler.cacheable[@intCast(task.id)])
                try self.computed.put(compiler.allocator, task.id, result);
            _ = tasks.pop();
            if (tasks.items.len == 0) return result;
            const parent = &tasks.items[tasks.items.len - 1];
            parent.operands[parent.next] = result;
            parent.next += 1;
        }
        return error.InvalidSource;
    }

    fn valueTask(self: *Block, id: p.Id) Error!ValueTask {
        const compiler = self.function.compiler;
        const expression = compiler.source.values[@intCast(id)].expression;
        const count = if (expression == .primitive) expression.primitive.operands.len else 0;
        return .{ .id = id, .operands = try compiler.allocator.alloc(p.Id, count) };
    }

    fn emitValue(self: *Block, id: p.Id, operands: []const p.Id) Error!p.Id {
        const compiler = self.function.compiler;
        const definition = compiler.source.values[@intCast(id)];
        const operation: Operation = switch (definition.expression) {
            .variable => |name| return self.function.resolve(self.environment, name),
            .literal => |literal| .{
                .opcode = .constant,
                .immediate = literal,
            },
            .primitive => |primitive| .{
                .opcode = primitive.opcode,
                .operands = operands,
                .immediate = primitive.immediate,
                .failures = primitive.failures,
            },
            .lambda => |function| .{
                .opcode = .computation,
                .operands = try self.captures(function),
                .immediate = try compiler.constructor(function, definition.schema),
            },
        };
        return self.instruction(definition.schema, operation);
    }

    fn captures(self: *Block, function: p.Id) Error![]const p.Id {
        const compiler = self.function.compiler;
        const free = compiler.facts.functions[@intCast(function)].items;
        const result = try compiler.allocator.alloc(p.Id, free.len);
        for (result, free) |*slot, name| {
            slot.* = try self.function.resolve(self.environment, name);
        }
        return result;
    }

    fn callArguments(self: *Block, function: p.Id, supplied: []const p.Id) Error![]const p.Id {
        const captured = try self.captures(function);
        const arguments = try self.values(supplied);
        return std.mem.concat(self.function.compiler.allocator, p.Id, &.{ captured, arguments });
    }

    fn values(self: *Block, supplied: []const p.Id) Error![]const p.Id {
        const result = try self.function.compiler.allocator.alloc(p.Id, supplied.len);
        for (result, supplied) |*slot, id| slot.* = try self.value(id);
        return result;
    }

    fn optional(self: *Block, supplied: ?p.Id) Error!?p.Id {
        return if (supplied) |id| try self.value(id) else null;
    }
};
