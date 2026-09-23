//! Bounded test-only authoring generator; World sees only ordinary compiled code.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.computation;
const hyper = boundary.library.hyper;
const Id = source.Id;

const Generator = struct {
    b: *source.Builder,
    group: hyper.Group,
    types: hyper.Pair,
    seed: u32,

    fn next(self: *Generator) u32 {
        self.seed ^= self.seed << 13;
        self.seed ^= self.seed >> 17;
        self.seed ^= self.seed << 5;
        return self.seed;
    }
    fn transform(self: *Generator, amount: u64, strict: bool) !Id {
        const b = self.b;
        const result = self.types.answer_forward;
        const function = try b.declare(&.{self.types.answer_backward}, result, &.{}, &.{});
        const body = try b.declare(&.{}, try b.scalar(u64), &.{}, &.{});
        var term = try b.pure(try b.constant(u64, amount));
        if (strict) {
            const value = try b.variable(try b.scalar(u64));
            const overflow = try b.failureLiteral(try b.constant(void, {}));
            const plus = try b.value(.{ .schema = try b.scalar(u64), .expression = .{
                .primitive = .{
                    .opcode = .integer_add,
                    .operands = &.{ try b.reference(value), try b.constant(u64, amount) },
                    .failures = &.{.{ .kind = .arithmetic_overflow, .value = overflow }},
                },
            } });
            const demand = try hyper.force(b, try b.reference(b.parameter(function, 0)));
            term = try b.bind(value, demand, try b.pure(plus));
        }
        try b.define(body, term);
        try b.define(function, try b.pure(try b.lambda(body, self.types.answer_forward)));
        return function;
    }
    fn compose(self: *Generator, left: Id, right: Id) !Id {
        const b = self.b;
        const l = try b.variable(self.types.forward);
        const r = try b.variable(self.types.forward);
        const lv = try b.reference(l);
        const combined = try hyper.compose(b, self.group, 0, 0, 0, lv, try b.reference(r));
        return b.bind(l, left, try b.bind(r, right, combined));
    }
    fn generate(self: *Generator, depth: u8) source.Error!Id {
        const b = self.b;
        const kind = self.next() % @as(u32, if (depth == 0) 3 else 6);
        if (kind < 3) {
            const value = try b.constant(u64, self.next() % 23);
            const delayed = try hyper.deferValue(b, self.types.answer_forward, value);
            if (kind == 0) return b.pure(try hyper.base(b, self.types, delayed));
            if (kind == 1) {
                const constant = try self.transform(self.next() % 23, false);
                return hyper.lift(b, self.types, constant);
            }
            const result = self.types.answer_forward;
            const body = try b.declare(&.{self.types.peer_backward}, result, &.{}, &.{});
            try b.define(body, try b.pure(delayed));
            return b.pure(try hyper.make(b, body, self.types.forward));
        }
        if (kind == 3) {
            const function = try self.transform(self.next() % 7, true);
            const tail = try b.declare(&.{}, self.types.forward, &.{}, &.{});
            try b.define(tail, try self.generate(depth - 1));
            const delayed_tail = try b.lambda(tail, self.types.peer_forward);
            return b.pure(try hyper.push(b, self.types, function, delayed_tail));
        }
        if (kind == 4) {
            const left = try self.generate(depth - 1);
            const right = try self.generate(depth - 1);
            return self.compose(left, right);
        }
        const child = try self.generate(depth - 1);
        return self.compose(try hyper.identity(b, self.types), child);
    }
};
const Application = struct {
    var seed: u32 = 1;
    var variant: u8 = 0;
    pub fn emit(b: *source.Builder) !source.Module {
        const integer = try b.scalar(u64);
        const group = try hyper.group(b, &.{integer}, &.{});
        const types = try group.get(0, 0);
        var g = Generator{ .b = b, .group = group, .types = types, .seed = seed };
        var term = try g.generate(3);
        if (variant == 2) term = try g.compose(try hyper.identity(b, types), term);
        if (variant == 3) term = try g.compose(term, try hyper.identity(b, types));
        if (variant >= 4) {
            const left = try hyper.lift(b, types, try g.transform(2, true));
            const right = try hyper.lift(b, types, try g.transform(3, true));
            term = if (variant == 4)
                try g.compose(left, try g.compose(right, term))
            else
                try g.compose(try g.compose(left, right), term);
        }
        const entry = try b.declare(&.{}, integer, &.{}, &.{});
        const participant = try b.variable(types.forward);
        const answer = try b.variable(types.answer_forward);
        const argument = try hyper.deferValue(b, types.answer_backward, try b.constant(u64, 7));
        const observed = if (variant == 1)
            try hyper.project(b, types, try b.reference(participant), argument)
        else
            try hyper.run(b, types, try b.reference(participant));
        const demanded = try b.bind(answer, observed, try hyper.force(b, try b.reference(answer)));
        try b.define(entry, try b.bind(participant, term, demanded));
        return b.module(entry, try b.scalar(void));
    }
};
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const seed = args.next() orelse return error.MissingSeed;
    const variant = args.next() orelse return error.MissingVariant;
    Application.seed = try std.fmt.parseInt(u32, seed, 10);
    Application.variant = try std.fmt.parseInt(u8, variant, 10);
    if (Application.variant > 5 or args.next() != null) return error.InvalidArguments;
    var compiled = try boundary.program.lower(init.gpa, Application);
    defer compiled.deinit();
    const length = try boundary.data.program_image.encodedLength(compiled.program);
    const bytes = try init.gpa.alloc(u8, length);
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &buffer);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}
