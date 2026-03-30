const std = @import("std");

/// One canonical control class in the resolved Effect IR.
pub const ControlMode = enum {
    abort,
    choice,
    transform,
};

fn LeafDescriptor(
    comptime mode_value: ControlMode,
    comptime Payload: type,
    comptime Resume: type,
) type {
    return struct {
        /// Marker that this type is one effect-IR leaf descriptor.
        pub const is_effect_ir_leaf = true;
        /// The control mode carried by this leaf.
        pub const mode = mode_value;
        /// The payload type carried by this leaf.
        pub const PayloadType = Payload;
        /// The resumed answer type carried by this leaf.
        pub const ResumeType = Resume;
    };
}

/// One transform leaf descriptor for a structural row literal.
pub fn Transform(comptime Payload: type, comptime Resume: type) type {
    return LeafDescriptor(.transform, Payload, Resume);
}

/// One choice leaf descriptor for a structural row literal.
pub fn Choice(comptime Payload: type, comptime Resume: type) type {
    return LeafDescriptor(.choice, Payload, Resume);
}

/// One abort leaf descriptor for a structural row literal.
pub fn Abort(comptime Payload: type) type {
    return LeafDescriptor(.abort, Payload, noreturn);
}

/// One normalized leaf emitted from a nested structural row literal.
pub const NormalizedLeaf = struct {
    path: []const u8,
    mode: ControlMode,
    PayloadType: type,
    ResumeType: type,
};

fn isNormalizedLeafDescriptor(comptime T: type) bool {
    return @hasDecl(T, "is_effect_ir_leaf") and
        @hasDecl(T, "mode") and
        @hasDecl(T, "PayloadType") and
        @hasDecl(T, "ResumeType");
}

fn joinPath(comptime prefix: []const u8, comptime name: []const u8) []const u8 {
    if (prefix.len == 0) return name;
    return std.fmt.comptimePrint("{s}.{s}", .{ prefix, name });
}

fn countLeaves(comptime Spec: anytype) usize {
    const SpecType = @TypeOf(Spec);
    const info = @typeInfo(SpecType);
    if (info != .@"struct") @compileError("effect_ir row specs must be nested struct literals whose leaves are Transform/Choice/Abort descriptors");

    var count: usize = 0;
    inline for (info.@"struct".fields) |field| {
        const field_value = @field(Spec, field.name);
        const FieldType = @TypeOf(field_value);
        if (FieldType == type and isNormalizedLeafDescriptor(field_value)) {
            count += 1;
            continue;
        }
        count += countLeaves(field_value);
    }
    return count;
}

fn populateLeaves(
    comptime Spec: anytype,
    comptime prefix: []const u8,
    comptime leaves: []NormalizedLeaf,
    index: *usize,
) void {
    const SpecType = @TypeOf(Spec);
    const info = @typeInfo(SpecType);
    if (info != .@"struct") @compileError("effect_ir row specs must be nested struct literals whose leaves are Transform/Choice/Abort descriptors");

    inline for (info.@"struct".fields) |field| {
        const path = joinPath(prefix, field.name);
        const field_value = @field(Spec, field.name);
        const FieldType = @TypeOf(field_value);
        if (FieldType == type and isNormalizedLeafDescriptor(field_value)) {
            leaves[index.*] = .{
                .path = path,
                .mode = field_value.mode,
                .PayloadType = field_value.PayloadType,
                .ResumeType = field_value.ResumeType,
            };
            index.* += 1;
            continue;
        }
        populateLeaves(field_value, path, leaves, index);
    }
}

fn assertUniqueLeafPaths(comptime leaves: []const NormalizedLeaf) void {
    inline for (leaves, 0..) |leaf, index| {
        inline for (leaves[(index + 1)..]) |other| {
            if (std.mem.eql(u8, leaf.path, other.path)) {
                @compileError(std.fmt.comptimePrint("duplicate effect_ir leaf path: {s}", .{leaf.path}));
            }
        }
    }
}

/// Resolve one nested row literal into a stable normalized leaf set.
pub fn NormalizedRow(comptime Spec: anytype) type {
    const leaf_count_value = comptime countLeaves(Spec);
    const normalized_leaves = comptime blk: {
        var leaf_buffer: [leaf_count_value]NormalizedLeaf = undefined;
        var index: usize = 0;
        populateLeaves(Spec, "", leaf_buffer[0..], &index);
        assertUniqueLeafPaths(leaf_buffer[0..]);
        break :blk leaf_buffer;
    };

    return struct {
        /// The original nested row spec.
        pub const raw = Spec;
        /// The normalized leaves derived from this row.
        pub const leaves = normalized_leaves;
        /// The number of normalized leaves derived from this row.
        pub const leaf_count = leaf_count_value;
    };
}

/// Merge multiple row literals into one normalized leaf set.
pub fn MergedRows(comptime Specs: anytype) type {
    const specs_info = @typeInfo(@TypeOf(Specs));
    if (specs_info != .@"struct" or !specs_info.@"struct".is_tuple) {
        @compileError("MergedRows expects a tuple of row specs");
    }

    const total_value = comptime blk: {
        var total: usize = 0;
        for (Specs) |Spec| total += countLeaves(Spec);
        break :blk total;
    };
    const normalized_leaves = comptime blk: {
        var leaf_buffer: [total_value]NormalizedLeaf = undefined;
        var index: usize = 0;
        for (Specs) |Spec| populateLeaves(Spec, "", leaf_buffer[0..], &index);
        assertUniqueLeafPaths(leaf_buffer[0..]);
        break :blk leaf_buffer;
    };

    return struct {
        /// The original tuple of row specs.
        pub const specs = Specs;
        /// The normalized leaves derived from the merged rows.
        pub const leaves = normalized_leaves;
        /// The total number of normalized leaves in the merged rows.
        pub const leaf_count = total_value;
    };
}

/// Stable reference to one elaborated function symbol.
pub const SymbolRef = struct {
    module_path: []const u8,
    symbol_name: []const u8,

    /// Compare two symbolic references for equality.
    pub fn eql(self: SymbolRef, other: SymbolRef) bool {
        return std.mem.eql(u8, self.module_path, other.module_path) and
            std.mem.eql(u8, self.symbol_name, other.symbol_name);
    }
};

/// One explicit output carried out of a handled root.
pub const OutputSpec = struct {
    label: []const u8,
    OutputType: type,
};

/// One structural operation descriptor in the resolved Effect IR.
pub const OpSpec = struct {
    requirement_label: []const u8,
    op_name: []const u8,
    mode: ControlMode,
    PayloadType: type,
    ResumeType: type,
};

/// One top-level named requirement in the resolved row.
pub const Requirement = struct {
    label: []const u8,
    ops: []const OpSpec,
};

/// One normalized open requirement row.
pub const Row = struct {
    requirements: []const Requirement,
};

/// One explicit call edge used by the resolver and SCC pass.
pub const CallEdge = struct {
    caller: SymbolRef,
    callee: SymbolRef,
};

/// Stable local slot identifier inside one public helper body.
pub const LocalId = u16;

/// Stable basic-block identifier inside one public helper body.
pub const BlockId = u16;

/// Serializable local codec admitted by the public helper-body machine.
pub const LocalCodec = enum {
    bool,
    i32,
    string,
    string_list,
    unit,
    usize,
};

/// Public helper-body instruction tags.
pub const InstructionKind = enum {
    add_const_i32,
    call_helper,
    call_op,
    compare_eq_zero,
    const_i32,
    const_string,
    return_value,
    sub_one,
};

/// Public helper-body instruction.
pub const Instruction = struct {
    kind: InstructionKind,
    dst: LocalId = 0,
    operand: u16 = 0,
    aux: u16 = 0,
    string_literal: []const u8 = "",
};

/// Public helper-body terminator tags.
pub const TerminatorKind = enum {
    branch_if,
    jump,
    return_unit,
    return_value,
};

/// Public helper-body terminator.
pub const Terminator = struct {
    kind: TerminatorKind,
    primary: u16 = 0,
    secondary: u16 = 0,
};

/// Public helper-body basic block.
pub const Block = struct {
    instructions: []const Instruction,
    terminator: Terminator,
};

/// Public helper-body payload aligned to one function.
pub const FunctionBody = struct {
    local_codecs: []const LocalCodec = &.{},
    call_arg_locals: []const LocalId = &.{},
    entry_block: BlockId = 0,
    blocks: []const Block = &.{},
};

/// One graph owned by the symbol/SCC resolver.
pub const ResolverGraph = struct {
    symbols: []const SymbolRef,
    edges: []const CallEdge,
};

/// One strongly connected component in the resolver graph.
pub const SccGroup = struct {
    symbol_indexes: []usize,
};

/// One elaborated function body signature in the resolved Effect IR.
pub const Function = struct {
    symbol: SymbolRef,
    row: Row,
    parameter_codecs: []const LocalCodec = &.{},
    ValueType: type = void,
    outputs: []const OutputSpec = &.{},
};

/// One resolved program plus the call graph it was elaborated from.
pub const Program = struct {
    entry_index: u16 = 0,
    functions: []const Function,
    call_edges: []const CallEdge,
    function_bodies: []const FunctionBody = &.{},
};

/// One strongly connected component over symbolic functions.
pub const SccComponent = struct {
    indices: []usize,
};

/// Allocator-owned SCC resolution result.
pub const SccResolution = struct {
    components: []SccComponent,

    /// Release allocator-owned component index storage.
    pub fn deinit(self: *SccResolution, allocator: std.mem.Allocator) void {
        for (self.components) |component| allocator.free(component.indices);
        allocator.free(self.components);
        self.* = undefined;
    }
};

/// Stable digest over one normalized row/program shape.
pub const NormalizationDigest = struct {
    hash: u64,
    requirement_count: usize,
    op_count: usize,
    output_count: usize,
};

/// Error set for row normalization and graph validation.
pub const NormalizeError = error{
    DuplicateRequirementLabel,
    DuplicateOpName,
    DuplicateOutputLabel,
    EmptyRequirementLabel,
    EmptyOpName,
    InvalidRequirementShape,
    InvalidRowShape,
    OutputWithoutRequirement,
    DuplicateSymbol,
    InvalidProgramBodyShape,
    UnknownSymbol,
    UnsupportedHelperCallEdge,
    OutOfMemory,
};

fn hashBytes(hasher: *std.hash.Wyhash, value: []const u8) void {
    hasher.update(value);
    hasher.update(&.{0});
}

fn hashTypeName(hasher: *std.hash.Wyhash, comptime T: type) void {
    hashBytes(hasher, @typeName(T));
}

fn assertRowShape(comptime Spec: anytype) void {
    if (@typeInfo(@TypeOf(Spec)) != .@"struct") {
        @compileError("effect_ir row specs must be nested struct literals");
    }
}

fn assertRequirementShape(comptime label: []const u8, comptime Spec: anytype) void {
    if (@typeInfo(@TypeOf(Spec)) != .@"struct") {
        @compileError(std.fmt.comptimePrint(
            "effect_ir requirement '{s}' must be a nested struct of op descriptors",
            .{label},
        ));
    }
}

fn countOps(comptime RequirementSpec: anytype) usize {
    comptime assertRequirementShape("?", RequirementSpec);
    return @typeInfo(@TypeOf(RequirementSpec)).@"struct".fields.len;
}

fn requirementFromSpec(comptime label: []const u8, comptime RequirementSpec: anytype) Requirement {
    comptime assertRequirementShape(label, RequirementSpec);
    const fields = @typeInfo(@TypeOf(RequirementSpec)).@"struct".fields;
    const ops = comptime blk: {
        var buffer: [fields.len]OpSpec = undefined;
        for (fields, 0..) |field, index| {
            const leaf_value = @field(RequirementSpec, field.name);
            const LeafType = @TypeOf(leaf_value);
            if (LeafType != type or !isNormalizedLeafDescriptor(leaf_value)) {
                @compileError(std.fmt.comptimePrint(
                    "effect_ir requirement '{s}' field '{s}' must be Transform/Choice/Abort",
                    .{ label, field.name },
                ));
            }
            buffer[index] = .{
                .requirement_label = label,
                .op_name = field.name,
                .mode = leaf_value.mode,
                .PayloadType = leaf_value.PayloadType,
                .ResumeType = leaf_value.ResumeType,
            };
        }
        break :blk buffer;
    };
    return .{
        .label = label,
        .ops = &ops,
    };
}

/// Normalize one structural row literal into the canonical row shape.
pub fn rowFromSpec(comptime Spec: anytype) Row {
    comptime assertRowShape(Spec);
    const fields = @typeInfo(@TypeOf(Spec)).@"struct".fields;
    const requirements = comptime blk: {
        var buffer: [fields.len]Requirement = undefined;
        for (fields, 0..) |field, index| {
            buffer[index] = requirementFromSpec(field.name, @field(Spec, field.name));
        }
        break :blk buffer;
    };
    return .{
        .requirements = &requirements,
    };
}

fn mergedRequirementCount(comptime Specs: anytype) usize {
    var total: usize = 0;
    for (Specs, 0..) |Spec, spec_index| {
        inline for (@typeInfo(@TypeOf(Spec)).@"struct".fields) |field| {
            var seen = false;
            for (Specs, 0..) |EarlierSpec, earlier_index| {
                if (earlier_index >= spec_index) break;
                inline for (@typeInfo(@TypeOf(EarlierSpec)).@"struct".fields) |earlier_field| {
                    if (std.mem.eql(u8, earlier_field.name, field.name)) seen = true;
                }
            }
            if (!seen) total += 1;
        }
    }
    return total;
}

fn mergedRequirementCountFromRows(comptime Rows: anytype) usize {
    var total: usize = 0;
    inline for (Rows, 0..) |row_value, row_index| {
        inline for (row_value.requirements) |requirement| {
            var seen = false;
            inline for (Rows, 0..) |earlier_row, earlier_index| {
                if (earlier_index >= row_index) break;
                inline for (earlier_row.requirements) |earlier_requirement| {
                    if (std.mem.eql(u8, earlier_requirement.label, requirement.label)) seen = true;
                }
            }
            if (!seen) total += 1;
        }
    }
    return total;
}

fn mergedRequirementForLabel(comptime label: []const u8, comptime Specs: anytype) Requirement {
    const op_total = comptime blk: {
        var total: usize = 0;
        for (Specs) |Spec| {
            for (@typeInfo(@TypeOf(Spec)).@"struct".fields) |field| {
                if (std.mem.eql(u8, field.name, label)) total += countOps(@field(Spec, field.name));
            }
        }
        break :blk total;
    };
    const ops = comptime blk: {
        var buffer: [op_total]OpSpec = undefined;
        var index: usize = 0;
        for (Specs) |Spec| {
            for (@typeInfo(@TypeOf(Spec)).@"struct".fields) |field| {
                if (!std.mem.eql(u8, field.name, label)) continue;
                const requirement = requirementFromSpec(label, @field(Spec, field.name));
                for (requirement.ops) |op| {
                    for (buffer[0..index]) |existing| {
                        if (std.mem.eql(u8, existing.op_name, op.op_name)) {
                            @compileError(std.fmt.comptimePrint(
                                "duplicate effect_ir op name '{s}.{s}' in merged rows",
                                .{ label, op.op_name },
                            ));
                        }
                    }
                    buffer[index] = op;
                    index += 1;
                }
            }
        }
        break :blk buffer;
    };
    return .{
        .label = label,
        .ops = &ops,
    };
}

fn mergedRequirementForLabelFromRows(comptime label: []const u8, comptime Rows: anytype) Requirement {
    const op_total = comptime blk: {
        var total: usize = 0;
        for (Rows) |row_value| {
            for (row_value.requirements) |requirement| {
                if (std.mem.eql(u8, requirement.label, label)) total += requirement.ops.len;
            }
        }
        break :blk total;
    };
    const ops = comptime blk: {
        var buffer: [op_total]OpSpec = undefined;
        var index: usize = 0;
        for (Rows) |row_value| {
            for (row_value.requirements) |requirement| {
                if (!std.mem.eql(u8, requirement.label, label)) continue;
                for (requirement.ops) |op| {
                    for (buffer[0..index]) |existing| {
                        if (std.mem.eql(u8, existing.op_name, op.op_name)) {
                            @compileError(std.fmt.comptimePrint(
                                "duplicate effect_ir op name '{s}.{s}' in merged rows",
                                .{ label, op.op_name },
                            ));
                        }
                    }
                    buffer[index] = op;
                    index += 1;
                }
            }
        }
        break :blk buffer;
    };
    return .{
        .label = label,
        .ops = &ops,
    };
}

/// Merge multiple row literals left-to-right into one canonical row.
pub fn mergeRows(comptime Specs: anytype) Row {
    const info = @typeInfo(@TypeOf(Specs));
    if (info != .@"struct" or !info.@"struct".is_tuple) {
        @compileError("effect_ir mergeRows expects a tuple of row specs");
    }

    const rows_are_normalized = comptime blk: {
        var all_rows = true;
        for (Specs) |spec| {
            if (@TypeOf(spec) != Row) all_rows = false;
        }
        break :blk all_rows;
    };

    if (rows_are_normalized) {
        const requirement_count = comptime mergedRequirementCountFromRows(Specs);
        const requirements = comptime blk: {
            var buffer: [requirement_count]Requirement = undefined;
            var index: usize = 0;
            for (Specs, 0..) |row_value, row_index| {
                for (row_value.requirements) |requirement| {
                    var seen = false;
                    for (Specs, 0..) |earlier_row, earlier_index| {
                        if (earlier_index >= row_index) break;
                        for (earlier_row.requirements) |earlier_requirement| {
                            if (std.mem.eql(u8, earlier_requirement.label, requirement.label)) seen = true;
                        }
                    }
                    if (seen) continue;
                    buffer[index] = mergedRequirementForLabelFromRows(requirement.label, Specs);
                    index += 1;
                }
            }
            break :blk buffer;
        };
        return .{
            .requirements = &requirements,
        };
    }

    const requirement_count = comptime mergedRequirementCount(Specs);
    const requirements = comptime blk: {
        var buffer: [requirement_count]Requirement = undefined;
        var index: usize = 0;
        for (Specs, 0..) |Spec, spec_index| {
            for (@typeInfo(@TypeOf(Spec)).@"struct".fields) |field| {
                var seen = false;
                for (Specs, 0..) |EarlierSpec, earlier_index| {
                    if (earlier_index >= spec_index) break;
                    for (@typeInfo(@TypeOf(EarlierSpec)).@"struct".fields) |earlier_field| {
                        if (std.mem.eql(u8, earlier_field.name, field.name)) seen = true;
                    }
                }
                if (seen) continue;
                buffer[index] = mergedRequirementForLabel(field.name, Specs);
                index += 1;
            }
        }
        break :blk buffer;
    };
    return .{
        .requirements = &requirements,
    };
}

fn symbolIndexSlice(symbols: []const SymbolRef, target: SymbolRef) ?usize {
    for (symbols, 0..) |symbol, index| {
        if (symbol.eql(target)) return index;
    }
    return null;
}

fn modeBytes(mode: ControlMode) []const u8 {
    return switch (mode) {
        .transform => "transform",
        .choice => "choice",
        .abort => "abort",
    };
}

fn symbolEq(left: SymbolRef, right: SymbolRef) bool {
    return std.mem.eql(u8, left.module_path, right.module_path) and std.mem.eql(u8, left.symbol_name, right.symbol_name);
}

/// Return the index of one symbol in a resolver graph.
pub fn symbolIndex(graph: ResolverGraph, symbol: SymbolRef) ?usize {
    for (graph.symbols, 0..) |candidate, index| {
        if (symbolEq(candidate, symbol)) return index;
    }
    return null;
}

/// Validate that every graph symbol is unique and every edge resolves.
pub fn validateGraph(graph: ResolverGraph) NormalizeError!void {
    for (graph.symbols, 0..) |symbol, index| {
        for (graph.symbols[index + 1 ..]) |other| {
            if (symbolEq(symbol, other)) return error.DuplicateSymbol;
        }
    }
    for (graph.edges) |edge| {
        _ = symbolIndex(graph, edge.caller) orelse return error.UnknownSymbol;
        _ = symbolIndex(graph, edge.callee) orelse return error.UnknownSymbol;
    }
}

/// Compute strongly connected components for one validated resolver graph.
pub fn computeSccs(allocator: std.mem.Allocator, graph: ResolverGraph) NormalizeError![]SccGroup {
    try validateGraph(graph);
    var state = struct {
        allocator: std.mem.Allocator,
        graph: ResolverGraph,
        stack: std.ArrayList(usize),
        groups: std.ArrayList(SccGroup),
        indexes: []usize,
        lowlinks: []usize,
        on_stack: []bool,
        next_index: usize = 0,

        fn visit(self: *@This(), vertex: usize) NormalizeError!void {
            self.indexes[vertex] = self.next_index;
            self.lowlinks[vertex] = self.next_index;
            self.next_index += 1;
            try self.stack.append(self.allocator, vertex);
            self.on_stack[vertex] = true;

            for (self.graph.edges) |edge| {
                const caller_index = symbolIndex(self.graph, edge.caller).?;
                if (caller_index != vertex) continue;
                const callee_index = symbolIndex(self.graph, edge.callee).?;
                if (self.indexes[callee_index] == std.math.maxInt(usize)) {
                    try self.visit(callee_index);
                    self.lowlinks[vertex] = @min(self.lowlinks[vertex], self.lowlinks[callee_index]);
                } else if (self.on_stack[callee_index]) {
                    self.lowlinks[vertex] = @min(self.lowlinks[vertex], self.indexes[callee_index]);
                }
            }

            if (self.lowlinks[vertex] != self.indexes[vertex]) return;

            var component = std.ArrayList(usize){};
            while (true) {
                const member = self.stack.pop().?;
                self.on_stack[member] = false;
                try component.append(self.allocator, member);
                if (member == vertex) break;
            }
            try self.groups.append(self.allocator, .{
                .symbol_indexes = try component.toOwnedSlice(self.allocator),
            });
        }
    }{
        .allocator = allocator,
        .graph = graph,
        .stack = .{},
        .groups = .{},
        .indexes = try allocator.alloc(usize, graph.symbols.len),
        .lowlinks = try allocator.alloc(usize, graph.symbols.len),
        .on_stack = try allocator.alloc(bool, graph.symbols.len),
    };
    defer state.stack.deinit(allocator);
    defer allocator.free(state.indexes);
    defer allocator.free(state.lowlinks);
    defer allocator.free(state.on_stack);
    errdefer {
        for (state.groups.items) |group| allocator.free(group.symbol_indexes);
        state.groups.deinit(allocator);
    }

    @memset(state.indexes, std.math.maxInt(usize));
    @memset(state.lowlinks, 0);
    @memset(state.on_stack, false);

    for (graph.symbols, 0..) |_, vertex| {
        if (state.indexes[vertex] != std.math.maxInt(usize)) continue;
        try state.visit(vertex);
    }
    return try state.groups.toOwnedSlice(allocator);
}

/// Free SCC groups returned by `computeSccs`.
pub fn deinitSccs(allocator: std.mem.Allocator, groups: []SccGroup) void {
    for (groups) |group| allocator.free(group.symbol_indexes);
    allocator.free(groups);
}

/// Validate one resolved row before later elaboration passes consume it.
pub fn validateRow(comptime row: Row) NormalizeError!void {
    inline for (row.requirements, 0..) |requirement, requirement_index| {
        if (requirement.label.len == 0) return error.EmptyRequirementLabel;
        inline for (row.requirements[requirement_index + 1 ..]) |other| {
            if (std.mem.eql(u8, requirement.label, other.label)) {
                return error.DuplicateRequirementLabel;
            }
        }
        inline for (requirement.ops, 0..) |op, op_index| {
            if (op.op_name.len == 0) return error.EmptyOpName;
            if (!std.mem.eql(u8, op.requirement_label, requirement.label)) {
                return error.DuplicateRequirementLabel;
            }
            inline for (requirement.ops[op_index + 1 ..]) |other_op| {
                if (std.mem.eql(u8, op.op_name, other_op.op_name)) {
                    return error.DuplicateOpName;
                }
            }
        }
    }
}

/// Validate the explicit output schema attached to one elaborated function.
pub fn validateOutputs(comptime row: Row, comptime outputs: []const OutputSpec) NormalizeError!void {
    inline for (outputs, 0..) |output, output_index| {
        var found_requirement = false;
        inline for (row.requirements) |requirement| {
            if (std.mem.eql(u8, output.label, requirement.label)) {
                found_requirement = true;
                break;
            }
        }
        if (!found_requirement) return error.OutputWithoutRequirement;
        inline for (outputs[output_index + 1 ..]) |other| {
            if (std.mem.eql(u8, output.label, other.label)) {
                return error.DuplicateOutputLabel;
            }
        }
    }
}

/// Compute a stable digest for one normalized row plus output schema.
pub fn rowDigest(comptime row: Row, comptime outputs: []const OutputSpec) NormalizeError!NormalizationDigest {
    try validateRow(row);
    try validateOutputs(row, outputs);

    var hasher = std.hash.Wyhash.init(0);
    var op_count: usize = 0;
    inline for (row.requirements) |requirement| {
        hashBytes(&hasher, requirement.label);
        inline for (requirement.ops) |op| {
            hashBytes(&hasher, op.requirement_label);
            hashBytes(&hasher, op.op_name);
            hashBytes(&hasher, modeBytes(op.mode));
            hashTypeName(&hasher, op.PayloadType);
            hashTypeName(&hasher, op.ResumeType);
            op_count += 1;
        }
    }
    inline for (outputs) |output| {
        hashBytes(&hasher, output.label);
        hashTypeName(&hasher, output.OutputType);
    }
    return .{
        .hash = hasher.final(),
        .requirement_count = row.requirements.len,
        .op_count = op_count,
        .output_count = outputs.len,
    };
}

/// Resolve strongly connected components over the symbolic call graph.
pub fn resolveSccs(
    allocator: std.mem.Allocator,
    symbols: []const SymbolRef,
    edges: []const CallEdge,
) NormalizeError!SccResolution {
    try validateGraph(.{
        .symbols = symbols,
        .edges = edges,
    });
    var state = struct {
        allocator: std.mem.Allocator,
        symbols: []const SymbolRef,
        edges: []const CallEdge,
        next_index: usize = 0,
        stack: std.ArrayList(usize),
        indices: []isize,
        low_links: []usize,
        on_stack: []bool,
        components: std.ArrayList(SccComponent),

        fn visit(self: *@This(), index: usize) !void {
            self.indices[index] = @as(isize, @intCast(self.next_index));
            self.low_links[index] = self.next_index;
            self.next_index += 1;
            try self.stack.append(self.allocator, index);
            self.on_stack[index] = true;

            const caller = self.symbols[index];
            for (self.edges) |edge| {
                if (!caller.eql(edge.caller)) continue;
                const callee_index = symbolIndexSlice(self.symbols, edge.callee).?;
                if (self.indices[callee_index] == -1) {
                    try self.visit(callee_index);
                    self.low_links[index] = @min(self.low_links[index], self.low_links[callee_index]);
                    continue;
                }
                if (self.on_stack[callee_index]) {
                    const discovery: usize = @intCast(self.indices[callee_index]);
                    self.low_links[index] = @min(self.low_links[index], discovery);
                }
            }

            if (self.low_links[index] != @as(usize, @intCast(self.indices[index]))) return;

            var members = std.ArrayList(usize).empty;
            defer members.deinit(self.allocator);
            while (true) {
                const member = self.stack.pop().?;
                self.on_stack[member] = false;
                try members.append(self.allocator, member);
                if (member == index) break;
            }

            try self.components.append(self.allocator, .{
                .indices = try members.toOwnedSlice(self.allocator),
            });
        }
    }{
        .allocator = allocator,
        .symbols = symbols,
        .edges = edges,
        .stack = .empty,
        .indices = try allocator.alloc(isize, symbols.len),
        .low_links = try allocator.alloc(usize, symbols.len),
        .on_stack = try allocator.alloc(bool, symbols.len),
        .components = .empty,
    };
    defer state.stack.deinit(allocator);
    defer allocator.free(state.indices);
    defer allocator.free(state.low_links);
    defer allocator.free(state.on_stack);
    errdefer {
        for (state.components.items) |component| allocator.free(component.indices);
        state.components.deinit(allocator);
    }

    @memset(state.indices, -1);
    @memset(state.low_links, 0);
    @memset(state.on_stack, false);

    for (symbols, 0..) |_, index| {
        if (state.indices[index] != -1) continue;
        try state.visit(index);
    }

    return .{
        .components = try state.components.toOwnedSlice(allocator),
    };
}

test "row digest counts requirements ops and outputs" {
    const row = Row{
        .requirements = &.{
            .{
                .label = "state",
                .ops = &.{
                    .{
                        .requirement_label = "state",
                        .op_name = "get",
                        .mode = .transform,
                        .PayloadType = void,
                        .ResumeType = i32,
                    },
                    .{
                        .requirement_label = "state",
                        .op_name = "set",
                        .mode = .transform,
                        .PayloadType = i32,
                        .ResumeType = void,
                    },
                },
            },
            .{
                .label = "writer",
                .ops = &.{
                    .{
                        .requirement_label = "writer",
                        .op_name = "tell",
                        .mode = .transform,
                        .PayloadType = []const u8,
                        .ResumeType = void,
                    },
                },
            },
        },
    };
    const digest = try rowDigest(row, &.{
        .{ .label = "state", .OutputType = i32 },
        .{ .label = "writer", .OutputType = [][]const u8 },
    });
    try std.testing.expectEqual(@as(usize, 2), digest.requirement_count);
    try std.testing.expectEqual(@as(usize, 3), digest.op_count);
    try std.testing.expectEqual(@as(usize, 2), digest.output_count);
}

test "duplicate requirement label is rejected" {
    const row = Row{
        .requirements = &.{
            .{ .label = "state", .ops = &.{} },
            .{ .label = "state", .ops = &.{} },
        },
    };
    try std.testing.expectError(error.DuplicateRequirementLabel, validateRow(row));
}

test "duplicate output label is rejected" {
    const row = Row{
        .requirements = &.{
            .{ .label = "state", .ops = &.{} },
        },
    };
    try std.testing.expectError(error.DuplicateOutputLabel, validateOutputs(row, &.{
        .{ .label = "state", .OutputType = i32 },
        .{ .label = "state", .OutputType = i32 },
    }));
}

test "resolver graph rejects unknown symbols" {
    const graph = ResolverGraph{
        .symbols = &.{
            .{ .module_path = "a.zig", .symbol_name = "f" },
        },
        .edges = &.{
            .{
                .caller = .{ .module_path = "a.zig", .symbol_name = "f" },
                .callee = .{ .module_path = "b.zig", .symbol_name = "g" },
            },
        },
    };
    try std.testing.expectError(error.UnknownSymbol, validateGraph(graph));
}

test "resolver graph computes one SCC for a mutual recursion pair" {
    const allocator = std.testing.allocator;
    const graph = ResolverGraph{
        .symbols = &.{
            .{ .module_path = "a.zig", .symbol_name = "f" },
            .{ .module_path = "b.zig", .symbol_name = "g" },
        },
        .edges = &.{
            .{
                .caller = .{ .module_path = "a.zig", .symbol_name = "f" },
                .callee = .{ .module_path = "b.zig", .symbol_name = "g" },
            },
            .{
                .caller = .{ .module_path = "b.zig", .symbol_name = "g" },
                .callee = .{ .module_path = "a.zig", .symbol_name = "f" },
            },
        },
    };
    const groups = try computeSccs(allocator, graph);
    defer deinitSccs(allocator, groups);
    try std.testing.expectEqual(@as(usize, 1), groups.len);
    try std.testing.expectEqual(@as(usize, 2), groups[0].symbol_indexes.len);
}

test "resolveSccs groups mutually recursive symbols together" {
    const symbols = [_]SymbolRef{
        .{ .module_path = "a.zig", .symbol_name = "alpha" },
        .{ .module_path = "b.zig", .symbol_name = "beta" },
        .{ .module_path = "c.zig", .symbol_name = "gamma" },
    };
    const edges = [_]CallEdge{
        .{ .caller = symbols[0], .callee = symbols[1] },
        .{ .caller = symbols[1], .callee = symbols[0] },
        .{ .caller = symbols[1], .callee = symbols[2] },
    };

    var resolution = try resolveSccs(std.testing.allocator, &symbols, &edges);
    defer resolution.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), resolution.components.len);

    var found_pair = false;
    var found_single = false;
    for (resolution.components) |component| {
        if (component.indices.len == 2) found_pair = true;
        if (component.indices.len == 1) found_single = true;
    }
    try std.testing.expect(found_pair);
    try std.testing.expect(found_single);
}

test "resolveSccs rejects unknown symbols" {
    const symbols = [_]SymbolRef{
        .{ .module_path = "a.zig", .symbol_name = "alpha" },
    };
    const edges = [_]CallEdge{
        .{
            .caller = symbols[0],
            .callee = .{ .module_path = "missing.zig", .symbol_name = "beta" },
        },
    };

    try std.testing.expectError(error.UnknownSymbol, resolveSccs(std.testing.allocator, &symbols, &edges));
}
