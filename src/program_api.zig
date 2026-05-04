// zlinter-disable function_naming no_empty_block no_undefined no_swallow_error
const lowered_machine = @import("lowered_machine");
const lowering_api = @import("lowering_api");
const std = @import("std");

fn hasDeclSafe(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, name),
        else => false,
    };
}

fn dummyPointer(comptime PtrType: type) PtrType {
    const pointer = @typeInfo(PtrType).pointer;
    const Child = std.meta.Child(PtrType);
    if (pointer.size == .slice) {
        const many = @as([*]Child, @ptrFromInt(std.mem.alignForward(usize, 1, @alignOf(Child))));
        const slice = if (comptime pointer.sentinel()) |sentinel| many[0..1 :sentinel] else many[0..1];
        if (pointer.is_const) return @as(PtrType, slice);
        return @as(PtrType, @constCast(slice));
    }
    return @as(PtrType, @ptrFromInt(std.mem.alignForward(usize, 1, @alignOf(Child))));
}

fn dummyValue(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .pointer => dummyPointer(T),
        .optional => |optional| dummyValue(optional.child),
        .void => {},
        .@"struct" => |info| blk: {
            var value: T = undefined;
            inline for (info.fields) |field| {
                @field(value, field.name) = dummyValue(field.type);
            }
            break :blk value;
        },
        else => dummyPointer(*T).*,
    };
}

fn ProgramPlanForBody(comptime Body: type) lowering_api.ProgramPlan {
    if (!hasDeclSafe(Body, "compiled_plan")) {
        @compileError("ability.program bodies must declare pub const compiled_plan: ability.ir.ProgramPlan");
    }
    const plan = Body.compiled_plan;
    if (@TypeOf(plan) != lowering_api.ProgramPlan) {
        @compileError("Body.compiled_plan must have type ability.ir.ProgramPlan");
    }
    comptime {
        @setEvalBranchQuota(100_000);
        plan.validate() catch |err| {
            @compileError("Body.compiled_plan failed ProgramPlan.validate: " ++ @errorName(err));
        };
        validatePlanReturnErrors(plan, BodyErrorSet(Body));
    }
    return plan;
}

fn BodyErrorSet(comptime Body: type) type {
    if (comptime !hasDeclSafe(Body, "Error")) return error{};
    if (@typeInfo(Body.Error) != .error_set) @compileError("Body.Error must be an error set");
    return Body.Error;
}

fn errorSetContains(comptime ErrorSet: type, literal: []const u8) bool {
    return switch (@typeInfo(ErrorSet)) {
        .error_set => |errors| blk: {
            if (errors) |decls| {
                inline for (decls) |decl| {
                    if (std.mem.eql(u8, decl.name, literal)) break :blk true;
                }
            }
            break :blk false;
        },
        else => @compileError("Body.Error must be an error set"),
    };
}

fn validatePlanReturnErrors(comptime plan: lowering_api.ProgramPlan, comptime ErrorSet: type) void {
    for (plan.instructions) |instruction| {
        if (instruction.kind == .return_error and !errorSetContains(ErrorSet, instruction.string_literal)) {
            @compileError("Body.compiled_plan return_error is not declared in Body.Error: " ++ instruction.string_literal);
        }
    }
}

fn ProgramValueTypeForCodec(comptime codec: lowering_api.ValueCodec) type {
    return switch (codec) {
        .unit => void,
        .bool => bool,
        .i32 => i32,
        .product => @compileError("product ProgramPlan results require schema-specific ability.program decoding"),
        .usize => usize,
        .string => []const u8,
        .string_list => @compileError("string-list ProgramPlan results require interpreter value support"),
        .sum => @compileError("sum ProgramPlan results require schema-specific ability.program decoding"),
    };
}

fn ProgramErrorSet(comptime Body: type) type {
    if (comptime hasDeclSafe(Body, "Error")) return lowered_machine.ResetError(Body.Error);
    return anyerror;
}

/// Declare one reusable explicit local effect program.
pub fn program(
    comptime label: []const u8,
    comptime HandlersType: type,
    comptime Body: type,
) type {
    if (label.len == 0) @compileError("ability.program label must be non-empty");
    const body_compiled_plan = ProgramPlanForBody(Body);
    const Value = ProgramValueTypeForCodec(lowering_api.executableResultCodecForPlan(body_compiled_plan));
    const Outputs = void;

    return struct {
        /// Runtime-owned executable plan for this public program.
        pub const compiled_plan = body_compiled_plan;
        /// Public execution error for this program.
        pub const Error = ProgramErrorSet(Body);

        /// Public result value plus outputs. Cleanup is uniform even for void outputs.
        pub const Result = struct {
            allocator: std.mem.Allocator,
            value: Value,
            outputs: Outputs,

            /// Release owned result resources declared by the program body.
            pub fn deinit(self: *@This()) void {
                if (comptime hasDeclSafe(Body, "deinitResult")) {
                    const DeinitFn = @TypeOf(Body.deinitResult);
                    if (DeinitFn != fn (std.mem.Allocator, Value, Outputs) void) {
                        @compileError("Body.deinitResult must have type fn (std.mem.Allocator, value, outputs) void");
                    }
                    Body.deinitResult(self.allocator, self.value, self.outputs);
                }
            }
        };

        /// Execute the compiled ProgramPlan against one caller-owned runtime.
        pub fn run(runtime: *lowered_machine.Runtime, handlers: HandlersType) Error!Result {
            var mutable_handlers = handlers;
            const args = if (comptime hasDeclSafe(Body, "encodeArgs"))
                Body.encodeArgs(mutable_handlers)
            else
                &.{};
            const raw = lowering_api.runExecutablePlanWithArgsForErrorSet(BodyErrorSet(Body), runtime, compiled_plan, &mutable_handlers, args) catch |err| return @errorCast(err);
            return .{
                .allocator = lowered_machine.runtimeAllocator(runtime),
                .value = raw.value,
                .outputs = {},
            };
        }
    };
}

test "program rejects empty labels" {
    _ = program;
}
