// zlinter-disable declaration_naming field_ordering require_doc_comment no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

fn mustInstruction(result: anyerror!ability.ir.plan.Instruction) ability.ir.plan.Instruction {
    return result catch |err| std.debug.panic("invalid plan-native optional instruction: {s}", .{@errorName(err)});
}

fn mustPlan(result: anyerror!ability.ir.ProgramPlan) ability.ir.ProgramPlan {
    return result catch |err| std.debug.panic("invalid plan-native optional plan: {s}", .{@errorName(err)});
}

const OptionalOutcome = ?i32;

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

        pub fn dispatch(self: *const @This()) !ability.effect.choice.Decision(OptionalOutcome, i32) {
            self.dispatches.* += 1;
            return switch (self.mode) {
                .resume_some => ability.effect.choice.Decision(OptionalOutcome, i32).resumeWith(40),
                .resume_none => ability.effect.choice.Decision(OptionalOutcome, i32).resumeWith(null),
                .return_now => ability.effect.choice.Decision(OptionalOutcome, i32).returnNow(77),
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

fn optionalPlan() ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const resumed = ability.ir.builder.local(root, 0);
    const is_some = ability.ir.builder.local(root, 1);
    const extracted = ability.ir.builder.local(root, 2);
    const fallback = ability.ir.builder.local(root, 3);
    const instructions = [_]ability.ir.plan.Instruction{
        mustInstruction(ability.ir.builder.callOp(root, resumed, ability.ir.builder.op(root, 0), null)),
        mustInstruction(ability.ir.builder.sumVariantIs(root, is_some, resumed, 1)),
        mustInstruction(ability.ir.builder.sumExtractPayload(root, extracted, resumed, 1)),
        mustInstruction(ability.ir.builder.returnValue(root, extracted)),
        .{ .kind = .const_i32, .dst = fallback.index, .operand = 0 },
        mustInstruction(ability.ir.builder.returnValue(root, fallback)),
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 4,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 3,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "optional",
        .first_op = 0,
        .op_count = 1,
        .lifecycle_tag = .choice_policy,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "request",
        .mode = .choice,
        .payload_codec = .unit,
        .resume_codec = .sum,
        .resume_schema_index = 0,
        .has_after = true,
    }};
    const variants = [_]ability.ir.ValueVariantPlan{
        ability.ir.value.unitVariant("none"),
        ability.ir.value.variant("some", i32),
    };
    const schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(OptionalOutcome),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = @intCast(variants.len),
    }};
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
        .{ .first_instruction = 4, .instruction_count = 2, .terminator_index = 2 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return mustPlan(ability.ir.builder.finish(.{
        .label = "plan-native-optional",
        .ir_hash = 40,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &schemas,
        .value_fields = &.{},
        .value_variants = &variants,
        .locals = &.{
            .{ .codec = .sum, .schema_index = 0 },
            .{ .codec = .bool },
            .{ .codec = .i32 },
            .{ .codec = .i32 },
        },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }));
}

const OptionalBody = struct {
    pub const value_schema_types = .{OptionalOutcome};
    pub const compiled_plan = optionalPlan();
};

pub fn runCase(runtime: *ability.Runtime, mode: OptionalMode) !RunResult {
    const Program = ability.program("plan-native-optional", OptionalHandlers, OptionalBody);
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

/// Run the plan-native optional prototype through `ability.program`.
pub fn run(writer: anytype) !void {
    var runtime = ability.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const Program = ability.program("plan-native-optional", OptionalHandlers, OptionalBody);
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
