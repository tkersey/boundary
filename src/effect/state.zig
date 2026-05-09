const algebraic = @import("algebraic.zig");
const effect_schema = @import("../effect_schema.zig");
const family = @import("family.zig");
const lexical_with = @import("../internal/lexical_support.zig");
const lowered_machine = @import("lowered_machine");
const plan_ir = @import("../ir_api.zig");
const ability = lowered_machine;
const std = @import("std");

/// Prompt-backed effect instance for a state family.
pub const Instance = family.Instance;

/// Final state plus body answer returned from a handled state program.
pub const HandleResult = family.HandleResult;

/// Handler state handle used by `ability.effect handlers`.
pub fn LexicalHandle(comptime Cap: type, comptime ContextPtrType: type) type {
    return struct {
        ctx: ?ContextPtrType,

        /// Read the current state value through the handler handle.
        pub fn get(self: @This()) lowered_machine.ResetError(family.ContextErrorSetType(ContextPtrType))!family.ContextStateType(ContextPtrType) {
            return try algebraic.stateGet(Cap, self.ctx.?);
        }

        /// Replace the current state value through the handler handle.
        pub fn set(self: @This(), value: family.ContextStateType(ContextPtrType)) lowered_machine.ResetError(family.ContextErrorSetType(ContextPtrType))!void {
            try algebraic.stateSet(Cap, self.ctx.?, value);
        }
    };
}

/// Descriptor value used by `ability.effect handlers` for the built-in state family.
pub fn LexicalDescriptor(comptime StateType: type, comptime ErrorSetType: type) type {
    return struct {
        /// Shared error set carried by the handler state descriptor.
        pub const ErrorSet = ErrorSetType;
        /// State type threaded through the handler state context.
        pub const State = StateType;
        /// Final state output produced by the handler state descriptor.
        pub const Output = StateType;

        initial_state: StateType,

        /// Resolve the handler state handle type for one exact context.
        pub fn HandleType(comptime Cap: type, comptime ContextPtrType: type) type {
            return LexicalHandle(Cap, ContextPtrType);
        }

        /// Bind one handler state handle to the active exact context.
        pub fn bindLexical(self: @This(), comptime Cap: type, ctx: anytype) HandleType(Cap, @TypeOf(ctx)) {
            _ = self;
            return .{ .ctx = ctx };
        }

        /// Return the shared binding schema for this handler descriptor under one requirement label.
        pub fn BindingSchema(comptime requirement_label: [:0]const u8) type {
            return effect_schema.Binding(requirement_label, Schema(StateType, ErrorSetType), struct {});
        }

        /// Run one handler state descriptor through the existing state family.
        pub fn run(self: @This(), comptime AnswerType: type, comptime RunErrorSetType: type, run_ctx: anytype, comptime Body: type) lowered_machine.ResetError(RunErrorSetType)!lexical_with.DescriptorResult(Output, AnswerType) {
            var instance = family.Instance(StateType, ErrorSetType).init();
            const result = try algebraic.handleStateWithErrorSetLexical(AnswerType, RunErrorSetType, .{
                .runtime = run_ctx.runtime,
                .instance = &instance,
                .initial_state = self.initial_state,
                .lexical_state = @constCast(run_ctx.lexical_state),
            }, Body);
            return .{
                .output = result.state,
                .value = result.value,
            };
        }
    };
}

/// Create one handler state descriptor for `ability.effect handlers`.
pub fn use(initial_state: anytype) LexicalDescriptor(@TypeOf(initial_state), error{}) {
    return .{ .initial_state = initial_state };
}

/// Shared effect schema for the built-in state family.
pub fn Schema(comptime StateType: type, comptime ErrorSetType: type) type {
    return effect_schema.state_cell(StateType, ErrorSetType);
}

/// Read the current state value for the supplied capability and handled context.
pub inline fn get(
    comptime Cap: type,
    ctx: anytype,
) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!family.ContextStateType(@TypeOf(ctx)) {
    return try algebraic.stateGet(Cap, ctx);
}

/// Replace the current state value for the supplied capability and handled context.
pub inline fn set(
    comptime Cap: type,
    ctx: anytype,
    value: family.ContextStateType(@TypeOf(ctx)),
) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!void {
    return try algebraic.stateSet(Cap, ctx, value);
}

/// Build one explicit state body program with no prompt operation.
pub inline fn computeProgram(
    comptime Cap: type,
    ctx: anytype,
    comptime Thunk: type,
) @TypeOf(family.computeProgram(Cap, ctx, Thunk)) {
    return family.computeProgram(Cap, ctx, Thunk);
}

/// Run a state effect body and return the final state plus the body answer.
pub fn handle(
    comptime AnswerType: type,
    runtime: *ability.Runtime,
    instance: anytype,
    initial_state: family.InstanceStateType(@TypeOf(instance)),
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!HandleResult(
    family.InstanceStateType(@TypeOf(instance)),
    AnswerType,
) {
    return try algebraic.handleState(AnswerType, runtime, instance, initial_state, Body);
}

/// Public `handleWithErrorSet` helper.
// zlinter-disable max_positional_args - public caller provenance and state inputs stay explicit at this compatibility wrapper.
pub fn handleWithErrorSet(
    comptime AnswerType: type,
    comptime RunErrorSetType: type,
    runtime: *ability.Runtime,
    instance: anytype,
    initial_state: family.InstanceStateType(@TypeOf(instance)),
    comptime Body: type,
) lowered_machine.ResetError(RunErrorSetType)!HandleResult(
    family.InstanceStateType(@TypeOf(instance)),
    AnswerType,
) {
    return try algebraic.handleStateWithErrorSet(AnswerType, RunErrorSetType, runtime, instance, initial_state, Body);
}

/// Plan-native ProgramPlan construction helpers for the built-in state family.
pub const plan = struct {
    /// Canonical operation ordinal for `state.get`.
    pub const get_op_ordinal: u16 = 0;
    /// Canonical operation ordinal for `state.set`.
    pub const set_op_ordinal: u16 = 1;

    /// Build the canonical state binding schema for one requirement label.
    pub fn Binding(comptime label: [:0]const u8, comptime StateType: type, comptime ErrorSetType: type) type {
        return plan_ir.schema.Binding(label, Schema(StateType, ErrorSetType), void);
    }

    /// Lower the canonical state binding to ordinary ProgramPlan rows.
    pub fn Rows(
        comptime label: [:0]const u8,
        comptime StateType: type,
        comptime ErrorSetType: type,
        comptime offsets: plan_ir.schema.BindingOffsets,
    ) type {
        return plan_ir.schema.LowerBinding(Binding(label, StateType, ErrorSetType), offsets);
    }

    /// Build a scalar state value reference.
    pub fn stateRef(comptime StateType: type) plan_ir.ValueRef {
        return scalarRef(StateType);
    }

    /// Build a structured state value reference at a caller-owned schema index.
    pub fn stateRefFromSchema(comptime StateType: type, schema_index: u16) plan_ir.ValueRef {
        return structuredRef(StateType, schema_index);
    }

    /// Build a scalar state local descriptor.
    pub fn stateLocal(comptime StateType: type) plan_ir.plan.Local {
        const ref = stateRef(StateType);
        return .{ .codec = ref.codec, .schema_index = ref.schema_index };
    }

    /// Build a structured state local descriptor at a caller-owned schema index.
    pub fn stateLocalFromSchema(comptime StateType: type, schema_index: u16) plan_ir.plan.Local {
        const ref = stateRefFromSchema(StateType, schema_index);
        return .{ .codec = ref.codec, .schema_index = ref.schema_index };
    }

    /// Build the canonical `get` operation reference from a caller-owned op offset.
    pub fn getOp(function_ref: plan_ir.builder.FunctionRef, first_op: u16) plan_ir.builder.OpRef {
        return plan_ir.builder.op(function_ref, first_op + get_op_ordinal);
    }

    /// Build the canonical `set` operation reference from a caller-owned op offset.
    pub fn setOp(function_ref: plan_ir.builder.FunctionRef, first_op: u16) plan_ir.builder.OpRef {
        return plan_ir.builder.op(function_ref, first_op + set_op_ordinal);
    }

    /// Build a state `get` call instruction.
    pub fn callGet(
        function_ref: plan_ir.builder.FunctionRef,
        dst_local: plan_ir.builder.LocalRef,
        op_ref: plan_ir.builder.OpRef,
    ) anyerror!plan_ir.plan.Instruction {
        return plan_ir.builder.callOp(function_ref, dst_local, op_ref, null);
    }

    /// Build a state `set` call instruction.
    pub fn callSet(
        function_ref: plan_ir.builder.FunctionRef,
        payload_local: plan_ir.builder.LocalRef,
        op_ref: plan_ir.builder.OpRef,
    ) anyerror!plan_ir.plan.Instruction {
        return plan_ir.builder.callOp(function_ref, null, op_ref, payload_local);
    }

    /// Build the canonical final-state output row through schema lowering.
    pub fn finalStateOutput(
        comptime label: [:0]const u8,
        comptime StateType: type,
        comptime ErrorSetType: type,
        comptime schema_refs: type,
    ) plan_ir.plan.Output {
        const lowered_rows = Rows(label, StateType, ErrorSetType, .{
            .requirement_index = 0,
            .first_op = 0,
            .first_output = 0,
            .schema_refs = schema_refs,
        });
        return lowered_rows.outputs[0];
    }

    fn scalarRef(comptime StateType: type) plan_ir.ValueRef {
        const codec = comptime plan_ir.value.codecForType(StateType) catch @compileError("unsupported state type");
        return switch (codec) {
            .product, .sum => @compileError("use state.plan.stateRefFromSchema for structured state types"),
            else => .{ .codec = codec },
        };
    }

    fn structuredRef(comptime StateType: type, schema_index: u16) plan_ir.ValueRef {
        const codec = comptime plan_ir.value.codecForType(StateType) catch @compileError("unsupported state type");
        return switch (codec) {
            .product, .sum => .{ .codec = codec, .schema_index = schema_index },
            else => @compileError("use state.plan.stateRef for scalar state types"),
        };
    }
};

test "state plan helpers build canonical rows" {
    const lowered_rows = plan.Rows("state", i32, error{}, .{
        .requirement_index = 2,
        .first_op = 5,
        .first_output = 7,
    });

    try std.testing.expectEqual(@as(u16, 2), lowered_rows.requirement_index);
    try std.testing.expectEqual(@as(u16, 7), lowered_rows.first_output);
    try std.testing.expectEqualStrings("state", lowered_rows.requirement.label);
    try std.testing.expectEqual(@as(u16, 5), lowered_rows.requirement.first_op);
    try std.testing.expectEqual(@as(u16, 2), lowered_rows.requirement.op_count);
    try std.testing.expectEqual(@as(@TypeOf(lowered_rows.requirement.lifecycle_tag), .state_cell), lowered_rows.requirement.lifecycle_tag);
    try std.testing.expectEqual(@as(@TypeOf(lowered_rows.requirement.output_tag), .final_state), lowered_rows.requirement.output_tag);
    try std.testing.expectEqualStrings("get", lowered_rows.ops[plan.get_op_ordinal].op_name);
    try std.testing.expectEqual(plan_ir.PlanControlMode.transform, lowered_rows.ops[plan.get_op_ordinal].mode);
    try std.testing.expectEqual(plan_ir.ValueCodec.unit, lowered_rows.ops[plan.get_op_ordinal].payload_codec);
    try std.testing.expectEqual(plan_ir.ValueCodec.i32, lowered_rows.ops[plan.get_op_ordinal].resume_codec);
    try std.testing.expectEqualStrings("set", lowered_rows.ops[plan.set_op_ordinal].op_name);
    try std.testing.expectEqual(plan_ir.PlanControlMode.transform, lowered_rows.ops[plan.set_op_ordinal].mode);
    try std.testing.expectEqual(plan_ir.ValueCodec.i32, lowered_rows.ops[plan.set_op_ordinal].payload_codec);
    try std.testing.expectEqual(plan_ir.ValueCodec.unit, lowered_rows.ops[plan.set_op_ordinal].resume_codec);
    try std.testing.expectEqualStrings("state", lowered_rows.outputs[0].label);
    try std.testing.expectEqual(plan_ir.ValueCodec.i32, lowered_rows.outputs[0].codec);

    const ref = plan.stateRef(i32);
    try std.testing.expectEqual(plan_ir.ValueCodec.i32, ref.codec);
    try std.testing.expectEqual(@as(?u16, null), ref.schema_index);
    const local = plan.stateLocal(i32);
    try std.testing.expectEqual(plan_ir.ValueCodec.i32, local.codec);
    try std.testing.expectEqual(@as(?u16, null), local.schema_index);
}

test "state plan helpers build call instructions" {
    const root = plan_ir.builder.function(0);
    const state_local = plan_ir.builder.local(root, 3);
    const get_instruction = try plan.callGet(root, state_local, plan.getOp(root, 8));
    try std.testing.expectEqual(plan_ir.plan.InstructionKind.call_op, get_instruction.kind);
    try std.testing.expectEqual(@as(u16, 3), get_instruction.dst);
    try std.testing.expectEqual(@as(u16, 8), get_instruction.operand);
    try std.testing.expectEqual(std.math.maxInt(u16), get_instruction.aux);

    const set_instruction = try plan.callSet(root, state_local, plan.setOp(root, 8));
    try std.testing.expectEqual(plan_ir.plan.InstructionKind.call_op, set_instruction.kind);
    try std.testing.expectEqual(std.math.maxInt(u16), set_instruction.dst);
    try std.testing.expectEqual(@as(u16, 9), set_instruction.operand);
    try std.testing.expectEqual(@as(u16, 3), set_instruction.aux);
}

test "state plan helpers support structured state schema refs" {
    const ProductState = struct {
        amount: i32,
    };
    const schema_refs = plan_ir.schema.SchemaRefs(.{plan_ir.schema.ref(ProductState, 4)});
    const lowered_rows = plan.Rows("state", ProductState, error{}, .{
        .requirement_index = 0,
        .first_op = 0,
        .first_output = 0,
        .schema_refs = schema_refs,
    });

    try std.testing.expectEqual(plan_ir.ValueCodec.product, lowered_rows.ops[plan.get_op_ordinal].resume_codec);
    try std.testing.expectEqual(@as(?u16, 4), lowered_rows.ops[plan.get_op_ordinal].resume_schema_index);
    try std.testing.expectEqual(plan_ir.ValueCodec.product, lowered_rows.ops[plan.set_op_ordinal].payload_codec);
    try std.testing.expectEqual(@as(?u16, 4), lowered_rows.ops[plan.set_op_ordinal].payload_schema_index);
    try std.testing.expectEqual(plan_ir.ValueCodec.product, lowered_rows.outputs[0].codec);
    try std.testing.expectEqual(@as(?u16, 4), lowered_rows.outputs[0].schema_index);

    const ref = plan.stateRefFromSchema(ProductState, 4);
    try std.testing.expectEqual(plan_ir.ValueCodec.product, ref.codec);
    try std.testing.expectEqual(@as(?u16, 4), ref.schema_index);
    const local = plan.stateLocalFromSchema(ProductState, 4);
    try std.testing.expectEqual(plan_ir.ValueCodec.product, local.codec);
    try std.testing.expectEqual(@as(?u16, 4), local.schema_index);

    const output = plan.finalStateOutput("state", ProductState, error{}, schema_refs);
    try std.testing.expectEqualStrings("state", output.label);
    try std.testing.expectEqual(plan_ir.ValueCodec.product, output.codec);
    try std.testing.expectEqual(@as(?u16, 4), output.schema_index);
}

test "state instance shell stays prompt-sized" {
    const StateInstance = Instance(i32, error{});
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(StateInstance));
}

test "state private context stays pointer-sized" {
    const NoError = error{};
    const StateContext = family.Context(struct {}, i32, i32, NoError);
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(StateContext));
}

test "state handle threads value and final state" {
    const NoError = error{};
    const StateInstance = Instance(i32, NoError);

    const demo = struct {
        /// Execute the strict-affinity state-effect test body.
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(family.computeProgram(Cap, ctx, struct {
            /// Read, update, and read the state cell once.
            pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(NoError)!i32 {
                const before = try get(ProgramCap, program_ctx);
                try set(ProgramCap, program_ctx, before + 1);
                return try get(ProgramCap, program_ctx);
            }
        })) {
            return family.computeProgram(Cap, ctx, struct {
                /// Read, update, and read the state cell once.
                pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(NoError)!i32 {
                    const before = try get(ProgramCap, program_ctx);
                    try set(ProgramCap, program_ctx, before + 1);
                    return try get(ProgramCap, program_ctx);
                }
            });
        }
    };

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = StateInstance.init();
    const result = try handle(i32, &runtime, &instance, 5, demo);
    try std.testing.expectEqual(@as(i32, 6), result.state);
    try std.testing.expectEqual(@as(i32, 6), result.value);
}

test "nested same-shaped state handles get distinct capability types" {
    const NoError = error{};
    const StateInstance = Instance(i32, NoError);
    const demo = struct {
        var runtime_ptr: ?*ability.Runtime = null;
        var inner_ptr: ?*const StateInstance = null;

        /// Open an inner handle and prove its capability type differs from the outer one.
        pub fn outer(comptime OuterCap: type, _: anytype) lowered_machine.ResetError(NoError)!i32 {
            const result = try handle(i32, runtime_ptr.?, inner_ptr.?, 0, struct {
                /// Reject capability-type collapse inside the nested handle.
                pub fn program(comptime InnerCap: type, inner_ctx: anytype) @TypeOf(family.computeProgram(InnerCap, inner_ctx, struct {
                    /// Return a neutral value from the nested state body.
                    pub fn run(_: type, _: anytype) i32 {
                        return 0;
                    }
                })) {
                    comptime if (OuterCap == InnerCap) {
                        @compileError("nested state handles must receive distinct capability types");
                    };
                    return family.computeProgram(InnerCap, inner_ctx, struct {
                        /// Return a neutral value from the nested state body.
                        pub fn run(_: type, _: anytype) i32 {
                            return 0;
                        }
                    });
                }
            });
            return result.value;
        }
    };

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var outer_instance = StateInstance.init();
    var inner_instance = StateInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    const result = try handle(i32, &runtime, &outer_instance, 0, struct {
        /// Enter the outer handle and hand its capability to the nested check.
        pub fn program(comptime OuterCap: type, ctx: anytype) @TypeOf(family.computeProgram(OuterCap, ctx, struct {
            /// Re-enter the nested state witness through the outer capability.
            pub fn run(_: type, _: anytype) lowered_machine.ResetError(NoError)!i32 {
                return try demo.outer(OuterCap, {});
            }
        })) {
            return family.computeProgram(OuterCap, ctx, struct {
                /// Re-enter the nested state witness through the outer capability.
                pub fn run(_: type, _: anytype) lowered_machine.ResetError(NoError)!i32 {
                    return try demo.outer(OuterCap, {});
                }
            });
        }
    });
    try std.testing.expectEqual(@as(i32, 0), result.value);
}

test "public state handleWithErrorSet leaves caller provenance absent by default" {
    const NoError = error{};
    const StateInstance = Instance(i32, NoError);

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = StateInstance.init();

    const result = try handleWithErrorSet([]const u8, NoError, &runtime, &instance, @as(i32, 0), struct {
        /// Report whether the source-compatible state wrapper leaves caller provenance absent.
        pub fn body(comptime Cap: type, ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
            _ = Cap;
            return if (@TypeOf(ctx.*).caller_source == null) "absent" else "present";
        }
    });

    try std.testing.expectEqualStrings("absent", result.value);
}
