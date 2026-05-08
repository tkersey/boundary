// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

fn mustInstruction(result: anyerror!ability.ir.plan.Instruction) ability.ir.plan.Instruction {
    return result catch |err| std.debug.panic("invalid state/reader instruction: {s}", .{@errorName(err)});
}

fn mustPlan(result: anyerror!ability.ir.ProgramPlan) ability.ir.ProgramPlan {
    return result catch |err| std.debug.panic("invalid state/reader plan: {s}", .{@errorName(err)});
}

const StateReaderHandlers = struct {
    get: struct {
        state: *i32,

        pub fn dispatch(self: *const @This()) !i32 {
            return self.state.*;
        }
    },
    set: struct {
        state: *i32,

        pub fn dispatch(self: *const @This(), value: i32) !void {
            self.state.* = value;
        }
    },
    ask: struct {
        environment: *const i32,

        pub fn dispatch(self: *const @This()) !i32 {
            return self.environment.*;
        }
    },
};

fn stateReaderPlan() ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const env = ability.ir.builder.local(root, 0);
    const before = ability.ir.builder.local(root, 1);
    const next = ability.ir.builder.local(root, 2);
    const instructions = [_]ability.ir.plan.Instruction{
        mustInstruction(ability.ir.builder.callOp(root, env, ability.ir.builder.op(root, 2), null)),
        mustInstruction(ability.ir.builder.callOp(root, before, ability.ir.builder.op(root, 0), null)),
        .{ .kind = .add_i32, .dst = next.index, .operand = before.index, .aux = env.index },
        mustInstruction(ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 1), next)),
        mustInstruction(ability.ir.builder.returnValue(root, next)),
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 2,
        .first_output = 0,
        .output_count = 1,
        .first_local = 0,
        .local_count = 3,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{
        .{
            .label = "state",
            .first_op = 0,
            .op_count = 2,
            .lifecycle_tag = .state_cell,
            .output_tag = .final_state,
        },
        .{
            .label = "reader",
            .first_op = 2,
            .op_count = 1,
            .lifecycle_tag = .reader_environment,
        },
    };
    const ops = [_]ability.ir.plan.Op{
        .{ .requirement_index = 0, .op_name = "get", .mode = .transform, .payload_codec = .unit, .resume_codec = .i32 },
        .{ .requirement_index = 0, .op_name = "set", .mode = .transform, .payload_codec = .i32, .resume_codec = .unit },
        .{ .requirement_index = 1, .op_name = "ask", .mode = .transform, .payload_codec = .unit, .resume_codec = .i32 },
    };
    const outputs = [_]ability.ir.plan.Output{.{
        .label = "final_state",
        .codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return mustPlan(ability.ir.builder.finish(.{
        .label = "plan-native-state-reader",
        .ir_hash = 50,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &outputs,
        .locals = &.{
            .{ .codec = .i32 },
            .{ .codec = .i32 },
            .{ .codec = .i32 },
        },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }));
}

const StateReaderBody = struct {
    pub const Outputs = []i32;
    pub const compiled_plan = stateReaderPlan();

    pub fn collectOutputs(allocator: std.mem.Allocator, handlers: *StateReaderHandlers) !Outputs {
        const outputs = try allocator.alloc(i32, 1);
        outputs[0] = handlers.get.state.*;
        return outputs;
    }

    pub fn deinitOutputs(allocator: std.mem.Allocator, outputs: Outputs) void {
        allocator.free(outputs);
    }
};

pub fn run(writer: anytype) !void {
    var runtime = ability.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    var state: i32 = 5;
    const environment: i32 = 7;
    const Program = ability.program("plan-native-state-reader", StateReaderHandlers, StateReaderBody);
    var result = try Program.run(&runtime, .{
        .get = .{ .state = &state },
        .set = .{ .state = &state },
        .ask = .{ .environment = &environment },
    });
    defer result.deinit();

    try writer.print("value={d} final_state_output={d} state={d} env={d}\n", .{
        result.value,
        result.outputs[0],
        state,
        environment,
    });
    try writer.print("contract.state={s}:{s} reader={s}:{s} output={s}\n", .{
        Program.contract.requirements[0].label,
        @tagName(Program.contract.requirements[0].lifecycle_tag),
        Program.contract.requirements[1].label,
        @tagName(Program.contract.requirements[1].lifecycle_tag),
        Program.contract.outputs[0].label,
    });
}

/// Run the plan-native state/reader example.
pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
