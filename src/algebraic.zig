const engine = @import("internal/algebraic_engine.zig");
const lowered_machine = @import("lowered_machine");

fn ReturnTypeErrorSet(comptime ReturnType: type) type {
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.error_set,
        else => error{},
    };
}

fn SpecErrorSet(comptime SpecType: type) type {
    const Impl = SpecType.ImplType;
    return switch (SpecType.builder_kind) {
        .direct_transform, .transform => ReturnTypeErrorSet(@typeInfo(@TypeOf(Impl.resumeValue)).@"fn".return_type.?) ||
            ReturnTypeErrorSet(@typeInfo(@TypeOf(Impl.afterResume)).@"fn".return_type.?),
        .choice => ReturnTypeErrorSet(@typeInfo(@TypeOf(Impl.resumeOrReturn)).@"fn".return_type.?) ||
            ReturnTypeErrorSet(@typeInfo(@TypeOf(Impl.afterResume)).@"fn".return_type.?),
        .abort => ReturnTypeErrorSet(@typeInfo(@TypeOf(Impl.directReturn)).@"fn".return_type.?),
    };
}

fn SpecsErrorSet(comptime SpecsType: type) type {
    const fields = @typeInfo(SpecsType).@"struct".fields;
    var ErrorSet = error{};
    inline for (fields) |field| {
        ErrorSet = ErrorSet || SpecErrorSet(field.type);
    }
    return ErrorSet;
}

fn ConfiguredBodyErrorSet(comptime ContextType: type, comptime Body: type) type {
    if (@hasDecl(Body, "program")) {
        const AuthoredType = @TypeOf(Body.program(DummyValue(*ContextType)));
        switch (@typeInfo(AuthoredType)) {
            .@"struct" => if (@hasField(AuthoredType, "prompt")) {
                return switch (@typeInfo(@FieldType(AuthoredType, "prompt"))) {
                    .pointer => |pointer| if (@hasDecl(pointer.child, "ErrorSet")) pointer.child.ErrorSet else error{},
                    else => error{},
                };
            },
            else => {},
        }
        return error{};
    }
    if (!@hasDecl(Body, "body")) return error{};
    return ReturnTypeErrorSet(@TypeOf(Body.body(DummyValue(*ContextType))));
}

/// Define one closed-world abortive operation.
pub const AbortOp = engine.AbortOp;
/// Define one closed-world zero-or-one-resume choice operation.
pub const ChoiceOp = engine.ChoiceOp;
/// Define one closed-world resumptive transform operation.
pub const TransformOp = engine.TransformOp;

/// Build an abort handler specification for a declared abort op.
pub const handleAbort = engine.handleAbort;
/// Build a choice handler specification for a declared choice op.
pub const handleChoice = engine.handleChoice;
/// Build a transform handler specification for a declared transform op.
pub const handleTransform = engine.handleTransform;

/// Build a closed-world algebraic program over the existing one-shot prompt runtime with an explicit error set.
pub fn ProgramWithErrorSet(
    comptime Answer: type,
    comptime ErrorSet: type,
    comptime ops: anytype,
) type {
    return engine.Program(Answer, Answer, ErrorSet, ops);
}

/// Build a closed-world algebraic program over the existing one-shot prompt runtime.
pub fn Program(
    comptime Answer: type,
    comptime ops: anytype,
) type {
    return struct {
        fn HandlersReturnType(comptime SpecsType: type) type {
            const InferredSpecErrorSet = SpecsErrorSet(SpecsType);
            const BaseConfigured = @TypeOf(ProgramWithErrorSet(Answer, InferredSpecErrorSet, ops).handlers(DummyValue(SpecsType)));
            return struct {
                specs: SpecsType,

                /// Context type exported by the public inferred-error wrapper.
                pub const Context = BaseConfigured.Context;

                /// Run the configured program while widening to inferred body errors when needed.
                pub fn run(self: @This(), runtime: anytype, comptime Body: type) lowered_machine.ResetError(InferredSpecErrorSet || ConfiguredBodyErrorSet(Context, Body))!Answer {
                    const RunErrorSet = InferredSpecErrorSet || ConfiguredBodyErrorSet(Context, Body);
                    const ConfiguredWithErrorSet = ProgramWithErrorSet(Answer, RunErrorSet, ops).handlers(self.specs);
                    if (@hasDecl(Body, "program")) {
                        const adapted_body = struct {
                            /// Public `program` helper.
                            pub fn program(ctx: *@TypeOf(ConfiguredWithErrorSet).Context) @TypeOf(Body.program(DummyValue(*Context))) {
                                // The public wrapper keeps its documented Context shape while the widened runner carries a larger inferred error set.
                                return Body.program(@as(*Context, @ptrCast(ctx)));
                            }
                        };
                        return ConfiguredWithErrorSet.run(runtime, adapted_body);
                    }
                    if (@hasDecl(Body, "body")) {
                        const adapted_body = struct {
                            /// Execute this public body hook.
                            pub fn body(ctx: *@TypeOf(ConfiguredWithErrorSet).Context) @TypeOf(Body.body(DummyValue(*Context))) {
                                return Body.body(@as(*Context, @ptrCast(ctx)));
                            }
                        };
                        return ConfiguredWithErrorSet.run(runtime, adapted_body);
                    }
                    @compileError("algebraic body must declare program or body");
                }
            };
        }

        /// Bind one handler specification per declared operation in declaration order.
        pub fn handlers(specs: anytype) HandlersReturnType(@TypeOf(specs)) {
            return .{ .specs = specs };
        }
    };
}

fn DummyPointer(comptime PtrType: type) PtrType {
    const pointer = @typeInfo(PtrType).pointer;
    return switch (pointer.size) {
        .slice => blk: {
            const empty: [0]pointer.child = .{};
            const slice = empty[0..];
            if (pointer.is_const) break :blk @as(PtrType, slice);
            break :blk @as(PtrType, @constCast(slice));
        },
        else => @as(PtrType, @ptrFromInt(std.mem.alignForward(usize, 1, @alignOf(pointer.child)))),
    };
}

fn DummyValue(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .pointer => DummyPointer(T),
        .optional => null,
        .void => {},
        else => DummyPointer(*T).*,
    };
}

test {
    _ = engine;
}
