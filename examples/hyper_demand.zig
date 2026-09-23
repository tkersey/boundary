//! Reciprocal ana steps use structured source authoring around existing hyperfunctions.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.computation;
const a = boundary.authoring;
const hyper = boundary.library.hyper;
const bridge = boundary.library.hyper_authoring;

fn step(raw: *source.Builder, q: hyper.Query, comptime consumer: bool) source.Error!source.Id {
    return stepForward(raw, q, consumer) catch |err| return a.sourceError(err);
}

fn stepForward(raw: *source.Builder, q: hyper.Query, comptime consumer: bool) a.Error!source.Id {
    const t = try bridge.types(raw);
    var author = a.Builder.init(raw);
    var frame = try author.ambient(if (consumer) "consumer step" else "producer step");
    const integer = try author.adoptSchema(t.integer);
    const boolean = try author.adoptSchema(t.boolean);
    const read = try author.adoptEffect(t.read);
    const need = if (consumer) t.consumer else t.producer;
    const need_effect = try author.adoptEffect(need.effect);
    const capability = try author.adoptSchema(need.capability);
    const state = try a.Interop.adoptValue(&frame, q.state, boolean);
    const peer = try a.Interop.adoptValue(&frame, q.peer, try author.adoptSchema(q.types.peer_backward));
    const interpretation = try bridge.interpretation(raw, q, need, t);

    const work = try author.declare("demand and contribute", &.{.{ .name = "need", .schema = capability }}, integer, &.{ read, need_effect });
    var body = try author.bodyWithin(&frame, work);
    const cap = try body.parameter("need");
    const failure = try author.literal(void, {});
    const contribution = if (consumer) blk: {
        var yes = try body.child("external reference");
        const external = try yes.perform(read, try author.literal(u64, 19));
        var no = try body.child("internal demand");
        const demanded = try bridge.request(&no, need, cap, try author.literal(bool, true), integer);
        const added = try no.checkedAdd(demanded, try author.literal(u64, 13), failure);
        break :blk try body.select(state, try yes.finish(external), try no.finish(added));
    } else blk: {
        const demanded = try bridge.request(&body, need, cap, try author.literal(bool, true), integer);
        break :blk try body.checkedAdd(demanded, try author.literal(u64, 10), failure);
    };
    try author.define(work, try body.finish(contribution));

    const task = try author.declare("demand task", &.{}, integer, &.{read});
    var task_body = try author.bodyWithin(&frame, task);
    const callable = try a.Interop.lambdaAs(&task_body, work, try author.adoptSchema(interpretation.body));
    const interpreted = try bridge.install(&task_body, interpretation, peer, callable, integer);
    try author.define(task, try task_body.finish(interpreted));

    const descriptor = try author.declare("delayed task descriptor", &.{}, try author.adoptSchema(t.task), &.{});
    var descriptor_body = try author.bodyWithin(&frame, descriptor);
    const delayed_task = try a.Interop.lambdaAs(&descriptor_body, task, try author.adoptSchema(t.task));
    try author.define(descriptor, try descriptor_body.finish(delayed_task.value));
    const result = try a.Interop.lambdaAs(&frame, descriptor, try author.adoptSchema(q.types.answer_forward));
    return a.Interop.rawTerm(try frame.finish(result.value));
}

const Producer = struct {
    pub fn emit(raw: *source.Builder, q: hyper.Query) source.Error!source.Id {
        return step(raw, q, false);
    }
};
const Consumer = struct {
    pub fn emit(raw: *source.Builder, q: hyper.Query) source.Error!source.Id {
        return step(raw, q, true);
    }
};

const Application = struct {
    pub fn emit(raw: *source.Builder) !source.Module {
        const t = try bridge.types(raw);
        const producer = try hyper.ana(raw, t.pair, t.boolean, Producer);
        const consumer = try hyper.ana(raw, hyper.swap(t.pair), t.boolean, Consumer);
        var author = a.Builder.init(raw);
        const integer = try author.adoptSchema(t.integer);
        const read = try author.adoptEffect(t.read);
        const entry = try author.declare("main", &.{}, integer, &.{read});
        var body = try author.body(entry);
        const p = try bridge.start(&body, producer, try author.literal(bool, false), try author.adoptSchema(t.pair.forward));
        const c = try bridge.start(&body, consumer, try author.literal(bool, false), try author.adoptSchema(t.pair.backward));
        const peer = try author.declare("producer peer", &.{}, try author.adoptSchema(t.pair.forward), &.{});
        var peer_body = try author.bodyWithin(&body, peer);
        try author.define(peer, try peer_body.finish(p));
        const peer_value = try a.Interop.lambdaAs(&body, peer, try author.adoptSchema(t.pair.peer_forward));
        const delayed = try bridge.invoke(&body, c, peer_value, try author.adoptSchema(t.pair.answer_backward));
        const task = try bridge.force(&body, delayed, try author.adoptSchema(t.task));
        const result = try bridge.force(&body, task, integer);
        try author.define(entry, try body.finish(result));
        return author.module(entry, try author.scalar(void));
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
