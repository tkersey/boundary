// zlinter-disable declaration_naming field_ordering require_doc_comment no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

fn mustInstruction(result: anyerror!boundary.ir.plan.Instruction) boundary.ir.plan.Instruction {
    return result catch |err| std.debug.panic("invalid plan-native optional instruction: {s}", .{@errorName(err)});
}

fn mustPlan(result: anyerror!boundary.ir.ProgramPlan) boundary.ir.ProgramPlan {
    return result catch |err| std.debug.panic("invalid plan-native optional plan: {s}", .{@errorName(err)});
}

const optional_plan = boundary.effect.optional.plan;
const OptionalOutcome = optional_plan.Outcome(i32);

const OptionalMode = enum {
    resume_some,
    resume_none,
    return_now,
};

const OptionalHandlers = struct {
    request: struct {
        mode: OptionalMode,
        dispatches: *usize,
        afters: *usize,

        pub fn dispatch(self: *const @This()) !boundary.effect.choice.Decision(OptionalOutcome, i32) {
            self.dispatches.* += 1;
            return switch (self.mode) {
                .resume_some => boundary.effect.choice.Decision(OptionalOutcome, i32).resumeWith(40),
                .resume_none => boundary.effect.choice.Decision(OptionalOutcome, i32).resumeWith(null),
                .return_now => boundary.effect.choice.Decision(OptionalOutcome, i32).returnNow(77),
            };
        }

        pub fn afterDispatch(self: *const @This(), value: i32) !i32 {
            self.afters.* += 1;
            return value + 1;
        }
    },
};

pub const RunResult = struct {
    value: i32,
    dispatches: usize,
    afters: usize,
};

fn optionalPlan() boundary.ir.ProgramPlan {
    const layout = boundary.ir.builder.layout;
    const root = comptime boundary.ir.builder.function(0);
    const resumed = comptime boundary.ir.builder.local(root, 0);
    const is_some = comptime boundary.ir.builder.local(root, 1);
    const extracted = comptime boundary.ir.builder.local(root, 2);
    const fallback = comptime boundary.ir.builder.local(root, 3);
    const requirements = [_]boundary.ir.plan.Requirement{optional_plan.requirement(0)};
    const ops = [_]boundary.ir.plan.Op{optional_plan.requestOp(0, 0, .present)};
    const variants = optional_plan.variants(i32);
    const schemas = [_]boundary.ir.ValueSchemaPlan{optional_plan.schema(i32, 0, 0)};

    return mustPlan(boundary.ir.builder.layout.finish(.{
        .label = "plan-native-optional",
        .ir_hash = 40,
        .entry = root,
        .requirements = &requirements,
        .ops = &ops,
        .value_schemas = &schemas,
        .value_variants = &variants,
        .functions = .{.{
            .symbol_name = "run",
            .value_ref = boundary.ir.ValueRef{ .codec = .i32 },
            .result_ref = boundary.ir.ValueRef{ .codec = .i32 },
            .requirements = layout.span(0, 1),
            .locals = .{
                optional_plan.local(0),
                .{ .codec = .bool },
                .{ .codec = .i32 },
                .{ .codec = .i32 },
            },
            .blocks = .{
                .{
                    .instructions = .{
                        mustInstruction(optional_plan.callRequest(root, resumed, boundary.ir.builder.op(root, 0))),
                        mustInstruction(optional_plan.isSome(root, is_some, resumed)),
                    },
                    .terminator = boundary.ir.plan.Terminator{ .kind = .branch_if, .primary = 1, .secondary = 2 },
                },
                .{
                    .instructions = .{
                        mustInstruction(optional_plan.extractSome(root, extracted, resumed)),
                        mustInstruction(boundary.ir.builder.returnValue(root, extracted)),
                    },
                    .terminator = boundary.ir.plan.Terminator{ .kind = .return_value },
                },
                .{
                    .instructions = .{
                        .{ .kind = .const_i32, .dst = fallback.index, .operand = 0 },
                        mustInstruction(boundary.ir.builder.returnValue(root, fallback)),
                    },
                    .terminator = boundary.ir.plan.Terminator{ .kind = .return_value },
                },
            },
        }},
    }));
}

const OptionalBody = struct {
    pub const value_schema_types = .{OptionalOutcome};
    pub const compiled_plan = optionalPlan();
};

pub fn runCase(runtime: *boundary.Runtime, mode: OptionalMode) !RunResult {
    const Program = boundary.program("plan-native-optional", OptionalHandlers, OptionalBody);
    var dispatches: usize = 0;
    var afters: usize = 0;
    var result = try Program.run(runtime, .{ .request = .{
        .mode = mode,
        .dispatches = &dispatches,
        .afters = &afters,
    } });
    defer result.deinit();
    return .{
        .value = result.value,
        .dispatches = dispatches,
        .afters = afters,
    };
}

/// Run the plan-native optional prototype through `boundary.program`.
pub fn run(writer: anytype) !void {
    var runtime = boundary.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const Program = boundary.program("plan-native-optional", OptionalHandlers, OptionalBody);
    try writer.print("contract.op={s} mode={s} resume={s} after={any} variants={d}\n", .{
        Program.contract.ops[0].op_name,
        @tagName(Program.contract.ops[0].mode),
        @tagName(Program.contract.ops[0].resume_ref.codec),
        Program.contract.ops[0].has_after,
        Program.contract.value_variants.len,
    });

    const some = try runCase(&runtime, .resume_some);
    const none = try runCase(&runtime, .resume_none);
    const early = try runCase(&runtime, .return_now);

    try writer.print("resume_some value={d} dispatches={d} afters={d}\n", .{ some.value, some.dispatches, some.afters });
    try writer.print("resume_none value={d} dispatches={d} afters={d}\n", .{ none.value, none.dispatches, none.afters });
    try writer.print("return_now value={d} dispatches={d} afters={d}\n", .{ early.value, early.dispatches, early.afters });
}

/// Run the plan-native optional example.
pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
