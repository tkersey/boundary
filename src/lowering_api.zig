// zlinter-disable require_doc_comment
const lowered_machine = @import("lowered_machine");
const program_plan = @import("internal_program_plan");
const std = @import("std");

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
    comptime mode: program_plan.ControlMode,
) ?program_plan.ProgramPlan {
    return program_plan.authoredBoundPlan(label, Payload, Resume, Answer, mode);
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

fn RunResultTypeForPlan(comptime compiled_plan: program_plan.ProgramPlan) type {
    return struct {
        value: ValueTypeForCodec(program_plan.functionResultCodec(compiled_plan.functions[compiled_plan.entry_index])),
    };
}

fn decodeArg(
    comptime codec: program_plan.ValueCodec,
    value: lowered_machine.ProgramValue,
) error{ProgramContractViolation}!ValueTypeForCodec(codec) {
    return switch (codec) {
        .unit => switch (value) {
            .none => {},
            else => error.ProgramContractViolation,
        },
        .bool => switch (value) {
            .bool => |typed| typed,
            else => error.ProgramContractViolation,
        },
        .i32 => switch (value) {
            .i32 => |typed| typed,
            else => error.ProgramContractViolation,
        },
        .usize => switch (value) {
            .usize => |typed| typed,
            else => error.ProgramContractViolation,
        },
        .string => switch (value) {
            .string => |typed| typed,
            else => error.ProgramContractViolation,
        },
        .string_list => error.ProgramContractViolation,
    };
}

pub fn runExecutablePlanWithArgs(
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers: anytype,
    args: []const lowered_machine.ProgramValue,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    try lowered_machine.beginExecution(runtime);
    defer lowered_machine.endExecution(runtime);

    const entry = comptime compiled_plan.functions[compiled_plan.entry_index];
    if (args.len != entry.parameter_count) return error.ProgramContractViolation;
    if (comptime compiled_plan.ops.len != 1 or !std.mem.eql(u8, compiled_plan.ops[0].op_name, "dispatch")) {
        @compileError("lowering_api.runExecutablePlanWithArgs only supports authored bound single-dispatch plans");
    }
    const authored = &handlers.authored;
    const op = comptime compiled_plan.ops[0];
    const dispatched = switch (comptime op.payload_codec) {
        .unit => try authored.dispatch(),
        .bool => try authored.dispatch(try decodeArg(.bool, args[0])),
        .i32 => try authored.dispatch(try decodeArg(.i32, args[0])),
        .usize => try authored.dispatch(try decodeArg(.usize, args[0])),
        .string => try authored.dispatch(try decodeArg(.string, args[0])),
        .string_list => unreachable,
    };
    return switch (comptime op.mode) {
        .abort => .{ .value = dispatched },
        .transform => .{ .value = try authored.afterDispatch(dispatched) },
        .choice => switch (dispatched) {
            .resume_with => |resume_value| .{ .value = try authored.afterDispatch(resume_value) },
            .return_now => |answer| .{ .value = answer },
        },
    };
}
