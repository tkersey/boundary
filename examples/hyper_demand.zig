//! Reciprocal internal demands, retained additions and delayed tasks.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.computation;
const hyper = boundary.library.hyper;
const bridge = boundary.library.hyper_authoring;

fn step(b: *source.Builder, q: hyper.Query, consumer: bool) !source.Id {
    const t = try bridge.Environment.init(b, bool, u64, .{ .external = "hyper/reference", .need = "hyper/need" });
    const c = t.context;
    const scope = try t.scope();
    const state = try t.state(scope, q);
    const interpretation = try t.interpretation(q, consumer);
    const body_schema = try t.bodySchema(interpretation);
    const work = try c.functionFor("demand body", body_schema);
    const body = try scope.closureBody(work);
    const nested = try body.branch();
    const contribution = try nested.performLocal(try t.need(consumer), try body.parameter("capability"), try nested.constant(bool, true));
    const plus = try nested.checkedAdd(contribution, try nested.constant(u64, if (consumer) 13 else 10), try c.literalFailure(void, {}));
    const result = if (consumer) blk: {
        const external_branch = try body.branch();
        const external_result = try external_branch.perform(t.read, try external_branch.constant(u64, 19));
        break :blk try body.conditional(state, try external_branch.ret(external_result), try nested.ret(plus));
    } else try body.block(try nested.ret(plus));
    try c.define(work, try body.ret(result));
    const task = try c.functionFor("delayed task", t.task);
    const task_body = try scope.closureBody(task);
    const handled = try t.handle(task_body, interpretation, q, try task_body.lambda(work, body_schema));
    try c.define(task, try task_body.ret(handled));
    const answer_schema = try t.answerSchema(q);
    const descriptor = try c.functionFor("task descriptor", answer_schema);
    const descriptor_body = try scope.closureBody(descriptor);
    try c.define(descriptor, try descriptor_body.ret(try descriptor_body.lambda(task, t.task)));
    return t.finish(scope, try scope.lambda(descriptor, answer_schema));
}
const Producer = struct {
    pub fn emit(b: *source.Builder, q: hyper.Query) !source.Id {
        return step(b, q, false);
    }
};
const Consumer = struct {
    pub fn emit(b: *source.Builder, q: hyper.Query) !source.Id {
        return step(b, q, true);
    }
};
const Application = struct {
    pub fn emit(b: *source.Builder) !source.Module {
        const t = try bridge.Environment.init(b, bool, u64, .{ .external = "hyper/reference", .need = "hyper/need" });
        const c = t.context;
        const producer = try t.definition(false, Producer);
        const consumer = try t.definition(true, Consumer);
        const entry = try c.function("entry", &.{}, t.integer, &.{t.read});
        const body = try c.body(entry);
        const p = try t.start(body, producer, try body.constant(bool, false));
        const other = try t.start(body, consumer, try body.constant(bool, false));
        const peer_schema = try t.peerSchema();
        const peer = try c.functionFor("delayed producer", peer_schema);
        const peer_body = try body.closureBody(peer);
        try c.define(peer, try peer_body.ret(p));
        const delayed = try t.invoke(body, other, try body.lambda(peer, peer_schema));
        const task = try body.apply(delayed, &.{});
        const result = try body.apply(task, &.{});
        try c.define(entry, try body.ret(result));
        return c.module(entry, try c.scalar(void));
    }
};
pub fn main(init: std.process.Init) !void {
    var compiled = try boundary.program.lower(init.gpa, Application);
    defer compiled.deinit();
    const bytes = try init.gpa.alloc(u8, try boundary.data.program_image.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &buffer);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}
