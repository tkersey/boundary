// zlinter-disable require_doc_comment
const lowered_machine = @import("lowered_machine");
const program_plan = @import("internal_program_plan");

pub const ProgramPlan = program_plan.ProgramPlan;
pub const ValueCodec = program_plan.ValueCodec;

pub fn executableResultCodecForType(comptime T: type) program_plan.CodecError!program_plan.ValueCodec {
    return program_plan.codecForType(T);
}

pub fn authoredBoundProgramPlan(
    comptime label: []const u8,
    comptime Payload: type,
    comptime Resume: type,
    comptime Answer: type,
    comptime mode: anytype,
) ?program_plan.ProgramPlan {
    _ = label;
    _ = Payload;
    _ = Resume;
    _ = Answer;
    _ = mode;
    return null;
}

fn ValueTypeForCodec(comptime codec: program_plan.ValueCodec) type {
    return switch (codec) {
        .unit => void,
        .bool => bool,
        .i32 => i32,
        .usize => usize,
        .string => []const u8,
        .string_list => []const []const u8,
    };
}

pub fn runExecutablePlanWithArgs(
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers: anytype,
    args: []const lowered_machine.ProgramValue,
) anyerror!struct { value: ValueTypeForCodec(compiled_plan.result_codec) } {
    _ = runtime;
    _ = handlers;
    _ = args;
    return error.ProgramContractViolation;
}
