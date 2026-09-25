//! Checked adapters for the existing recursive-demand library. No new evaluator.
const source = @import("../source.zig");
const a = @import("../authoring.zig");
const hyper = @import("hyper.zig");
const Id = source.Id;
const RawTypes = struct {
    integer: Id,
    boolean: Id,
    task: Id,
    pair: hyper.Pair,
    read: Id,
    producer: hyper.demand.Family,
    consumer: hyper.demand.Family,
};
pub const Names = struct { external: []const u8, need: []const u8 };
fn rawTypes(
    b: *source.Builder,
    comptime State: type,
    comptime Result: type,
    names: Names,
) source.Error!RawTypes {
    const integer = try b.scalar(Result);
    const boolean = try b.scalar(State);
    const cached = try b.specialization(RawTypes, "boundary.hyper-authoring/tasks/v1", .{ integer, boolean, names });
    if (cached.cached) |value| return value;
    const read = try b.effect(.{
        .identity = names.external,
        .payload = integer,
        .result = integer,
    });
    const task = try b.reserveSchema();
    const pair = try hyper.pairWith(b, task, task, &.{ integer, boolean });
    try b.defineSchema(task, .{ .internal = .{ .computation = .{
        .parameters = &.{},
        .result = integer,
        .effects = &.{read},
        .capture_bound = &.{ boolean, pair.peer_forward, pair.peer_backward },
    } } });
    return cached.finish(b, .{
        .integer = integer,
        .boolean = boolean,
        .task = task,
        .pair = pair,
        .read = read,
        .producer = try hyper.demand.family(b, names.need, boolean, integer),
        .consumer = try hyper.demand.family(b, names.need, boolean, integer),
    });
}

/// The application retains all sequencing and control. Only raw library calls
/// and the recursive interface knot live at this compatibility boundary.
pub const Environment = struct {
    context: *a.Context,
    integer: *const a.Schema,
    boolean: *const a.Schema,
    task: *const a.Schema,
    read: *const a.Operation,
    raw_types: RawTypes,

    pub fn init(
        b: *source.Builder,
        comptime State: type,
        comptime Result: type,
        names: Names,
    ) a.Error!Environment {
        const t = try rawTypes(b, State, Result, names);
        const c = try a.Context.init(b);
        return .{
            .context = c,
            .integer = try a.interop.schema(c, t.integer),
            .boolean = try a.interop.schema(c, t.boolean),
            .task = try a.interop.schema(c, t.task),
            .read = try a.interop.operation(c, t.read),
            .raw_types = t,
        };
    }
    pub fn need(self: Environment, consumer: bool) a.Error!*const a.Operation {
        return a.interop.operation(self.context, (if (consumer) self.raw_types.consumer else self.raw_types.producer).effect);
    }
    pub fn interpretation(
        self: Environment,
        q: hyper.Query,
        consumer: bool,
    ) a.Error!hyper.demand.Interpretation {
        const t = self.raw_types;
        return hyper.demand.interpret(a.interop.builder(self.context), q, if (consumer) t.consumer else t.producer, t.integer, .{
            .captures = &.{
                t.boolean,
                t.integer,
                t.pair.peer_forward,
                t.pair.peer_backward,
            },
            .residual = .{ .effects = &.{t.read} },
        });
    }
    pub fn scope(self: Environment) a.Error!*a.Body {
        return a.interop.scope(self.context);
    }
    pub fn state(self: Environment, body: *a.Body, q: hyper.Query) a.Error!*const a.Value {
        return a.interop.adoptValue(body, q.state, self.boolean);
    }
    pub fn bodySchema(
        self: Environment,
        interpretation_value: hyper.demand.Interpretation,
    ) a.Error!*const a.Schema {
        return a.interop.namedCallable(self.context, interpretation_value.body, &.{"capability"});
    }
    pub fn handle(
        self: Environment,
        body: *a.Body,
        interpretation_value: hyper.demand.Interpretation,
        q: hyper.Query,
        work: *const a.Value,
    ) a.Error!*const a.Value {
        const term = try hyper.demand.handle(a.interop.builder(self.context), interpretation_value, q.peer, try a.interop.valueId(body, work));
        return a.interop.term(body, term, self.integer);
    }
    pub fn answerSchema(self: Environment, q: hyper.Query) a.Error!*const a.Schema {
        return a.interop.schema(self.context, q.types.answer_forward);
    }
    pub fn finish(self: Environment, body: *a.Body, value: *const a.Value) a.Error!Id {
        return a.interop.computationId(self.context, try body.ret(value));
    }
    pub fn definition(self: Environment, consumer: bool, comptime Step: type) a.Error!hyper.Ana {
        const pair = if (consumer) hyper.swap(self.raw_types.pair) else self.raw_types.pair;
        return hyper.ana(a.interop.builder(self.context), pair, self.raw_types.boolean, struct {
            pub fn emit(b: *source.Builder, q: hyper.Query) source.Error!Id {
                return Step.emit(b, q) catch |err| return a.sourceError(err);
            }
        });
    }
    pub fn start(
        self: Environment,
        body: *a.Body,
        definition_value: hyper.Ana,
        state_value: *const a.Value,
    ) a.Error!*const a.Value {
        const term = try hyper.start(a.interop.builder(self.context), definition_value, try a.interop.valueId(body, state_value));
        return a.interop.term(body, term, try a.interop.schema(self.context, definition_value.interface));
    }
    pub fn peerSchema(self: Environment) a.Error!*const a.Schema {
        return a.interop.schema(self.context, self.raw_types.pair.peer_forward);
    }
    pub fn invoke(
        self: Environment,
        body: *a.Body,
        participant: *const a.Value,
        peer: *const a.Value,
    ) a.Error!*const a.Value {
        _ = self;
        return body.apply(participant, &.{.{ .name = "0", .value = peer }});
    }
};
