// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

fn mustInstruction(result: anyerror!ability.ir.plan.Instruction) ability.ir.plan.Instruction {
    return result catch |err| std.debug.panic("invalid writer instruction: {s}", .{@errorName(err)});
}

fn mustPlan(result: anyerror!ability.ir.ProgramPlan) ability.ir.ProgramPlan {
    return result catch |err| std.debug.panic("invalid writer plan: {s}", .{@errorName(err)});
}

const WriterHandlers = struct {
    tell: struct {
        values: *[8]i32,
        count: *usize,

        pub fn dispatch(self: *const @This(), value: i32) !void {
            self.values[self.count.*] = value;
            self.count.* += 1;
        }
    },
};

fn writerPlan() ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const first = ability.ir.builder.local(root, 0);
    const second = ability.ir.builder.local(root, 1);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = first.index, .operand = 4 },
        mustInstruction(ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 0), first)),
        .{ .kind = .const_i32, .dst = second.index, .operand = 8 },
        mustInstruction(ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 0), second)),
    };
    const WriterRows = ability.ir.schema.LowerBinding(
        ability.ir.schema.Binding("writer", ability.effect.writer.Schema(i32, error{}), void),
        .{ .requirement_index = 0, .first_op = 0, .first_output = 0 },
    );
    const requirements = [_]ability.ir.plan.Requirement{WriterRows.requirement};
    const ops = WriterRows.ops;
    const outputs = WriterRows.outputs;
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 1,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};

    return mustPlan(ability.ir.builder.finish(.{
        .label = "plan-native-writer",
        .ir_hash = 60,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &outputs,
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }));
}

const Cleanup = struct {
    var outputs_deinitialized = false;
};

const WriterBody = struct {
    pub const Outputs = []i32;
    pub const compiled_plan = writerPlan();

    pub fn collectOutputs(allocator: std.mem.Allocator, handlers: *WriterHandlers) !Outputs {
        const outputs = try allocator.alloc(i32, handlers.tell.count.*);
        @memcpy(outputs, handlers.tell.values[0..handlers.tell.count.*]);
        return outputs;
    }

    pub fn deinitOutputs(allocator: std.mem.Allocator, outputs: Outputs) void {
        Cleanup.outputs_deinitialized = true;
        allocator.free(outputs);
    }
};

pub fn run(writer: anytype) !void {
    var runtime = ability.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    var values = [_]i32{0} ** 8;
    var count: usize = 0;
    const Program = ability.program("plan-native-writer", WriterHandlers, WriterBody);
    Cleanup.outputs_deinitialized = false;
    var result = try Program.run(&runtime, .{ .tell = .{ .values = &values, .count = &count } });
    try writer.print("outputs={d},{d} count={d}\n", .{ result.outputs[0], result.outputs[1], result.outputs.len });
    result.deinit();
    try writer.print("cleanup={any} contract={s}:{s}\n", .{
        Cleanup.outputs_deinitialized,
        Program.contract.outputs[0].label,
        @tagName(Program.contract.requirements[0].lifecycle_tag),
    });
}

/// Run the plan-native writer example.
pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
