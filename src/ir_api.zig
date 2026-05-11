// zlinter-disable declaration_naming - retained compatibility aliases intentionally preserve the prior public IR vocabulary.
// zlinter-disable field_naming function_naming - public schema helpers intentionally use value-like names and type-valued fields.
// zlinter-disable max_positional_args - schema/protocol fingerprint helpers mirror the explicit fingerprint field set.
// zlinter-disable no_undefined - the layout builder fills fixed comptime table buffers before validation observes them.
// zlinter-disable require_doc_comment - this compatibility module re-exports documented declarations from the underlying namespaces.
const effect_ir = @import("effect_ir");
const effect_schema = @import("effect_schema.zig");
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
                    .entry_block = try checkedIndex(comptime usizeField(function_spec, "entry_block", 0)),
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

    /// Semantic/compositional ProgramPlan authoring layer.
    pub const semantic = struct {
        const SemanticInstructionKind = enum {
            add_i32,
            call,
            compare_eq_zero,
            const_i32,
            const_string,
            const_usize,
            sub_one,
            sum_extract_payload,
            sum_variant_is,
        };

        const SemanticTerminatorKind = enum {
            branch_if,
            jump,
            return_error,
            return_unit,
            return_value,
        };

        /// Semantic label attached to one lowered call_op instruction.
        pub const SiteMetadata = struct {
            instruction_index: usize,
            label: []const u8,
        };

        /// Build a compact span descriptor for function-local requirements or outputs.
        pub const span = layout.span;

        const LocalKind = enum {
            ordinary,
            parameter,
        };

        fn LocalSpec(comptime T: type, comptime kind: LocalKind) type {
            return struct {
                pub const Type = T;
                pub const is_param = kind == .parameter;
                name: []const u8,
            };
        }

        fn RefLocalSpec(comptime kind: LocalKind) type {
            return struct {
                pub const is_param = kind == .parameter;
                name: []const u8,
                ref: program_plan.ValueRef,
            };
        }

        /// Declare a function parameter local by Zig type.
        pub fn param(comptime name: []const u8, comptime T: type) LocalSpec(T, .parameter) {
            return .{ .name = name };
        }

        /// Declare an ordinary function local by Zig type.
        pub fn local(comptime name: []const u8, comptime T: type) LocalSpec(T, .ordinary) {
            return .{ .name = name };
        }

        /// Declare a function parameter local by explicit ProgramPlan value ref.
        pub fn paramRef(comptime name: []const u8, comptime ref_value: program_plan.ValueRef) RefLocalSpec(.parameter) {
            return .{ .name = name, .ref = ref_value };
        }

        /// Declare an ordinary function local by explicit ProgramPlan value ref.
        pub fn localRef(comptime name: []const u8, comptime ref_value: program_plan.ValueRef) RefLocalSpec(.ordinary) {
            return .{ .name = name, .ref = ref_value };
        }

        fn NamedInstruction(comptime kind: SemanticInstructionKind) type {
            return struct {
                pub const semantic_kind = kind;
                dst: []const u8 = "",
                operand: []const u8 = "",
                aux_name: []const u8 = "",
                aux: u16 = 0,
                string_literal: []const u8 = "",
            };
        }

        fn CallInstruction(comptime OpDescriptor: type) type {
            return struct {
                pub const semantic_kind = SemanticInstructionKind.call;
                pub const Op = OpDescriptor;
                dst: ?[]const u8 = null,
                payload: ?[]const u8 = null,
                label: ?[]const u8 = null,
            };
        }

        fn TerminatorSpec(comptime kind: SemanticTerminatorKind) type {
            return struct {
                pub const semantic_terminator_kind = kind;
                condition: []const u8 = "",
                target: []const u8 = "",
                then_target: []const u8 = "",
                else_target: []const u8 = "",
                value: []const u8 = "",
                error_name: []const u8 = "",
            };
        }

        /// Emit a string literal into a string local.
        pub fn constString(comptime dst: []const u8, comptime literal: []const u8) NamedInstruction(.const_string) {
            return .{ .dst = dst, .string_literal = literal };
        }

        /// Emit an i32 literal into an i32 local.
        pub fn constI32(comptime dst: []const u8, comptime literal: i32) NamedInstruction(.const_i32) {
            return .{ .dst = dst, .string_literal = standard.fmt.comptimePrint("{d}", .{literal}) };
        }

        /// Emit a usize literal into a usize local.
        pub fn constUsize(comptime dst: []const u8, comptime literal: usize) NamedInstruction(.const_usize) {
            return .{ .dst = dst, .string_literal = standard.fmt.comptimePrint("{d}", .{literal}) };
        }

        /// Add two i32 locals.
        pub fn addI32(comptime dst: []const u8, comptime lhs: []const u8, comptime rhs: []const u8) NamedInstruction(.add_i32) {
            return .{ .dst = dst, .operand = lhs, .aux_name = rhs };
        }

        /// Subtract one from an i32 or usize local.
        pub fn subOne(comptime dst: []const u8, comptime operand: []const u8) NamedInstruction(.sub_one) {
            return .{ .dst = dst, .operand = operand };
        }

        /// Compare a bool/i32/usize local against false/zero and write a bool local.
        pub fn compareEqZero(comptime dst: []const u8, comptime operand: []const u8) NamedInstruction(.compare_eq_zero) {
            return .{ .dst = dst, .operand = operand };
        }

        /// Test whether a sum local is the requested variant ordinal.
        pub fn sumVariantIs(comptime dst: []const u8, comptime source: []const u8, comptime variant_ordinal: u16) NamedInstruction(.sum_variant_is) {
            return .{ .dst = dst, .operand = source, .aux = variant_ordinal };
        }

        /// Extract a sum variant payload into a payload-typed local.
        pub fn sumExtractPayload(comptime dst: []const u8, comptime source: []const u8, comptime variant_ordinal: u16) NamedInstruction(.sum_extract_payload) {
            return .{ .dst = dst, .operand = source, .aux = variant_ordinal };
        }

        /// Call a schema.Protocol row operation descriptor.
        pub fn call(comptime OpDescriptor: type, comptime args: anytype) CallInstruction(OpDescriptor) {
            if (@hasField(@TypeOf(args), "label") and args.label.len == 0) {
                @compileError("semantic builder protocol call label must be non-empty");
            }
            return .{
                .dst = optionalStringField(args, "dst"),
                .payload = optionalStringField(args, "payload"),
                .label = optionalStringField(args, "label"),
            };
        }

        /// Jump to a named block.
        pub fn jump(comptime target: []const u8) TerminatorSpec(.jump) {
            return .{ .target = target };
        }

        /// Branch to named blocks using the last condition-producing instruction.
        pub fn branchIf(comptime condition: []const u8, comptime targets: anytype) TerminatorSpec(.branch_if) {
            return .{
                .condition = condition,
                .then_target = requiredStringField(targets, "then"),
                .else_target = requiredStringField(targets, "else"),
            };
        }

        /// Return a named local value.
        pub fn returnValue(comptime value_name: []const u8) TerminatorSpec(.return_value) {
            return .{ .value = value_name };
        }

        /// Return unit.
        pub fn returnUnit() TerminatorSpec(.return_unit) {
            return .{};
        }

        /// Return a Body.Error literal.
        pub fn returnError(comptime error_name: []const u8) TerminatorSpec(.return_error) {
            return .{ .error_name = error_name };
        }

        fn Compiled(comptime spec: anytype) type {
            return struct {
                plan: program_plan.ProgramPlan,
                site_metadata: [countSiteLabels(spec)]SiteMetadata,
            };
        }

        /// Lower semantic functions, locals, blocks, and calls into one validated ProgramPlan.
        pub fn finish(comptime spec: anytype) program_plan.ValidationError!Compiled(spec) {
            const Static = Storage(spec);
            return .{ .plan = Static.plan, .site_metadata = Static.site_metadata };
        }

        fn TableSet(comptime spec: anytype) type {
            return struct {
                functions: [spec.functions.len]program_plan.FunctionPlan,
                locals: [countLocals(spec)]program_plan.LocalPlan,
                blocks: [countBlocks(spec)]program_plan.BlockPlan,
                terminators: [countBlocks(spec)]program_plan.Terminator,
                instructions: [countInstructions(spec)]program_plan.Instruction,
                site_metadata: [countSiteLabels(spec)]SiteMetadata,
            };
        }

        fn Storage(comptime spec: anytype) type {
            const tables = comptime finishImpl(spec) catch |err|
                @compileError("semantic builder produced invalid table layout: " ++ @errorName(err));
            return struct {
                pub const functions = tables.functions;
                pub const locals = tables.locals;
                pub const blocks = tables.blocks;
                pub const terminators = tables.terminators;
                pub const instructions = tables.instructions;
                pub const site_metadata = tables.site_metadata;
                pub const plan = inner.finish(.{
                    .schema_version = layout.u32Field(spec, "schema_version", program_plan.ProgramPlan.current_schema_version),
                    .label = spec.label,
                    .ir_hash = spec.ir_hash,
                    .entry = entryFunctionRef(spec),
                    .functions = &functions,
                    .requirements = layout.tableField(program_plan.RequirementPlan, spec, "requirements"),
                    .ops = layout.tableField(program_plan.OpPlan, spec, "ops"),
                    .outputs = layout.tableField(program_plan.OutputPlan, spec, "outputs"),
                    .value_schemas = valueSchemaTable(spec),
                    .value_fields = valueFieldTable(spec),
                    .value_variants = valueVariantTable(spec),
                    .locals = &locals,
                    .call_args = layout.tableField(u16, spec, "call_args"),
                    .blocks = &blocks,
                    .terminators = &terminators,
                    .instructions = &instructions,
                }) catch |err| @compileError("semantic builder produced invalid ProgramPlan: " ++ @errorName(err));
            };
        }

        fn optionalStringField(comptime source: anytype, comptime field_name: []const u8) ?[]const u8 {
            if (@hasField(@TypeOf(source), field_name)) return @field(source, field_name);
            return null;
        }

        fn rejectExplicitSchemaTableWithRegistry(comptime spec: anytype, comptime field_name: []const u8) void {
            if (comptime hasField(spec, "schemas")) {
                if (comptime hasField(spec, field_name)) {
                    @compileError("semantic builder derives " ++ field_name ++ " from schemas; omit the explicit table");
                }
            }
        }

        fn valueSchemaTable(comptime spec: anytype) []const program_plan.ValueSchemaPlan {
            rejectExplicitSchemaTableWithRegistry(spec, "value_schemas");
            if (comptime hasField(spec, "schemas")) return &spec.schemas.value_schemas;
            return layout.tableField(program_plan.ValueSchemaPlan, spec, "value_schemas");
        }

        fn valueFieldTable(comptime spec: anytype) []const program_plan.ValueFieldPlan {
            rejectExplicitSchemaTableWithRegistry(spec, "value_fields");
            if (comptime hasField(spec, "schemas")) return &spec.schemas.value_fields;
            return layout.tableField(program_plan.ValueFieldPlan, spec, "value_fields");
        }

        fn valueVariantTable(comptime spec: anytype) []const program_plan.ValueVariantPlan {
            rejectExplicitSchemaTableWithRegistry(spec, "value_variants");
            if (comptime hasField(spec, "schemas")) return &spec.schemas.value_variants;
            return layout.tableField(program_plan.ValueVariantPlan, spec, "value_variants");
        }

        fn requiredStringField(comptime source: anytype, comptime field_name: []const u8) []const u8 {
            if (!@hasField(@TypeOf(source), field_name)) @compileError("semantic builder missing field '" ++ field_name ++ "'");
            return @field(source, field_name);
        }

        fn hasField(comptime source: anytype, comptime field_name: []const u8) bool {
            return @hasField(@TypeOf(source), field_name);
        }

        fn valueRefForType(comptime spec: anytype, comptime T: type) program_plan.ValueRef {
            const codec = comptime program_plan.codecForType(T) catch |err| @compileError(standard.fmt.comptimePrint(
                "semantic builder unsupported value type '{s}': {s}",
                .{ @typeName(T), @errorName(err) },
            ));
            return switch (codec) {
                .product, .sum => {
                    if (comptime hasField(spec, "schemas")) {
                        return spec.schemas.valueRef(T) orelse @compileError(standard.fmt.comptimePrint(
                            "semantic builder requires schema.Registry entry for structured type '{s}'",
                            .{@typeName(T)},
                        ));
                    }
                    @compileError(standard.fmt.comptimePrint(
                        "semantic builder requires schema.Registry for structured type '{s}'",
                        .{@typeName(T)},
                    ));
                },
                else => .{ .codec = codec },
            };
        }

        fn valueRefFromLocalSpec(comptime spec: anytype, comptime local_spec: anytype) program_plan.ValueRef {
            const LocalSpecType = @TypeOf(local_spec);
            if (@hasField(LocalSpecType, "ref")) return local_spec.ref;
            return valueRefForType(spec, LocalSpecType.Type);
        }

        fn valueRefFromTypeField(comptime spec: anytype, comptime T: type) program_plan.ValueRef {
            return valueRefForType(spec, T);
        }

        fn functionValueRef(comptime spec: anytype, comptime function_spec: anytype) program_plan.ValueRef {
            if (comptime hasField(function_spec, "value_ref")) return function_spec.value_ref;
            if (comptime hasField(function_spec, "value")) return valueRefFromTypeField(spec, function_spec.value);
            if (comptime hasField(function_spec, "result_ref")) return function_spec.result_ref;
            if (comptime hasField(function_spec, "result")) return valueRefFromTypeField(spec, function_spec.result);
            return .{ .codec = .unit };
        }

        fn functionResultRef(comptime spec: anytype, comptime function_spec: anytype) ?program_plan.ValueRef {
            if (comptime hasField(function_spec, "result_ref")) return function_spec.result_ref;
            if (comptime hasField(function_spec, "result")) return valueRefFromTypeField(spec, function_spec.result);
            return null;
        }

        const LocalInfo = struct {
            index: u16,
            ref: program_plan.ValueRef,
        };

        fn refsEqual(lhs: program_plan.ValueRef, rhs: program_plan.ValueRef) bool {
            return lhs.codec == rhs.codec and lhs.schema_index == rhs.schema_index;
        }

        fn expectRef(comptime actual: program_plan.ValueRef, comptime expected: program_plan.ValueRef, comptime message: []const u8) void {
            if (!refsEqual(actual, expected)) @compileError(message);
        }

        fn localInfo(comptime spec: anytype, comptime function_spec: anytype, comptime name: []const u8) LocalInfo {
            comptime var next: u16 = 0;
            inline for (function_spec.params) |param_spec| {
                if (standard.mem.eql(u8, param_spec.name, name)) {
                    return .{ .index = next, .ref = valueRefFromLocalSpec(spec, param_spec) };
                }
                next += 1;
            }
            inline for (function_spec.locals) |local_spec| {
                if (standard.mem.eql(u8, local_spec.name, name)) {
                    return .{ .index = next, .ref = valueRefFromLocalSpec(spec, local_spec) };
                }
                next += 1;
            }
            @compileError("semantic builder local not found: " ++ name);
        }

        fn validateLocalNames(comptime function_spec: anytype) void {
            inline for (function_spec.params, 0..) |lhs, lhs_index| {
                inline for (function_spec.params, 0..) |rhs, rhs_index| {
                    if (rhs_index > lhs_index and standard.mem.eql(u8, lhs.name, rhs.name)) {
                        @compileError("semantic builder duplicate local name: " ++ lhs.name);
                    }
                }
                inline for (function_spec.locals) |rhs| {
                    if (standard.mem.eql(u8, lhs.name, rhs.name)) {
                        @compileError("semantic builder duplicate local name: " ++ lhs.name);
                    }
                }
            }
            inline for (function_spec.locals, 0..) |lhs, lhs_index| {
                inline for (function_spec.locals, 0..) |rhs, rhs_index| {
                    if (rhs_index > lhs_index and standard.mem.eql(u8, lhs.name, rhs.name)) {
                        @compileError("semantic builder duplicate local name: " ++ lhs.name);
                    }
                }
            }
        }

        fn blockIndex(comptime function_spec: anytype, comptime name: []const u8) u16 {
            inline for (function_spec.blocks, 0..) |block_spec, index| {
                if (standard.mem.eql(u8, block_spec.name, name)) return @intCast(index);
            }
            @compileError("semantic builder block not found: " ++ name);
        }

        fn validateBlockNames(comptime function_spec: anytype) void {
            inline for (function_spec.blocks, 0..) |lhs, lhs_index| {
                inline for (function_spec.blocks, 0..) |rhs, rhs_index| {
                    if (rhs_index > lhs_index and standard.mem.eql(u8, lhs.name, rhs.name)) {
                        @compileError("semantic builder duplicate block name: " ++ lhs.name);
                    }
                }
            }
        }

        fn entryFunctionRef(comptime spec: anytype) FunctionRef {
            if (comptime hasField(spec, "entry")) {
                inline for (spec.functions, 0..) |function_spec, index| {
                    if (standard.mem.eql(u8, function_spec.symbol_name, spec.entry)) return inner.function(@intCast(index));
                }
                @compileError("semantic builder entry function not found: " ++ spec.entry);
            }
            return inner.function(0);
        }

        fn countLocals(comptime spec: anytype) usize {
            var count: usize = 0;
            inline for (spec.functions) |function_spec| count += function_spec.params.len + function_spec.locals.len;
            return count;
        }

        fn countBlocks(comptime spec: anytype) usize {
            var count: usize = 0;
            inline for (spec.functions) |function_spec| count += function_spec.blocks.len;
            return count;
        }

        fn terminatorInstructionCount(comptime terminator: anytype) usize {
            return switch (@TypeOf(terminator).semantic_terminator_kind) {
                .return_error, .return_value => 1,
                .branch_if, .jump, .return_unit => 0,
            };
        }

        fn countInstructions(comptime spec: anytype) usize {
            var count: usize = 0;
            inline for (spec.functions) |function_spec| {
                inline for (function_spec.blocks) |block_spec| {
                    count += block_spec.instructions.len + terminatorInstructionCount(block_spec.terminator);
                }
            }
            return count;
        }

        fn countSiteLabels(comptime spec: anytype) usize {
            var count: usize = 0;
            inline for (spec.functions) |function_spec| {
                inline for (function_spec.blocks) |block_spec| {
                    inline for (block_spec.instructions) |instruction| {
                        if (@TypeOf(instruction).semantic_kind == .call and instruction.label != null) count += 1;
                    }
                }
            }
            return count;
        }

        fn validateBranchCondition(
            comptime block_spec: anytype,
            comptime terminator: anytype,
        ) void {
            if (block_spec.instructions.len == 0) {
                @compileError("semantic builder branch_if requires a preceding condition instruction");
            }
            const last = block_spec.instructions[block_spec.instructions.len - 1];
            switch (@TypeOf(last).semantic_kind) {
                .compare_eq_zero, .sum_variant_is => {
                    if (!standard.mem.eql(u8, last.dst, terminator.condition)) {
                        @compileError("semantic builder branch_if condition must name the last condition instruction destination");
                    }
                },
                else => @compileError("semantic builder branch_if requires compareEqZero or sumVariantIs immediately before it"),
            }
        }

        fn emitInstruction(
            comptime spec: anytype,
            comptime function_spec: anytype,
            function_ref: FunctionRef,
            comptime instruction: anytype,
        ) program_plan.Instruction {
            switch (@TypeOf(instruction).semantic_kind) {
                .const_string => {
                    const dst = localInfo(spec, function_spec, instruction.dst);
                    expectRef(dst.ref, .{ .codec = .string }, "semantic builder constString destination must be string");
                    return .{ .kind = .const_string, .dst = dst.index, .string_literal = instruction.string_literal };
                },
                .const_i32 => {
                    const dst = localInfo(spec, function_spec, instruction.dst);
                    expectRef(dst.ref, .{ .codec = .i32 }, "semantic builder constI32 destination must be i32");
                    return .{ .kind = .const_i32, .dst = dst.index, .string_literal = instruction.string_literal };
                },
                .const_usize => {
                    const dst = localInfo(spec, function_spec, instruction.dst);
                    expectRef(dst.ref, .{ .codec = .usize }, "semantic builder constUsize destination must be usize");
                    return .{ .kind = .const_usize, .dst = dst.index, .string_literal = instruction.string_literal };
                },
                .add_i32 => {
                    const dst = localInfo(spec, function_spec, instruction.dst);
                    const lhs = localInfo(spec, function_spec, instruction.operand);
                    const rhs = localInfo(spec, function_spec, instruction.aux_name);
                    expectRef(dst.ref, .{ .codec = .i32 }, "semantic builder addI32 destination must be i32");
                    expectRef(lhs.ref, .{ .codec = .i32 }, "semantic builder addI32 lhs must be i32");
                    expectRef(rhs.ref, .{ .codec = .i32 }, "semantic builder addI32 rhs must be i32");
                    return .{ .kind = .add_i32, .dst = dst.index, .operand = lhs.index, .aux = rhs.index };
                },
                .sub_one => {
                    const dst = localInfo(spec, function_spec, instruction.dst);
                    const operand = localInfo(spec, function_spec, instruction.operand);
                    if (operand.ref.codec != .i32 and operand.ref.codec != .usize) @compileError("semantic builder subOne operand must be i32 or usize");
                    expectRef(dst.ref, operand.ref, "semantic builder subOne destination must match operand type");
                    return .{ .kind = .sub_one, .dst = dst.index, .operand = operand.index };
                },
                .compare_eq_zero => {
                    const dst = localInfo(spec, function_spec, instruction.dst);
                    const operand = localInfo(spec, function_spec, instruction.operand);
                    expectRef(dst.ref, .{ .codec = .bool }, "semantic builder compareEqZero destination must be bool");
                    if (operand.ref.codec != .bool and operand.ref.codec != .i32 and operand.ref.codec != .usize) {
                        @compileError("semantic builder compareEqZero operand must be bool, i32, or usize");
                    }
                    return .{ .kind = .compare_eq_zero, .dst = dst.index, .operand = operand.index };
                },
                .sum_variant_is => {
                    const dst = localInfo(spec, function_spec, instruction.dst);
                    const source = localInfo(spec, function_spec, instruction.operand);
                    expectRef(dst.ref, .{ .codec = .bool }, "semantic builder sumVariantIs destination must be bool");
                    if (source.ref.codec != .sum) @compileError("semantic builder sumVariantIs source must be sum");
                    return .{ .kind = .sum_variant_is, .dst = dst.index, .operand = source.index, .aux = instruction.aux };
                },
                .sum_extract_payload => {
                    const dst = localInfo(spec, function_spec, instruction.dst);
                    const source = localInfo(spec, function_spec, instruction.operand);
                    if (source.ref.codec != .sum) @compileError("semantic builder sumExtractPayload source must be sum");
                    return .{ .kind = .sum_extract_payload, .dst = dst.index, .operand = source.index, .aux = instruction.aux };
                },
                .call => {
                    const Op = @TypeOf(instruction).Op;
                    const payload_local: ?LocalRef = if (instruction.payload) |payload_name| blk: {
                        const info = localInfo(spec, function_spec, payload_name);
                        expectRef(info.ref, Op.payload_ref, "semantic builder protocol call payload type mismatch");
                        break :blk inner.local(function_ref, info.index);
                    } else null;
                    if (instruction.payload == null and Op.payload_ref.codec != .unit) {
                        @compileError("semantic builder protocol call payload is required");
                    }
                    if (instruction.payload != null and Op.payload_ref.codec == .unit) {
                        @compileError("semantic builder protocol call payload must be omitted for unit payload");
                    }

                    const dst_local: ?LocalRef = if (instruction.dst) |dst_name| blk: {
                        const info = localInfo(spec, function_spec, dst_name);
                        expectRef(info.ref, Op.resume_ref, "semantic builder protocol call destination/resume type mismatch");
                        break :blk inner.local(function_ref, info.index);
                    } else null;
                    if (instruction.dst == null and Op.resume_ref.codec != .unit) {
                        @compileError("semantic builder protocol call destination is required for non-unit resume");
                    }
                    if (instruction.dst != null and Op.resume_ref.codec == .unit) {
                        @compileError("semantic builder protocol call destination must be omitted for unit resume");
                    }

                    return Op.call(function_ref, dst_local, payload_local) catch |err|
                        @compileError("semantic builder protocol call produced invalid instruction: " ++ @errorName(err));
                },
            }
        }

        fn finishImpl(comptime spec: anytype) program_plan.ValidationError!TableSet(spec) {
            const local_count = countLocals(spec);
            const block_count = countBlocks(spec);
            const instruction_count = countInstructions(spec);
            const site_label_count = countSiteLabels(spec);

            var functions: [spec.functions.len]program_plan.FunctionPlan = undefined;
            var locals: [local_count]program_plan.LocalPlan = undefined;
            var blocks: [block_count]program_plan.BlockPlan = undefined;
            var terminators: [block_count]program_plan.Terminator = undefined;
            var instructions: [instruction_count]program_plan.Instruction = undefined;
            var site_metadata: [site_label_count]SiteMetadata = undefined;

            var next_local: usize = 0;
            var next_block: usize = 0;
            var next_instruction: usize = 0;
            var next_site_label: usize = 0;

            inline for (spec.functions, 0..) |function_spec, function_index| {
                comptime validateLocalNames(function_spec);
                comptime validateBlockNames(function_spec);
                const function_ref = inner.function(@intCast(function_index));
                const first_local = next_local;
                inline for (function_spec.params) |param_spec| {
                    const ref_value = comptime valueRefFromLocalSpec(spec, param_spec);
                    locals[next_local] = .{ .codec = ref_value.codec, .schema_index = ref_value.schema_index };
                    next_local += 1;
                }
                inline for (function_spec.locals) |local_spec| {
                    const ref_value = comptime valueRefFromLocalSpec(spec, local_spec);
                    locals[next_local] = .{ .codec = ref_value.codec, .schema_index = ref_value.schema_index };
                    next_local += 1;
                }

                const first_block = next_block;
                const first_instruction = next_instruction;
                inline for (function_spec.blocks) |block_spec| {
                    const block_first_instruction = next_instruction;
                    inline for (block_spec.instructions) |instruction| {
                        instructions[next_instruction] = comptime emitInstruction(spec, function_spec, function_ref, instruction);
                        if (@TypeOf(instruction).semantic_kind == .call) {
                            if (instruction.label) |label| {
                                site_metadata[next_site_label] = .{
                                    .instruction_index = next_instruction,
                                    .label = label,
                                };
                                next_site_label += 1;
                            }
                        }
                        next_instruction += 1;
                    }

                    const terminator_kind = @TypeOf(block_spec.terminator).semantic_terminator_kind;
                    if (terminator_kind == .branch_if) comptime validateBranchCondition(block_spec, block_spec.terminator);
                    switch (terminator_kind) {
                        .return_value => {
                            const info = comptime localInfo(spec, function_spec, block_spec.terminator.value);
                            const value_ref = comptime functionValueRef(spec, function_spec);
                            expectRef(info.ref, value_ref, "semantic builder returnValue local type must match function value type");
                            instructions[next_instruction] = comptime inner.returnValue(function_ref, inner.local(function_ref, info.index)) catch |err|
                                @compileError("semantic builder returnValue produced invalid instruction: " ++ @errorName(err));
                            next_instruction += 1;
                            terminators[next_block] = .{ .kind = .return_value };
                        },
                        .return_error => {
                            if (block_spec.terminator.error_name.len == 0) @compileError("semantic builder returnError requires a non-empty error name");
                            instructions[next_instruction] = .{ .kind = .return_error, .string_literal = block_spec.terminator.error_name };
                            next_instruction += 1;
                            terminators[next_block] = .{ .kind = .return_unit };
                        },
                        .return_unit => terminators[next_block] = .{ .kind = .return_unit },
                        .jump => terminators[next_block] = .{
                            .kind = .jump,
                            .primary = try layout.checkedIndex(first_block + comptime blockIndex(function_spec, block_spec.terminator.target)),
                        },
                        .branch_if => terminators[next_block] = .{
                            .kind = .branch_if,
                            .primary = try layout.checkedIndex(first_block + comptime blockIndex(function_spec, block_spec.terminator.then_target)),
                            .secondary = try layout.checkedIndex(first_block + comptime blockIndex(function_spec, block_spec.terminator.else_target)),
                        },
                    }

                    blocks[next_block] = .{
                        .first_instruction = try layout.checkedIndex(block_first_instruction),
                        .instruction_count = try layout.checkedIndex(next_instruction - block_first_instruction),
                        .terminator_index = try layout.checkedIndex(next_block),
                    };
                    next_block += 1;
                }

                const value_ref = comptime functionValueRef(spec, function_spec);
                const result_ref = comptime functionResultRef(spec, function_spec);
                const requirement_span = if (comptime hasField(function_spec, "requirements")) function_spec.requirements else layout.Span{};
                const output_span = if (comptime hasField(function_spec, "outputs")) function_spec.outputs else layout.Span{};
                const entry_block = if (comptime hasField(function_spec, "entry_block")) comptime blockIndex(function_spec, function_spec.entry_block) else 0;
                functions[function_index] = .{
                    .symbol_name = function_spec.symbol_name,
                    .value_codec = value_ref.codec,
                    .value_schema_index = value_ref.schema_index,
                    .result_codec = if (result_ref) |ref| ref.codec else null,
                    .result_schema_index = if (result_ref) |ref| ref.schema_index else null,
                    .parameter_count = try layout.checkedIndex(function_spec.params.len),
                    .first_requirement = requirement_span.first,
                    .requirement_count = requirement_span.count,
                    .first_output = output_span.first,
                    .output_count = output_span.count,
                    .first_local = try layout.checkedIndex(first_local),
                    .local_count = try layout.checkedIndex(next_local - first_local),
                    .first_block = try layout.checkedIndex(first_block),
                    .entry_block = try layout.checkedIndex(entry_block),
                    .block_count = try layout.checkedIndex(next_block - first_block),
                    .first_instruction = try layout.checkedIndex(first_instruction),
                    .instruction_count = try layout.checkedIndex(next_instruction - first_instruction),
                };
            }

            return .{
                .functions = functions,
                .locals = locals,
                .blocks = blocks,
                .terminators = terminators,
                .instructions = instructions,
                .site_metadata = site_metadata,
            };
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

/// Schema-first helpers that lower effect binding metadata into ProgramPlan rows.
pub const schema = struct {
    /// Build one explicit ProgramPlan schema-index map entry.
    pub fn ref(comptime T: type, comptime schema_index: u16) type {
        return struct {
            pub const Type = T;
            pub const index: u16 = schema_index;
        };
    }

    /// Caller-provided schema-index map used by `LowerBinding`.
    pub fn SchemaRefs(comptime entries: anytype) type {
        comptime validateSchemaRefs(entries);
        return struct {
            pub fn valueRef(comptime T: type) ?program_plan.ValueRef {
                const codec = comptime program_plan.codecForType(T) catch return null;
                inline for (entries) |entry| {
                    if (entry.Type == T) {
                        return .{
                            .codec = codec,
                            .schema_index = entry.index,
                        };
                    }
                }
                return null;
            }
        };
    }

    /// Derive ProgramPlan value schema tables and schema refs from an explicit
    /// tuple of Zig scalar/product/sum types.
    pub fn Registry(comptime entries: anytype) type {
        comptime validateRegistryEntries(entries);
        const schema_types = comptime registryStructuredTypes(entries);
        const registry = program_plan.ValueSchemaRegistryForTypes(schema_types[0..]);
        const ref_entries = comptime registrySchemaRefs(schema_types[0..]);
        const Refs = SchemaRefs(ref_entries);

        return struct {
            pub const value_schema_types = schema_types;
            pub const registered_schema_types = schema_types;
            pub const value_schemas = registry.value_schemas;
            pub const value_fields = registry.value_fields;
            pub const value_variants = registry.value_variants;
            pub const schema_refs_type = Refs;
            pub const schema_refs = Refs;

            pub fn valueRef(comptime T: type) ?program_plan.ValueRef {
                const codec = comptime program_plan.codecForType(T) catch return null;
                return switch (codec) {
                    .product, .sum => Refs.valueRef(T),
                    else => .{ .codec = codec },
                };
            }
        };
    }

    /// Caller-owned offsets for one binding's ProgramPlan rows.
    pub const BindingOffsets = struct {
        requirement_index: u16,
        first_op: u16,
        first_output: u16 = 0,
        schema_refs: type = SchemaRefs(.{}),
    };

    /// Custom protocol transform operation schema.
    pub fn transform(
        comptime name: [:0]const u8,
        comptime Payload: type,
        comptime Resume: type,
    ) type {
        return effect_schema.op(name, .transform, Payload, Resume, .none);
    }

    /// Custom protocol transform operation schema with an optional after hook.
    pub fn transformAfter(
        comptime name: [:0]const u8,
        comptime Payload: type,
        comptime Resume: type,
    ) type {
        return effect_schema.op(name, .transform, Payload, Resume, .binding_optional);
    }

    /// Custom protocol choice operation schema.
    pub fn choice(
        comptime name: [:0]const u8,
        comptime Payload: type,
        comptime Resume: type,
    ) type {
        return effect_schema.op(name, .choice, Payload, Resume, .none);
    }

    /// Custom protocol choice operation schema with an optional after hook.
    pub fn choiceAfter(
        comptime name: [:0]const u8,
        comptime Payload: type,
        comptime Resume: type,
    ) type {
        return effect_schema.op(name, .choice, Payload, Resume, .binding_optional);
    }

    /// Custom protocol abort operation schema.
    pub fn abort(
        comptime name: [:0]const u8,
        comptime Payload: type,
    ) type {
        return effect_schema.op(name, .abort, Payload, noreturn, .none);
    }

    /// Nested constructor aliases for call sites that prefer `schema.op.*`.
    pub const op = struct {
        pub fn transform(
            comptime name: [:0]const u8,
            comptime Payload: type,
            comptime Resume: type,
        ) type {
            return schema.transform(name, Payload, Resume);
        }

        pub fn transformAfter(
            comptime name: [:0]const u8,
            comptime Payload: type,
            comptime Resume: type,
        ) type {
            return schema.transformAfter(name, Payload, Resume);
        }

        pub fn choice(
            comptime name: [:0]const u8,
            comptime Payload: type,
            comptime Resume: type,
        ) type {
            return schema.choice(name, Payload, Resume);
        }

        pub fn choiceAfter(
            comptime name: [:0]const u8,
            comptime Payload: type,
            comptime Resume: type,
        ) type {
            return schema.choiceAfter(name, Payload, Resume);
        }

        pub fn abort(
            comptime name: [:0]const u8,
            comptime Payload: type,
        ) type {
            return schema.abort(name, Payload);
        }
    };

    /// Minimal schema-first custom protocol-family descriptor.
    pub fn Protocol(comptime spec: anytype) type {
        comptime validateProtocolSpec(spec);
        const FamilySchema = comptime protocolFamilySchema(spec);
        const protocol_family_label: [:0]const u8 = spec.label;
        const protocol_ops = spec.ops;

        return struct {
            pub const label: [:0]const u8 = protocol_family_label;
            pub const Family = FamilySchema;
            pub const family = FamilySchema;
            pub const lifecycle_tag = FamilySchema.lifecycle_tag;
            pub const output_tag = FamilySchema.output;
            pub const ops = protocol_ops;
            pub const op_count = protocol_ops.len;

            pub fn Binding(comptime HandlerType: type) type {
                return schema.Binding(protocol_family_label, FamilySchema, HandlerType);
            }

            /// Return a typed protocol-level operation descriptor independent of any Program call site.
            pub fn operation(comptime name: []const u8, comptime options: anytype) type {
                const OptionsType = @TypeOf(options);
                const schema_refs = comptime if (@hasField(OptionsType, "schema_refs")) options.schema_refs else schema.SchemaRefs(.{});
                const ResultType: type = comptime if (@hasField(OptionsType, "Result")) options.Result else void;
                inline for (protocol_ops, 0..) |OpSchema, ordinal| {
                    if (standard.mem.eql(u8, OpSchema.name, name)) {
                        const op_mode_value = comptime schemaControlMode(OpSchema.control_mode);
                        if (comptime op_mode_value == .transform and @hasField(OptionsType, "Result")) {
                            @compileError("schema.Protocol transform operation does not accept Result");
                        }
                        const payload_ref_value = comptime protocolRefForType(OpSchema.Payload, "payload", schema_refs);
                        const resume_ref_value = comptime protocolRefForType(OpSchema.Resume, "resume", schema_refs);
                        const result_ref_value = comptime protocolRefForType(ResultType, "result", schema_refs);
                        const descriptor_fingerprint = comptime protocolOperationFingerprint(
                            protocol_family_label,
                            OpSchema.name,
                            @intCast(ordinal),
                            op_mode_value,
                            OpSchema.Payload,
                            payload_ref_value,
                            OpSchema.Resume,
                            resume_ref_value,
                            ResultType,
                            result_ref_value,
                        );
                        const descriptor_protocol_label = protocol_family_label;
                        return struct {
                            pub const kind = .protocol_operation;
                            pub const protocol_label: [:0]const u8 = descriptor_protocol_label;
                            pub const protocol = descriptor_protocol_label;
                            pub const op_name: [:0]const u8 = OpSchema.name;
                            pub const op_ordinal: u16 = @intCast(ordinal);
                            pub const mode = op_mode_value;
                            pub const op_mode = op_mode_value;
                            pub const Payload = OpSchema.Payload;
                            pub const Resume = OpSchema.Resume;
                            pub const Result = ResultType;
                            pub const payload_ref: program_plan.ValueRef = payload_ref_value;
                            pub const resume_ref: program_plan.ValueRef = resume_ref_value;
                            pub const result_ref: program_plan.ValueRef = result_ref_value;
                            pub const may_resume = op_mode_value != .abort;
                            pub const may_return_now = op_mode_value != .transform;
                            pub const fingerprint: u64 = descriptor_fingerprint;
                        };
                    }
                }
                @compileError(standard.fmt.comptimePrint(
                    "schema.Protocol operation '{s}' is not declared for '{s}'",
                    .{ name, protocol_family_label },
                ));
            }

            /// Short alias for `operation`.
            pub const op = operation;

            pub fn Rows(
                comptime HandlerType: type,
                comptime offsets: BindingOffsets,
            ) type {
                const BindingSchema = schema.Binding(protocol_family_label, FamilySchema, HandlerType);
                const Lowered = schema.LowerBinding(BindingSchema, offsets);
                return struct {
                    pub const requirement_index = Lowered.requirement_index;
                    pub const first_output = Lowered.first_output;
                    pub const first_op = offsets.first_op;
                    pub const op_count = Lowered.op_count;
                    pub const output_count = Lowered.output_count;
                    pub const requirement = Lowered.requirement;
                    pub const ops = Lowered.ops;
                    pub const outputs = Lowered.outputs;

                    pub fn op(comptime name: []const u8) type {
                        inline for (protocol_ops, 0..) |OpSchema, ordinal| {
                            if (standard.mem.eql(u8, OpSchema.name, name)) {
                                const global_op_index: u16 = offsets.first_op + @as(u16, @intCast(ordinal));
                                const op_row = Lowered.ops[ordinal];
                                return struct {
                                    pub const protocol = protocol_family_label;
                                    pub const op_ordinal: u16 = @intCast(ordinal);
                                    pub const op_index: u16 = global_op_index;
                                    pub const op_name: [:0]const u8 = OpSchema.name;
                                    pub const mode = op_row.mode;
                                    pub const Payload = OpSchema.Payload;
                                    pub const Resume = OpSchema.Resume;
                                    pub const payload_ref: program_plan.ValueRef = .{
                                        .codec = op_row.payload_codec,
                                        .schema_index = op_row.payload_schema_index,
                                    };
                                    pub const resume_ref: program_plan.ValueRef = .{
                                        .codec = op_row.resume_codec,
                                        .schema_index = op_row.resume_schema_index,
                                    };

                                    pub fn opRef(function_ref: builder.FunctionRef) builder.OpRef {
                                        return builder.op(function_ref, global_op_index);
                                    }

                                    pub fn call(
                                        function_ref: builder.FunctionRef,
                                        dst: ?builder.LocalRef,
                                        payload: ?builder.LocalRef,
                                    ) program_plan.ValidationError!program_plan.Instruction {
                                        return builder.callOp(function_ref, dst, opRef(function_ref), payload);
                                    }
                                };
                            }
                        }
                        @compileError(standard.fmt.comptimePrint(
                            "schema.Protocol op '{s}' is not declared for '{s}'",
                            .{ name, protocol_family_label },
                        ));
                    }
                };
            }
        };
    }

    /// Build a schema binding type without exposing `effect_schema` at the root.
    pub fn Binding(
        comptime label: [:0]const u8,
        comptime FamilySchema: type,
        comptime HandlerType: type,
    ) type {
        return effect_schema.Binding(label, FamilySchema, HandlerType);
    }

    /// Lower one effect binding schema to ordinary ProgramPlan requirement/op/output rows.
    pub fn LowerBinding(
        comptime BindingSchema: type,
        comptime offsets: BindingOffsets,
    ) type {
        comptime effect_schema.assertBindingSchema(BindingSchema);
        const row = comptime effect_schema.row(BindingSchema);
        if (row.requirements.len != 1) {
            @compileError("schema.LowerBinding expects exactly one requirement per effect binding");
        }
        const FamilySchema = comptime effect_schema.bindingFamily(BindingSchema);
        const requirement_schema = row.requirements[0];
        const lowered_output_count: usize = comptime if (FamilySchema.output == .none) 0 else 1;
        const lowered_ops = comptime lowerOps(
            BindingSchema,
            FamilySchema,
            requirement_schema.ops,
            offsets.requirement_index,
            offsets.schema_refs,
        );
        const lowered_outputs = comptime lowerOutputs(
            BindingSchema,
            FamilySchema,
            lowered_output_count,
            offsets.schema_refs,
        );

        return struct {
            pub const requirement_index: u16 = offsets.requirement_index;
            pub const first_output: u16 = offsets.first_output;
            pub const op_count: u16 = @intCast(lowered_ops.len);
            pub const output_count: u16 = @intCast(lowered_outputs.len);
            pub const requirement: program_plan.RequirementPlan = .{
                .label = BindingSchema.requirement_label,
                .first_op = offsets.first_op,
                .op_count = @intCast(lowered_ops.len),
                .lifecycle_tag = requirementLifecycleFromSchema(FamilySchema),
                .output_tag = requirementOutputFromSchema(FamilySchema),
            };
            pub const ops = lowered_ops;
            pub const outputs = lowered_outputs;
        };
    }

    fn lowerOps(
        comptime BindingSchema: type,
        comptime FamilySchema: type,
        comptime op_specs: []const effect_ir.OpSpec,
        comptime requirement_index: u16,
        comptime schema_refs: type,
    ) [op_specs.len]program_plan.OpPlan {
        var ops: [op_specs.len]program_plan.OpPlan = undefined;
        inline for (op_specs, 0..) |op_spec, index| {
            const payload_ref = comptime refForType(op_spec.PayloadType, "payload", schema_refs);
            const resume_ref = comptime refForType(op_spec.ResumeType, "resume", schema_refs);
            ops[index] = .{
                .requirement_index = requirement_index,
                .op_name = op_spec.op_name,
                .mode = planControlMode(op_spec.mode),
                .payload_codec = payload_ref.codec,
                .payload_schema_index = payload_ref.schema_index,
                .resume_codec = resume_ref.codec,
                .resume_schema_index = resume_ref.schema_index,
                .has_after = programPlanHasAfter(BindingSchema, FamilySchema, FamilySchema.ops[index], op_spec),
            };
        }
        return ops;
    }

    fn programPlanHasAfter(
        comptime BindingSchema: type,
        comptime FamilySchema: type,
        comptime OpSchema: type,
        comptime op_spec: effect_ir.OpSpec,
    ) bool {
        if (op_spec.mode == .abort) return false;
        // ProgramPlan execution invokes only afterDispatch; schema-style
        // after{OpName} hooks remain effect_schema row metadata.
        return switch (OpSchema.after) {
            .none => false,
            .binding_optional => runtimeHandlerHasAfterDispatch(BindingSchema, FamilySchema, OpSchema.name),
        };
    }

    fn hasDeclSafe(comptime T: type, comptime name: []const u8) bool {
        return switch (@typeInfo(T)) {
            .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, name),
            else => false,
        };
    }

    fn handlerSetType(comptime HandlerType: type) type {
        return switch (@typeInfo(HandlerType)) {
            .pointer => |pointer| pointer.child,
            else => HandlerType,
        };
    }

    fn authoredHandlerType(comptime HandlerType: type) type {
        return handlerSetType(HandlerType);
    }

    fn hasFieldSafe(comptime HandlerType: type, comptime field_name: []const u8) bool {
        const SetType = handlerSetType(HandlerType);
        return switch (@typeInfo(SetType)) {
            .@"struct" => |info| {
                inline for (info.fields) |field| {
                    if (standard.mem.eql(u8, field.name, field_name)) {
                        return true;
                    }
                }
                return false;
            },
            else => false,
        };
    }

    fn fieldType(comptime HandlerType: type, comptime field_name: []const u8) type {
        return @FieldType(handlerSetType(HandlerType), field_name);
    }

    fn fieldHasAfterDispatch(comptime HandlerType: type, comptime field_name: []const u8) bool {
        if (!hasFieldSafe(HandlerType, field_name)) return false;
        return hasDeclSafe(authoredHandlerType(fieldType(HandlerType, field_name)), "afterDispatch");
    }

    fn handlerHasAfterDispatch(comptime HandlerType: type, comptime op_name: []const u8) bool {
        if (hasFieldSafe(HandlerType, op_name) or hasFieldSafe(HandlerType, "authored")) return false;
        const AuthoredType = authoredHandlerType(HandlerType);
        return hasDeclSafe(AuthoredType, "dispatch") and hasDeclSafe(AuthoredType, "afterDispatch");
    }

    fn nestedFieldHasAfterDispatch(
        comptime HandlerType: type,
        comptime parent_field_name: []const u8,
        comptime child_field_name: []const u8,
    ) bool {
        if (!hasFieldSafe(HandlerType, parent_field_name)) return false;
        const ParentType = authoredHandlerType(fieldType(HandlerType, parent_field_name));
        return fieldHasAfterDispatch(ParentType, child_field_name);
    }

    fn runtimeHandlerHasAfterDispatch(
        comptime BindingSchema: type,
        comptime FamilySchema: type,
        comptime op_name: []const u8,
    ) bool {
        _ = FamilySchema;
        const HandlerType = BindingSchema.Handler;
        const requirement_label = BindingSchema.requirement_label;
        if (comptime hasFieldSafe(HandlerType, requirement_label)) {
            const RequirementType = authoredHandlerType(fieldType(HandlerType, requirement_label));
            if (comptime hasDeclSafe(RequirementType, "dispatch")) {
                return fieldHasAfterDispatch(HandlerType, requirement_label);
            }
            if (comptime hasFieldSafe(RequirementType, op_name)) {
                return fieldHasAfterDispatch(RequirementType, op_name);
            }
            if (comptime hasFieldSafe(RequirementType, "authored")) {
                return fieldHasAfterDispatch(RequirementType, "authored");
            }
        }
        return handlerHasAfterDispatch(HandlerType, op_name);
    }

    fn lowerOutputs(
        comptime BindingSchema: type,
        comptime FamilySchema: type,
        comptime output_count: usize,
        comptime schema_refs: type,
    ) [output_count]program_plan.OutputPlan {
        if (output_count == 0) return .{};
        const ref_value = outputRef(BindingSchema, FamilySchema, schema_refs);
        return .{.{
            .label = outputLabel(BindingSchema, FamilySchema),
            .codec = ref_value.codec,
            .schema_index = ref_value.schema_index,
        }};
    }

    fn planControlMode(comptime mode: effect_ir.ControlMode) program_plan.ControlMode {
        return switch (mode) {
            .abort => .abort,
            .choice => .choice,
            .transform => .transform,
        };
    }

    fn schemaControlMode(comptime mode: effect_schema.ControlMode) program_plan.ControlMode {
        return switch (mode) {
            .abort => .abort,
            .choice => .choice,
            .transform => .transform,
        };
    }

    fn requirementLifecycleFromSchema(comptime FamilySchema: type) @TypeOf(@as(program_plan.RequirementPlan, undefined).lifecycle_tag) {
        const LifecycleTag = @TypeOf(@as(program_plan.RequirementPlan, undefined).lifecycle_tag);
        return standard.meta.stringToEnum(LifecycleTag, @tagName(FamilySchema.lifecycle_tag)) orelse
            @compileError("effect schema lifecycle_tag must map to ProgramPlan RequirementLifecycleTag");
    }

    fn requirementOutputFromSchema(comptime FamilySchema: type) @TypeOf(@as(program_plan.RequirementPlan, undefined).output_tag) {
        const OutputTag = @TypeOf(@as(program_plan.RequirementPlan, undefined).output_tag);
        return standard.meta.stringToEnum(OutputTag, @tagName(FamilySchema.output)) orelse
            @compileError("effect schema output tag must map to ProgramPlan RequirementOutputTag");
    }

    fn outputLabel(comptime BindingSchema: type, comptime FamilySchema: type) []const u8 {
        return switch (FamilySchema.output) {
            .none => @compileError("schema output label requested for binding without output metadata"),
            .final_state => BindingSchema.requirement_label,
            .accumulator => BindingSchema.requirement_label,
            .custom_finalizer => @compileError("schema.LowerBinding does not support custom_finalizer outputs yet"),
        };
    }

    fn outputRef(
        comptime BindingSchema: type,
        comptime FamilySchema: type,
        comptime schema_refs: type,
    ) program_plan.ValueRef {
        return switch (FamilySchema.output) {
            .none => @compileError("schema output ref requested for binding without output metadata"),
            .final_state => refForType(FamilySchema.Output, "output", schema_refs),
            .accumulator => refForType(FamilySchema.Item, "output", schema_refs),
            .custom_finalizer => @compileError(standard.fmt.comptimePrint(
                "schema.LowerBinding does not support custom_finalizer output for '{s}' yet",
                .{BindingSchema.requirement_label},
            )),
        };
    }

    fn refForType(
        comptime T: type,
        comptime role: []const u8,
        comptime schema_refs: type,
    ) program_plan.ValueRef {
        const codec = comptime program_plan.codecForType(T) catch |err| @compileError(standard.fmt.comptimePrint(
            "schema.LowerBinding unsupported {s} type '{s}': {s}",
            .{ role, @typeName(T), @errorName(err) },
        ));
        return switch (codec) {
            .product, .sum => schema_refs.valueRef(T) orelse @compileError(standard.fmt.comptimePrint(
                "schema.LowerBinding requires a schema ref for product/sum {s} type '{s}'",
                .{ role, @typeName(T) },
            )),
            else => .{ .codec = codec },
        };
    }

    fn protocolRefForType(
        comptime T: type,
        comptime role: []const u8,
        comptime schema_refs: type,
    ) program_plan.ValueRef {
        const codec = comptime program_plan.codecForType(T) catch |err| @compileError(standard.fmt.comptimePrint(
            "schema.Protocol operation unsupported {s} type '{s}': {s}",
            .{ role, @typeName(T), @errorName(err) },
        ));
        return switch (codec) {
            .product, .sum => schema_refs.valueRef(T) orelse @compileError(standard.fmt.comptimePrint(
                "schema.Protocol operation requires a schema ref for product/sum {s} type '{s}'",
                .{ role, @typeName(T) },
            )),
            else => .{ .codec = codec },
        };
    }

    fn protocolHashU16(hasher: *standard.hash.Wyhash, raw_value: u16) void {
        var bytes: [2]u8 = undefined;
        standard.mem.writeInt(u16, &bytes, raw_value, .little);
        hasher.update(&bytes);
    }

    fn protocolHashUsize(hasher: *standard.hash.Wyhash, raw_value: usize) void {
        var bytes: [8]u8 = undefined;
        standard.mem.writeInt(u64, &bytes, @intCast(raw_value), .little);
        hasher.update(&bytes);
    }

    fn protocolHashBytes(hasher: *standard.hash.Wyhash, bytes: []const u8) void {
        protocolHashUsize(hasher, bytes.len);
        hasher.update(bytes);
    }

    fn protocolHashValueRef(hasher: *standard.hash.Wyhash, value_ref: program_plan.ValueRef) void {
        protocolHashBytes(hasher, @tagName(value_ref.codec));
        if (value_ref.schema_index) |schema_index| {
            protocolHashU16(hasher, schema_index);
        } else {
            protocolHashBytes(hasher, "none");
        }
    }

    fn protocolHashTypeIdentity(hasher: *standard.hash.Wyhash, comptime ValueType: type) void {
        protocolHashBytes(hasher, @typeName(ValueType));
    }

    fn protocolOperationFingerprint(
        comptime protocol_label: []const u8,
        comptime op_name: []const u8,
        comptime op_ordinal: u16,
        comptime mode: program_plan.ControlMode,
        comptime Payload: type,
        comptime payload_ref: program_plan.ValueRef,
        comptime Resume: type,
        comptime resume_ref: program_plan.ValueRef,
        comptime Result: type,
        comptime result_ref: program_plan.ValueRef,
    ) u64 {
        @setEvalBranchQuota(10_000);
        var hasher = standard.hash.Wyhash.init(0);
        protocolHashBytes(&hasher, "ability.schema.protocol.operation");
        protocolHashBytes(&hasher, protocol_label);
        protocolHashBytes(&hasher, op_name);
        protocolHashU16(&hasher, op_ordinal);
        protocolHashBytes(&hasher, @tagName(mode));
        protocolHashTypeIdentity(&hasher, Payload);
        protocolHashValueRef(&hasher, payload_ref);
        protocolHashTypeIdentity(&hasher, Resume);
        protocolHashValueRef(&hasher, resume_ref);
        protocolHashTypeIdentity(&hasher, Result);
        protocolHashValueRef(&hasher, result_ref);
        return hasher.final();
    }

    fn validateSchemaRefs(comptime entries: anytype) void {
        inline for (entries, 0..) |entry, index| {
            if (!@hasDecl(entry, "Type") or !@hasDecl(entry, "index")) {
                @compileError("schema.SchemaRefs entries must be built with schema.ref(T, schema_index)");
            }
            const codec = comptime program_plan.codecForType(entry.Type) catch |err| @compileError(standard.fmt.comptimePrint(
                "schema.SchemaRefs unsupported type '{s}': {s}",
                .{ @typeName(entry.Type), @errorName(err) },
            ));
            switch (codec) {
                .product, .sum => {},
                else => @compileError(standard.fmt.comptimePrint(
                    "schema.SchemaRefs entry type '{s}' is scalar and must not carry a schema index",
                    .{@typeName(entry.Type)},
                )),
            }
            inline for (entries, 0..) |prior, prior_index| {
                if (prior_index < index and prior.Type == entry.Type) {
                    @compileError(standard.fmt.comptimePrint(
                        "schema.SchemaRefs has duplicate entry for type '{s}'",
                        .{@typeName(entry.Type)},
                    ));
                }
            }
        }
    }

    fn validateRegistryEntries(comptime entries: anytype) void {
        inline for (entries, 0..) |Entry, index| {
            const codec = comptime program_plan.codecForType(Entry) catch |err| @compileError(standard.fmt.comptimePrint(
                "schema.Registry unsupported type '{s}': {s}",
                .{ @typeName(Entry), @errorName(err) },
            ));
            switch (codec) {
                .product, .sum => inline for (entries, 0..) |Prior, prior_index| {
                    if (prior_index < index and Prior == Entry) {
                        @compileError(standard.fmt.comptimePrint(
                            "schema.Registry has duplicate structured type '{s}'",
                            .{@typeName(Entry)},
                        ));
                    }
                },
                else => {},
            }
            validateRegistryNestedRefs(entries, Entry);
        }
    }

    fn registryContainsStructuredType(comptime entries: anytype, comptime T: type) bool {
        inline for (entries) |Entry| {
            if (Entry == T) return true;
        }
        return false;
    }

    fn validateRegistryNestedType(
        comptime entries: anytype,
        comptime Owner: type,
        comptime Child: type,
    ) void {
        const codec = comptime program_plan.codecForType(Child) catch |err| @compileError(standard.fmt.comptimePrint(
            "schema.Registry unsupported nested type '{s}' referenced by '{s}': {s}",
            .{ @typeName(Child), @typeName(Owner), @errorName(err) },
        ));
        switch (codec) {
            .product, .sum => if (!registryContainsStructuredType(entries, Child)) {
                @compileError(standard.fmt.comptimePrint(
                    "schema.Registry missing nested structured type '{s}' referenced by '{s}'",
                    .{ @typeName(Child), @typeName(Owner) },
                ));
            },
            else => {},
        }
    }

    fn validateRegistryNestedRefs(comptime entries: anytype, comptime Entry: type) void {
        const codec = comptime program_plan.codecForType(Entry) catch |err| @compileError(standard.fmt.comptimePrint(
            "schema.Registry unsupported type '{s}': {s}",
            .{ @typeName(Entry), @errorName(err) },
        ));
        switch (codec) {
            .product => switch (@typeInfo(Entry)) {
                .@"struct" => |info| inline for (info.fields) |field| {
                    validateRegistryNestedType(entries, Entry, field.type);
                },
                else => {},
            },
            .sum => switch (@typeInfo(Entry)) {
                .@"union" => |info| inline for (info.fields) |field| {
                    validateRegistryNestedType(entries, Entry, field.type);
                },
                .optional => |info| validateRegistryNestedType(entries, Entry, info.child),
                else => {},
            },
            else => {},
        }
    }

    fn registryStructuredCount(comptime entries: anytype) usize {
        var count: usize = 0;
        inline for (entries) |Entry| {
            const codec = comptime program_plan.codecForType(Entry) catch |err| @compileError(standard.fmt.comptimePrint(
                "schema.Registry unsupported type '{s}': {s}",
                .{ @typeName(Entry), @errorName(err) },
            ));
            switch (codec) {
                .product, .sum => count += 1,
                else => {},
            }
        }
        return count;
    }

    fn registryStructuredTypes(comptime entries: anytype) [registryStructuredCount(entries)]type {
        var types: [registryStructuredCount(entries)]type = undefined;
        var next: usize = 0;
        inline for (entries) |Entry| {
            const codec = comptime program_plan.codecForType(Entry) catch |err| @compileError(standard.fmt.comptimePrint(
                "schema.Registry unsupported type '{s}': {s}",
                .{ @typeName(Entry), @errorName(err) },
            ));
            switch (codec) {
                .product, .sum => {
                    types[next] = Entry;
                    next += 1;
                },
                else => {},
            }
        }
        return types;
    }

    fn registrySchemaRefs(comptime schema_types: anytype) [schema_types.len]type {
        var refs: [schema_types.len]type = undefined;
        inline for (schema_types, 0..) |SchemaType, index| {
            refs[index] = schema.ref(SchemaType, @intCast(index));
        }
        return refs;
    }

    fn validateProtocolSpec(comptime spec: anytype) void {
        const SpecType = @TypeOf(spec);
        if (!@hasField(SpecType, "label")) {
            @compileError("schema.Protocol requires a label");
        }
        const protocol_label: [:0]const u8 = spec.label;
        if (protocol_label.len == 0) {
            @compileError("schema.Protocol requires a non-empty label");
        }
        if (!@hasField(SpecType, "ops")) {
            @compileError("schema.Protocol requires ops");
        }
        if (spec.ops.len == 0) {
            @compileError("schema.Protocol requires at least one op");
        }
        inline for (spec.ops, 0..) |OpSchema, index| {
            validateProtocolOp(OpSchema);
            inline for (spec.ops, 0..) |prior, prior_index| {
                if (prior_index < index and standard.mem.eql(u8, prior.name, OpSchema.name)) {
                    @compileError(standard.fmt.comptimePrint(
                        "schema.Protocol has duplicate op name '{s}'",
                        .{OpSchema.name},
                    ));
                }
            }
        }
    }

    fn validateProtocolOp(comptime OpSchema: type) void {
        if (!hasDeclSafe(OpSchema, "name")) {
            @compileError("schema.Protocol op must declare a name");
        }
        if (OpSchema.name.len == 0) {
            @compileError("schema.Protocol op name must be non-empty");
        }
        inline for (.{
            "control_mode",
            "Payload",
            "Resume",
            "after",
        }) |decl_name| {
            if (!hasDeclSafe(OpSchema, decl_name)) {
                @compileError("schema.Protocol op is missing " ++ decl_name);
            }
        }
        if (OpSchema.control_mode == .abort and OpSchema.after != .none) {
            @compileError("schema.Protocol abort op cannot declare an after hook");
        }
    }

    fn protocolFamilySchema(comptime spec: anytype) type {
        const SpecType = @TypeOf(spec);
        const ErrorSetType: type = if (@hasField(SpecType, "error_set_type"))
            spec.error_set_type
        else if (@hasField(SpecType, "ErrorSet"))
            spec.ErrorSet
        else
            error{};
        const StateType: type = if (@hasField(SpecType, "state_type"))
            spec.state_type
        else
            void;
        const OutputType: type = if (@hasField(SpecType, "output_type"))
            spec.output_type
        else if (@hasField(SpecType, "Output"))
            spec.Output
        else
            void;
        const ItemType: type = if (@hasField(SpecType, "item_type"))
            spec.item_type
        else
            OutputType;
        const OutputFinalizerValue: type = if (@hasField(SpecType, "output_finalizer_type"))
            spec.output_finalizer_type
        else
            void;
        const PolicyType: type = if (@hasField(SpecType, "policy_type"))
            spec.policy_type
        else
            void;
        const CatchType: type = if (@hasField(SpecType, "catch_type"))
            spec.catch_type
        else
            void;
        const ManagerType: type = if (@hasField(SpecType, "manager_type"))
            spec.manager_type
        else
            void;
        const lifecycle_value: effect_schema.LifecycleTag = if (@hasField(SpecType, "lifecycle_tag"))
            standard.meta.stringToEnum(effect_schema.LifecycleTag, @tagName(spec.lifecycle_tag)) orelse
                @compileError("schema.Protocol lifecycle_tag must map to effect schema lifecycle tags")
        else
            .generated_family;
        const output_value: effect_schema.OutputTag = if (@hasField(SpecType, "output_tag"))
            standard.meta.stringToEnum(effect_schema.OutputTag, @tagName(spec.output_tag)) orelse
                @compileError("schema.Protocol output_tag must map to effect schema output tags")
        else
            .none;
        const protocol_label: [:0]const u8 = spec.label;

        return struct {
            pub const logical_family_name: [:0]const u8 = protocol_label;
            pub const lifecycle_tag = lifecycle_value;
            pub const ErrorSet = ErrorSetType;
            pub const State = StateType;
            pub const Item = ItemType;
            pub const Output = OutputType;
            pub const output = output_value;
            pub const OutputFinalizerType = OutputFinalizerValue;
            pub const Policy = PolicyType;
            pub const Catch = CatchType;
            pub const Manager = ManagerType;
            pub const ops = spec.ops;
            pub const op_count = spec.ops.len;
        };
    }
};

test "compatibility IR module re-exports retained surface" {
    const std = @import("std");

    try std.testing.expect(@hasDecl(@This(), "Program"));
    try std.testing.expect(@hasDecl(@This(), "rowDigest"));
    try std.testing.expect(@hasDecl(@This(), "builder"));
    try std.testing.expect(@hasDecl(@This(), "value"));
    try std.testing.expect(@hasDecl(@This(), "schema"));
    try std.testing.expect(!@hasDecl(@This(), "compile"));
    try std.testing.expect(internal_kernel.ValueSchemaPlan == program_plan.ValueSchemaPlan);
    try std.testing.expect(internal_kernel.ValueFieldPlan == program_plan.ValueFieldPlan);
    try std.testing.expect(internal_kernel.ValueVariantPlan == program_plan.ValueVariantPlan);
}

test "schema lowerer lowers state binding to ProgramPlan rows" {
    const StateBinding = schema.Binding("state", effect_schema.state_cell(i32, error{}), void);
    const Rows = schema.LowerBinding(StateBinding, .{
        .requirement_index = 2,
        .first_op = 5,
        .first_output = 7,
    });

    try standard.testing.expectEqual(@as(u16, 2), Rows.requirement_index);
    try standard.testing.expectEqual(@as(u16, 7), Rows.first_output);
    try standard.testing.expectEqualStrings("state", Rows.requirement.label);
    try standard.testing.expectEqual(@as(u16, 5), Rows.requirement.first_op);
    try standard.testing.expectEqual(@as(u16, 2), Rows.requirement.op_count);
    try standard.testing.expectEqual(@as(@TypeOf(Rows.requirement.lifecycle_tag), .state_cell), Rows.requirement.lifecycle_tag);
    try standard.testing.expectEqual(@as(@TypeOf(Rows.requirement.output_tag), .final_state), Rows.requirement.output_tag);
    try standard.testing.expectEqualStrings("get", Rows.ops[0].op_name);
    try standard.testing.expectEqual(program_plan.ValueCodec.unit, Rows.ops[0].payload_codec);
    try standard.testing.expectEqual(program_plan.ValueCodec.i32, Rows.ops[0].resume_codec);
    try standard.testing.expectEqualStrings("set", Rows.ops[1].op_name);
    try standard.testing.expectEqual(program_plan.ValueCodec.i32, Rows.ops[1].payload_codec);
    try standard.testing.expectEqual(program_plan.ValueCodec.unit, Rows.ops[1].resume_codec);
    try standard.testing.expectEqualStrings("state", Rows.outputs[0].label);
    try standard.testing.expectEqual(program_plan.ValueCodec.i32, Rows.outputs[0].codec);
}

test "schema lowerer keeps final-state output labels binding-specific" {
    const LeftRows = schema.LowerBinding(
        schema.Binding("left_state", effect_schema.state_cell(i32, error{}), void),
        .{ .requirement_index = 0, .first_op = 0, .first_output = 0 },
    );
    const RightRows = schema.LowerBinding(
        schema.Binding("right_state", effect_schema.state_cell(i32, error{}), void),
        .{
            .requirement_index = 1,
            .first_op = LeftRows.op_count,
            .first_output = LeftRows.output_count,
        },
    );
    const root = builder.function(0);
    const requirements = [_]program_plan.RequirementPlan{
        LeftRows.requirement,
        RightRows.requirement,
    };
    const ops = LeftRows.ops ++ RightRows.ops;
    const outputs = LeftRows.outputs ++ RightRows.outputs;
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "root",
        .first_requirement = 0,
        .requirement_count = @intCast(requirements.len),
        .first_output = 0,
        .output_count = @intCast(outputs.len),
        .first_block = 0,
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

    const built_plan = try builder.finish(.{
        .label = "schema.binding-specific-final-state-outputs",
        .ir_hash = 2,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &outputs,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &.{},
    });

    try standard.testing.expectEqualStrings("left_state", built_plan.outputs[0].label);
    try standard.testing.expectEqualStrings("right_state", built_plan.outputs[1].label);
}

test "schema lowerer maps binding-optional after hooks to ProgramPlan afterDispatch metadata" {
    const OptionalNoAfterRows = schema.LowerBinding(
        schema.Binding("optional", effect_schema.choice_policy(i32, error{}, void), void),
        .{ .requirement_index = 0, .first_op = 0 },
    );
    try standard.testing.expectEqualStrings("request", OptionalNoAfterRows.ops[0].op_name);
    try standard.testing.expect(!OptionalNoAfterRows.ops[0].has_after);

    const OptionalAfterRows = schema.LowerBinding(
        schema.Binding("optional", effect_schema.choice_policy(i32, error{}, void), struct {
            pub fn dispatch(_: *const @This(), _: void) error{}!i32 {
                return 1;
            }

            pub fn afterDispatch(_: *const @This(), answer: i32) error{}!i32 {
                return answer;
            }
        }),
        .{ .requirement_index = 0, .first_op = 0 },
    );
    try standard.testing.expect(OptionalAfterRows.ops[0].has_after);

    const OptionalSchemaAfterBinding = schema.Binding("optional", effect_schema.choice_policy(i32, error{}, void), struct {
        pub fn afterRequest(_: *@This(), answer: i32) i32 {
            return answer;
        }
    });
    try standard.testing.expect(effect_schema.row(OptionalSchemaAfterBinding).requirements[0].ops[0].has_after);
    const OptionalSchemaAfterRows = schema.LowerBinding(
        OptionalSchemaAfterBinding,
        .{ .requirement_index = 0, .first_op = 0 },
    );
    try standard.testing.expect(!OptionalSchemaAfterRows.ops[0].has_after);

    const GeneratedFamily = effect_schema.generated_family(.{
        .state_type = i32,
        .ops = .{
            struct {
                pub const op_name: [:0]const u8 = "get";
                pub const mode = enum { direct_return, resume_or_return, resume_then_transform }.resume_then_transform;
                pub const Payload = void;
                pub const Resume = i32;
            },
        },
    });
    const GeneratedRows = schema.LowerBinding(
        schema.Binding("counter", GeneratedFamily, struct {
            counter: struct {
                get: struct {
                    pub fn afterDispatch(_: *const @This(), answer: i32) error{}!i32 {
                        return answer + 1;
                    }
                },
            },
        }),
        .{ .requirement_index = 0, .first_op = 0 },
    );
    try standard.testing.expectEqualStrings("get", GeneratedRows.ops[0].op_name);
    try standard.testing.expect(GeneratedRows.ops[0].has_after);

    const GeneratedSchemaAfterBinding = schema.Binding("counter", GeneratedFamily, struct {
        pub fn afterGet(_: *@This(), answer: i32) i32 {
            return answer + 1;
        }
    });
    try standard.testing.expect(effect_schema.row(GeneratedSchemaAfterBinding).requirements[0].ops[0].has_after);
    const GeneratedSchemaAfterRows = schema.LowerBinding(
        GeneratedSchemaAfterBinding,
        .{ .requirement_index = 0, .first_op = 0 },
    );
    try standard.testing.expect(!GeneratedSchemaAfterRows.ops[0].has_after);
}

test "schema Protocol lowers custom transform choice and abort rows" {
    const ProductPayload = struct {
        request_id: i32,
    };
    const Decision = union(enum) {
        approve: i32,
        deny,
    };
    const Approval = schema.Protocol(.{
        .label = "approval",
        .ops = .{
            schema.transform("exists", []const u8, i32),
            schema.choiceAfter("request", ProductPayload, Decision),
            schema.abort("invalid", ProductPayload),
        },
    });
    const Handlers = struct {
        approval: struct {
            request: struct {
                pub fn afterDispatch(_: *const @This(), answer: []const u8) error{}![]const u8 {
                    return answer;
                }
            },
        },
    };
    const Rows = Approval.Rows(Handlers, .{
        .requirement_index = 3,
        .first_op = 7,
        .schema_refs = schema.SchemaRefs(.{
            schema.ref(ProductPayload, 5),
            schema.ref(Decision, 6),
        }),
    });

    try standard.testing.expectEqualStrings("approval", Approval.label);
    try standard.testing.expectEqual(@as(usize, 3), Approval.op_count);
    try standard.testing.expectEqualStrings("approval", Rows.requirement.label);
    try standard.testing.expectEqual(@as(u16, 3), Rows.requirement_index);
    try standard.testing.expectEqual(@as(u16, 7), Rows.requirement.first_op);
    try standard.testing.expectEqual(@as(u16, 3), Rows.requirement.op_count);
    try standard.testing.expectEqual(@as(@TypeOf(Rows.requirement.lifecycle_tag), .generated_family), Rows.requirement.lifecycle_tag);
    try standard.testing.expectEqual(@as(@TypeOf(Rows.requirement.output_tag), .none), Rows.requirement.output_tag);

    try standard.testing.expectEqualStrings("exists", Rows.ops[0].op_name);
    try standard.testing.expectEqual(program_plan.ControlMode.transform, Rows.ops[0].mode);
    try standard.testing.expectEqual(program_plan.ValueCodec.string, Rows.ops[0].payload_codec);
    try standard.testing.expectEqual(@as(?u16, null), Rows.ops[0].payload_schema_index);
    try standard.testing.expectEqual(program_plan.ValueCodec.i32, Rows.ops[0].resume_codec);
    try standard.testing.expectEqual(@as(?u16, null), Rows.ops[0].resume_schema_index);
    try standard.testing.expect(!Rows.ops[0].has_after);

    try standard.testing.expectEqualStrings("request", Rows.ops[1].op_name);
    try standard.testing.expectEqual(program_plan.ControlMode.choice, Rows.ops[1].mode);
    try standard.testing.expectEqual(program_plan.ValueCodec.product, Rows.ops[1].payload_codec);
    try standard.testing.expectEqual(@as(?u16, 5), Rows.ops[1].payload_schema_index);
    try standard.testing.expectEqual(program_plan.ValueCodec.sum, Rows.ops[1].resume_codec);
    try standard.testing.expectEqual(@as(?u16, 6), Rows.ops[1].resume_schema_index);
    try standard.testing.expect(Rows.ops[1].has_after);

    try standard.testing.expectEqualStrings("invalid", Rows.ops[2].op_name);
    try standard.testing.expectEqual(program_plan.ControlMode.abort, Rows.ops[2].mode);
    try standard.testing.expectEqual(program_plan.ValueCodec.product, Rows.ops[2].payload_codec);
    try standard.testing.expectEqual(@as(?u16, 5), Rows.ops[2].payload_schema_index);
    try standard.testing.expectEqual(program_plan.ValueCodec.unit, Rows.ops[2].resume_codec);
    try standard.testing.expectEqual(@as(?u16, null), Rows.ops[2].resume_schema_index);
    try standard.testing.expect(!Rows.ops[2].has_after);
}

test "schema Protocol mirrors runtime handler lookup for after metadata" {
    const Workflow = schema.Protocol(.{
        .label = "workflow",
        .ops = .{
            schema.choiceAfter("request", []const u8, i32),
        },
    });
    const NestedOpRows = Workflow.Rows(struct {
        workflow: struct {
            request: struct {
                pub fn afterDispatch(_: *const @This(), answer: []const u8) error{}![]const u8 {
                    return answer;
                }
            },
        },
    }, .{ .requirement_index = 0, .first_op = 0 });
    try standard.testing.expect(NestedOpRows.ops[0].has_after);

    const NestedAuthoredRows = Workflow.Rows(struct {
        workflow: struct {
            authored: struct {
                pub fn afterDispatch(_: *const @This(), answer: []const u8) error{}![]const u8 {
                    return answer;
                }
            },
        },
    }, .{ .requirement_index = 0, .first_op = 0 });
    try standard.testing.expect(NestedAuthoredRows.ops[0].has_after);

    const TopLevelFallbackRows = Workflow.Rows(struct {
        pub fn dispatch(_: *const @This(), _: []const u8) error{}!i32 {
            return 1;
        }

        pub fn afterDispatch(_: *const @This(), answer: []const u8) error{}![]const u8 {
            return answer;
        }

        request: struct {
            pub fn dispatch(_: *const @This(), _: []const u8) error{}!i32 {
                return 1;
            }
        },

        authored: struct {
            pub fn afterDispatch(_: *const @This(), answer: []const u8) error{}![]const u8 {
                return answer;
            }
        },
    }, .{ .requirement_index = 0, .first_op = 0 });
    try standard.testing.expect(!TopLevelFallbackRows.ops[0].has_after);

    const RequirementHandlerWinsRows = Workflow.Rows(struct {
        workflow: struct {
            pub fn dispatch(_: *const @This(), _: []const u8) error{}!i32 {
                return 1;
            }

            request: struct {
                pub fn afterDispatch(_: *const @This(), answer: []const u8) error{}![]const u8 {
                    return answer;
                }
            },
        },
    }, .{ .requirement_index = 0, .first_op = 0 });
    try standard.testing.expect(!RequirementHandlerWinsRows.ops[0].has_after);

    const OpFieldShadowsAuthoredRows = Workflow.Rows(struct {
        workflow: struct {
            request: struct {
                pub fn dispatch(_: *const @This(), _: []const u8) error{}!i32 {
                    return 1;
                }
            },

            authored: struct {
                pub fn afterDispatch(_: *const @This(), answer: []const u8) error{}![]const u8 {
                    return answer;
                }
            },
        },
    }, .{ .requirement_index = 0, .first_op = 0 });
    try standard.testing.expect(!OpFieldShadowsAuthoredRows.ops[0].has_after);
}

test "schema Protocol exposes op descriptors for builder authoring" {
    const Approval = schema.Protocol(.{
        .label = "approval",
        .ops = .{
            schema.transform("exists", []const u8, i32),
            schema.choice("request", []const u8, i32),
            schema.abort("invalid", []const u8),
        },
    });
    const Rows = Approval.Rows(void, .{
        .requirement_index = 0,
        .first_op = 4,
    });
    const Exists = Rows.op("exists");
    const Request = Rows.op("request");
    const Invalid = Rows.op("invalid");
    const root = builder.function(0);
    const payload = builder.local(root, 0);
    const dst = builder.local(root, 1);

    try standard.testing.expectEqual(@as(u16, 0), Exists.op_ordinal);
    try standard.testing.expectEqual(@as(u16, 4), Exists.op_index);
    try standard.testing.expectEqual(@as(u16, 5), Request.opRef(root).index);
    try standard.testing.expectEqual(@as(u16, 6), Invalid.opRef(root).index);
    try standard.testing.expectEqualStrings("request", Request.op_name);
    try standard.testing.expect(Request.Payload == []const u8);
    try standard.testing.expect(Request.Resume == i32);
    try standard.testing.expectEqual(program_plan.ValueCodec.string, Exists.payload_ref.codec);
    try standard.testing.expectEqual(program_plan.ValueCodec.i32, Exists.resume_ref.codec);

    const exists_call = try Exists.call(root, dst, payload);
    try standard.testing.expectEqual(program_plan.InstructionKind.call_op, exists_call.kind);
    try standard.testing.expectEqual(@as(u16, 1), exists_call.dst);
    try standard.testing.expectEqual(@as(u16, 4), exists_call.operand);
    try standard.testing.expectEqual(@as(u16, 0), exists_call.aux);

    const invalid_call = try Invalid.call(root, null, payload);
    try standard.testing.expectEqual(program_plan.InstructionKind.call_op, invalid_call.kind);
    try standard.testing.expectEqual(standard.math.maxInt(u16), invalid_call.dst);
    try standard.testing.expectEqual(@as(u16, 6), invalid_call.operand);
    try standard.testing.expectEqual(@as(u16, 0), invalid_call.aux);
}

test "schema Protocol exposes protocol-level operation descriptors" {
    const PolicyRequest = struct {
        subject: []const u8,
    };
    const AlternateRequest = struct {
        resource: []const u8,
    };
    const PolicyDecision = enum {
        allow,
        deny,
    };
    const ResultNote = struct {
        message: []const u8,
    };
    const AlternateResultNote = struct {
        code: i32,
    };
    const Policy = schema.Protocol(.{
        .label = "policy",
        .ops = .{
            schema.transform("check", PolicyRequest, PolicyDecision),
            schema.choice("decide", PolicyRequest, PolicyDecision),
            schema.abort("reject", PolicyRequest),
        },
    });
    const AlternatePolicy = schema.Protocol(.{
        .label = "policy",
        .ops = .{
            schema.transform("check", AlternateRequest, PolicyDecision),
        },
    });
    const Schemas = schema.Registry(.{ PolicyRequest, PolicyDecision });
    const AlternateSchemas = schema.Registry(.{ AlternateRequest, PolicyDecision });
    const ResultSchemas = schema.Registry(.{ PolicyRequest, PolicyDecision, ResultNote });
    const AlternateResultSchemas = schema.Registry(.{ PolicyRequest, PolicyDecision, AlternateResultNote });

    const Check = Policy.operation("check", .{ .schema_refs = Schemas.schema_refs });
    const AlternateCheck = AlternatePolicy.operation("check", .{ .schema_refs = AlternateSchemas.schema_refs });
    const Decide = Policy.op("decide", .{
        .schema_refs = Schemas.schema_refs,
        .Result = []const u8,
    });
    const DecideResultNote = Policy.op("decide", .{
        .schema_refs = ResultSchemas.schema_refs,
        .Result = ResultNote,
    });
    const DecideAlternateResultNote = Policy.op("decide", .{
        .schema_refs = AlternateResultSchemas.schema_refs,
        .Result = AlternateResultNote,
    });
    const Reject = Policy.operation("reject", .{
        .schema_refs = Schemas.schema_refs,
        .Result = PolicyDecision,
    });
    const CheckAgain = Policy.op("check", .{ .schema_refs = Schemas.schema_refs });

    try standard.testing.expect(Check.kind == .protocol_operation);
    try standard.testing.expectEqualStrings("policy", Check.protocol_label);
    try standard.testing.expectEqualStrings("check", Check.op_name);
    try standard.testing.expectEqual(@as(u16, 0), Check.op_ordinal);
    try standard.testing.expect(Check.Payload == PolicyRequest);
    try standard.testing.expect(Check.Resume == PolicyDecision);
    try standard.testing.expect(Check.Result == void);
    try standard.testing.expectEqual(program_plan.ControlMode.transform, Check.op_mode);
    try standard.testing.expectEqual(program_plan.ValueCodec.product, Check.payload_ref.codec);
    try standard.testing.expectEqual(@as(?u16, 0), Check.payload_ref.schema_index);
    try standard.testing.expectEqual(program_plan.ValueCodec.sum, Check.resume_ref.codec);
    try standard.testing.expectEqual(@as(?u16, 1), Check.resume_ref.schema_index);
    try standard.testing.expectEqual(program_plan.ValueCodec.unit, Check.result_ref.codec);
    try standard.testing.expect(Check.may_resume);
    try standard.testing.expect(!Check.may_return_now);
    try standard.testing.expectEqual(Check.fingerprint, CheckAgain.fingerprint);
    try standard.testing.expect(Check.fingerprint != AlternateCheck.fingerprint);

    try standard.testing.expectEqual(program_plan.ControlMode.choice, Decide.mode);
    try standard.testing.expectEqual(program_plan.ValueCodec.string, Decide.result_ref.codec);
    try standard.testing.expect(Decide.may_resume);
    try standard.testing.expect(Decide.may_return_now);
    try standard.testing.expect(DecideResultNote.fingerprint != DecideAlternateResultNote.fingerprint);

    try standard.testing.expectEqual(program_plan.ControlMode.abort, Reject.mode);
    try standard.testing.expectEqual(program_plan.ValueCodec.sum, Reject.result_ref.codec);
    try standard.testing.expectEqual(@as(?u16, 1), Reject.result_ref.schema_index);
    try standard.testing.expect(!Reject.may_resume);
    try standard.testing.expect(Reject.may_return_now);
    try standard.testing.expect(Check.fingerprint != Decide.fingerprint);
    try standard.testing.expect(Decide.fingerprint != Reject.fingerprint);
}

test "schema Protocol lowers output row when declared" {
    const OutputPayload = struct {
        value: i32,
    };
    const Workflow = schema.Protocol(.{
        .label = "approval",
        .output_tag = .final_state,
        .output_type = OutputPayload,
        .ops = .{
            schema.transform("exists", void, i32),
        },
    });
    const Rows = Workflow.Rows(void, .{
        .requirement_index = 1,
        .first_op = 2,
        .first_output = 3,
        .schema_refs = schema.SchemaRefs(.{
            schema.ref(OutputPayload, 8),
        }),
    });

    try standard.testing.expectEqual(@as(u16, 1), Rows.output_count);
    try standard.testing.expectEqual(@as(u16, 3), Rows.first_output);
    try standard.testing.expectEqual(@as(@TypeOf(Rows.requirement.output_tag), .final_state), Rows.requirement.output_tag);
    try standard.testing.expectEqualStrings("approval", Rows.outputs[0].label);
    try standard.testing.expectEqual(program_plan.ValueCodec.product, Rows.outputs[0].codec);
    try standard.testing.expectEqual(@as(?u16, 8), Rows.outputs[0].schema_index);
}

test "schema lowerer lowers reader binding to ProgramPlan rows" {
    const ReaderBinding = schema.Binding("reader", effect_schema.reader_environment(i32, error{}), void);
    const Rows = schema.LowerBinding(ReaderBinding, .{
        .requirement_index = 1,
        .first_op = 3,
    });

    try standard.testing.expectEqualStrings("reader", Rows.requirement.label);
    try standard.testing.expectEqual(@as(u16, 3), Rows.requirement.first_op);
    try standard.testing.expectEqual(@as(u16, 1), Rows.requirement.op_count);
    try standard.testing.expectEqual(@as(@TypeOf(Rows.requirement.lifecycle_tag), .reader_environment), Rows.requirement.lifecycle_tag);
    try standard.testing.expectEqual(@as(@TypeOf(Rows.requirement.output_tag), .none), Rows.requirement.output_tag);
    try standard.testing.expectEqual(@as(usize, 1), Rows.ops.len);
    try standard.testing.expectEqual(@as(usize, 0), Rows.outputs.len);
    try standard.testing.expectEqualStrings("ask", Rows.ops[0].op_name);
    try standard.testing.expectEqual(program_plan.ValueCodec.unit, Rows.ops[0].payload_codec);
    try standard.testing.expectEqual(program_plan.ValueCodec.i32, Rows.ops[0].resume_codec);
}

test "schema lowerer lowers writer binding to ProgramPlan rows" {
    const WriterBinding = schema.Binding("writer", effect_schema.writer_accumulator(i32, error{}), void);
    const schema_outputs = comptime effect_schema.outputs(WriterBinding);
    const Rows = schema.LowerBinding(WriterBinding, .{
        .requirement_index = 0,
        .first_op = 0,
        .first_output = 0,
    });

    try standard.testing.expectEqualStrings("writer", Rows.requirement.label);
    try standard.testing.expectEqual(@as(u16, 1), Rows.requirement.op_count);
    try standard.testing.expectEqual(@as(@TypeOf(Rows.requirement.lifecycle_tag), .writer_accumulator), Rows.requirement.lifecycle_tag);
    try standard.testing.expectEqual(@as(@TypeOf(Rows.requirement.output_tag), .accumulator), Rows.requirement.output_tag);
    try standard.testing.expectEqualStrings("tell", Rows.ops[0].op_name);
    try standard.testing.expectEqual(program_plan.ValueCodec.i32, Rows.ops[0].payload_codec);
    try standard.testing.expectEqual(program_plan.ValueCodec.unit, Rows.ops[0].resume_codec);
    try standard.testing.expectEqual(@as(usize, 1), schema_outputs.len);
    comptime {
        if (schema_outputs[0].OutputType != []i32) {
            @compileError("writer schema output should remain the collected accumulator slice");
        }
    }
    try standard.testing.expectEqualStrings("writer", Rows.outputs[0].label);
    // ProgramPlan output rows describe accumulator item refs; Body.Outputs owns
    // the final collection shape.
    try standard.testing.expectEqual(program_plan.ValueCodec.i32, Rows.outputs[0].codec);
}

test "schema Registry emits product value schemas and refs" {
    const ProductPayload = struct {
        id: []const u8,
        amount: i32,
    };
    const Schemas = schema.Registry(.{ ProductPayload, i32, []const u8 });

    try standard.testing.expectEqual(@as(usize, 1), Schemas.value_schema_types.len);
    try standard.testing.expect(Schemas.value_schema_types[0] == ProductPayload);
    try standard.testing.expectEqual(@as(usize, 1), Schemas.value_schemas.len);
    try standard.testing.expectEqual(program_plan.ValueCodec.product, Schemas.value_schemas[0].codec);
    try standard.testing.expectEqual(@as(u16, 0), Schemas.value_schemas[0].first_field);
    try standard.testing.expectEqual(@as(u16, 2), Schemas.value_schemas[0].field_count);
    try standard.testing.expectEqualStrings("id", Schemas.value_fields[0].name);
    try standard.testing.expectEqual(program_plan.ValueCodec.string, Schemas.value_fields[0].codec);
    try standard.testing.expectEqualStrings("amount", Schemas.value_fields[1].name);
    try standard.testing.expectEqual(program_plan.ValueCodec.i32, Schemas.value_fields[1].codec);
    try standard.testing.expectEqual(program_plan.ValueRef{ .codec = .product, .schema_index = 0 }, Schemas.valueRef(ProductPayload).?);
    try standard.testing.expectEqual(program_plan.ValueRef{ .codec = .i32 }, Schemas.valueRef(i32).?);
}

test "schema Registry emits sum value variants from tuple order" {
    const LookupResult = union(enum) {
        found: []const u8,
        missing: void,
    };
    const ProductPayload = struct {
        result: LookupResult,
    };
    const Schemas = schema.Registry(.{ LookupResult, ProductPayload });

    try standard.testing.expectEqual(@as(usize, 2), Schemas.value_schema_types.len);
    try standard.testing.expect(Schemas.value_schema_types[0] == LookupResult);
    try standard.testing.expect(Schemas.value_schema_types[1] == ProductPayload);
    try standard.testing.expectEqual(program_plan.ValueCodec.sum, Schemas.value_schemas[0].codec);
    try standard.testing.expectEqual(@as(u16, 0), Schemas.value_schemas[0].first_variant);
    try standard.testing.expectEqual(@as(u16, 2), Schemas.value_schemas[0].variant_count);
    try standard.testing.expectEqualStrings("found", Schemas.value_variants[0].name);
    try standard.testing.expectEqual(program_plan.ValueCodec.string, Schemas.value_variants[0].codec);
    try standard.testing.expectEqualStrings("missing", Schemas.value_variants[1].name);
    try standard.testing.expectEqual(program_plan.ValueCodec.unit, Schemas.value_variants[1].codec);
    try standard.testing.expectEqualStrings("result", Schemas.value_fields[0].name);
    try standard.testing.expectEqual(program_plan.ValueCodec.sum, Schemas.value_fields[0].codec);
    try standard.testing.expectEqual(@as(?u16, 0), Schemas.value_fields[0].schema_index);
}

test "schema Registry refs are accepted by Protocol.Rows" {
    const RequestPayload = struct {
        id: []const u8,
    };
    const Decision = union(enum) {
        approved: []const u8,
        denied: void,
    };
    const Schemas = schema.Registry(.{ RequestPayload, Decision });
    const Protocol = schema.Protocol(.{
        .label = "registry.protocol",
        .ops = .{
            schema.transform("ask", RequestPayload, Decision),
        },
    });
    const Rows = Protocol.Rows(struct {}, .{
        .requirement_index = 0,
        .first_op = 0,
        .schema_refs = Schemas.schema_refs,
    });

    try standard.testing.expectEqual(program_plan.ValueCodec.product, Rows.ops[0].payload_codec);
    try standard.testing.expectEqual(@as(?u16, 0), Rows.ops[0].payload_schema_index);
    try standard.testing.expectEqual(program_plan.ValueCodec.sum, Rows.ops[0].resume_codec);
    try standard.testing.expectEqual(@as(?u16, 1), Rows.ops[0].resume_schema_index);
}

test "semantic builder emits valid scalar plan and computes spans" {
    const compiled = comptime builder.semantic.finish(.{
        .label = "semantic.scalar",
        .ir_hash = 0x5151,
        .entry = "run",
        .functions = .{.{
            .symbol_name = "run",
            .params = .{},
            .locals = .{
                builder.semantic.local("result", i32),
            },
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    builder.semantic.constI32("result", 42),
                },
                .terminator = builder.semantic.returnValue("result"),
            }},
        }},
    }) catch |err| @compileError("semantic scalar plan failed: " ++ @errorName(err));

    try standard.testing.expectEqual(@as(usize, 1), compiled.plan.functions.len);
    try standard.testing.expectEqual(@as(u16, 0), compiled.plan.functions[0].first_local);
    try standard.testing.expectEqual(@as(u16, 1), compiled.plan.functions[0].local_count);
    try standard.testing.expectEqual(@as(u16, 0), compiled.plan.functions[0].first_block);
    try standard.testing.expectEqual(@as(u16, 1), compiled.plan.functions[0].block_count);
    try standard.testing.expectEqual(@as(u16, 0), compiled.plan.functions[0].first_instruction);
    try standard.testing.expectEqual(@as(u16, 2), compiled.plan.functions[0].instruction_count);
    try standard.testing.expectEqual(program_plan.InstructionKind.const_i32, compiled.plan.instructions[0].kind);
    try standard.testing.expectEqual(program_plan.InstructionKind.return_value, compiled.plan.instructions[1].kind);
}

test "semantic builder emits valid product identity plan" {
    const Payload = struct {
        amount: i32,
    };
    const Schemas = schema.Registry(.{Payload});
    const compiled = comptime builder.semantic.finish(.{
        .label = "semantic.product",
        .ir_hash = 0x5152,
        .entry = "run",
        .schemas = Schemas,
        .functions = .{.{
            .symbol_name = "run",
            .params = .{
                builder.semantic.param("payload", Payload),
            },
            .locals = .{},
            .result = Payload,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{},
                .terminator = builder.semantic.returnValue("payload"),
            }},
        }},
    }) catch |err| @compileError("semantic product plan failed: " ++ @errorName(err));

    try standard.testing.expectEqual(program_plan.ValueCodec.product, compiled.plan.functions[0].value_codec);
    try standard.testing.expectEqual(@as(?u16, 0), compiled.plan.functions[0].value_schema_index);
    try standard.testing.expectEqual(@as(u16, 1), compiled.plan.functions[0].parameter_count);
    try standard.testing.expectEqual(@as(usize, 1), compiled.plan.value_schemas.len);
}

test "semantic builder emits valid sum branch plan" {
    const Decision = union(enum) {
        approved: []const u8,
        denied: void,
    };
    const Schemas = schema.Registry(.{Decision});
    const compiled = comptime builder.semantic.finish(.{
        .label = "semantic.sum",
        .ir_hash = 0x5153,
        .entry = "run",
        .schemas = Schemas,
        .functions = .{.{
            .symbol_name = "run",
            .params = .{
                builder.semantic.param("decision", Decision),
            },
            .locals = .{
                builder.semantic.local("is_approved", bool),
                builder.semantic.local("answer", []const u8),
            },
            .result = []const u8,
            .blocks = .{
                .{
                    .name = "entry",
                    .instructions = .{
                        builder.semantic.sumVariantIs("is_approved", "decision", 0),
                    },
                    .terminator = builder.semantic.branchIf("is_approved", .{ .then = "approved", .@"else" = "denied" }),
                },
                .{
                    .name = "approved",
                    .instructions = .{
                        builder.semantic.sumExtractPayload("answer", "decision", 0),
                    },
                    .terminator = builder.semantic.returnValue("answer"),
                },
                .{
                    .name = "denied",
                    .instructions = .{
                        builder.semantic.constString("answer", "denied"),
                    },
                    .terminator = builder.semantic.returnValue("answer"),
                },
            },
        }},
    }) catch |err| @compileError("semantic sum plan failed: " ++ @errorName(err));

    try standard.testing.expectEqual(@as(usize, 3), compiled.plan.blocks.len);
    try standard.testing.expectEqual(program_plan.TerminatorKind.branch_if, compiled.plan.terminators[0].kind);
    try standard.testing.expectEqual(@as(u16, 1), compiled.plan.terminators[0].primary);
    try standard.testing.expectEqual(@as(u16, 2), compiled.plan.terminators[0].secondary);
}

test "semantic builder emits protocol transform call with site label" {
    const Protocol = schema.Protocol(.{
        .label = "semantic.protocol.transform",
        .ops = .{
            schema.transform("exists", []const u8, i32),
        },
    });
    const Rows = Protocol.Rows(struct {}, .{ .requirement_index = 0, .first_op = 0 });
    const Exists = Rows.op("exists");
    const compiled = comptime builder.semantic.finish(.{
        .label = "semantic.protocol.transform.plan",
        .ir_hash = 0x5154,
        .entry = "run",
        .requirements = &.{Rows.requirement},
        .ops = &Rows.ops,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = builder.semantic.span(0, 1),
            .params = .{},
            .locals = .{
                builder.semantic.local("payload", []const u8),
                builder.semantic.local("exists", i32),
            },
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    builder.semantic.constString("payload", "request-7"),
                    builder.semantic.call(Exists, .{ .dst = "exists", .payload = "payload", .label = "semantic.exists" }),
                },
                .terminator = builder.semantic.returnValue("exists"),
            }},
        }},
    }) catch |err| @compileError("semantic protocol transform plan failed: " ++ @errorName(err));

    try standard.testing.expectEqual(program_plan.InstructionKind.call_op, compiled.plan.instructions[1].kind);
    try standard.testing.expectEqual(@as(u16, 0), compiled.plan.instructions[1].operand);
    try standard.testing.expectEqual(@as(usize, 1), compiled.site_metadata.len);
    try standard.testing.expectEqual(@as(usize, 1), compiled.site_metadata[0].instruction_index);
    try standard.testing.expectEqualStrings("semantic.exists", compiled.site_metadata[0].label);
}

test "semantic builder emits protocol choice call" {
    const Protocol = schema.Protocol(.{
        .label = "semantic.protocol.choice",
        .ops = .{
            schema.choice("request", []const u8, i32),
        },
    });
    const Rows = Protocol.Rows(struct {}, .{ .requirement_index = 0, .first_op = 0 });
    const Request = Rows.op("request");
    const compiled = comptime builder.semantic.finish(.{
        .label = "semantic.protocol.choice.plan",
        .ir_hash = 0x5155,
        .entry = "run",
        .requirements = &.{Rows.requirement},
        .ops = &Rows.ops,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = builder.semantic.span(0, 1),
            .params = .{},
            .locals = .{
                builder.semantic.local("payload", []const u8),
                builder.semantic.local("answer", i32),
            },
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    builder.semantic.constString("payload", "request-7"),
                    builder.semantic.call(Request, .{ .dst = "answer", .payload = "payload" }),
                },
                .terminator = builder.semantic.returnValue("answer"),
            }},
        }},
    }) catch |err| @compileError("semantic protocol choice plan failed: " ++ @errorName(err));

    try standard.testing.expectEqual(program_plan.ControlMode.choice, compiled.plan.ops[0].mode);
    try standard.testing.expectEqual(program_plan.InstructionKind.call_op, compiled.plan.instructions[1].kind);
}

test "semantic builder emits protocol abort call" {
    const Protocol = schema.Protocol(.{
        .label = "semantic.protocol.abort",
        .ops = .{
            schema.abort("invalid", []const u8),
        },
    });
    const Rows = Protocol.Rows(struct {}, .{ .requirement_index = 0, .first_op = 0 });
    const Invalid = Rows.op("invalid");
    const compiled = comptime builder.semantic.finish(.{
        .label = "semantic.protocol.abort.plan",
        .ir_hash = 0x5156,
        .entry = "run",
        .requirements = &.{Rows.requirement},
        .ops = &Rows.ops,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = builder.semantic.span(0, 1),
            .params = .{},
            .locals = .{
                builder.semantic.local("payload", []const u8),
            },
            .result = []const u8,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    builder.semantic.constString("payload", "missing"),
                    builder.semantic.call(Invalid, .{ .payload = "payload", .label = "semantic.invalid" }),
                },
                .terminator = builder.semantic.returnValue("payload"),
            }},
        }},
    }) catch |err| @compileError("semantic protocol abort plan failed: " ++ @errorName(err));

    try standard.testing.expectEqual(program_plan.ControlMode.abort, compiled.plan.ops[0].mode);
    try standard.testing.expectEqual(@as(u16, standard.math.maxInt(u16)), compiled.plan.instructions[1].dst);
    try standard.testing.expectEqualStrings("semantic.invalid", compiled.site_metadata[0].label);
}

test "schema lowerer maps product refs through explicit schema refs" {
    const ProductPayload = struct {
        amount: i32,
    };
    const Rows = schema.LowerBinding(
        schema.Binding("state", effect_schema.state_cell(ProductPayload, error{}), void),
        .{
            .requirement_index = 0,
            .first_op = 0,
            .first_output = 0,
            .schema_refs = schema.SchemaRefs(.{
                schema.ref(ProductPayload, 3),
            }),
        },
    );

    try standard.testing.expectEqual(program_plan.ValueCodec.unit, Rows.ops[0].payload_codec);
    try standard.testing.expectEqual(@as(?u16, null), Rows.ops[0].payload_schema_index);
    try standard.testing.expectEqual(program_plan.ValueCodec.product, Rows.ops[0].resume_codec);
    try standard.testing.expectEqual(@as(?u16, 3), Rows.ops[0].resume_schema_index);
    try standard.testing.expectEqual(program_plan.ValueCodec.product, Rows.ops[1].payload_codec);
    try standard.testing.expectEqual(@as(?u16, 3), Rows.ops[1].payload_schema_index);
    try standard.testing.expectEqual(program_plan.ValueCodec.unit, Rows.ops[1].resume_codec);
    try standard.testing.expectEqual(@as(?u16, null), Rows.ops[1].resume_schema_index);
    try standard.testing.expectEqual(program_plan.ValueCodec.product, Rows.outputs[0].codec);
    try standard.testing.expectEqual(@as(?u16, 3), Rows.outputs[0].schema_index);
}

test "schema lowerer leaves nested schema indexes caller owned" {
    const InnerPayload = struct {
        amount: i32,
    };
    const OuterPayload = struct {
        inner: InnerPayload,
    };
    const Rows = schema.LowerBinding(
        schema.Binding("exception", effect_schema.abort_catch(OuterPayload, error{}, void), void),
        .{
            .requirement_index = 0,
            .first_op = 0,
            .schema_refs = schema.SchemaRefs(.{
                schema.ref(OuterPayload, 1),
            }),
        },
    );
    const fields = [_]program_plan.ValueFieldPlan{
        value.nestedField("inner", InnerPayload, 0),
    };

    try standard.testing.expectEqual(program_plan.ValueCodec.product, Rows.ops[0].payload_codec);
    try standard.testing.expectEqual(@as(?u16, 1), Rows.ops[0].payload_schema_index);
    try standard.testing.expectEqual(program_plan.ValueCodec.product, fields[0].codec);
    try standard.testing.expectEqual(@as(?u16, 0), fields[0].schema_index);
}

test "schema lowerer maps sum and abort payload refs through explicit schema refs" {
    const OptionalPayload = ?i32;
    const OptionalRows = schema.LowerBinding(
        schema.Binding("optional", effect_schema.choice_policy(OptionalPayload, error{}, void), void),
        .{
            .requirement_index = 0,
            .first_op = 0,
            .schema_refs = schema.SchemaRefs(.{
                schema.ref(OptionalPayload, 1),
            }),
        },
    );
    try standard.testing.expectEqualStrings("request", OptionalRows.ops[0].op_name);
    try standard.testing.expectEqual(program_plan.ValueCodec.unit, OptionalRows.ops[0].payload_codec);
    try standard.testing.expectEqual(program_plan.ValueCodec.sum, OptionalRows.ops[0].resume_codec);
    try standard.testing.expectEqual(@as(?u16, 1), OptionalRows.ops[0].resume_schema_index);

    const ProductPayload = struct {
        amount: i32,
    };
    const ExceptionRows = schema.LowerBinding(
        schema.Binding("exception", effect_schema.abort_catch(ProductPayload, error{}, void), void),
        .{
            .requirement_index = 0,
            .first_op = 0,
            .schema_refs = schema.SchemaRefs(.{
                schema.ref(ProductPayload, 4),
            }),
        },
    );
    try standard.testing.expectEqualStrings("throw", ExceptionRows.ops[0].op_name);
    try standard.testing.expectEqual(program_plan.ValueCodec.product, ExceptionRows.ops[0].payload_codec);
    try standard.testing.expectEqual(@as(?u16, 4), ExceptionRows.ops[0].payload_schema_index);
    try standard.testing.expectEqual(program_plan.ValueCodec.unit, ExceptionRows.ops[0].resume_codec);
    try standard.testing.expectEqual(@as(?u16, null), ExceptionRows.ops[0].resume_schema_index);
}

test "schema lowerer emits resource acquire and release structured refs" {
    const Resource = struct {
        id: i32,
    };
    const Rows = schema.LowerBinding(
        schema.Binding("resource", effect_schema.resource_bracket(Resource, error{}, void), void),
        .{
            .requirement_index = 0,
            .first_op = 0,
            .schema_refs = schema.SchemaRefs(.{
                schema.ref(Resource, 2),
            }),
        },
    );

    try standard.testing.expectEqualStrings("resource", Rows.requirement.label);
    try standard.testing.expectEqual(@as(u16, 2), Rows.op_count);
    try standard.testing.expectEqual(@as(u16, 0), Rows.output_count);

    try standard.testing.expectEqualStrings("acquire", Rows.ops[0].op_name);
    try standard.testing.expectEqual(program_plan.ControlMode.transform, Rows.ops[0].mode);
    try standard.testing.expectEqual(program_plan.ValueCodec.unit, Rows.ops[0].payload_codec);
    try standard.testing.expectEqual(@as(?u16, null), Rows.ops[0].payload_schema_index);
    try standard.testing.expectEqual(program_plan.ValueCodec.product, Rows.ops[0].resume_codec);
    try standard.testing.expectEqual(@as(?u16, 2), Rows.ops[0].resume_schema_index);

    try standard.testing.expectEqualStrings("release", Rows.ops[1].op_name);
    try standard.testing.expectEqual(program_plan.ControlMode.transform, Rows.ops[1].mode);
    try standard.testing.expectEqual(program_plan.ValueCodec.product, Rows.ops[1].payload_codec);
    try standard.testing.expectEqual(@as(?u16, 2), Rows.ops[1].payload_schema_index);
    try standard.testing.expectEqual(program_plan.ValueCodec.unit, Rows.ops[1].resume_codec);
    try standard.testing.expectEqual(@as(?u16, null), Rows.ops[1].resume_schema_index);
}

test "raw ProgramPlan row construction remains available" {
    const requirement = plan.Requirement{
        .label = "raw",
        .first_op = 4,
        .op_count = 1,
    };
    const op = plan.Op{
        .requirement_index = 0,
        .op_name = "dispatch",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .unit,
    };
    const output = plan.Output{
        .label = "raw-output",
        .codec = .unit,
    };

    try standard.testing.expectEqualStrings("raw", requirement.label);
    try standard.testing.expectEqualStrings("dispatch", op.op_name);
    try standard.testing.expectEqualStrings("raw-output", output.label);
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
    try std.testing.expectEqual(@as(u16, 0), built_plan.functions[1].entry_block);
    try std.testing.expectEqual(@as(u16, 2), built_plan.terminators[1].primary);
    try std.testing.expectEqual(@as(u16, 3), built_plan.terminators[1].secondary);
    _ = helper;
}

test "layout builder keeps second function entry block function-relative" {
    const std = @import("std");

    const helper = comptime builder.function(0);
    const root = comptime builder.function(1);
    const built_plan = comptime builder.layout.finish(.{
        .label = "layout.entry.relative",
        .ir_hash = 13,
        .entry = root,
        .functions = .{
            .{
                .symbol_name = "helper",
                .locals = .{},
                .blocks = .{.{
                    .instructions = .{},
                    .terminator = program_plan.Terminator{ .kind = .return_unit },
                }},
            },
            .{
                .symbol_name = "run",
                .locals = .{},
                .entry_block = 0,
                .blocks = .{.{
                    .instructions = .{},
                    .terminator = program_plan.Terminator{ .kind = .return_unit },
                }},
            },
        },
    }) catch unreachable;

    try std.testing.expectEqual(@as(u16, 1), built_plan.functions[1].first_block);
    try std.testing.expectEqual(@as(u16, 0), built_plan.functions[1].entry_block);
    _ = helper;
}
