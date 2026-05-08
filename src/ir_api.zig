// zlinter-disable declaration_naming - retained compatibility aliases intentionally preserve the prior public IR vocabulary.
// zlinter-disable no_undefined - the layout builder fills fixed comptime table buffers before validation observes them.
// zlinter-disable require_doc_comment - this compatibility module re-exports documented declarations from the underlying namespaces.
const effect_ir = @import("effect_ir");
const internal_kernel = @import("internal_kernel");
const lowering_api = @import("lowering_api");
const program_plan = @import("internal_program_plan");
const standard = @import("std");

/// Preserve the prior effect_ir namespace while layering public compile helpers on top.
pub const ControlMode = effect_ir.ControlMode;
/// Runtime-owned executable plan control mode.
pub const PlanControlMode = program_plan.ControlMode;
pub const Transform = effect_ir.Transform;
pub const Choice = effect_ir.Choice;
pub const Abort = effect_ir.Abort;
pub const NormalizedLeaf = effect_ir.NormalizedLeaf;
pub const NormalizedRow = effect_ir.NormalizedRow;
pub const MergedRows = effect_ir.MergedRows;
pub const SymbolRef = effect_ir.SymbolRef;
pub const OutputSpec = effect_ir.OutputSpec;
pub const OpSpec = effect_ir.OpSpec;
pub const Requirement = effect_ir.Requirement;
pub const Row = effect_ir.Row;
pub const CallEdge = effect_ir.CallEdge;
pub const LocalId = effect_ir.LocalId;
pub const BlockId = effect_ir.BlockId;
pub const LocalCodec = effect_ir.LocalCodec;
pub const EffectValueCodec = effect_ir.ValueCodec;
pub const EffectValueRef = effect_ir.ValueRef;
pub const InstructionKind = effect_ir.InstructionKind;
pub const Instruction = effect_ir.Instruction;
pub const TerminatorKind = effect_ir.TerminatorKind;
pub const Terminator = effect_ir.Terminator;
pub const Block = effect_ir.Block;
pub const FunctionBody = effect_ir.FunctionBody;
pub const ResolverGraph = effect_ir.ResolverGraph;
pub const SccGroup = effect_ir.SccGroup;
pub const Function = effect_ir.Function;
pub const Program = effect_ir.Program;
pub const SccComponent = effect_ir.SccComponent;
pub const SccResolution = effect_ir.SccResolution;
pub const NormalizationDigest = effect_ir.NormalizationDigest;
pub const NormalizeError = effect_ir.NormalizeError;
/// Runtime-owned executable program plan.
pub const ProgramPlan = program_plan.ProgramPlan;
/// Runtime-owned scalar value carrier for ProgramPlan entry arguments.
pub const ProgramValue = internal_kernel.ProgramValue;
/// Runtime-owned value codec tag.
pub const ValueCodec = program_plan.ValueCodec;
/// Runtime-owned value reference.
pub const ValueRef = program_plan.ValueRef;
/// Explicit resolver entry for executable nested lexical-with rows.
pub const NestedWithTarget = lowering_api.NestedWithTarget;
/// Runtime-owned value schema descriptor.
pub const ValueSchemaPlan = program_plan.ValueSchemaPlan;
/// Runtime-owned product-field descriptor.
pub const ValueFieldPlan = program_plan.ValueFieldPlan;
/// Runtime-owned sum-variant descriptor.
pub const ValueVariantPlan = program_plan.ValueVariantPlan;
/// ProgramPlan descriptor aliases for public builder arrays.
pub const plan = struct {
    pub const Block = program_plan.BlockPlan;
    pub const Function = program_plan.FunctionPlan;
    pub const Instruction = program_plan.Instruction;
    pub const InstructionKind = program_plan.InstructionKind;
    pub const Local = program_plan.LocalPlan;
    pub const Op = program_plan.OpPlan;
    pub const Output = program_plan.OutputPlan;
    pub const Requirement = program_plan.RequirementPlan;
    pub const Terminator = program_plan.Terminator;
    pub const TerminatorKind = program_plan.TerminatorKind;
};
pub const rowFromSpec = effect_ir.rowFromSpec;
pub const mergeRows = effect_ir.mergeRows;
pub const symbolIndex = effect_ir.symbolIndex;
pub const validateGraph = effect_ir.validateGraph;
pub const computeSccs = effect_ir.computeSccs;
pub const deinitSccs = effect_ir.deinitSccs;
pub const validateRow = effect_ir.validateRow;
pub const validateOutputs = effect_ir.validateOutputs;
pub const rowDigest = effect_ir.rowDigest;
pub const resolveSccs = effect_ir.resolveSccs;

/// Minimal public ProgramPlan builder namespace.
pub const builder = struct {
    const inner = program_plan.program_plan_builder;

    /// Opaque public function handle.
    pub const FunctionRef = inner.FunctionRef;
    /// Function-owned public local handle.
    pub const LocalRef = inner.LocalRef;
    /// Function-owned public operation handle.
    pub const OpRef = inner.OpRef;
    /// Final materialization payload for a ProgramPlan.
    pub const FinishSpec = inner.FinishSpec;

    /// Create a public function handle by table ordinal.
    pub const function = inner.function;
    /// Create a local handle scoped to a function.
    pub const local = inner.local;
    /// Create an operation handle scoped to a function.
    pub const op = inner.op;
    /// Build a helper call instruction.
    pub const callHelper = inner.callHelper;
    /// Build a helper call instruction that discards its result.
    pub const callHelperDiscardingResult = inner.callHelperDiscardingResult;
    /// Build an effect operation call instruction.
    pub const callOp = inner.callOp;
    /// Build a sum-tag predicate instruction.
    pub const sumVariantIs = inner.sumVariantIs;
    /// Build a sum-payload extraction instruction.
    pub const sumExtractPayload = inner.sumExtractPayload;
    /// Build a return-value instruction.
    pub const returnValue = inner.returnValue;
    /// Materialize and validate a ProgramPlan.
    pub const finish = inner.finish;
    /// Materialize and validate a ProgramPlan with nested lexical-with resolver rows.
    pub const finishWithNestedTargets = inner.finishWithNestedTargets;
    /// Validate an already assembled ProgramPlan through the builder.
    pub const fromValidatedPlan = inner.fromValidatedPlan;

    /// Compositional ProgramPlan authoring layer that computes flat layout spans.
    pub const layout = struct {
        const Span = struct {
            first: u16 = 0,
            count: u16 = 0,
        };

        /// Build a compact span descriptor for function-local requirements or outputs.
        pub fn span(first: u16, count: u16) Span {
            return .{ .first = first, .count = count };
        }

        /// Materialize and validate a ProgramPlan from nested function/block specs.
        pub fn finish(comptime spec: anytype) program_plan.ValidationError!program_plan.ProgramPlan {
            return comptime layout.finishWithNestedTargets(spec, &.{});
        }

        /// Materialize and validate a ProgramPlan with explicit nested lexical-with resolver rows.
        pub fn finishWithNestedTargets(
            comptime spec: anytype,
            comptime nested_with_targets: anytype,
        ) program_plan.ValidationError!program_plan.ProgramPlan {
            return comptime finishWithNestedTargetsImpl(spec, nested_with_targets);
        }

        fn finishWithNestedTargetsImpl(
            comptime spec: anytype,
            comptime nested_with_targets: anytype,
        ) program_plan.ValidationError!program_plan.ProgramPlan {
            const tables = try layoutTables(spec);

            return inner.finishWithNestedTargets(.{
                .schema_version = comptime u32Field(spec, "schema_version", program_plan.ProgramPlan.current_schema_version),
                .label = spec.label,
                .ir_hash = spec.ir_hash,
                .entry = spec.entry,
                .functions = &tables.functions,
                .requirements = comptime tableField(program_plan.RequirementPlan, spec, "requirements"),
                .ops = comptime tableField(program_plan.OpPlan, spec, "ops"),
                .outputs = comptime tableField(program_plan.OutputPlan, spec, "outputs"),
                .value_schemas = comptime tableField(program_plan.ValueSchemaPlan, spec, "value_schemas"),
                .value_fields = comptime tableField(program_plan.ValueFieldPlan, spec, "value_fields"),
                .value_variants = comptime tableField(program_plan.ValueVariantPlan, spec, "value_variants"),
                .locals = &tables.locals,
                .call_args = comptime tableField(u16, spec, "call_args"),
                .blocks = &tables.blocks,
                .terminators = &tables.terminators,
                .instructions = &tables.instructions,
            }, nested_with_targets);
        }

        fn LayoutTables(comptime spec: anytype) type {
            const function_count = spec.functions.len;
            const local_count = comptime countLocals(spec.functions);
            const block_count = comptime countBlocks(spec.functions);
            const instruction_count = comptime countInstructions(spec.functions);

            return struct {
                functions: [function_count]program_plan.FunctionPlan,
                locals: [local_count]program_plan.LocalPlan,
                blocks: [block_count]program_plan.BlockPlan,
                terminators: [block_count]program_plan.Terminator,
                instructions: [instruction_count]program_plan.Instruction,
            };
        }

        fn layoutTables(comptime spec: anytype) program_plan.ValidationError!LayoutTables(spec) {
            const function_count = spec.functions.len;
            const local_count = comptime countLocals(spec.functions);
            const block_count = comptime countBlocks(spec.functions);
            const instruction_count = comptime countInstructions(spec.functions);

            var functions: [function_count]program_plan.FunctionPlan = undefined;
            var locals: [local_count]program_plan.LocalPlan = undefined;
            var blocks: [block_count]program_plan.BlockPlan = undefined;
            var terminators: [block_count]program_plan.Terminator = undefined;
            var instructions: [instruction_count]program_plan.Instruction = undefined;

            var next_local: usize = 0;
            var next_block: usize = 0;
            var next_instruction: usize = 0;

            inline for (spec.functions, 0..) |function_spec, function_index| {
                const first_local = next_local;
                inline for (function_spec.locals) |local_spec| {
                    locals[next_local] = comptime localFromSpec(local_spec);
                    next_local += 1;
                }

                const first_block = next_block;
                const first_instruction = next_instruction;
                inline for (function_spec.blocks) |block_spec| {
                    const block_first_instruction = next_instruction;
                    inline for (block_spec.instructions) |instruction| {
                        instructions[next_instruction] = comptime instructionFromSpec(instruction);
                        next_instruction += 1;
                    }
                    blocks[next_block] = .{
                        .first_instruction = try checkedIndex(block_first_instruction),
                        .instruction_count = try checkedIndex(next_instruction - block_first_instruction),
                        .terminator_index = try checkedIndex(next_block),
                    };
                    terminators[next_block] = try globalizeTerminator(
                        block_spec.terminator,
                        first_block,
                        function_spec.blocks.len,
                    );
                    next_block += 1;
                }

                const value_ref = comptime valueRefField(function_spec, "value_ref", .{ .codec = .unit });
                const result_ref = comptime optionalValueRefField(function_spec, "result_ref");
                const requirement_span = comptime spanField(function_spec, "requirements");
                const output_span = comptime spanField(function_spec, "outputs");
                functions[function_index] = .{
                    .symbol_name = function_spec.symbol_name,
                    .value_codec = value_ref.codec,
                    .value_schema_index = value_ref.schema_index,
                    .result_codec = if (result_ref) |ref| ref.codec else null,
                    .result_schema_index = if (result_ref) |ref| ref.schema_index else null,
                    .parameter_count = comptime u16Field(function_spec, "parameter_count", 0),
                    .first_requirement = requirement_span.first,
                    .requirement_count = requirement_span.count,
                    .first_output = output_span.first,
                    .output_count = output_span.count,
                    .first_local = try checkedIndex(first_local),
                    .local_count = try checkedIndex(next_local - first_local),
                    .first_block = try checkedIndex(first_block),
                    .entry_block = try checkedIndex(first_block + comptime usizeField(function_spec, "entry_block", 0)),
                    .block_count = try checkedIndex(next_block - first_block),
                    .first_instruction = try checkedIndex(first_instruction),
                    .instruction_count = try checkedIndex(next_instruction - first_instruction),
                };
            }

            return .{
                .functions = functions,
                .locals = locals,
                .blocks = blocks,
                .terminators = terminators,
                .instructions = instructions,
            };
        }

        fn countLocals(comptime functions: anytype) usize {
            var count: usize = 0;
            inline for (functions) |function_spec| count += function_spec.locals.len;
            return count;
        }

        fn countBlocks(comptime functions: anytype) usize {
            var count: usize = 0;
            inline for (functions) |function_spec| count += function_spec.blocks.len;
            return count;
        }

        fn countInstructions(comptime functions: anytype) usize {
            var count: usize = 0;
            inline for (functions) |function_spec| {
                inline for (function_spec.blocks) |block_spec| count += block_spec.instructions.len;
            }
            return count;
        }

        fn localFromSpec(comptime local_spec: anytype) program_plan.LocalPlan {
            return .{
                .codec = local_spec.codec,
                .schema_index = if (@hasField(@TypeOf(local_spec), "schema_index")) local_spec.schema_index else null,
            };
        }

        fn instructionFromSpec(comptime instruction: anytype) program_plan.Instruction {
            return .{
                .kind = instruction.kind,
                .dst = if (@hasField(@TypeOf(instruction), "dst")) instruction.dst else 0,
                .operand = if (@hasField(@TypeOf(instruction), "operand")) instruction.operand else 0,
                .aux = if (@hasField(@TypeOf(instruction), "aux")) instruction.aux else 0,
                .string_literal = if (@hasField(@TypeOf(instruction), "string_literal")) instruction.string_literal else "",
            };
        }

        fn globalizeTerminator(
            terminator: program_plan.Terminator,
            comptime first_block: usize,
            comptime block_count: usize,
        ) program_plan.ValidationError!program_plan.Terminator {
            return switch (terminator.kind) {
                .branch_if => .{
                    .kind = .branch_if,
                    .primary = try checkedBlockTarget(first_block, block_count, terminator.primary),
                    .secondary = try checkedBlockTarget(first_block, block_count, terminator.secondary),
                },
                .jump => .{
                    .kind = .jump,
                    .primary = try checkedBlockTarget(first_block, block_count, terminator.primary),
                },
                .return_unit, .return_value => terminator,
            };
        }

        fn checkedBlockTarget(
            comptime first_block: usize,
            comptime block_count: usize,
            target: u16,
        ) program_plan.ValidationError!u16 {
            if (target >= block_count) return error.InvalidTerminatorTarget;
            return checkedIndex(first_block + target);
        }

        fn checkedIndex(comptime index_value: usize) program_plan.ValidationError!u16 {
            if (index_value > standard.math.maxInt(u16)) return error.ProgramPlanTableTooLarge;
            return @intCast(index_value);
        }

        fn tableField(comptime T: type, comptime spec: anytype, comptime field_name: []const u8) []const T {
            if (@hasField(@TypeOf(spec), field_name)) return @field(spec, field_name);
            return &.{};
        }

        fn spanField(comptime spec: anytype, comptime field_name: []const u8) Span {
            if (@hasField(@TypeOf(spec), field_name)) return @field(spec, field_name);
            return .{};
        }

        fn valueRefField(
            comptime spec: anytype,
            comptime field_name: []const u8,
            comptime default: program_plan.ValueRef,
        ) program_plan.ValueRef {
            if (@hasField(@TypeOf(spec), field_name)) return @field(spec, field_name);
            return default;
        }

        fn optionalValueRefField(comptime spec: anytype, comptime field_name: []const u8) ?program_plan.ValueRef {
            if (@hasField(@TypeOf(spec), field_name)) return @field(spec, field_name);
            return null;
        }

        fn u16Field(comptime spec: anytype, comptime field_name: []const u8, comptime default: u16) u16 {
            if (@hasField(@TypeOf(spec), field_name)) return @field(spec, field_name);
            return default;
        }

        fn u32Field(comptime spec: anytype, comptime field_name: []const u8, comptime default: u32) u32 {
            if (@hasField(@TypeOf(spec), field_name)) return @field(spec, field_name);
            return default;
        }

        fn usizeField(comptime spec: anytype, comptime field_name: []const u8, comptime default: usize) usize {
            if (@hasField(@TypeOf(spec), field_name)) return @field(spec, field_name);
            return default;
        }
    };

    /// Higher-level typed ProgramPlan constructors for common public examples.
    pub const typed = struct {
        fn mustPlan(result: program_plan.ValidationError!program_plan.ProgramPlan) program_plan.ProgramPlan {
            return result catch |err| @compileError("ability.ir.builder.typed produced invalid ProgramPlan: " ++ @errorName(err));
        }

        fn mustInstruction(result: program_plan.ValidationError!program_plan.Instruction) program_plan.Instruction {
            return result catch |err| @compileError("ability.ir.builder.typed produced invalid instruction: " ++ @errorName(err));
        }

        fn constI32(dst: LocalRef, comptime literal: i32) program_plan.Instruction {
            if (literal >= 0 and literal <= standard.math.maxInt(u16)) {
                return .{ .kind = .const_i32, .dst = dst.index, .operand = @intCast(literal) };
            }
            return .{
                .kind = .const_i32,
                .dst = dst.index,
                .string_literal = standard.fmt.comptimePrint("{d}", .{literal}),
            };
        }

        /// Options for a one-argument sum branch returning one of two `i32` constants.
        pub const SumVariantI32BranchSpec = struct {
            label: []const u8,
            variants: []const program_plan.ValueVariantPlan,
            variant_ordinal: u16,
            matched_value: i32,
            fallback_value: i32,
        };

        /// Build a scalar no-arg program that returns one `i32` constant.
        pub fn scalarConstI32(comptime label: []const u8, comptime constant: i32) program_plan.ProgramPlan {
            const root = function(0);
            const result = local(root, 0);

            return mustPlan(layout.finish(.{
                .label = label,
                .ir_hash = 0x746270000001,
                .entry = root,
                .functions = .{.{
                    .symbol_name = "run",
                    .value_ref = program_plan.ValueRef{ .codec = .i32 },
                    .locals = .{.{ .codec = .i32 }},
                    .blocks = .{.{
                        .instructions = .{
                            constI32(result, constant),
                            mustInstruction(returnValue(root, result)),
                        },
                        .terminator = program_plan.Terminator{ .kind = .return_value },
                    }},
                }},
            }));
        }

        /// Build a one-argument product identity program.
        pub fn productIdentity(
            comptime Payload: type,
            comptime label: []const u8,
            comptime fields: []const program_plan.ValueFieldPlan,
        ) program_plan.ProgramPlan {
            const root = function(0);
            const payload = local(root, 0);
            const value_schemas = [_]program_plan.ValueSchemaPlan{.{
                .label = @typeName(Payload),
                .codec = .product,
                .first_field = 0,
                .field_count = @intCast(fields.len),
            }};

            return mustPlan(layout.finish(.{
                .label = label,
                .ir_hash = 0x746270000002,
                .entry = root,
                .value_schemas = &value_schemas,
                .value_fields = fields,
                .functions = .{.{
                    .symbol_name = "run",
                    .value_ref = program_plan.ValueRef{ .codec = .product, .schema_index = 0 },
                    .parameter_count = 1,
                    .locals = .{.{ .codec = .product, .schema_index = 0 }},
                    .blocks = .{.{
                        .instructions = .{
                            mustInstruction(returnValue(root, payload)),
                        },
                        .terminator = program_plan.Terminator{ .kind = .return_value },
                    }},
                }},
            }));
        }

        /// Build a one-argument sum program that returns one of two `i32` constants.
        pub fn sumVariantI32Branch(
            comptime Sum: type,
            comptime spec: SumVariantI32BranchSpec,
        ) program_plan.ProgramPlan {
            const root = function(0);
            const payload = local(root, 0);
            const condition = local(root, 1);
            const result = local(root, 2);
            const value_schemas = [_]program_plan.ValueSchemaPlan{.{
                .label = @typeName(Sum),
                .codec = .sum,
                .first_variant = 0,
                .variant_count = @intCast(spec.variants.len),
            }};

            return mustPlan(layout.finish(.{
                .label = spec.label,
                .ir_hash = 0x746270000003,
                .entry = root,
                .value_schemas = &value_schemas,
                .value_variants = spec.variants,
                .functions = .{.{
                    .symbol_name = "run",
                    .value_ref = program_plan.ValueRef{ .codec = .i32 },
                    .parameter_count = 1,
                    .locals = .{
                        .{ .codec = .sum, .schema_index = 0 },
                        .{ .codec = .bool },
                        .{ .codec = .i32 },
                    },
                    .blocks = .{
                        .{
                            .instructions = .{
                                mustInstruction(sumVariantIs(root, condition, payload, spec.variant_ordinal)),
                            },
                            .terminator = program_plan.Terminator{ .kind = .branch_if, .primary = 1, .secondary = 2 },
                        },
                        .{
                            .instructions = .{
                                constI32(result, spec.matched_value),
                                mustInstruction(returnValue(root, result)),
                            },
                            .terminator = program_plan.Terminator{ .kind = .return_value },
                        },
                        .{
                            .instructions = .{
                                constI32(result, spec.fallback_value),
                                mustInstruction(returnValue(root, result)),
                            },
                            .terminator = program_plan.Terminator{ .kind = .return_value },
                        },
                    },
                }},
            }));
        }

        /// Build a one-argument sum program that extracts an `i32` payload variant.
        pub fn sumExtractI32Payload(
            comptime Sum: type,
            comptime label: []const u8,
            comptime variants: []const program_plan.ValueVariantPlan,
            comptime variant_ordinal: u16,
        ) program_plan.ProgramPlan {
            const root = function(0);
            const payload = local(root, 0);
            const extracted = local(root, 1);
            const value_schemas = [_]program_plan.ValueSchemaPlan{.{
                .label = @typeName(Sum),
                .codec = .sum,
                .first_variant = 0,
                .variant_count = @intCast(variants.len),
            }};

            return mustPlan(layout.finish(.{
                .label = label,
                .ir_hash = 0x746270000004,
                .entry = root,
                .value_schemas = &value_schemas,
                .value_variants = variants,
                .functions = .{.{
                    .symbol_name = "run",
                    .value_ref = program_plan.ValueRef{ .codec = .i32 },
                    .parameter_count = 1,
                    .locals = .{
                        .{ .codec = .sum, .schema_index = 0 },
                        .{ .codec = .i32 },
                    },
                    .blocks = .{.{
                        .instructions = .{
                            mustInstruction(sumExtractPayload(root, extracted, payload, variant_ordinal)),
                            mustInstruction(returnValue(root, extracted)),
                        },
                        .terminator = program_plan.Terminator{ .kind = .return_value },
                    }},
                }},
            }));
        }

        /// Build a unit-returning plan that declares typed outputs for collection hooks.
        pub fn unitWithOutputs(
            comptime label: []const u8,
            comptime outputs: []const program_plan.OutputPlan,
        ) program_plan.ProgramPlan {
            const root = function(0);

            return mustPlan(layout.finish(.{
                .label = label,
                .ir_hash = 0x746270000005,
                .entry = root,
                .outputs = outputs,
                .functions = .{.{
                    .symbol_name = "run",
                    .outputs = layout.span(0, outputs.len),
                    .locals = .{},
                    .blocks = .{.{
                        .instructions = .{},
                        .terminator = program_plan.Terminator{ .kind = .return_unit },
                    }},
                }},
            }));
        }
    };
};

/// Minimal public value-shape helpers for ProgramPlan schemas.
pub const value = struct {
    /// Derive the coarse ProgramPlan codec for a Zig type.
    pub const codecForType = program_plan.codecForType;
    /// Count product fields for a supported Zig product type.
    pub const fieldCountForType = program_plan.fieldCountForType;
    /// Count sum variants for a supported Zig sum type.
    pub const variantCountForType = program_plan.variantCountForType;

    /// Build a scalar value field descriptor.
    pub fn field(comptime name: []const u8, comptime T: type) program_plan.ValueFieldPlan {
        const codec = comptime program_plan.codecForType(T) catch @compileError("unsupported ProgramPlan field type");
        return .{
            .name = name,
            .codec = codec,
        };
    }

    /// Build a nested value field descriptor.
    pub fn nestedField(comptime name: []const u8, comptime T: type, schema_index: u16) program_plan.ValueFieldPlan {
        const codec = comptime program_plan.codecForType(T) catch @compileError("unsupported ProgramPlan field type");
        return .{
            .name = name,
            .codec = codec,
            .schema_index = schema_index,
        };
    }

    /// Build a scalar sum variant descriptor.
    pub fn variant(comptime name: []const u8, comptime T: type) program_plan.ValueVariantPlan {
        const codec = comptime program_plan.codecForType(T) catch @compileError("unsupported ProgramPlan variant type");
        return .{
            .name = name,
            .codec = codec,
        };
    }

    /// Build a unit sum variant descriptor.
    pub fn unitVariant(comptime name: []const u8) program_plan.ValueVariantPlan {
        return .{ .name = name };
    }

    /// Build a nested sum variant descriptor.
    pub fn nestedVariant(comptime name: []const u8, comptime T: type, schema_index: u16) program_plan.ValueVariantPlan {
        const codec = comptime program_plan.codecForType(T) catch @compileError("unsupported ProgramPlan variant type");
        return .{
            .name = name,
            .codec = codec,
            .schema_index = schema_index,
        };
    }
};

test "compatibility IR module re-exports retained surface" {
    const std = @import("std");

    try std.testing.expect(@hasDecl(@This(), "Program"));
    try std.testing.expect(@hasDecl(@This(), "rowDigest"));
    try std.testing.expect(@hasDecl(@This(), "builder"));
    try std.testing.expect(@hasDecl(@This(), "value"));
    try std.testing.expect(!@hasDecl(@This(), "compile"));
    try std.testing.expect(internal_kernel.ValueSchemaPlan == program_plan.ValueSchemaPlan);
    try std.testing.expect(internal_kernel.ValueFieldPlan == program_plan.ValueFieldPlan);
    try std.testing.expect(internal_kernel.ValueVariantPlan == program_plan.ValueVariantPlan);
}

test "public builder materializes a ProgramPlan with product schema metadata" {
    const std = @import("std");

    const Product = struct {
        amount: i32,
        label: []const u8,
    };
    const root = builder.function(0);
    const product_fields = [_]ValueFieldPlan{
        value.field("amount", i32),
        value.field("label", []const u8),
    };
    const value_schemas = [_]ValueSchemaPlan{.{
        .label = "Product",
        .codec = try value.codecForType(Product),
        .first_field = 0,
        .field_count = @intCast(product_fields.len),
    }};
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "root",
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 1,
        .first_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 0,
    }};
    const outputs = [_]program_plan.OutputPlan{.{
        .label = "product",
        .codec = .product,
        .schema_index = 0,
    }};
    const blocks = [_]program_plan.BlockPlan{.{
        .first_instruction = 0,
        .instruction_count = 0,
        .terminator_index = 0,
    }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_unit }};

    const built_plan = try builder.finish(.{
        .label = "public.builder.product",
        .ir_hash = 1,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &outputs,
        .value_schemas = &value_schemas,
        .value_fields = &product_fields,
        .value_variants = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &.{},
    });

    try std.testing.expectEqual(ValueCodec.product, built_plan.outputs[0].codec);
    try std.testing.expectEqual(@as(u16, 0), built_plan.outputs[0].schema_index.?);
}

fn testInstruction(result: program_plan.ValidationError!program_plan.Instruction) program_plan.Instruction {
    return result catch |err| standard.debug.panic("invalid layout test instruction: {s}", .{@errorName(err)});
}

fn testConstI32(dst: builder.LocalRef, comptime literal: i32) program_plan.Instruction {
    if (literal >= 0 and literal <= standard.math.maxInt(u16)) {
        return .{ .kind = .const_i32, .dst = dst.index, .operand = @intCast(literal) };
    }
    return .{
        .kind = .const_i32,
        .dst = dst.index,
        .string_literal = standard.fmt.comptimePrint("{d}", .{literal}),
    };
}

test "layout builder computes scalar and output plan spans" {
    const std = @import("std");

    const root = comptime builder.function(0);
    const result = comptime builder.local(root, 0);
    const outputs = [_]program_plan.OutputPlan{.{
        .label = "writer",
        .codec = .i32,
    }};
    const built_plan = comptime builder.layout.finish(.{
        .label = "layout.scalar.output",
        .ir_hash = 10,
        .entry = root,
        .outputs = &outputs,
        .functions = .{.{
            .symbol_name = "run",
            .value_ref = program_plan.ValueRef{ .codec = .i32 },
            .outputs = builder.layout.span(0, outputs.len),
            .locals = .{.{ .codec = .i32 }},
            .entry_block = 0,
            .blocks = .{.{
                .instructions = .{
                    testConstI32(result, 42),
                    testInstruction(builder.returnValue(root, result)),
                },
                .terminator = program_plan.Terminator{ .kind = .return_value },
            }},
        }},
    }) catch unreachable;

    try std.testing.expectEqualStrings("layout.scalar.output", built_plan.label);
    try std.testing.expectEqual(@as(u16, 0), built_plan.functions[0].first_local);
    try std.testing.expectEqual(@as(u16, 1), built_plan.functions[0].local_count);
    try std.testing.expectEqual(@as(u16, 0), built_plan.functions[0].first_block);
    try std.testing.expectEqual(@as(u16, 0), built_plan.functions[0].entry_block);
    try std.testing.expectEqual(@as(u16, 1), built_plan.functions[0].block_count);
    try std.testing.expectEqual(@as(u16, 0), built_plan.functions[0].first_instruction);
    try std.testing.expectEqual(@as(u16, 2), built_plan.functions[0].instruction_count);
    try std.testing.expectEqual(@as(u16, 0), built_plan.blocks[0].first_instruction);
    try std.testing.expectEqual(@as(u16, 2), built_plan.blocks[0].instruction_count);
    try std.testing.expectEqual(@as(u16, 0), built_plan.blocks[0].terminator_index);
    try std.testing.expectEqual(@as(u16, 0), built_plan.functions[0].first_output);
    try std.testing.expectEqual(@as(u16, 1), built_plan.functions[0].output_count);
}

test "layout builder computes product and sum instruction layout" {
    const std = @import("std");

    const Product = struct {
        amount: i32,
    };
    const Sum = union(enum) {
        none,
        yes: i32,
    };
    const root = comptime builder.function(0);
    const product_local = comptime builder.local(root, 0);
    const sum_local = comptime builder.local(root, 1);
    const is_yes = comptime builder.local(root, 2);
    const extracted = comptime builder.local(root, 3);
    const fallback = comptime builder.local(root, 4);
    const product_fields = comptime [_]program_plan.ValueFieldPlan{
        value.field("amount", i32),
    };
    const sum_variants = comptime [_]program_plan.ValueVariantPlan{
        value.unitVariant("none"),
        value.variant("yes", i32),
    };
    const value_schemas = comptime [_]program_plan.ValueSchemaPlan{
        .{
            .label = @typeName(Product),
            .codec = .product,
            .first_field = 0,
            .field_count = product_fields.len,
        },
        .{
            .label = @typeName(Sum),
            .codec = .sum,
            .first_variant = 0,
            .variant_count = sum_variants.len,
        },
    };
    const built_plan = comptime builder.layout.finish(.{
        .label = "layout.product.sum",
        .ir_hash = 11,
        .entry = root,
        .value_schemas = &value_schemas,
        .value_fields = &product_fields,
        .value_variants = &sum_variants,
        .functions = .{.{
            .symbol_name = "run",
            .value_ref = program_plan.ValueRef{ .codec = .i32 },
            .parameter_count = 2,
            .locals = .{
                .{ .codec = .product, .schema_index = 0 },
                .{ .codec = .sum, .schema_index = 1 },
                .{ .codec = .bool },
                .{ .codec = .i32 },
                .{ .codec = .i32 },
            },
            .entry_block = 0,
            .blocks = .{
                .{
                    .instructions = .{
                        testInstruction(builder.sumVariantIs(root, is_yes, sum_local, 1)),
                    },
                    .terminator = program_plan.Terminator{ .kind = .branch_if, .primary = 1, .secondary = 2 },
                },
                .{
                    .instructions = .{
                        testInstruction(builder.sumExtractPayload(root, extracted, sum_local, 1)),
                        testInstruction(builder.returnValue(root, extracted)),
                    },
                    .terminator = program_plan.Terminator{ .kind = .return_value },
                },
                .{
                    .instructions = .{
                        testConstI32(fallback, 0),
                        testInstruction(builder.returnValue(root, fallback)),
                    },
                    .terminator = program_plan.Terminator{ .kind = .return_value },
                },
            },
        }},
    }) catch unreachable;

    _ = product_local;
    try std.testing.expectEqual(@as(u16, 5), built_plan.functions[0].local_count);
    try std.testing.expectEqual(@as(u16, 3), built_plan.functions[0].block_count);
    try std.testing.expectEqual(@as(u16, 5), built_plan.functions[0].instruction_count);
    try std.testing.expectEqual(@as(u16, 0), built_plan.blocks[0].first_instruction);
    try std.testing.expectEqual(@as(u16, 1), built_plan.blocks[1].first_instruction);
    try std.testing.expectEqual(@as(u16, 3), built_plan.blocks[2].first_instruction);
    try std.testing.expectEqual(@as(u16, 1), built_plan.terminators[0].primary);
    try std.testing.expectEqual(@as(u16, 2), built_plan.terminators[0].secondary);
    try std.testing.expectEqual(ValueCodec.product, built_plan.locals[0].codec);
    try std.testing.expectEqual(@as(u16, 0), built_plan.locals[0].schema_index.?);
    try std.testing.expectEqual(ValueCodec.sum, built_plan.locals[1].codec);
    try std.testing.expectEqual(@as(u16, 1), built_plan.locals[1].schema_index.?);
}

test "layout builder globalizes function-local branch targets" {
    const std = @import("std");

    const helper = comptime builder.function(0);
    const root = comptime builder.function(1);
    const condition = comptime builder.local(root, 0);
    const result = comptime builder.local(root, 1);
    const built_plan = comptime builder.layout.finish(.{
        .label = "layout.branch.target",
        .ir_hash = 12,
        .entry = root,
        .functions = .{
            .{
                .symbol_name = "helper",
                .locals = .{},
                .entry_block = 0,
                .blocks = .{.{
                    .instructions = .{},
                    .terminator = program_plan.Terminator{ .kind = .return_unit },
                }},
            },
            .{
                .symbol_name = "run",
                .value_ref = program_plan.ValueRef{ .codec = .i32 },
                .locals = .{
                    .{ .codec = .bool },
                    .{ .codec = .i32 },
                },
                .entry_block = 0,
                .blocks = .{
                    .{
                        .instructions = .{
                            .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = result.index },
                        },
                        .terminator = program_plan.Terminator{ .kind = .branch_if, .primary = 1, .secondary = 2 },
                    },
                    .{
                        .instructions = .{
                            testConstI32(result, 7),
                            testInstruction(builder.returnValue(root, result)),
                        },
                        .terminator = program_plan.Terminator{ .kind = .return_value },
                    },
                    .{
                        .instructions = .{
                            testConstI32(result, 8),
                            testInstruction(builder.returnValue(root, result)),
                        },
                        .terminator = program_plan.Terminator{ .kind = .return_value },
                    },
                },
            },
        },
    }) catch unreachable;

    try std.testing.expectEqual(@as(u16, 1), built_plan.functions[1].first_block);
    try std.testing.expectEqual(@as(u16, 1), built_plan.functions[1].entry_block);
    try std.testing.expectEqual(@as(u16, 2), built_plan.terminators[1].primary);
    try std.testing.expectEqual(@as(u16, 3), built_plan.terminators[1].secondary);
    _ = helper;
}
