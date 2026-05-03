// zlinter-disable function_naming no_empty_block no_undefined no_swallow_error
const lowered_machine = @import("lowered_machine");
const std = @import("std");

fn hasDeclSafe(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, name),
        else => false,
    };
}

fn hasFieldSafe(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => @hasField(T, name),
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

fn ProgramReturnType(comptime HandlersType: type, comptime Body: type) type {
    if (!hasDeclSafe(Body, "program")) {
        @compileError("ability.program bodies must declare pub fn program(runtime, handlers)");
    }
    return @TypeOf(Body.program(dummyValue(*lowered_machine.Runtime), dummyValue(HandlersType)));
}

fn ProgramValueType(comptime ReturnType: type) type {
    const Payload = switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.payload,
        else => ReturnType,
    };
    if (comptime hasFieldSafe(Payload, "value")) return @FieldType(Payload, "value");
    return Payload;
}

fn ProgramOutputsType(comptime ReturnType: type) type {
    const Payload = switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.payload,
        else => ReturnType,
    };
    if (comptime hasFieldSafe(Payload, "outputs")) return @FieldType(Payload, "outputs");
    return void;
}

fn ProgramErrorSet(comptime ReturnType: type) type {
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| lowered_machine.ResetError(err_union.error_set),
        else => lowered_machine.ResetError(error{}),
    };
}

/// Declare one reusable explicit local effect program.
pub fn program(
    comptime label: []const u8,
    comptime HandlersType: type,
    comptime Body: type,
) type {
    if (label.len == 0) @compileError("ability.program label must be non-empty");
    const ReturnType = ProgramReturnType(HandlersType, Body);
    const Value = ProgramValueType(ReturnType);
    const Outputs = ProgramOutputsType(ReturnType);

    return struct {
        /// Public execution error for this program.
        pub const Error = ProgramErrorSet(ReturnType);

        /// Public result value plus outputs. Cleanup is uniform even for void outputs.
        pub const Result = struct {
            allocator: std.mem.Allocator,
            value: Value,
            outputs: Outputs,

            /// Release owned result resources. Current explicit programs own no hidden storage.
            pub fn deinit(self: *@This()) void {
                _ = self.allocator;
            }
        };

        /// Execute the explicit body against one caller-owned runtime.
        pub fn run(runtime: *lowered_machine.Runtime, handlers: HandlersType) Error!Result {
            try lowered_machine.beginExecution(runtime);
            defer lowered_machine.endExecution(runtime);

            const raw = if (comptime @typeInfo(ReturnType) == .error_union)
                Body.program(runtime, handlers) catch |err| return @errorCast(err)
            else
                Body.program(runtime, handlers);
            const payload = raw;
            const value = if (comptime hasFieldSafe(@TypeOf(payload), "value")) payload.value else payload;
            const outputs = if (comptime hasFieldSafe(@TypeOf(payload), "outputs")) payload.outputs else {};
            return .{
                .allocator = lowered_machine.runtimeAllocator(runtime),
                .value = value,
                .outputs = outputs,
            };
        }
    };
}

test "program rejects empty labels" {
    _ = program;
}
