// Copyright (c) 2026 Boundary contributors. MIT license.
//! Closure conversion and continuation lowering of checked higher-order terms.
const std = @import("std");
const data = @import("boundary_data_v2");
const p = data.program;
const ast = @import("ast.zig");
const check = @import("check.zig");
const custody = @import("custody.zig");
const source_api = @import("../source.zig");
const Error = source_api.Error;
pub const Compiled = @import("compiled.zig").Compiled;
const Block = struct { id: p.Id, variables: []const p.Id };
const Continuation = struct { block: Block, result: p.Id };
const ConstructorKey = struct { function: p.Id, schema: p.Id };
const BlockKey = struct {
    expression: p.Id,
    next: p.Id,
    result: p.Id,
    bindings: []const p.Id,
    ordering: []const p.Id,
    depth: usize,
    depths: []const usize,
};
const RetainedKey = struct { block: p.Id, schema: p.Id, position: usize, depth: usize };
const none = std.math.maxInt(p.Id);
// Resolve source names within their lexical scope. Cache the live bindings and
// their owner order; unrelated scalar bindings do not split shared code.
const Environment = struct {
    names: []const p.Id = &.{},
    bindings: []const p.Id = &.{},
    ordering: []const p.Id = &.{}, // Non-Drop owners, inner scope before outer.
    depths: []const usize = &.{},
    depth: usize = 0,

    fn ownerDepth(self: Environment, binding: p.Id) usize {
        const index = std.mem.indexOfScalar(p.Id, self.ordering, binding) orelse return 0;
        return self.depths[index];
    }

    fn resolve(self: Environment, name: p.Id) Error!p.Id {
        const index = std.mem.indexOfScalar(p.Id, self.names, name) orelse
            return error.UnboundVariable;
        return self.bindings[index];
    }
    fn enter(
        self: Environment,
        compiler: *Compiler,
        names: []const p.Id,
        bound: Environment,
    ) Error!Environment {
        const allocator = compiler.allocator;
        std.debug.assert(self.names.len == self.bindings.len);
        std.debug.assert(bound.names.len == bound.bindings.len);
        if (bound.names.len == 0 and std.mem.eql(p.Id, names, self.names)) return self;
        const bindings = try allocator.alloc(p.Id, names.len);
        for (bindings, names) |*binding, name| {
            binding.* = if (std.mem.indexOfScalar(p.Id, bound.names, name)) |index|
                bound.bindings[index]
            else
                try self.resolve(name);
        }
        var ordering: check.Set = .empty;
        var depths: std.ArrayList(usize) = .empty;
        var owns_binding = false;
        for (bound.bindings) |binding| {
            const schema = compiler.variables.items[@intCast(binding)];
            owns_binding = owns_binding or !compiler.traits.copy[@intCast(schema)];
            if (!compiler.traits.drop[@intCast(schema)]) {
                try ordering.append(allocator, binding);
                try depths.append(allocator, self.depth + 1);
            }
        }
        // An affine value still creates an owned scope even when it may be dropped.
        const depth = self.depth + @intFromBool(owns_binding);
        for (self.ordering) |binding| {
            if (std.mem.indexOfScalar(p.Id, ordering.items, binding) == null) {
                try ordering.append(allocator, binding);
                try depths.append(allocator, self.ownerDepth(binding));
            }
        }
        return .{ .names = names, .bindings = bindings, .ordering = ordering.items, .depths = depths.items, .depth = depth };
    }
};
const BlockContext = struct {
    pub fn hash(_: BlockContext, key: BlockKey) u64 {
        var result = std.hash.Wyhash.init(0);
        std.hash.autoHash(&result, key.expression);
        std.hash.autoHash(&result, key.next);
        std.hash.autoHash(&result, key.result);
        for (key.bindings) |binding| std.hash.autoHash(&result, binding);
        for (key.ordering) |binding| std.hash.autoHash(&result, binding);
        std.hash.autoHash(&result, key.depth);
        for (key.depths) |depth| std.hash.autoHash(&result, depth);
        return result.final();
    }
    pub fn eql(_: BlockContext, left: BlockKey, right: BlockKey) bool {
        return left.expression == right.expression and left.next == right.next and
            left.result == right.result and std.mem.eql(p.Id, left.bindings, right.bindings) and
            std.mem.eql(p.Id, left.ordering, right.ordering) and left.depth == right.depth and
            std.mem.eql(usize, left.depths, right.depths);
    }
};
const Request = struct {
    id: p.Id,
    next: ?Continuation,
    environment: Environment,
    ordering: []const p.Id,
    depths: []const usize,
    child: usize = 0,
    fn key(self: Request) BlockKey {
        return .{
            .expression = self.id,
            .next = if (self.next) |continuation| continuation.block.id else none,
            .result = if (self.next) |continuation| continuation.result else none,
            .bindings = self.environment.bindings,
            .ordering = self.ordering,
            .depth = self.environment.depth,
            .depths = self.depths,
        };
    }
    fn descend(
        self: Request,
        compiler: *Compiler,
        id: p.Id,
        next: ?Continuation,
        bound: Environment,
    ) Error!Request {
        const environment = try self.environment.enter(
            compiler,
            compiler.facts.terms[@intCast(id)].items,
            bound,
        );
        const ordering = try liveOrder(compiler, environment, next);
        return .{
            .id = id,
            .next = next,
            .environment = environment,
            .ordering = ordering,
            .depths = try ownerDepths(compiler.allocator, environment, ordering),
        };
    }
    fn under(self: Request, compiler: *Compiler, id: p.Id, bound: Environment) Error!Request {
        return self.descend(compiler, id, self.next, bound);
    }
    fn liveOrder(compiler: *Compiler, environment: Environment, next: ?Continuation) Error![]const p.Id {
        const allocator = compiler.allocator;
        var live: check.Set = .empty;
        try live.appendSlice(allocator, environment.bindings);
        if (next) |continuation| _ = try check.merge(allocator, &live, continuation.block.variables, &.{continuation.result});
        const ordered = try allocator.dupe(p.Id, live.items);
        std.mem.sort(p.Id, ordered, {}, std.sort.asc(p.Id));
        var index: usize = 0;
        for (environment.ordering) |variable| {
            if (std.mem.indexOfScalar(p.Id, live.items, variable) == null) continue;
            while (index < ordered.len and compiler.traits.drop[@intCast(compiler.variables.items[@intCast(ordered[index])])]) : (index += 1) {}
            std.debug.assert(index < ordered.len);
            ordered[index] = variable;
            index += 1;
        }
        for (ordered[index..]) |variable| std.debug.assert(compiler.traits.drop[@intCast(compiler.variables.items[@intCast(variable)])]);
        return ordered;
    }
    fn ownerDepths(a: std.mem.Allocator, env: Environment, variables: []const p.Id) Error![]usize {
        const depths = try a.alloc(usize, variables.len);
        for (depths, variables) |*depth, variable| depth.* = env.ownerDepth(variable);
        return depths;
    }
};

pub fn lower(allocator: std.mem.Allocator, source: ast.Module) Error!Compiled {
    return lowerObserved(allocator, source, .{});
}

pub fn lowerObserved(allocator: std.mem.Allocator, source: ast.Module, options: source_api.CompileOptions) Error!Compiled {
    if (options.diagnostic) |d| d.* = .{};
    errdefer |err| if (options.diagnostic) |d| {
        d.code = err;
    };
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const storage = arena.allocator();
    options.stage(.source_copy);
    const owned = try source_api.own(ast.Module, storage, source);
    options.stage(.source_check);
    const source_facts = try check.analyzeDiagnosed(storage, owned, options.diagnostic);
    options.stage(.lowering);
    const use_facts = try data.traits.derive(storage, owned.schemas);
    var compiler: Compiler = .{ .allocator = storage, .source = owned, .facts = source_facts, .cacheable = try cacheableValues(storage, owned, use_facts), .traits = use_facts };
    try compiler.prepare();
    const functions = try storage.alloc(p.Function, owned.functions.len);
    for (owned.functions, 0..) |function, id| {
        if (options.diagnostic) |d| {
            d.function = id;
            d.term = function.body;
        }
        var code: Function = .{ .compiler = &compiler, .id = id };
        const body = try code.expression(function.body.?, null);
        var parameters: check.Set = .empty;
        try parameters.appendSlice(storage, compiler.facts.functions[id].items);
        try parameters.appendSlice(storage, function.parameters);
        const entry = if (std.mem.eql(p.Id, parameters.items, body.variables)) body else blk: {
            var block = try code.start(parameters.items);
            break :blk try block.finish(.{ .jump = try block.edge(body, null, null) });
        };
        functions[id] = .{ .entry = entry.id, .parameters = try compiler.types(parameters.items), .result = function.result, .effects = function.effects, .regions = function.regions };
    }
    const program: p.Program = .{
        .roots = .{ .entry = owned.entry, .result = owned.functions[@intCast(owned.entry)].result, .failure = owned.failure },
        .schemas = owned.schemas,
        .constants = compiler.constants.items,
        .effects = owned.effects,
        .functions = functions,
        .blocks = compiler.blocks.items,
        .handlers = owned.handlers,
        .scopes = .{ .captures = compiler.captures.items, .region_count = owned.region_count, .resources = owned.resources },
        .constructors = compiler.constructors.items,
    };
    // The independent target checker closes effects, capture bounds and linear
    // transfer on the actual emitted call edges, including recursive functions.
    options.stage(.target_check);
    if (options.diagnostic) |d| {
        d.function = null;
        d.term = null;
    }
    data.admission.programDiagnosed(storage, program, if (options.diagnostic) |d| &d.target else null) catch |err| {
        if (options.diagnostic) |d| {
            d.function = d.target.function;
            if (d.target.capture) |capture| {
                for (program.constructors) |constructor| if (constructor.capture == capture) {
                    d.function = constructor.function;
                    if (d.target.field) |field| {
                        const free = compiler.facts.functions[@intCast(constructor.function)].items;
                        if (field < free.len) d.variable = free[@intCast(field)];
                    }
                    break;
                };
            }
        }
        // Keep the return union explicit when errdefer captures the error.
        return @as(Error!Compiled, err);
    };
    // Order only an admitted graph. Slot elimination must never hide an illegal
    // use; canonicalization independently admits the reordered result below.
    try options.observeProgram(.lowered, program);
    const ordered = try custody.normalize(storage, program, compiler.custody_blocks, use_facts);
    try options.observeProgram(.custody, ordered);
    options.stage(.direct_optimization);
    const optimized = try @import("direct.zig").optimize(storage, ordered);
    try options.observeProgram(.direct, optimized);
    options.stage(.canonicalization);
    var canonical = try data.canonical.normalize(allocator, optimized);
    errdefer canonical.deinit();
    try options.observeProgram(.canonical, canonical.program);
    options.stage(.complete);
    if (options.diagnostic) |d| d.* = .{ .phase = .complete };
    return .{ .arena = canonical.arena, .program = canonical.program };
}

const Compiler = struct {
    allocator: std.mem.Allocator,
    source: ast.Module,
    facts: check.Facts,
    cacheable: []bool,
    traits: data.traits.Facts,
    variables: check.Set = .empty,
    binders: []const []const p.Id = &.{},
    constants: std.ArrayList(p.Literal) = .empty,
    blocks: std.ArrayList(p.Block) = .empty,
    scoped_parameters: @import("retain.zig").Scopes = .empty,
    custody_blocks: custody.Blocks = .empty,
    captures: std.ArrayList(p.Capture) = .empty,
    constructors: std.ArrayList(p.Constructor) = .empty,
    constructor_ids: std.AutoHashMapUnmanaged(ConstructorKey, p.Id) = .empty,

    fn prepare(self: *Compiler) Error!void {
        try self.variables.appendSlice(self.allocator, self.source.variables);
        try self.constants.appendSlice(self.allocator, self.source.constants);
        // The checked term DAG cannot nest a binder inside itself. One fresh
        // identity per binder site therefore separates all simultaneous scopes.
        const binders = try self.allocator.alloc([]const p.Id, self.source.terms.len);
        for (self.source.terms, binders) |term, *ids| ids.* = switch (term) {
            .bind => |binding| try self.fresh(&.{binding.variable}),
            .unpack_product => |unpack| try self.fresh(unpack.variables),
            .match_sum => |match| blk: {
                const names = try self.allocator.alloc(p.Id, match.cases.len);
                for (names, match.cases) |*name, case| name.* = case.variable;
                break :blk try self.fresh(names);
            },
            else => &.{},
        };
        self.binders = binders;
    }
    fn fresh(self: *Compiler, names: []const p.Id) Error![]const p.Id {
        const result = try self.allocator.alloc(p.Id, names.len);
        for (result, names) |*binding, name| {
            binding.* = self.variables.items.len;
            try self.variables.append(self.allocator, self.source.variables[@intCast(name)]);
        }
        return result;
    }
    fn types(self: *Compiler, variables: []const p.Id) Error![]const p.Id {
        const result = try self.allocator.alloc(p.Id, variables.len);
        for (result, variables) |*schema, variable| {
            if (variable >= self.variables.items.len) return error.UnboundVariable;
            schema.* = self.variables.items[@intCast(variable)];
        }
        return result;
    }
    fn constructor(self: *Compiler, function: p.Id, schema: p.Id) Error!p.Id {
        const key: ConstructorKey = .{ .function = function, .schema = schema };
        if (self.constructor_ids.get(key)) |id| return id;
        const shape = self.source.schemas[@intCast(schema)];
        if (shape != .internal or shape.internal != .computation) return error.TypeMismatch;
        const capture_id = self.captures.items.len;
        const fields = try self.types(self.facts.functions[@intCast(function)].items);
        try self.captures.append(self.allocator, .{ .fields = fields, .use = shape.internal.computation.use });
        const id = self.constructors.items.len;
        try self.constructors.append(self.allocator, .{ .function = function, .schema = schema, .capture = capture_id });
        try self.constructor_ids.put(self.allocator, key, id);
        return id;
    }
    fn unit(self: *Compiler) Error!p.Id {
        var schema_id: ?p.Id = null;
        for (self.source.schemas, 0..) |schema, id| if (schema == .unit) {
            schema_id = id;
            break;
        };
        const schema = schema_id orelse return error.TypeMismatch;
        for (self.constants.items, 0..) |literal, id| if (literal.schema == schema and literal.bytes.len == 0) return id;
        const id = self.constants.items.len;
        try self.constants.append(self.allocator, .{ .schema = schema, .bytes = &.{} });
        return id;
    }
};

const Function = struct {
    compiler: *Compiler,
    id: p.Id,
    memo: std.HashMapUnmanaged(BlockKey, Block, BlockContext, 80) = .empty,
    returns: ?Continuation = null,
    retained: std.AutoHashMapUnmanaged(RetainedKey, p.Id) = .empty,

    fn retainBlock(self: *Function, block: p.Id, schema: p.Id, position: usize, depth: usize) Error!p.Id {
        const key: RetainedKey = .{
            .block = block,
            .schema = schema,
            .position = position,
            .depth = depth,
        };
        if (self.retained.get(key)) |present| return present;
        const compiler = self.compiler;
        const retained = try @import("retain.zig").throughGraph(
            compiler.allocator,
            &compiler.blocks,
            &compiler.scoped_parameters,
            &compiler.custody_blocks,
            block,
            schema,
            position,
            depth,
        );
        try self.retained.put(compiler.allocator, key, retained);
        return retained;
    }
    fn bindingRest(self: *Function, request: Request) Error!Block {
        const compiler = self.compiler;
        const binding = compiler.source.terms[@intCast(request.id)].bind;
        const ids = compiler.binders[@intCast(request.id)];
        const bound: Environment = .{ .names = &.{binding.variable}, .bindings = ids };
        return self.resolved(try request.under(compiler, binding.next, bound));
    }

    fn start(self: *Function, variables: []const p.Id) Error!BuildBlock {
        return .{ .function = self, .variables = try self.compiler.allocator.dupe(p.Id, variables) };
    }
    fn returnContinuation(self: *Function) Error!Continuation {
        if (self.returns) |returns| return returns;
        const compiler = self.compiler;
        const variable = compiler.variables.items.len;
        try compiler.variables.append(compiler.allocator, compiler.source.functions[@intCast(self.id)].result);
        var block = try self.start(&.{variable});
        const result: Continuation = .{ .block = try block.finish(.{ .return_value = 0 }), .result = variable };
        self.returns = result;
        return result;
    }
    fn expression(self: *Function, id: p.Id, next: ?Continuation) Error!Block {
        var pending: std.ArrayList(Request) = .empty;
        defer pending.deinit(self.compiler.allocator);
        const free = self.compiler.facts.terms[@intCast(id)].items;
        var order: check.Set = .empty;
        for (self.compiler.facts.functions[@intCast(self.id)].items) |variable| {
            if (!self.compiler.traits.drop[@intCast(self.compiler.variables.items[@intCast(variable)])])
                try order.append(self.compiler.allocator, variable);
        }
        for (self.compiler.source.functions[@intCast(self.id)].parameters) |variable| {
            if (!self.compiler.traits.drop[@intCast(self.compiler.variables.items[@intCast(variable)])])
                try order.append(self.compiler.allocator, variable);
        }
        const depths = try self.compiler.allocator.alloc(usize, order.items.len);
        @memset(depths, 0);
        const environment: Environment = .{
            .names = free,
            .bindings = free,
            .ordering = order.items,
            .depths = depths,
        };
        const ordering = try Request.liveOrder(self.compiler, environment, next);
        const root: Request = .{
            .id = id,
            .next = next,
            .environment = environment,
            .ordering = ordering,
            .depths = try Request.ownerDepths(self.compiler.allocator, environment, ordering),
        };
        try pending.append(self.compiler.allocator, root);
        while (pending.items.len != 0) {
            const request = &pending.items[pending.items.len - 1];
            if (self.memo.contains(request.key())) {
                _ = pending.pop();
                continue;
            }
            if (try self.dependency(request)) |child| {
                try pending.append(self.compiler.allocator, child);
                continue;
            }
            const result = try self.lowerExpression(request.*);
            try self.memo.put(self.compiler.allocator, request.key(), result);
            _ = pending.pop();
        }
        return self.memo.get(root.key()).?;
    }
    fn dependency(self: *Function, request: *Request) Error!?Request {
        const compiler = self.compiler;
        const term = compiler.source.terms[@intCast(request.id)];
        const ids = compiler.binders[@intCast(request.id)];
        return switch (term) {
            .bind => |binding| blk: {
                const bound: Environment = .{ .names = &.{binding.variable}, .bindings = ids };
                const rest = try request.under(compiler, binding.next, bound);
                if (self.missing(rest)) |required| break :blk required;
                const block = try self.bindingRest(request.*);
                const next: Continuation = .{ .block = block, .result = ids[0] };
                break :blk self.missing(try request.descend(compiler, binding.value, next, .{}));
            },
            .yield_then => |body| self.missing(try request.under(compiler, body, .{})),
            .conditional => |branch| blk: {
                const left = try request.under(compiler, branch.when_true, .{});
                if (self.missing(left)) |required| break :blk required;
                break :blk self.missing(try request.under(compiler, branch.when_false, .{}));
            },
            .match_sum => |selected| blk: {
                while (request.child < selected.cases.len) : (request.child += 1) {
                    const case = selected.cases[request.child];
                    const bound: Environment = .{
                        .names = &.{case.variable},
                        .bindings = ids[request.child..][0..1],
                    };
                    const child = try request.under(compiler, case.body, bound);
                    if (self.missing(child)) |required| break :blk required;
                }
                break :blk null;
            },
            .unpack_product => |unpack| self.missing(try request.under(compiler, unpack.body, .{
                .names = unpack.variables,
                .bindings = ids,
            })),
            else => null,
        };
    }
    fn missing(self: *Function, request: Request) ?Request {
        return if (self.memo.contains(request.key())) null else request;
    }
    fn resolved(self: *Function, request: Request) Error!Block {
        return self.memo.get(request.key()) orelse error.InvalidSource;
    }
    fn lowerExpression(self: *Function, request: Request) Error!Block {
        const compiler = self.compiler;
        const term = compiler.source.terms[@intCast(request.id)];
        const next = request.next;
        if (term == .bind) {
            const rest = try self.bindingRest(request);
            const result = compiler.binders[@intCast(request.id)][0];
            const continuation: Continuation = .{ .block = rest, .result = result };
            return self.resolved(try request.descend(compiler, term.bind.value, continuation, .{}));
        }
        if (term == .yield_then) {
            const rest = try self.resolved(try request.under(compiler, term.yield_then, .{}));
            var block = try self.start(rest.variables);
            block.environment = request.environment;
            return block.finish(.{ .yield_value = try block.edge(rest, null, null) });
        }
        var block = try self.start(request.ordering);
        block.environment = request.environment;
        switch (term) {
            .value => |value| {
                const slot = try block.value(value);
                return block.finish(if (next) |continuation| .{ .jump = try block.edge(continuation.block, continuation.result, slot) } else .{ .return_value = slot });
            },
            .fail => |value| return block.finish(.{ .fail = try block.value(value) }),
            .conditional => return self.lowerConditional(&block, request),
            .match_sum => return self.lowerMatch(&block, request),
            .unpack_product => return self.lowerUnpack(&block, request),
            .dispose => |value| return self.lowerDispose(&block, value, next),
            else => {},
        }
        const continuation = next orelse try self.returnContinuation();
        const edge = try block.edge(continuation.block, continuation.result, null);
        const terminator: p.Terminator = switch (term) {
            .call => |call| blk: {
                const free = compiler.facts.functions[@intCast(call.function)].items;
                const arguments = try compiler.allocator.alloc(p.Id, free.len + call.arguments.len);
                for (arguments[0..free.len], free) |*argument, variable| {
                    argument.* = try block.namedVariable(variable);
                }
                for (arguments[free.len..], call.arguments) |*argument, value| argument.* = try block.value(value);
                break :blk .{ .call = .{ .function = call.function, .arguments = arguments, .next = edge } };
            },
            .apply => |apply| .{ .apply = .{ .computation = try block.value(apply.computation), .arguments = try block.values(apply.arguments), .next = edge } },
            .perform => |perform| .{ .perform = .{ .effect = perform.effect, .capability = if (perform.capability) |value| try block.value(value) else null, .payload = try block.value(perform.payload), .bodies = try block.values(perform.bodies), .use_site_capabilities = try block.values(perform.use_site_capabilities), .next = edge } },
            .handle => |handle| .{ .handle = .{ .handler = handle.handler, .body = try block.value(handle.body), .arguments = try block.values(handle.arguments), .state = try block.values(handle.state), .next = edge } },
            .resume_value => |resuming| .{ .resume_value = .{ .resumption = try block.value(resuming.resumption), .argument = try block.value(resuming.argument), .next = edge } },
            .resume_with => |resuming| .{ .resume_with = .{ .resumption = try block.value(resuming.resumption), .argument = try block.value(resuming.argument), .handler = resuming.handler, .state = try block.values(resuming.state), .next = edge } },
            .resume_computation => |resuming| .{ .resume_computation = .{ .resumption = try block.value(resuming.resumption), .computation = try block.value(resuming.computation), .next = edge } },
            .protect => |protection| .{ .protect = .{ .body = try block.value(protection.body), .cleanup = try block.value(protection.cleanup), .arguments = try block.values(protection.arguments), .resource = if (protection.resource) |resource| try block.value(resource) else null, .loan_region = protection.loan_region, .next = edge } },
            .with_region => |region| .{ .with_region = .{ .region = region.region, .body = try block.value(region.body), .arguments = try block.values(region.arguments), .next = edge } },
            else => return error.InvalidSource,
        };
        return block.finish(terminator);
    }

    fn lowerConditional(self: *Function, block: *BuildBlock, request: Request) Error!Block {
        const compiler = self.compiler;
        const conditional = compiler.source.terms[@intCast(request.id)].conditional;
        const left = try self.resolved(try request.under(compiler, conditional.when_true, .{}));
        const right = try self.resolved(try request.under(compiler, conditional.when_false, .{}));
        const condition = try block.value(conditional.condition);
        return block.finish(.{ .branch = .{
            .condition = condition,
            .when_true = try block.edge(left, null, null),
            .when_false = try block.edge(right, null, null),
        } });
    }
    fn lowerMatch(self: *Function, block: *BuildBlock, request: Request) Error!Block {
        const compiler = self.compiler;
        const match = compiler.source.terms[@intCast(request.id)].match_sum;
        const ids = compiler.binders[@intCast(request.id)];
        const cases = try compiler.allocator.alloc(p.Edge, match.cases.len);
        const value = try block.value(match.value);
        for (cases, match.cases, ids) |*edge, case, binding| {
            const bound: Environment = .{ .names = &.{case.variable}, .bindings = &.{binding} };
            const target = try self.resolved(try request.under(compiler, case.body, bound));
            edge.* = try block.edge(target, binding, null);
        }
        return block.finish(.{ .switch_variant = .{
            .value = value,
            .cases = cases,
        } });
    }
    fn lowerUnpack(self: *Function, block: *BuildBlock, request: Request) Error!Block {
        const compiler = self.compiler;
        const unpack = compiler.source.terms[@intCast(request.id)].unpack_product;
        const ids = compiler.binders[@intCast(request.id)];
        const bound: Environment = .{ .names = unpack.variables, .bindings = ids };
        const rest = try self.resolved(try request.under(compiler, unpack.body, bound));
        var variables: check.Set = .empty;
        try variables.appendSlice(compiler.allocator, ids);
        _ = try check.merge(compiler.allocator, &variables, rest.variables, ids);
        var adapter = try self.start(variables.items);
        adapter.environment = (try request.under(compiler, unpack.body, bound)).environment;
        const target = try adapter.finish(.{ .jump = try adapter.edge(rest, null, null) });
        const arguments = try compiler.allocator.alloc(p.Id, variables.items.len - ids.len);
        for (arguments, variables.items[ids.len..]) |*argument, variable| {
            argument.* = try block.variable(variable);
        }
        return block.finish(.{ .unpack_product = .{
            .value = try block.value(unpack.value),
            .block = target.id,
            .arguments = arguments,
        } });
    }
    fn lowerDispose(
        self: *Function,
        block: *BuildBlock,
        value: p.Id,
        next: ?Continuation,
    ) Error!Block {
        const compiler = self.compiler;
        var variables: check.Set = .empty;
        if (next) |continuation| _ = try check.merge(
            compiler.allocator,
            &variables,
            continuation.block.variables,
            &.{continuation.result},
        );
        var adapter = try self.start(variables.items);
        adapter.environment = block.environment;
        const literal = try compiler.unit();
        const unit_slot = try adapter.instruction(.{
            .opcode = .constant,
            .result_type = compiler.constants.items[@intCast(literal)].schema,
            .immediate = literal,
        });
        const target = try adapter.finish(if (next) |continuation| .{
            .jump = try adapter.edge(continuation.block, continuation.result, unit_slot),
        } else .{ .return_value = unit_slot });
        return block.finish(.{ .dispose = .{
            .owned = try block.value(value),
            .next = try block.edge(target, null, null),
        } });
    }
};

const BuildBlock = struct {
    function: *Function,
    variables: []const p.Id,
    environment: Environment = .{},
    instructions: std.ArrayList(p.Instruction) = .empty,
    computed: std.AutoHashMapUnmanaged(p.Id, p.Id) = .empty,
    const ValueTask = struct { id: p.Id, operands: []p.Id, next: usize = 0 };

    fn variable(self: BuildBlock, id: p.Id) Error!p.Id {
        return std.mem.indexOfScalar(p.Id, self.variables, id) orelse error.UnboundVariable;
    }
    fn namedVariable(self: BuildBlock, name: p.Id) Error!p.Id {
        return self.variable(try self.environment.resolve(name));
    }
    fn instruction(self: *BuildBlock, operation: p.Instruction) Error!p.Id {
        const slot = self.variables.len + self.instructions.items.len;
        try self.instructions.append(self.function.compiler.allocator, operation);
        return slot;
    }
    fn value(self: *BuildBlock, id: p.Id) Error!p.Id {
        if (self.computed.get(id)) |slot| return slot;
        const compiler = self.function.compiler;
        var pending: std.ArrayList(ValueTask) = .empty;
        defer pending.deinit(compiler.allocator);
        try pending.append(compiler.allocator, try self.valueTask(id));
        while (pending.items.len != 0) {
            const task = &pending.items[pending.items.len - 1];
            const expression = compiler.source.values[@intCast(task.id)];
            if (expression.expression == .primitive and task.next < task.operands.len) {
                const child = expression.expression.primitive.operands[task.next];
                if (self.computed.get(child)) |slot| {
                    task.operands[task.next] = slot;
                    task.next += 1;
                } else try pending.append(compiler.allocator, try self.valueTask(child));
                continue;
            }
            const slot = try self.emitValue(task.id, task.operands);
            if (compiler.cacheable[@intCast(task.id)]) try self.computed.put(compiler.allocator, task.id, slot);
            _ = pending.pop();
            if (pending.items.len == 0) return slot;
            const parent = &pending.items[pending.items.len - 1];
            parent.operands[parent.next] = slot;
            parent.next += 1;
        }
        unreachable;
    }
    fn valueTask(self: *BuildBlock, id: p.Id) Error!ValueTask {
        const compiler = self.function.compiler;
        const expression = compiler.source.values[@intCast(id)].expression;
        return .{ .id = id, .operands = try compiler.allocator.alloc(p.Id, if (expression == .primitive) expression.primitive.operands.len else 0) };
    }
    fn emitValue(self: *BuildBlock, id: p.Id, operands: []const p.Id) Error!p.Id {
        const compiler = self.function.compiler;
        const expression = compiler.source.values[@intCast(id)];
        const slot = switch (expression.expression) {
            .variable => |variable_id| try self.namedVariable(variable_id),
            .literal => |literal| try self.instruction(.{ .opcode = .constant, .result_type = expression.schema, .immediate = literal }),
            .primitive => |primitive| try self.instruction(.{ .opcode = primitive.opcode, .result_type = expression.schema, .operands = operands, .immediate = primitive.immediate, .failures = primitive.failures }),
            .lambda => |function| blk: {
                const free = compiler.facts.functions[@intCast(function)].items;
                const captures = try compiler.allocator.alloc(p.Id, free.len);
                for (captures, free) |*capture, variable_id| {
                    capture.* = try self.namedVariable(variable_id);
                }
                break :blk try self.instruction(.{ .opcode = .computation, .result_type = expression.schema, .operands = captures, .immediate = try compiler.constructor(function, expression.schema) });
            },
        };
        return slot;
    }
    fn values(self: *BuildBlock, expressions: []const p.Id) Error![]const p.Id {
        const result = try self.function.compiler.allocator.alloc(p.Id, expressions.len);
        for (result, expressions) |*slot, expression| slot.* = try self.value(expression);
        return result;
    }
    fn edge(self: BuildBlock, target: Block, result_variable: ?p.Id, result_slot: ?p.Id) Error!p.Edge {
        const compiler = self.function.compiler;
        const retain_result = if (result_variable) |variable_id|
            !compiler.traits.drop[@intCast(compiler.variables.items[@intCast(variable_id)])] and
                std.mem.indexOfScalar(p.Id, target.variables, variable_id) == null
        else
            false;
        const arguments = try compiler.allocator.alloc(
            p.Argument,
            target.variables.len + @intFromBool(retain_result),
        );
        const result: p.Argument = if (result_slot) |slot| .{ .slot = slot } else .returned;
        for (arguments[@intFromBool(retain_result)..], target.variables) |*argument, variable_id| {
            argument.* = if (result_variable != null and variable_id == result_variable.?)
                result
            else
                .{ .slot = try self.variable(variable_id) };
        }
        if (!retain_result) {
            if (result_variable) |variable_id| {
                if (!compiler.traits.drop[@intCast(compiler.variables.items[@intCast(variable_id)])]) {
                    const position = std.mem.indexOfScalar(p.Id, target.variables, variable_id).?;
                    try compiler.scoped_parameters.put(compiler.allocator, target.id, position);
                }
            }
            return .{ .block = target.id, .arguments = arguments };
        }
        arguments[0] = result;
        const schema = compiler.variables.items[@intCast(result_variable.?)];
        const depth = compiler.custody_blocks.get(target.id).?.depth;
        const retained = try self.function.retainBlock(target.id, schema, 0, depth);
        try compiler.scoped_parameters.put(compiler.allocator, retained, 0);
        return .{ .block = retained, .arguments = arguments };
    }
    fn consumed(self: BuildBlock, terminator: p.Terminator) Error![]const bool {
        const compiler = self.function.compiler;
        const used = try compiler.allocator.alloc(bool, self.variables.len + self.instructions.items.len);
        @memset(used, false);
        for (self.instructions.items, 0..) |operation, index| {
            if (operation.opcode.borrowsOperands()) continue;
            for (operation.operands) |operand| {
                std.debug.assert(operand < self.variables.len + index);
                used[@intCast(operand)] = true;
            }
        }
        switch (terminator) {
            .return_value, .fail => |slot| use(used, &.{slot}),
            .jump, .yield_value => {},
            .branch => |branch| use(used, &.{branch.condition}),
            .switch_variant => |selected| use(used, &.{selected.value}),
            .unpack_product => |unpack| use(used, &.{unpack.value}),
            .call => |call| use(used, call.arguments),
            .perform => |perform| {
                use(used, &.{perform.payload});
                if (perform.capability) |slot| use(used, &.{slot});
                use(used, perform.bodies);
                use(used, perform.use_site_capabilities);
            },
            .apply => |apply| {
                use(used, &.{apply.computation});
                use(used, apply.arguments);
            },
            .handle => |handle| {
                use(used, &.{handle.body});
                use(used, handle.arguments);
                use(used, handle.state);
            },
            .resume_value => |resuming| use(used, &.{ resuming.resumption, resuming.argument }),
            .resume_with => |resuming| {
                use(used, &.{ resuming.resumption, resuming.argument });
                use(used, resuming.state);
            },
            .resume_computation => |resuming| use(used, &.{ resuming.resumption, resuming.computation }),
            .dispose => |disposal| use(used, &.{disposal.owned}),
            .protect => |protection| {
                use(used, &.{ protection.body, protection.cleanup });
                if (protection.resource) |slot| use(used, &.{slot});
                use(used, protection.arguments);
            },
            .with_region => |region| {
                use(used, &.{region.body});
                use(used, region.arguments);
            },
            .forward => return error.InvalidSource,
        }
        return used;
    }
    fn use(used: []bool, slots: []const p.Id) void {
        for (slots) |slot| {
            std.debug.assert(slot < used.len);
            used[@intCast(slot)] = true;
        }
    }
    fn retainEdge(self: BuildBlock, original: p.Edge, consumed_slots: []const bool, prefix: usize) Error!p.Edge {
        const compiler = self.function.compiler;
        const used = try compiler.allocator.dupe(bool, consumed_slots);
        var arguments: std.ArrayList(p.Argument) = .empty;
        try arguments.appendSlice(compiler.allocator, original.arguments);
        for (original.arguments) |argument| if (argument == .slot) {
            used[@intCast(argument.slot)] = true;
        };
        var target = original.block;
        for (used, 0..) |transferred, slot| {
            if (transferred) continue;
            const schema = if (slot < self.variables.len)
                compiler.variables.items[@intCast(self.variables[slot])]
            else
                self.instructions.items[slot - self.variables.len].result_type;
            if (compiler.traits.drop[@intCast(schema)]) continue;
            std.debug.assert(!compiler.traits.copy[@intCast(schema)]);
            var position = arguments.items.len;
            for (arguments.items, 0..) |argument, index| {
                if (compiler.scoped_parameters.get(target)) |scoped| {
                    if (prefix + index <= scoped) continue;
                }
                if (argument == .slot and argument.slot > slot) {
                    position = index;
                    break;
                }
            }
            const depth = if (slot < self.variables.len)
                self.environment.ownerDepth(self.variables[slot])
            else
                self.environment.depth;
            target = try self.function.retainBlock(target, schema, prefix + position, depth);
            try arguments.insert(compiler.allocator, position, .{ .slot = slot });
        }
        return .{ .block = target, .arguments = arguments.items };
    }
    fn complete(self: BuildBlock, terminator: p.Terminator) Error!p.Terminator {
        // Only emitted slots decide custody. In particular, evaluate every
        // call/control operand before completing any of its successor edges.
        if (terminator == .return_value or terminator == .fail) return terminator;
        const compiler = self.function.compiler;
        const used = try self.consumed(terminator);
        return switch (terminator) {
            .return_value, .fail => unreachable,
            .jump => |edge_value| .{ .jump = try self.retainEdge(edge_value, used, 0) },
            .yield_value => |edge_value| .{ .yield_value = try self.retainEdge(edge_value, used, 0) },
            .branch => |branch| .{ .branch = .{
                .condition = branch.condition,
                .when_true = try self.retainEdge(branch.when_true, used, 0),
                .when_false = try self.retainEdge(branch.when_false, used, 0),
            } },
            .switch_variant => |selected| blk: {
                const cases = try compiler.allocator.alloc(p.Edge, selected.cases.len);
                for (cases, selected.cases) |*edge_value, original| {
                    edge_value.* = try self.retainEdge(original, used, 0);
                }
                break :blk .{ .switch_variant = .{ .value = selected.value, .cases = cases } };
            },
            .unpack_product => |unpack| blk: {
                const original = try compiler.allocator.alloc(p.Argument, unpack.arguments.len);
                for (original, unpack.arguments) |*argument, slot| argument.* = .{ .slot = slot };
                const target = try self.retainEdge(.{
                    .block = unpack.block,
                    .arguments = original,
                }, used, compiler.blocks.items[@intCast(unpack.block)].parameters.len - unpack.arguments.len);
                const arguments = try compiler.allocator.alloc(p.Id, target.arguments.len);
                for (arguments, target.arguments) |*slot, argument| slot.* = argument.slot;
                break :blk .{ .unpack_product = .{
                    .value = unpack.value,
                    .block = target.block,
                    .arguments = arguments,
                } };
            },
            inline .call,
            .perform,
            .apply,
            .handle,
            .resume_value,
            .resume_with,
            .resume_computation,
            .dispose,
            .protect,
            .with_region,
            => |operation, kind| blk: {
                var changed = operation;
                changed.next = try self.retainEdge(operation.next, used, 0);
                break :blk @unionInit(p.Terminator, @tagName(kind), changed);
            },
            .forward => return error.InvalidSource,
        };
    }
    fn finish(self: *BuildBlock, terminator: p.Terminator) Error!Block {
        const compiler = self.function.compiler;
        const completed = try self.complete(terminator);
        const id = compiler.blocks.items.len;
        try compiler.custody_blocks.put(compiler.allocator, id, .{
            .depth = self.environment.depth,
            .parameters = try Request.ownerDepths(
                compiler.allocator,
                self.environment,
                self.variables,
            ),
        });
        try compiler.blocks.append(compiler.allocator, .{ .function = self.function.id, .parameters = try compiler.types(self.variables), .instructions = self.instructions.items, .terminator = completed });
        return .{ .id = id, .variables = self.variables };
    }
};

fn cacheableValues(allocator: std.mem.Allocator, source: ast.Module, traits: data.traits.Facts) Error![]bool {
    const cacheable = try allocator.alloc(bool, source.values.len);
    for (source.values, 0..) |value, id| cacheable[id] = switch (value.expression) {
        .variable, .literal => true,
        .lambda => traits.copy[@intCast(value.schema)],
        .primitive => |primitive| blk: {
            if (!traits.copy[@intCast(value.schema)]) break :blk false;
            switch (primitive.opcode) {
                .cell_new, .cell_get, .cell_set, .clone_resumption, .package, .unpack, .resource_pack, .resource_unpack => break :blk false,
                else => {},
            }
            for (primitive.operands) |operand| {
                if (!cacheable[@intCast(operand)]) break :blk false;
                // Even a borrow requires its owner to remain live at this occurrence.
                if (!traits.copy[@intCast(source.values[@intCast(operand)].schema)]) break :blk false;
            }
            break :blk true;
        },
    };
    return cacheable;
}
