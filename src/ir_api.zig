// zlinter-disable declaration_naming - retained compatibility aliases intentionally preserve the prior public IR vocabulary.
// zlinter-disable require_doc_comment - this compatibility module re-exports documented declarations from the underlying namespaces.
const effect_ir = @import("effect_ir");
const internal_kernel = @import("internal_kernel");
const lowering_api = @import("lowering_api");
const program_plan = @import("internal_program_plan");

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

    /// Higher-level typed ProgramPlan constructors for common public examples.
    pub const typed = struct {
        fn mustPlan(result: program_plan.ValidationError!program_plan.ProgramPlan) program_plan.ProgramPlan {
            return result catch |err| @compileError("ability.ir.builder.typed produced invalid ProgramPlan: " ++ @errorName(err));
        }

        fn mustInstruction(result: program_plan.ValidationError!program_plan.Instruction) program_plan.Instruction {
            return result catch |err| @compileError("ability.ir.builder.typed produced invalid instruction: " ++ @errorName(err));
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
            const instructions = [_]program_plan.Instruction{
                .{ .kind = .const_i32, .dst = result.index, .operand = constant },
                mustInstruction(returnValue(root, result)),
            };
            const functions = [_]program_plan.FunctionPlan{.{
                .symbol_name = "run",
                .value_codec = .i32,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 1,
                .first_block = 0,
                .entry_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = @intCast(instructions.len),
            }};
            const blocks = [_]program_plan.BlockPlan{.{
                .first_instruction = 0,
                .instruction_count = @intCast(instructions.len),
                .terminator_index = 0,
            }};
            const terminators = [_]program_plan.Terminator{.{ .kind = .return_value }};

            return mustPlan(finish(.{
                .label = label,
                .ir_hash = 0x746270000001,
                .entry = root,
                .functions = &functions,
                .requirements = &.{},
                .ops = &.{},
                .outputs = &.{},
                .locals = &.{.{ .codec = .i32 }},
                .blocks = &blocks,
                .terminators = &terminators,
                .instructions = &instructions,
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
            const instructions = [_]program_plan.Instruction{
                mustInstruction(returnValue(root, payload)),
            };
            const functions = [_]program_plan.FunctionPlan{.{
                .symbol_name = "run",
                .value_codec = .product,
                .value_schema_index = 0,
                .parameter_count = 1,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 1,
                .first_block = 0,
                .entry_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = @intCast(instructions.len),
            }};
            const value_schemas = [_]program_plan.ValueSchemaPlan{.{
                .label = @typeName(Payload),
                .codec = .product,
                .first_field = 0,
                .field_count = @intCast(fields.len),
            }};
            const blocks = [_]program_plan.BlockPlan{.{
                .first_instruction = 0,
                .instruction_count = @intCast(instructions.len),
                .terminator_index = 0,
            }};
            const terminators = [_]program_plan.Terminator{.{ .kind = .return_value }};

            return mustPlan(finish(.{
                .label = label,
                .ir_hash = 0x746270000002,
                .entry = root,
                .functions = &functions,
                .requirements = &.{},
                .ops = &.{},
                .outputs = &.{},
                .value_schemas = &value_schemas,
                .value_fields = fields,
                .value_variants = &.{},
                .locals = &.{.{ .codec = .product, .schema_index = 0 }},
                .blocks = &blocks,
                .terminators = &terminators,
                .instructions = &instructions,
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
            const instructions = [_]program_plan.Instruction{
                mustInstruction(sumVariantIs(root, condition, payload, spec.variant_ordinal)),
                .{ .kind = .const_i32, .dst = result.index, .operand = spec.matched_value },
                mustInstruction(returnValue(root, result)),
                .{ .kind = .const_i32, .dst = result.index, .operand = spec.fallback_value },
                mustInstruction(returnValue(root, result)),
            };
            const functions = [_]program_plan.FunctionPlan{.{
                .symbol_name = "run",
                .value_codec = .i32,
                .parameter_count = 1,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 3,
                .first_block = 0,
                .entry_block = 0,
                .block_count = 3,
                .first_instruction = 0,
                .instruction_count = @intCast(instructions.len),
            }};
            const value_schemas = [_]program_plan.ValueSchemaPlan{.{
                .label = @typeName(Sum),
                .codec = .sum,
                .first_variant = 0,
                .variant_count = @intCast(spec.variants.len),
            }};
            const blocks = [_]program_plan.BlockPlan{
                .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
                .{ .first_instruction = 1, .instruction_count = 2, .terminator_index = 1 },
                .{ .first_instruction = 3, .instruction_count = 2, .terminator_index = 2 },
            };
            const terminators = [_]program_plan.Terminator{
                .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
                .{ .kind = .return_value },
                .{ .kind = .return_value },
            };

            return mustPlan(finish(.{
                .label = spec.label,
                .ir_hash = 0x746270000003,
                .entry = root,
                .functions = &functions,
                .requirements = &.{},
                .ops = &.{},
                .outputs = &.{},
                .value_schemas = &value_schemas,
                .value_fields = &.{},
                .value_variants = spec.variants,
                .locals = &.{
                    .{ .codec = .sum, .schema_index = 0 },
                    .{ .codec = .bool },
                    .{ .codec = .i32 },
                },
                .blocks = &blocks,
                .terminators = &terminators,
                .instructions = &instructions,
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
            const instructions = [_]program_plan.Instruction{
                mustInstruction(sumExtractPayload(root, extracted, payload, variant_ordinal)),
                mustInstruction(returnValue(root, extracted)),
            };
            const functions = [_]program_plan.FunctionPlan{.{
                .symbol_name = "run",
                .value_codec = .i32,
                .parameter_count = 1,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 2,
                .first_block = 0,
                .entry_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = @intCast(instructions.len),
            }};
            const value_schemas = [_]program_plan.ValueSchemaPlan{.{
                .label = @typeName(Sum),
                .codec = .sum,
                .first_variant = 0,
                .variant_count = @intCast(variants.len),
            }};
            const blocks = [_]program_plan.BlockPlan{.{
                .first_instruction = 0,
                .instruction_count = @intCast(instructions.len),
                .terminator_index = 0,
            }};
            const terminators = [_]program_plan.Terminator{.{ .kind = .return_value }};

            return mustPlan(finish(.{
                .label = label,
                .ir_hash = 0x746270000004,
                .entry = root,
                .functions = &functions,
                .requirements = &.{},
                .ops = &.{},
                .outputs = &.{},
                .value_schemas = &value_schemas,
                .value_fields = &.{},
                .value_variants = variants,
                .locals = &.{
                    .{ .codec = .sum, .schema_index = 0 },
                    .{ .codec = .i32 },
                },
                .blocks = &blocks,
                .terminators = &terminators,
                .instructions = &instructions,
            }));
        }

        /// Build a unit-returning plan that declares typed outputs for collection hooks.
        pub fn unitWithOutputs(
            comptime label: []const u8,
            comptime outputs: []const program_plan.OutputPlan,
        ) program_plan.ProgramPlan {
            const root = function(0);
            const functions = [_]program_plan.FunctionPlan{.{
                .symbol_name = "run",
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = @intCast(outputs.len),
                .first_local = 0,
                .local_count = 0,
                .first_block = 0,
                .entry_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 0,
            }};
            const blocks = [_]program_plan.BlockPlan{.{
                .first_instruction = 0,
                .instruction_count = 0,
                .terminator_index = 0,
            }};
            const terminators = [_]program_plan.Terminator{.{ .kind = .return_unit }};

            return mustPlan(finish(.{
                .label = label,
                .ir_hash = 0x746270000005,
                .entry = root,
                .functions = &functions,
                .requirements = &.{},
                .ops = &.{},
                .outputs = outputs,
                .locals = &.{},
                .blocks = &blocks,
                .terminators = &terminators,
                .instructions = &.{},
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
