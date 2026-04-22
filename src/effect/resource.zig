const algebraic = @import("algebraic.zig");
const effect_schema = @import("../effect_schema.zig");
const family = @import("family.zig");
const lexical_with = @import("../with_api.zig");
const lowered_machine = @import("lowered_machine");
const prompt_contract = @import("prompt_contract_support");
const shift = lowered_machine;
const std = @import("std");

fn ReturnTypeErrorSet(comptime ReturnType: type) type {
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.error_set,
        else => error{},
    };
}

fn ManagerErrorSet(comptime Manager: type) type {
    return ReturnTypeErrorSet(@typeInfo(@TypeOf(Manager.acquire)).@"fn".return_type.?) ||
        ReturnTypeErrorSet(@typeInfo(@TypeOf(Manager.release)).@"fn".return_type.?);
}

/// Prompt-backed effect instance for a bracketed resource family.
pub fn Instance(comptime ResourceType: type, comptime ErrorSetType: type) type {
    return family.InstanceWithMode(.resume_then_transform, ResourceType, ErrorSetType);
}

/// Lexical resource handle used by `shift.withAt(@src(), ...)`.
pub fn LexicalHandle(comptime Cap: type, comptime ContextPtrType: type) type {
    return struct {
        ctx: ?ContextPtrType,

        /// Acquire one resource through the lexical handle.
        pub fn acquire(self: @This()) lowered_machine.ResetError(family.ContextErrorSetType(ContextPtrType))!family.ContextStateType(ContextPtrType) {
            return try algebraic.acquireResource(Cap, self.ctx.?);
        }
    };
}

/// Descriptor value used by `shift.withAt(@src(), ...)` for the built-in resource family.
pub fn LexicalDescriptor(comptime ResourceType: type, comptime ErrorSetType: type, comptime Manager: type) type {
    return struct {
        /// Shared error set carried by the lexical resource descriptor.
        pub const ErrorSet = ErrorSetType;
        /// Resource type threaded through the lexical resource context.
        pub const State = ResourceType;
        /// Resource lexical descriptors do not surface an extra output value.
        pub const Output = void;

        /// Resolve the lexical resource handle type for one exact context.
        pub fn HandleType(comptime Cap: type, comptime ContextPtrType: type) type {
            return LexicalHandle(Cap, ContextPtrType);
        }

        /// Bind one lexical resource handle to the active exact context.
        pub fn bindLexical(self: @This(), comptime Cap: type, ctx: anytype) HandleType(Cap, @TypeOf(ctx)) {
            _ = self;
            return .{ .ctx = ctx };
        }

        /// Return the shared binding schema for this lexical descriptor under one requirement label.
        pub fn BindingSchema(comptime requirement_label: [:0]const u8) type {
            return effect_schema.Binding(requirement_label, Schema(ResourceType, ErrorSetType, Manager), struct {});
        }

        /// Run one lexical resource descriptor through the existing resource family.
        pub fn run(self: @This(), comptime AnswerType: type, comptime RunErrorSetType: type, run_ctx: anytype, comptime Body: type) lowered_machine.ResetError(RunErrorSetType)!lexical_with.DescriptorResult(Output, AnswerType) {
            _ = self;
            var instance = family.InstanceWithMode(.resume_then_transform, ResourceType, ErrorSetType).init();
            const result = try algebraic.handleResourceWithErrorSetLexicalAt(AnswerType, RunErrorSetType, @TypeOf(run_ctx).caller_source, .{
                .runtime = run_ctx.runtime,
                .instance = &instance,
                .lexical_state = @constCast(run_ctx.lexical_state),
            }, Manager, Body);
            return .{
                .output = {},
                .value = result,
            };
        }
    };
}

/// Create one lexical resource descriptor for `shift.withAt(@src(), ...)`.
pub fn use(comptime ResourceType: type, comptime Manager: type) LexicalDescriptor(ResourceType, ManagerErrorSet(Manager), Manager) {
    return .{};
}

/// Shared effect schema for the built-in resource family.
pub fn Schema(comptime ResourceType: type, comptime ErrorSetType: type, comptime Manager: type) type {
    return effect_schema.resource_bracket(ResourceType, ErrorSetType, Manager);
}

/// Acquire one resource under the supplied capability and handled context.
pub inline fn acquire(
    comptime Cap: type,
    ctx: anytype,
) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!family.ContextStateType(@TypeOf(ctx)) {
    return try algebraic.acquireResource(Cap, ctx);
}

/// Build one explicit resource body program with no prompt operation.
pub inline fn computeProgram(
    comptime Cap: type,
    ctx: anytype,
    comptime Thunk: type,
) @TypeOf(algebraic.resourceComputeProgram(Cap, ctx, Thunk)) {
    return algebraic.resourceComputeProgram(Cap, ctx, Thunk);
}

/// Run a resource effect body and guarantee LIFO cleanup of acquired resources.
pub fn handle(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Manager: type,
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    return try algebraic.handleResource(null, AnswerType, runtime, instance, Manager, Body);
}

/// Run a resource effect body with explicit caller provenance and guarantee LIFO cleanup of acquired resources.
pub fn handleAt(
    comptime caller_source: std.builtin.SourceLocation,
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Manager: type,
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    return try algebraic.handleResource(caller_source, AnswerType, runtime, instance, Manager, Body);
}

/// Public `handleWithErrorSet` helper.
// zlinter-disable max_positional_args - public caller provenance and manager inputs stay explicit at this compatibility wrapper.
pub fn handleWithErrorSet(
    comptime AnswerType: type,
    comptime RunErrorSetType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Manager: type,
    comptime Body: type,
) lowered_machine.ResetError(RunErrorSetType)!AnswerType {
    return try algebraic.handleResourceWithErrorSet(null, AnswerType, RunErrorSetType, runtime, instance, Manager, Body);
}

/// Public `handleWithErrorSetAt` helper.
// zlinter-disable max_positional_args - public caller provenance and manager inputs stay explicit at this compatibility wrapper.
pub fn handleWithErrorSetAt(
    comptime caller_source: std.builtin.SourceLocation,
    comptime AnswerType: type,
    comptime RunErrorSetType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Manager: type,
    comptime Body: type,
) lowered_machine.ResetError(RunErrorSetType)!AnswerType {
    return try algebraic.handleResourceWithErrorSet(caller_source, AnswerType, RunErrorSetType, runtime, instance, Manager, Body);
}

test "resource instance shell stays prompt-sized" {
    const ResourceInstance = Instance(i32, error{});
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(ResourceInstance));
}

test "resource handle releases in LIFO order after normal completion" {
    const NoError = error{};
    const ResourceInstance = Instance([]const u8, NoError);
    const manager = struct {
        var next_index: usize = 0;
        var transcript = [_][]const u8{ "", "", "", "", "", "" };
        var transcript_len: usize = 0;
        const resources = [_][]const u8{ "a", "b" };

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        /// Hand out resources in a fixed order for the normal resource test.
        pub fn acquire() []const u8 {
            const resource = resources[next_index];
            next_index += 1;
            note(resource);
            return resource;
        }

        /// Record release order for the normal resource test.
        pub fn release(resource: []const u8) void {
            note(resource);
        }
    };
    const demo = struct {
        /// Acquire two resources in order and return normally.
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(computeProgram(Cap, ctx, struct {
            /// Acquire two resources in order and return normally.
            pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
                const first = try acquire(ProgramCap, program_ctx);
                manager.note(first);
                const second = try acquire(ProgramCap, program_ctx);
                manager.note(second);
                return "done";
            }
        })) {
            return computeProgram(Cap, ctx, struct {
                /// Acquire two resources in order and return normally.
                pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
                    const first = try acquire(ProgramCap, program_ctx);
                    manager.note(first);
                    const second = try acquire(ProgramCap, program_ctx);
                    manager.note(second);
                    return "done";
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = ResourceInstance.init();
    manager.next_index = 0;
    manager.transcript_len = 0;
    const result = try handleAt(@src(), []const u8, &runtime, &instance, manager, demo);
    try std.testing.expectEqualStrings("done", result);
    try std.testing.expectEqualStrings("a", manager.transcript[0]);
    try std.testing.expectEqualStrings("a", manager.transcript[1]);
    try std.testing.expectEqualStrings("b", manager.transcript[2]);
    try std.testing.expectEqualStrings("b", manager.transcript[3]);
    try std.testing.expectEqualStrings("b", manager.transcript[4]);
    try std.testing.expectEqualStrings("a", manager.transcript[5]);
}

test "resource handle releases before outer exception catch returns" {
    const NoError = error{};
    const ResourceInstance = Instance([]const u8, NoError);
    const ExceptionInstance = @import("exception.zig").Instance([]const u8, NoError);

    const manager = struct {
        var transcript = [_][]const u8{ "", "", "", "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        /// Acquire one named resource for the abortive cleanup test.
        pub fn acquire() []const u8 {
            note("acquire=r");
            return "r";
        }

        /// Release the named resource before the outer catch runs.
        pub fn release(resource: []const u8) void {
            _ = resource;
            note("release=r");
        }
    };

    const catcher = struct {
        /// Record the catch after resource cleanup has already happened.
        pub fn directReturn(payload: []const u8) []const u8 {
            _ = payload;
            manager.note("catch=boom");
            return "handled=boom";
        }
    };

    const scenario = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var resource_ptr: ?*const ResourceInstance = null;
        var outer_exception_ctx: ?*const anyopaque = null;

        /// Open a resource handle and throw through the outer exception capability.
        pub fn outer(comptime ExceptionCap: type, exception_ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
            const ExceptionCtxType = @TypeOf(exception_ctx);
            const inner = struct {
                var active_exception_ctx: ?ExceptionCtxType = null;

                /// Acquire once, then abort through the outer exception handler.
                pub fn program(comptime ResourceCap: type, resource_ctx: anytype) @TypeOf(computeProgram(ResourceCap, resource_ctx, struct {
                    /// Acquire once, then abort through the outer exception handler.
                    pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
                        const resource = try acquire(ProgramCap, program_ctx);
                        _ = resource;
                        manager.note("use=r");
                        try @import("exception.zig").throw(ExceptionCap, active_exception_ctx.?, "boom");
                    }
                })) {
                    return computeProgram(ResourceCap, resource_ctx, struct {
                        /// Acquire once, then abort through the outer exception handler.
                        pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
                            const resource = try acquire(ProgramCap, program_ctx);
                            _ = resource;
                            manager.note("use=r");
                            try @import("exception.zig").throw(ExceptionCap, active_exception_ctx.?, "boom");
                        }
                    });
                }
            };

            const previous_exception_ctx = inner.active_exception_ctx;
            inner.active_exception_ctx = exception_ctx;
            defer inner.active_exception_ctx = previous_exception_ctx;
            return try handleAt(@src(), []const u8, runtime_ptr.?, resource_ptr.?, manager, inner);
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var exception_instance = ExceptionInstance.init();
    var resource_instance = ResourceInstance.init();
    scenario.runtime_ptr = &runtime;
    scenario.resource_ptr = &resource_instance;
    manager.transcript_len = 0;
    const result = try @import("exception.zig").handleAt(@src(), []const u8, &runtime, &exception_instance, catcher, struct {
        /// Enter the outer exception handle and hand its capability to the inner resource scope.
        pub fn program(comptime ExceptionCap: type, exception_ctx: anytype) @TypeOf(@import("exception.zig").computeProgram(ExceptionCap, exception_ctx, struct {
            /// Re-enter the resource witness through the outer exception capability.
            pub fn run() lowered_machine.ResetError(NoError)![]const u8 {
                const ExceptionCtxType = @TypeOf(exception_ctx);
                const ctx: ExceptionCtxType = @ptrCast(@alignCast(@constCast(scenario.outer_exception_ctx.?)));
                scenario.outer_exception_ctx = null;
                return try scenario.outer(ExceptionCap, ctx);
            }
        }.run)) {
            scenario.outer_exception_ctx = @ptrCast(exception_ctx);
            return @import("exception.zig").computeProgram(ExceptionCap, exception_ctx, struct {
                /// Re-enter the resource witness through the outer exception capability.
                pub fn run() lowered_machine.ResetError(NoError)![]const u8 {
                    const ExceptionCtxType = @TypeOf(exception_ctx);
                    const ctx: ExceptionCtxType = @ptrCast(@alignCast(@constCast(scenario.outer_exception_ctx.?)));
                    scenario.outer_exception_ctx = null;
                    return try scenario.outer(ExceptionCap, ctx);
                }
            }.run);
        }
    });
    try std.testing.expectEqualStrings("handled=boom", result);
    try std.testing.expectEqualStrings("acquire=r", manager.transcript[0]);
    try std.testing.expectEqualStrings("use=r", manager.transcript[1]);
    try std.testing.expectEqualStrings("release=r", manager.transcript[2]);
    try std.testing.expectEqualStrings("catch=boom", manager.transcript[3]);
}

test "public resource handleWithErrorSet leaves caller provenance absent by default" {
    const NoError = error{};
    const ResourceInstance = Instance([]const u8, NoError);
    const manager = struct {
        /// Return one resource for provenance verification.
        pub fn acquire() []const u8 {
            return "resource";
        }

        /// Release the borrowed resource with no extra effect.
        pub fn release(_: []const u8) void {
            // This provenance witness only needs the resource bracket shape.
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = ResourceInstance.init();

    const result = try handleWithErrorSet([]const u8, NoError, &runtime, &instance, manager, struct {
        /// Report whether the source-compatible resource wrapper leaves caller provenance absent.
        pub fn body(comptime Cap: type, ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
            _ = try acquire(Cap, ctx);
            return if (@TypeOf(ctx.*).caller_source == null) "absent" else "present";
        }
    });

    try std.testing.expectEqualStrings("absent", result);
}

test "resource handle releases before outer optional return-now completes" {
    const NoError = error{};
    const ResourceInstance = Instance([]const u8, NoError);
    const OptionalInstance = @import("optional.zig").Instance([]const u8, NoError);

    const manager = struct {
        var transcript = [_][]const u8{ "", "", "", "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        /// Acquire one named resource for the optional-return cleanup test.
        pub fn acquire() []const u8 {
            note("acquire=r");
            return "r";
        }

        /// Release the named resource before the outer optional answer completes.
        pub fn release(resource: []const u8) void {
            _ = resource;
            note("release=r");
        }
    };

    const policy = struct {
        /// Return the enclosing optional answer after resource cleanup has run.
        pub fn resumeOrReturn() prompt_contract.ResumeOrReturn([]const u8, []const u8) {
            manager.note("policy-return-now");
            return prompt_contract.ResumeOrReturn([]const u8, []const u8).returnNow("result=early");
        }

        /// Preserve the resumed answer if this branch were ever resumed.
        pub fn afterResume(value: []const u8) []const u8 {
            return value;
        }
    };

    const scenario = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var resource_ptr: ?*const ResourceInstance = null;
        var outer_optional_ctx: ?*const anyopaque = null;

        /// Open a resource handle and trigger the outer optional return-now branch.
        pub fn outer(comptime OptionalCap: type, optional_ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
            const OptionalCtxType = @TypeOf(optional_ctx);
            const inner = struct {
                var active_optional_ctx: ?OptionalCtxType = null;

                /// Acquire once, then early-return through the outer optional handler.
                pub fn program(comptime ResourceCap: type, resource_ctx: anytype) @TypeOf(computeProgram(ResourceCap, resource_ctx, struct {
                    /// Acquire once, then early-return through the outer optional handler.
                    pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
                        const resource = try acquire(ProgramCap, program_ctx);
                        _ = resource;
                        manager.note("use=r");
                        _ = try @import("optional.zig").request(OptionalCap, active_optional_ctx.?);
                        return "result=late";
                    }
                })) {
                    return computeProgram(ResourceCap, resource_ctx, struct {
                        /// Acquire once, then early-return through the outer optional handler.
                        pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
                            const resource = try acquire(ProgramCap, program_ctx);
                            _ = resource;
                            manager.note("use=r");
                            _ = try @import("optional.zig").request(OptionalCap, active_optional_ctx.?);
                            return "result=late";
                        }
                    });
                }
            };

            const previous_optional_ctx = inner.active_optional_ctx;
            inner.active_optional_ctx = optional_ctx;
            defer inner.active_optional_ctx = previous_optional_ctx;
            return try handleAt(@src(), []const u8, runtime_ptr.?, resource_ptr.?, manager, inner);
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var optional_instance = OptionalInstance.init();
    var resource_instance = ResourceInstance.init();
    scenario.runtime_ptr = &runtime;
    scenario.resource_ptr = &resource_instance;
    manager.transcript_len = 0;
    const result = try @import("optional.zig").handleAt(@src(), []const u8, &runtime, &optional_instance, policy, struct {
        /// Enter the outer optional handle and hand its capability to the inner resource scope.
        pub fn program(comptime OptionalCap: type, optional_ctx: anytype) @TypeOf(@import("optional.zig").computeProgram(OptionalCap, optional_ctx, struct {
            /// Re-enter the resource witness through the outer optional capability.
            pub fn run() lowered_machine.ResetError(NoError)![]const u8 {
                const OptionalCtxType = @TypeOf(optional_ctx);
                const ctx: OptionalCtxType = @ptrCast(@alignCast(@constCast(scenario.outer_optional_ctx.?)));
                scenario.outer_optional_ctx = null;
                return try scenario.outer(OptionalCap, ctx);
            }
        }.run)) {
            scenario.outer_optional_ctx = @ptrCast(optional_ctx);
            return @import("optional.zig").computeProgram(OptionalCap, optional_ctx, struct {
                /// Re-enter the resource witness through the outer optional capability.
                pub fn run() lowered_machine.ResetError(NoError)![]const u8 {
                    const OptionalCtxType = @TypeOf(optional_ctx);
                    const ctx: OptionalCtxType = @ptrCast(@alignCast(@constCast(scenario.outer_optional_ctx.?)));
                    scenario.outer_optional_ctx = null;
                    return try scenario.outer(OptionalCap, ctx);
                }
            }.run);
        }
    });
    try std.testing.expectEqualStrings("result=early", result);
    try std.testing.expectEqualStrings("acquire=r", manager.transcript[0]);
    try std.testing.expectEqualStrings("use=r", manager.transcript[1]);
    try std.testing.expectEqualStrings("policy-return-now", manager.transcript[2]);
    try std.testing.expectEqualStrings("release=r", manager.transcript[3]);
}

test "resource release error wins after a successful body" {
    const DemoError = error{ReleaseFailed};
    const ResourceInstance = Instance(i32, DemoError);

    const manager = struct {
        /// Hand out one resource for the release-error precedence test.
        pub fn acquire() i32 {
            return 1;
        }

        /// Fail release to prove cleanup errors become the public result after success.
        pub fn release(_: i32) lowered_machine.ResetError(DemoError)!void {
            return error.ReleaseFailed;
        }
    };

    const demo = struct {
        /// Acquire one resource and otherwise complete successfully.
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(computeProgram(Cap, ctx, struct {
            /// Acquire one resource and otherwise complete successfully.
            pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(DemoError)![]const u8 {
                _ = try acquire(ProgramCap, program_ctx);
                return "done";
            }
        })) {
            return computeProgram(Cap, ctx, struct {
                /// Acquire one resource and otherwise complete successfully.
                pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(DemoError)![]const u8 {
                    _ = try acquire(ProgramCap, program_ctx);
                    return "done";
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = ResourceInstance.init();
    try std.testing.expectError(error.ReleaseFailed, handleAt(@src(), []const u8, &runtime, &instance, manager, demo));
}

test "resource body error wins over release error" {
    const DemoError = error{ BodyFailed, ReleaseFailed };
    const ResourceInstance = Instance(i32, DemoError);

    const manager = struct {
        /// Hand out one resource for the body-error precedence test.
        pub fn acquire() i32 {
            return 1;
        }

        /// Also fail release, but the body error must remain public.
        pub fn release(_: i32) lowered_machine.ResetError(DemoError)!void {
            return error.ReleaseFailed;
        }
    };

    const demo = struct {
        /// Acquire one resource and then fail the body.
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(computeProgram(Cap, ctx, struct {
            /// Acquire one resource and then fail the body.
            pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(DemoError)![]const u8 {
                _ = try acquire(ProgramCap, program_ctx);
                return error.BodyFailed;
            }
        })) {
            return computeProgram(Cap, ctx, struct {
                /// Acquire one resource and then fail the body.
                pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(DemoError)![]const u8 {
                    _ = try acquire(ProgramCap, program_ctx);
                    return error.BodyFailed;
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = ResourceInstance.init();
    try std.testing.expectError(error.BodyFailed, handleAt(@src(), []const u8, &runtime, &instance, manager, demo));
}

test "nested same-shaped resource handles get distinct capability types" {
    const NoError = error{};
    const ResourceInstance = Instance(i32, NoError);
    const manager = struct {
        /// Acquire one dummy resource for the nested resource test.
        pub fn acquire() i32 {
            return 0;
        }

        /// Release the dummy resource for the nested resource test.
        pub fn release(_: i32) void {
            // Intentionally empty for this type-only test.
        }
    };
    const demo = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var inner_ptr: ?*const ResourceInstance = null;

        /// Open an inner resource handle and prove its capability differs from the outer one.
        pub fn outer(comptime OuterCap: type, _: anytype) lowered_machine.ResetError(NoError)!i32 {
            return try handleAt(@src(), i32, runtime_ptr.?, inner_ptr.?, manager, struct {
                /// Reject capability-type collapse inside the nested resource handle.
                pub fn program(comptime InnerCap: type, inner_ctx: anytype) @TypeOf(computeProgram(InnerCap, inner_ctx, struct {
                    /// Return a neutral value from the nested resource body.
                    pub fn run(_: type, _: anytype) i32 {
                        return 0;
                    }
                })) {
                    comptime if (OuterCap == InnerCap) {
                        @compileError("nested resource handles must receive distinct capability types");
                    };
                    return computeProgram(InnerCap, inner_ctx, struct {
                        /// Return a neutral value from the nested resource body.
                        pub fn run(_: type, _: anytype) i32 {
                            return 0;
                        }
                    });
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var outer_instance = ResourceInstance.init();
    var inner_instance = ResourceInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    const result = try handleAt(@src(), i32, &runtime, &outer_instance, manager, struct {
        /// Enter the outer resource handle and hand its capability inward.
        pub fn program(comptime OuterCap: type, ctx: anytype) @TypeOf(computeProgram(OuterCap, ctx, struct {
            /// Re-enter the nested resource witness through the outer capability.
            pub fn run(_: type, _: anytype) lowered_machine.ResetError(NoError)!i32 {
                return try demo.outer(OuterCap, {});
            }
        })) {
            return computeProgram(OuterCap, ctx, struct {
                /// Re-enter the nested resource witness through the outer capability.
                pub fn run(_: type, _: anytype) lowered_machine.ResetError(NoError)!i32 {
                    return try demo.outer(OuterCap, {});
                }
            });
        }
    });
    try std.testing.expectEqual(@as(i32, 0), result);
}
