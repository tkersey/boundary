const algebraic = @import("algebraic.zig");
const effect_schema = @import("../effect_schema.zig");
const family = @import("family.zig");
const lexical_with = @import("../internal/lexical_support.zig");
const lowered_machine = @import("lowered_machine");
const plan_ir = @import("../ir_api.zig");
const ability = lowered_machine;
const std = @import("std");

fn WriterState(comptime ItemType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        first_item: ?ItemType = null,
        items: std.ArrayList(ItemType) = .empty,

        /// Build one empty writer state backed by the supplied allocator.
        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{ .allocator = allocator };
        }

        /// Release any storage retained by the writer state.
        pub fn deinit(self: *@This()) void {
            self.items.deinit(self.allocator);
        }

        /// Append one item into the writer log state.
        pub fn append(self: *@This(), item: ItemType) std.mem.Allocator.Error!void {
            if (self.first_item == null and self.items.items.len == 0) {
                self.first_item = item;
                return;
            }
            if (self.items.items.len == 0) {
                try self.items.ensureTotalCapacity(self.allocator, 2);
                self.items.appendAssumeCapacity(self.first_item.?);
                self.first_item = null;
            }
            try self.items.append(self.allocator, item);
        }

        /// Materialize the accumulated writer log as an owned slice.
        pub fn intoOwnedSlice(self: *@This()) ![]ItemType {
            if (self.items.items.len != 0) {
                return try self.items.toOwnedSlice(self.allocator);
            }

            if (self.first_item) |item| {
                const slice = try self.allocator.alloc(ItemType, 1);
                slice[0] = item;
                self.first_item = null;
                return slice;
            }

            return try self.allocator.alloc(ItemType, 0);
        }
    };
}

/// Prompt-backed effect instance for an append-only writer family.
pub fn Instance(comptime ItemType: type, comptime ErrorSetType: type) type {
    return family.Instance(WriterState(ItemType), ErrorSetType);
}

/// Final writer log plus body answer returned from a handled writer program.
pub fn HandleResult(comptime ItemType: type, comptime ValueType: type) type {
    return struct {
        items: []ItemType,
        value: ValueType,
    };
}

const HandleWithErrorSetTypes = struct {
    Item: type,
    Answer: type,
    ErrorSet: type,
};

/// Handler writer handle used by `ability.effect handlers`.
pub fn LexicalHandle(comptime Cap: type, comptime ContextPtrType: type, comptime ItemType: type) type {
    return struct {
        ctx: ?ContextPtrType,

        /// Append one item through the handler writer handle.
        pub fn tell(self: @This(), item: ItemType) lowered_machine.ResetError(family.ContextErrorSetType(ContextPtrType))!void {
            try algebraic.writerTell(Cap, self.ctx.?, item);
        }
    };
}

/// Descriptor value used by `ability.effect handlers` for the built-in writer family.
pub fn LexicalDescriptor(comptime ItemType: type, comptime ErrorSetType: type) type {
    return struct {
        /// Shared error set carried by the handler writer descriptor.
        pub const ErrorSet = ErrorSetType;
        /// Preview-only state placeholder for handler writer contexts.
        pub const State = void;
        /// Final writer log output produced by the handler writer descriptor.
        pub const Output = []ItemType;

        allocator: std.mem.Allocator,

        /// Resolve the handler writer handle type for one exact context.
        pub fn HandleType(comptime Cap: type, comptime ContextPtrType: type) type {
            return LexicalHandle(Cap, ContextPtrType, ItemType);
        }

        /// Bind one handler writer handle to the active exact context.
        pub fn bindLexical(self: @This(), comptime Cap: type, ctx: anytype) HandleType(Cap, @TypeOf(ctx)) {
            _ = self;
            return .{ .ctx = ctx };
        }

        /// Return the shared binding schema for this handler descriptor under one requirement label.
        pub fn BindingSchema(comptime requirement_label: [:0]const u8) type {
            return effect_schema.Binding(requirement_label, Schema(ItemType, ErrorSetType), struct {});
        }

        /// Run one handler writer descriptor through the existing writer family.
        pub fn run(self: @This(), comptime AnswerType: type, comptime RunErrorSetType: type, run_ctx: anytype, comptime Body: type) lowered_machine.ResetError(RunErrorSetType)!lexical_with.DescriptorResult(Output, AnswerType) {
            var instance = family.Instance(WriterState(ItemType), ErrorSetType).init();
            const writer_contract = struct {
                /// Item type carried by this handler writer helper.
                pub const Item = ItemType;
                /// Answer type carried by this handler writer helper.
                pub const Answer = AnswerType;
                /// Writer state type carried by this handler writer helper.
                pub const WriterStateType = WriterState(ItemType);
            };
            const result = try algebraic.handleWriterWithErrorSetLexical(writer_contract, RunErrorSetType, .{
                .runtime = run_ctx.runtime,
                .instance = &instance,
                .allocator = self.allocator,
                .lexical_state = @constCast(run_ctx.lexical_state),
            }, Body);
            return .{
                .output = result.items,
                .value = result.value,
            };
        }
    };
}

/// Create one handler writer descriptor for `ability.effect handlers`.
pub fn use(comptime ItemType: type, allocator: std.mem.Allocator) LexicalDescriptor(ItemType, error{}) {
    return .{ .allocator = allocator };
}

/// Shared effect schema for the built-in writer family.
pub fn Schema(comptime ItemType: type, comptime ErrorSetType: type) type {
    return effect_schema.writer_accumulator(ItemType, ErrorSetType);
}

/// Append one item to the current writer log.
pub inline fn tell(
    comptime Cap: type,
    ctx: anytype,
    item: anytype,
) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!void {
    return try algebraic.writerTell(Cap, ctx, item);
}

/// Build one explicit writer body program with no prompt operation.
pub inline fn computeProgram(
    comptime Cap: type,
    ctx: anytype,
    comptime Thunk: type,
) @TypeOf(family.computeProgram(Cap, ctx, Thunk)) {
    return family.computeProgram(Cap, ctx, Thunk);
}

/// Run a writer effect body and return the accumulated log plus the body answer.
// zlinter-disable max_positional_args - public caller provenance and writer inputs stay explicit at this compatibility wrapper.
pub fn handle(
    comptime ItemType: type,
    comptime AnswerType: type,
    runtime: *ability.Runtime,
    instance: anytype,
    allocator: std.mem.Allocator,
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!HandleResult(ItemType, AnswerType) {
    const result = try algebraic.handleWriter(struct {
        /// Item type threaded through the shared writer engine adapter.
        pub const Item = ItemType;
        /// Final answer type threaded through the shared writer engine adapter.
        pub const Answer = AnswerType;
        /// Exact writer state type used by the shared writer engine adapter.
        pub const WriterStateType = WriterState(ItemType);
    }, runtime, instance, allocator, Body);
    return .{
        .items = result.items,
        .value = result.value,
    };
}

/// Public `handleWithErrorSet` helper.
pub fn handleWithErrorSet(
    comptime Types: HandleWithErrorSetTypes,
    runtime: *ability.Runtime,
    instance: anytype,
    allocator: std.mem.Allocator,
    comptime Body: type,
) lowered_machine.ResetError(Types.ErrorSet)!HandleResult(Types.Item, Types.Answer) {
    return try algebraic.handleWriterWithErrorSet(Types, runtime, instance, allocator, Body);
}

/// Plan-native ProgramPlan construction helpers for the built-in writer family.
pub const plan = struct {
    /// Canonical operation ordinal for `writer.tell`.
    pub const tell_op_ordinal: u16 = 0;

    /// Build the canonical writer binding schema for one requirement label.
    pub fn Binding(comptime label: [:0]const u8, comptime ItemType: type, comptime ErrorSetType: type) type {
        return plan_ir.schema.Binding(label, Schema(ItemType, ErrorSetType), void);
    }

    /// Lower the canonical writer binding to ordinary ProgramPlan rows.
    pub fn Rows(
        comptime label: [:0]const u8,
        comptime ItemType: type,
        comptime ErrorSetType: type,
        comptime offsets: plan_ir.schema.BindingOffsets,
    ) type {
        return plan_ir.schema.LowerBinding(Binding(label, ItemType, ErrorSetType), offsets);
    }

    /// Build a scalar writer item value reference.
    pub fn itemRef(comptime ItemType: type) plan_ir.ValueRef {
        return scalarRef(ItemType);
    }

    /// Build a structured writer item value reference at a caller-owned schema index.
    pub fn itemRefFromSchema(comptime ItemType: type, schema_index: u16) plan_ir.ValueRef {
        return structuredRef(ItemType, schema_index);
    }

    /// Build a scalar writer item local descriptor.
    pub fn itemLocal(comptime ItemType: type) plan_ir.plan.Local {
        const ref = itemRef(ItemType);
        return .{ .codec = ref.codec, .schema_index = ref.schema_index };
    }

    /// Build a structured writer item local descriptor at a caller-owned schema index.
    pub fn itemLocalFromSchema(comptime ItemType: type, schema_index: u16) plan_ir.plan.Local {
        const ref = itemRefFromSchema(ItemType, schema_index);
        return .{ .codec = ref.codec, .schema_index = ref.schema_index };
    }

    /// Build the canonical `tell` operation reference from a caller-owned op offset.
    pub fn tellOp(function_ref: plan_ir.builder.FunctionRef, first_op: u16) plan_ir.builder.OpRef {
        return plan_ir.builder.op(function_ref, first_op + tell_op_ordinal);
    }

    /// Build a writer `tell` call instruction.
    pub fn callTell(
        function_ref: plan_ir.builder.FunctionRef,
        payload_local: plan_ir.builder.LocalRef,
        op_ref: plan_ir.builder.OpRef,
    ) anyerror!plan_ir.plan.Instruction {
        return plan_ir.builder.callOp(function_ref, null, op_ref, payload_local);
    }

    /// Build the canonical accumulator output row through schema lowering.
    pub fn accumulatorOutput(
        comptime label: [:0]const u8,
        comptime ItemType: type,
        comptime ErrorSetType: type,
        comptime schema_refs: type,
    ) plan_ir.plan.Output {
        const lowered_rows = Rows(label, ItemType, ErrorSetType, .{
            .requirement_index = 0,
            .first_op = 0,
            .first_output = 0,
            .schema_refs = schema_refs,
        });
        return lowered_rows.outputs[0];
    }

    fn scalarRef(comptime ItemType: type) plan_ir.ValueRef {
        const codec = comptime plan_ir.value.codecForType(ItemType) catch @compileError("unsupported writer item type");
        return switch (codec) {
            .product, .sum => @compileError("use writer.plan.itemRefFromSchema for structured item types"),
            else => .{ .codec = codec },
        };
    }

    fn structuredRef(comptime ItemType: type, schema_index: u16) plan_ir.ValueRef {
        const codec = comptime plan_ir.value.codecForType(ItemType) catch @compileError("unsupported writer item type");
        return switch (codec) {
            .product, .sum => .{ .codec = codec, .schema_index = schema_index },
            else => @compileError("use writer.plan.itemRef for scalar item types"),
        };
    }
};

test "writer plan helpers build canonical rows" {
    const lowered_rows = plan.Rows("writer", i32, error{}, .{
        .requirement_index = 1,
        .first_op = 4,
        .first_output = 2,
    });

    try std.testing.expectEqual(@as(u16, 1), lowered_rows.requirement_index);
    try std.testing.expectEqual(@as(u16, 2), lowered_rows.first_output);
    try std.testing.expectEqualStrings("writer", lowered_rows.requirement.label);
    try std.testing.expectEqual(@as(u16, 4), lowered_rows.requirement.first_op);
    try std.testing.expectEqual(@as(u16, 1), lowered_rows.requirement.op_count);
    try std.testing.expectEqual(@as(@TypeOf(lowered_rows.requirement.lifecycle_tag), .writer_accumulator), lowered_rows.requirement.lifecycle_tag);
    try std.testing.expectEqual(@as(@TypeOf(lowered_rows.requirement.output_tag), .accumulator), lowered_rows.requirement.output_tag);
    try std.testing.expectEqualStrings("tell", lowered_rows.ops[plan.tell_op_ordinal].op_name);
    try std.testing.expectEqual(plan_ir.PlanControlMode.transform, lowered_rows.ops[plan.tell_op_ordinal].mode);
    try std.testing.expectEqual(plan_ir.ValueCodec.i32, lowered_rows.ops[plan.tell_op_ordinal].payload_codec);
    try std.testing.expectEqual(plan_ir.ValueCodec.unit, lowered_rows.ops[plan.tell_op_ordinal].resume_codec);
    try std.testing.expectEqualStrings("writer", lowered_rows.outputs[0].label);
    try std.testing.expectEqual(plan_ir.ValueCodec.i32, lowered_rows.outputs[0].codec);

    const ref = plan.itemRef(i32);
    try std.testing.expectEqual(plan_ir.ValueCodec.i32, ref.codec);
    try std.testing.expectEqual(@as(?u16, null), ref.schema_index);
    const local = plan.itemLocal(i32);
    try std.testing.expectEqual(plan_ir.ValueCodec.i32, local.codec);
    try std.testing.expectEqual(@as(?u16, null), local.schema_index);
}

test "writer plan helpers build call instructions" {
    const root = plan_ir.builder.function(0);
    const payload = plan_ir.builder.local(root, 1);
    const tell_instruction = try plan.callTell(root, payload, plan.tellOp(root, 3));
    try std.testing.expectEqual(plan_ir.plan.InstructionKind.call_op, tell_instruction.kind);
    try std.testing.expectEqual(std.math.maxInt(u16), tell_instruction.dst);
    try std.testing.expectEqual(@as(u16, 3), tell_instruction.operand);
    try std.testing.expectEqual(@as(u16, 1), tell_instruction.aux);
}

test "writer plan helpers support structured item schema refs" {
    const Item = struct {
        amount: i32,
    };
    const schema_refs = plan_ir.schema.SchemaRefs(.{plan_ir.schema.ref(Item, 5)});
    const lowered_rows = plan.Rows("writer", Item, error{}, .{
        .requirement_index = 0,
        .first_op = 0,
        .first_output = 0,
        .schema_refs = schema_refs,
    });

    try std.testing.expectEqual(plan_ir.ValueCodec.product, lowered_rows.ops[plan.tell_op_ordinal].payload_codec);
    try std.testing.expectEqual(@as(?u16, 5), lowered_rows.ops[plan.tell_op_ordinal].payload_schema_index);
    try std.testing.expectEqual(plan_ir.ValueCodec.unit, lowered_rows.ops[plan.tell_op_ordinal].resume_codec);
    try std.testing.expectEqual(plan_ir.ValueCodec.product, lowered_rows.outputs[0].codec);
    try std.testing.expectEqual(@as(?u16, 5), lowered_rows.outputs[0].schema_index);

    const ref = plan.itemRefFromSchema(Item, 5);
    try std.testing.expectEqual(plan_ir.ValueCodec.product, ref.codec);
    try std.testing.expectEqual(@as(?u16, 5), ref.schema_index);
    const local = plan.itemLocalFromSchema(Item, 5);
    try std.testing.expectEqual(plan_ir.ValueCodec.product, local.codec);
    try std.testing.expectEqual(@as(?u16, 5), local.schema_index);

    const output = plan.accumulatorOutput("writer", Item, error{}, schema_refs);
    try std.testing.expectEqualStrings("writer", output.label);
    try std.testing.expectEqual(plan_ir.ValueCodec.product, output.codec);
    try std.testing.expectEqual(@as(?u16, 5), output.schema_index);
}

test "writer instance shell stays prompt-sized" {
    const WriterInstance = Instance([]const u8, error{});
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(WriterInstance));
}

test "writer handle accumulates items in order" {
    const NoError = error{};
    const WriterInstance = Instance([]const u8, NoError);
    const demo = struct {
        /// Append two items and then return normally.
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(family.computeProgram(Cap, ctx, struct {
            /// Append two items and then return normally.
            pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
                try tell(ProgramCap, program_ctx, "a");
                try tell(ProgramCap, program_ctx, "b");
                return "done";
            }
        })) {
            return family.computeProgram(Cap, ctx, struct {
                /// Append two items and then return normally.
                pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
                    try tell(ProgramCap, program_ctx, "a");
                    try tell(ProgramCap, program_ctx, "b");
                    return "done";
                }
            });
        }
    };

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = WriterInstance.init();
    const result = try handle([]const u8, []const u8, &runtime, &instance, std.testing.allocator, demo);
    defer std.testing.allocator.free(result.items);
    try std.testing.expectEqual(@as(usize, 2), result.items.len);
    try std.testing.expectEqualStrings("a", result.items[0]);
    try std.testing.expectEqualStrings("b", result.items[1]);
    try std.testing.expectEqualStrings("done", result.value);
}

test "public writer handleWithErrorSet leaves caller provenance absent by default" {
    const NoError = error{};
    const WriterInstance = Instance([]const u8, NoError);

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = WriterInstance.init();

    const result = try handleWithErrorSet(.{
        .Item = []const u8,
        .Answer = []const u8,
        .ErrorSet = NoError,
    }, &runtime, &instance, std.testing.allocator, struct {
        /// Report whether the source-compatible writer wrapper leaves caller provenance absent.
        pub fn body(comptime Cap: type, ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
            _ = Cap;
            return if (@TypeOf(ctx.*).caller_source == null) "absent" else "present";
        }
    });
    defer std.testing.allocator.free(result.items);

    try std.testing.expectEqual(@as(usize, 0), result.items.len);
    try std.testing.expectEqualStrings("absent", result.value);
}

test "public writer handle leaves caller provenance absent by default" {
    const NoError = error{};
    const WriterInstance = Instance([]const u8, NoError);

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = WriterInstance.init();

    const result = try handle([]const u8, []const u8, &runtime, &instance, std.testing.allocator, struct {
        /// Report whether the source-compatible writer wrapper leaves caller provenance absent.
        pub fn body(comptime Cap: type, ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
            _ = Cap;
            return if (@TypeOf(ctx.*).caller_source == null) "absent" else "present";
        }
    });
    defer std.testing.allocator.free(result.items);

    try std.testing.expectEqual(@as(usize, 0), result.items.len);
    try std.testing.expectEqualStrings("absent", result.value);
}

test "nested same-shaped writer handles get distinct capability types" {
    const NoError = error{};
    const WriterInstance = Instance([]const u8, NoError);
    const demo = struct {
        var runtime_ptr: ?*ability.Runtime = null;
        var inner_ptr: ?*const WriterInstance = null;

        /// Open an inner writer handle and prove its capability differs from the outer one.
        pub fn outer(comptime OuterCap: type, _: anytype) lowered_machine.ResetError(NoError)![]const u8 {
            const result = try handle([]const u8, []const u8, runtime_ptr.?, inner_ptr.?, std.testing.allocator, struct {
                /// Reject capability-type collapse inside the nested writer handle.
                pub fn program(comptime InnerCap: type, inner_ctx: anytype) @TypeOf(family.computeProgram(InnerCap, inner_ctx, struct {
                    /// Return a neutral value from the nested writer body.
                    pub fn run(_: type, _: anytype) []const u8 {
                        return "done";
                    }
                })) {
                    comptime if (OuterCap == InnerCap) {
                        @compileError("nested writer handles must receive distinct capability types");
                    };
                    return family.computeProgram(InnerCap, inner_ctx, struct {
                        /// Return a neutral value from the nested writer body.
                        pub fn run(_: type, _: anytype) []const u8 {
                            return "done";
                        }
                    });
                }
            });
            defer std.testing.allocator.free(result.items);
            return result.value;
        }
    };

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var outer_instance = WriterInstance.init();
    var inner_instance = WriterInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    const result = try handle([]const u8, []const u8, &runtime, &outer_instance, std.testing.allocator, struct {
        /// Enter the outer writer handle and hand its capability inward.
        pub fn program(comptime OuterCap: type, ctx: anytype) @TypeOf(family.computeProgram(OuterCap, ctx, struct {
            /// Re-enter the nested writer witness through the outer capability.
            pub fn run(_: type, _: anytype) lowered_machine.ResetError(NoError)![]const u8 {
                return try demo.outer(OuterCap, {});
            }
        })) {
            return family.computeProgram(OuterCap, ctx, struct {
                /// Re-enter the nested writer witness through the outer capability.
                pub fn run(_: type, _: anytype) lowered_machine.ResetError(NoError)![]const u8 {
                    return try demo.outer(OuterCap, {});
                }
            });
        }
    });
    defer std.testing.allocator.free(result.items);
    try std.testing.expectEqualStrings("done", result.value);
}
