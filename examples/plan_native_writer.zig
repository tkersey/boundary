// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

const writer_plan = ability.effect.writer.plan;

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
    const layout = ability.ir.builder.layout;
    const root = comptime ability.ir.builder.function(0);
    const first = comptime ability.ir.builder.local(root, 0);
    const second = comptime ability.ir.builder.local(root, 1);
    const WriterRows = writer_plan.Rows("writer", i32, error{}, .{
        .requirement_index = 0,
        .first_op = 0,
        .first_output = 0,
    });
    const requirements = [_]ability.ir.plan.Requirement{WriterRows.requirement};
    const ops = WriterRows.ops;
    const outputs = WriterRows.outputs;

    return mustPlan(ability.ir.builder.layout.finish(.{
        .label = "plan-native-writer",
        .ir_hash = 60,
        .entry = root,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &outputs,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = layout.span(0, 1),
            .outputs = layout.span(0, 1),
            .locals = .{
                writer_plan.itemLocal(i32),
                writer_plan.itemLocal(i32),
            },
            .blocks = .{.{
                .instructions = .{
                    .{ .kind = .const_i32, .dst = first.index, .operand = 4 },
                    mustInstruction(writer_plan.callTell(root, first, writer_plan.tellOp(root, 0))),
                    .{ .kind = .const_i32, .dst = second.index, .operand = 8 },
                    mustInstruction(writer_plan.callTell(root, second, writer_plan.tellOp(root, 0))),
                },
                .terminator = ability.ir.plan.Terminator{ .kind = .return_unit },
            }},
        }},
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
