// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

fn mustInstruction(result: anyerror!boundary.ir.plan.Instruction) boundary.ir.plan.Instruction {
    return result catch |err| std.debug.panic("invalid state-basic instruction: {s}", .{@errorName(err)});
}

fn mustPlan(result: anyerror!boundary.ir.ProgramPlan) boundary.ir.ProgramPlan {
    return result catch |err| std.debug.panic("invalid state-basic plan: {s}", .{@errorName(err)});
}

const StateHandlers = struct {
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
};

fn statePlan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const before = boundary.ir.builder.local(root, 0);
    const next = boundary.ir.builder.local(root, 1);
    const after = boundary.ir.builder.local(root, 2);
    const total = boundary.ir.builder.local(root, 3);
    const instructions = [_]boundary.ir.plan.Instruction{
        mustInstruction(boundary.ir.builder.callOp(root, before, boundary.ir.builder.op(root, 0), null)),
        .{ .kind = .add_const_i32, .dst = next.index, .operand = before.index, .aux = 1 },
        mustInstruction(boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 1), next)),
        mustInstruction(boundary.ir.builder.callOp(root, after, boundary.ir.builder.op(root, 0), null)),
        .{ .kind = .add_i32, .dst = total.index, .operand = before.index, .aux = after.index },
        mustInstruction(boundary.ir.builder.returnValue(root, total)),
    };
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 4,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]boundary.ir.plan.Requirement{.{ .label = "state", .first_op = 0, .op_count = 2 }};
    const ops = [_]boundary.ir.plan.Op{
        .{ .requirement_index = 0, .op_name = "get", .mode = .transform, .payload_codec = .unit, .resume_codec = .i32 },
        .{ .requirement_index = 0, .op_name = "set", .mode = .transform, .payload_codec = .i32, .resume_codec = .unit },
    };
    const blocks = [_]boundary.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};

    return mustPlan(boundary.ir.builder.finish(.{
        .label = "state-basic",
        .ir_hash = 10,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 }, .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }));
}

const StateBody = struct {
    pub const compiled_plan = statePlan();
};

/// Write the state-effect transcript through an explicit reusable program.
pub fn run(writer: anytype) anyerror!void {
    var runtime = boundary.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    var state: i32 = 5;
    const Program = boundary.program("state-basic", StateHandlers, StateBody);
    var result = try Program.run(&runtime, .{
        .get = .{ .state = &state },
        .set = .{ .state = &state },
    });
    defer result.deinit();

    try writer.print("before=5\nafter=6\nfinal_state={d}\nvalue={d}\n", .{ state, result.value });
}

/// Run the state-effect example.
pub fn main(init: std.process.Init) anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
