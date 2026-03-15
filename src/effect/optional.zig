const algebraic = @import("algebraic.zig");
const family = @import("family.zig");
const shift = @import("../root.zig");
const std = @import("std");

/// Prompt-backed effect instance for an optional-resumption family.
pub fn Instance(comptime ResumeType: type, comptime ErrorSetType: type) type {
    return family.InstanceWithMode(.resume_or_return, ResumeType, ErrorSetType);
}

/// Request a policy decision for the supplied capability and handled context.
pub inline fn request(
    comptime Cap: type,
    ctx: anytype,
) shift.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!family.ContextStateType(@TypeOf(ctx)) {
    return try algebraic.optionalRequest(Cap, ctx);
}

/// Build one explicit optional request program for the supplied continuation.
pub inline fn requestProgram(
    comptime Cap: type,
    ctx: anytype,
    comptime Continuation: type,
) @TypeOf(algebraic.optionalRequestProgram(Cap, ctx, Continuation)) {
    return algebraic.optionalRequestProgram(Cap, ctx, Continuation);
}

/// Build one explicit optional body program with no request operation.
pub inline fn computeProgram(
    comptime Cap: type,
    ctx: anytype,
    thunk: anytype,
) @TypeOf(algebraic.optionalComputeProgram(Cap, ctx, thunk)) {
    return algebraic.optionalComputeProgram(Cap, ctx, thunk);
}

/// Run an optional-resumption effect body and return the final handler answer.
pub fn handle(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Policy: type,
    comptime Body: type,
) shift.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    return try algebraic.handleOptional(AnswerType, runtime, instance, Policy, Body);
}

test "optional instance shell stays prompt-sized" {
    const NoError = error{};
    const OptionalInstance = Instance(i32, NoError);
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(OptionalInstance));
}

test "optional handle can return now without resuming the body tail" {
    const NoError = error{};
    const OptionalInstance = Instance(i32, NoError);
    const policy = struct {
        /// Choose the direct-return branch for this optional-family test.
        pub fn resumeOrReturn() shift.ResumeOrReturn(i32, []const u8) {
            return shift.ResumeOrReturn(i32, []const u8).returnNow("result=early");
        }

        /// Preserve the late answer if this branch were ever resumed.
        pub fn afterResume(_: i32) []const u8 {
            return "result=late";
        }
    };
    const demo = struct {
        var after_request: bool = false;

        /// Attempt one optional request and prove the body tail never runs.
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(requestProgram(Cap, ctx, struct {
            /// Mark that the request continuation resumed unexpectedly.
            pub fn apply(_: i32) i32 {
                after_request = true;
                return 0;
            }
        })) {
            return requestProgram(Cap, ctx, struct {
                /// Mark that the request continuation resumed unexpectedly.
                pub fn apply(_: i32) i32 {
                    after_request = true;
                    return 0;
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = OptionalInstance.init();
    demo.after_request = false;
    const result = try handle([]const u8, &runtime, &instance, policy, demo);
    try std.testing.expectEqualStrings("result=early", result);
    try std.testing.expect(!demo.after_request);
}

test "optional handle can resume and transform the resumed answer" {
    const NoError = error{};
    const OptionalInstance = Instance(i32, NoError);
    const policy = struct {
        /// Resume the optional request with a known value.
        pub fn resumeOrReturn() shift.ResumeOrReturn(i32, []const u8) {
            return shift.ResumeOrReturn(i32, []const u8).resumeWith(41);
        }

        /// Convert the resumed answer into the enclosing result.
        pub fn afterResume(value: i32) []const u8 {
            if (value != 42) unreachable;
            return "answer=42";
        }
    };
    const demo = struct {
        /// Request once and increment the resumed answer.
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(requestProgram(Cap, ctx, struct {
            /// Increment the resumed optional answer.
            pub fn apply(current: i32) i32 {
                return current + 1;
            }
        })) {
            return requestProgram(Cap, ctx, struct {
                /// Increment the resumed optional answer.
                pub fn apply(current: i32) i32 {
                    return current + 1;
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = OptionalInstance.init();
    const result = try handle([]const u8, &runtime, &instance, policy, demo);
    try std.testing.expectEqualStrings("answer=42", result);
}

test "nested same-shaped optional handles get distinct capability types" {
    const NoError = error{};
    const OptionalInstance = Instance(i32, NoError);
    const policy = struct {
        /// Resume the nested optional test with a neutral value.
        pub fn resumeOrReturn() shift.ResumeOrReturn(i32, i32) {
            return shift.ResumeOrReturn(i32, i32).resumeWith(0);
        }

        /// Preserve the resumed answer in the nested optional test.
        pub fn afterResume(value: i32) i32 {
            return value;
        }
    };
    const demo = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var inner_ptr: ?*const OptionalInstance = null;

        /// Open an inner optional handle and compare its capability type.
        pub fn outer(comptime OuterCap: type, _: anytype) shift.ResetError(NoError)!i32 {
            return try handle(i32, runtime_ptr.?, inner_ptr.?, policy, struct {
                /// Reject capability-type collapse inside the nested handle.
                pub fn program(comptime InnerCap: type, inner_ctx: anytype) @TypeOf(computeProgram(InnerCap, inner_ctx, struct {
                    /// Return a neutral value from the nested optional body.
                    pub fn run() i32 {
                        return 0;
                    }
                }.run)) {
                    comptime if (OuterCap == InnerCap) {
                        @compileError("nested optional handles must receive distinct capability types");
                    };
                    return computeProgram(InnerCap, inner_ctx, struct {
                        /// Return a neutral value from the nested optional body.
                        pub fn run() i32 {
                            return 0;
                        }
                    }.run);
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var outer_instance = OptionalInstance.init();
    var inner_instance = OptionalInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    const result = try handle(i32, &runtime, &outer_instance, policy, struct {
        /// Enter the outer optional handle and hand its capability inward.
        pub fn program(comptime OuterCap: type, ctx: anytype) @TypeOf(computeProgram(OuterCap, ctx, struct {
            /// Re-enter the nested optional witness through the outer capability.
            pub fn run() shift.ResetError(NoError)!i32 {
                return try demo.outer(OuterCap, {});
            }
        }.run)) {
            return computeProgram(OuterCap, ctx, struct {
                /// Re-enter the nested optional witness through the outer capability.
                pub fn run() shift.ResetError(NoError)!i32 {
                    return try demo.outer(OuterCap, {});
                }
            }.run);
        }
    });
    try std.testing.expectEqual(@as(i32, 0), result);
}
