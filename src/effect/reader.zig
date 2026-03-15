const algebraic = @import("algebraic.zig");
const family = @import("family.zig");
const shift = @import("../root.zig");
const std = @import("std");

/// Prompt-backed effect instance for a reader family.
pub const Instance = family.Instance;

/// Read the current environment value for the supplied capability and handled context.
pub inline fn ask(
    comptime Cap: type,
    ctx: anytype,
) shift.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!family.ContextStateType(@TypeOf(ctx)) {
    return try algebraic.readTransformState(Cap, ctx);
}

/// Run a reader effect body and return the body answer.
pub fn handle(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    environment: family.InstanceStateType(@TypeOf(instance)),
    comptime Body: type,
) shift.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    const result = try family.handle(AnswerType, runtime, instance, environment, Body);
    return result.value;
}

test "reader instance shell stays prompt-sized" {
    const NoError = error{};
    const ReaderInstance = Instance(i32, NoError);
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(ReaderInstance));
}

test "reader handle threads environment into the body" {
    const NoError = error{};
    const ReaderInstance = Instance(i32, NoError);
    const demo = struct {
        /// Execute the reader body by asking for the environment once.
        pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)!i32 {
            return try ask(Cap, ctx);
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = ReaderInstance.init();
    const result = try handle(i32, &runtime, &instance, 21, demo);
    try std.testing.expectEqual(@as(i32, 21), result);
}

test "nested same-shaped reader handles get distinct capability types" {
    const NoError = error{};
    const ReaderInstance = Instance(i32, NoError);
    const demo = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var inner_ptr: ?*const ReaderInstance = null;

        /// Open an inner reader handle and prove its capability type differs from the outer one.
        pub fn outer(comptime OuterCap: type, _: anytype) shift.ResetError(NoError)!i32 {
            return try handle(i32, runtime_ptr.?, inner_ptr.?, 0, struct {
                /// Reject capability-type collapse inside the nested reader handle.
                pub fn body(comptime InnerCap: type, _: anytype) shift.ResetError(NoError)!i32 {
                    comptime if (OuterCap == InnerCap) {
                        @compileError("nested reader handles must receive distinct capability types");
                    };
                    return 0;
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var outer_instance = ReaderInstance.init();
    var inner_instance = ReaderInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    const result = try handle(i32, &runtime, &outer_instance, 0, struct {
        /// Enter the outer reader handle and hand its capability to the nested check.
        pub fn body(comptime OuterCap: type, ctx: anytype) shift.ResetError(NoError)!i32 {
            return try demo.outer(OuterCap, ctx);
        }
    });
    try std.testing.expectEqual(@as(i32, 0), result);
}
