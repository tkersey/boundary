// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

const reader_plan = boundary.effect.reader.plan;
const state_plan = boundary.effect.state.plan;

fn mustInstruction(result: anyerror!boundary.ir.plan.Instruction) boundary.ir.plan.Instruction {
    return result catch |err| std.debug.panic("invalid state/reader instruction: {s}", .{@errorName(err)});
}

fn mustPlan(result: anyerror!boundary.ir.ProgramPlan) boundary.ir.ProgramPlan {
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

fn stateReaderPlan() boundary.ir.ProgramPlan {
    const layout = boundary.ir.builder.layout;
    const root = comptime boundary.ir.builder.function(0);
    const env = comptime boundary.ir.builder.local(root, 0);
    const before = comptime boundary.ir.builder.local(root, 1);
    const next = comptime boundary.ir.builder.local(root, 2);
    const StateRows = state_plan.Rows("state", i32, error{}, .{
        .requirement_index = 0,
        .first_op = 0,
        .first_output = 0,
    });
    const ReaderRows = reader_plan.Rows("reader", i32, error{}, .{
        .requirement_index = 1,
        .first_op = StateRows.op_count,
        .first_output = StateRows.output_count,
    });
    const requirements = [_]boundary.ir.plan.Requirement{
        StateRows.requirement,
        ReaderRows.requirement,
    };
    const ops = StateRows.ops ++ ReaderRows.ops;
    const outputs = StateRows.outputs ++ ReaderRows.outputs;
    return mustPlan(boundary.ir.builder.layout.finish(.{
        .label = "plan-native-state-reader",
        .ir_hash = 50,
        .entry = root,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &outputs,
        .functions = .{.{
            .symbol_name = "run",
            .value_ref = boundary.ir.ValueRef{ .codec = .i32 },
            .result_ref = boundary.ir.ValueRef{ .codec = .i32 },
            .requirements = layout.span(0, 2),
            .outputs = layout.span(0, 1),
            .locals = .{
                reader_plan.envLocal(i32),
                state_plan.stateLocal(i32),
                state_plan.stateLocal(i32),
            },
            .blocks = .{.{
                .instructions = .{
                    mustInstruction(reader_plan.callAsk(root, env, reader_plan.askOp(root, StateRows.op_count))),
                    mustInstruction(state_plan.callGet(root, before, state_plan.getOp(root, 0))),
                    .{ .kind = .add_i32, .dst = next.index, .operand = before.index, .aux = env.index },
                    mustInstruction(state_plan.callSet(root, next, state_plan.setOp(root, 0))),
                    mustInstruction(boundary.ir.builder.returnValue(root, next)),
                },
                .terminator = boundary.ir.plan.Terminator{ .kind = .return_value },
            }},
        }},
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
    var runtime = boundary.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    var state: i32 = 5;
    const environment: i32 = 7;
    const Program = boundary.program("plan-native-state-reader", StateReaderHandlers, StateReaderBody);
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
