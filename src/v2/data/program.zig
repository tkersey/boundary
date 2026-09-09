// Copyright (c) 2026 Boundary contributors. MIT license.
//! First-order program records. All slices borrow caller-owned immutable storage.
//! IDs index the corresponding catalog; they never name native functions.
pub const Id = u64;
pub const Use = enum(u8) { reusable = 0, affine = 1, linear = 2, multi = 3 };
pub const Mode = enum(u8) { deep = 0, shallow = 1 };
pub const ComputationType = struct {
    parameters: []const Id,
    result: Id,
    effects: []const Id = &.{},
    capture_bound: []const Id = &.{},
    use: Use = .reusable,
    regions: []const Id = &.{},
};
pub const ResumptionType = struct {
    effect: Id,
    input: Id,
    answer: Id,
    effects: []const Id = &.{},
    capture_bound: []const Id = &.{},
    handled: []const Id,
    /// In shallow captures, these effects can select outside attachments and
    /// therefore remain exposed even when resumeWith installs a successor.
    escaping: []const Id = &.{},
    mode: Mode,
    use: Use,
    owned_regions: []const Id = &.{},
    /// Upper bound checked at every protected call/capture edge.
    obligations: bool = false,
};
pub const InternalTag = enum(u8) { computation = 0, capability = 1, cell = 2, region = 3, resumption = 4, suspension_package = 5, abstract_resource = 6, borrowed = 7 };
pub const Internal = union(InternalTag) {
    computation: ComputationType,
    capability: Id,
    cell: struct { element: Id, region: Id },
    region: Id,
    resumption: ResumptionType,
    suspension_package: Id,
    abstract_resource: Id,
    borrowed: struct { value: Id, region: Id },
};

pub const SchemaTag = enum(u8) { unit = 0, boolean = 1, i8 = 2, i16 = 3, i32 = 4, i64 = 5, u8 = 6, u16 = 7, u32 = 8, u64 = 9, bytes = 10, text = 11, product = 12, sum = 13, seq = 14, vector = 15, internal = 16, array = 17, bounded_bytes = 18, bounded_text = 19, enumeration = 20 };
pub const Schema = union(SchemaTag) {
    unit,
    boolean,
    i8,
    i16,
    i32,
    i64,
    u8,
    u16,
    u32,
    u64,
    bytes,
    text,
    product: []const Id,
    sum: []const Id,
    seq: Id,
    vector: struct { element: Id, maximum: u64 },
    internal: Internal,
    array: struct { element: Id, length: u64 },
    bounded_bytes: u64,
    bounded_text: u64,
    /// Sorted unique explicit tags. An empty enumeration has no valid value.
    enumeration: []const u32,
};

pub const Literal = struct { schema: Id, bytes: []const u8 };
pub const Effect = struct {
    identity: []const u8,
    payload: Id,
    result: Id,
    use_site_effects: []const Id = &.{},
    bodies: []const Id = &.{},
    control_use: Use = .linear,
    external: bool = true,
};

pub const Function = struct {
    entry: Id,
    parameters: []const Id,
    result: Id,
    effects: []const Id = &.{},
    regions: []const Id = &.{},
};

pub const ArgumentTag = enum(u8) { slot = 0, returned = 1 };
pub const Argument = union(ArgumentTag) { slot: Id, returned };
pub const Edge = struct { block: Id, arguments: []const Argument };
pub const Opcode = enum(u8) {
    constant = 0,
    move = 1,
    integer_add = 2,
    integer_sub = 3,
    integer_mul = 4,
    integer_div = 5,
    equal = 6,
    less = 7,
    boolean_not = 8,
    product = 9,
    field = 10,
    variant = 11,
    variant_tag = 12,
    variant_payload = 13,
    sequence = 14,
    sequence_length = 15,
    sequence_get = 16,
    sequence_append = 17,
    sequence_concat = 18,
    sequence_pop = 19,
    computation = 20,
    cell_new = 21,
    cell_get = 22,
    cell_set = 23,
    clone_resumption = 24,
    package = 25,
    unpack = 26,
    resource_pack = 27,
    resource_unpack = 28,
    integer_rem = 29,
    integer_bit_not = 30,
    integer_bit_and = 31,
    integer_bit_or = 32,
    integer_bit_xor = 33,
    integer_convert = 34,
    enum_tag = 35,
    blob_length = 36,
    blob_concat = 37,
    blob_slice = 38,
    blob_compare = 39,
    blob_byte = 40,
    text_scalar = 41,
    text_integer = 42,
    sequence_set = 43,
    sequence_take = 44,
    blob_from_byte = 45,
    sequence_pop_last = 46,
    select = 47,

    pub fn borrowsOperands(self: Opcode) bool {
        return switch (self) {
            .variant_tag, .sequence_length, .sequence_get => true,
            else => false,
        };
    }
};

pub const Fault = enum(u8) { arithmetic_overflow = 0, division_by_zero = 1, capacity_exceeded = 2, invalid_utf8 = 3, invalid_index = 4, invalid_variant = 5 };
pub const InstructionFailure = struct {
    kind: Fault,
    value: Id,
};

/// Instructions append one SSA slot after the block's parameters.
pub const Instruction = struct {
    opcode: Opcode,
    result_type: Id,
    operands: []const Id = &.{},
    immediate: Id = 0,
    failures: []const InstructionFailure = &.{},
};
pub const Call = struct { function: Id, arguments: []const Id, next: Edge };
pub const Perform = struct {
    effect: Id,
    capability: ?Id = null,
    payload: Id,
    bodies: []const Id = &.{},
    use_site_capabilities: []const Id = &.{},
    next: Edge,
};
pub const TerminatorTag = enum(u8) { return_value = 0, jump = 1, branch = 2, switch_variant = 3, unpack_product = 4, call = 5, perform = 6, yield_value = 7, fail = 8, apply = 9, handle = 10, resume_value = 11, resume_with = 12, resume_computation = 13, forward = 14, dispose = 15, protect = 16, with_region = 17 };
pub const Terminator = union(TerminatorTag) {
    return_value: Id,
    jump: Edge,
    branch: struct { condition: Id, when_true: Edge, when_false: Edge },
    switch_variant: struct { value: Id, cases: []const Edge },
    unpack_product: struct { value: Id, block: Id, arguments: []const Id },
    call: Call,
    perform: Perform,
    yield_value: Edge,
    fail: Id,
    apply: struct { computation: Id, arguments: []const Id, next: Edge },
    handle: struct { handler: Id, body: Id, arguments: []const Id, state: []const Id, next: Edge },
    resume_value: struct { resumption: Id, argument: Id, next: Edge },
    resume_with: struct { resumption: Id, argument: Id, handler: Id, state: []const Id = &.{}, next: Edge },
    resume_computation: struct { resumption: Id, computation: Id, next: Edge },
    forward: Perform,
    dispose: struct { owned: Id, next: Edge },
    protect: struct { body: Id, cleanup: Id, arguments: []const Id, resource: ?Id = null, loan_region: ?Id = null, next: Edge },
    with_region: struct { region: Id, body: Id, arguments: []const Id, next: Edge },
};
pub const Block = struct {
    function: Id,
    parameters: []const Id,
    instructions: []const Instruction,
    terminator: Terminator,
};
pub const Clause = struct {
    effect: Id,
    function: Id,
    resumption: Id,
    /// A direct clause is one total instruction block returning the operation
    /// result. Deep handling continues in place; no resumption value exists.
    direct: bool = false,
};
pub const Handler = struct {
    mode: Mode,
    input: Id,
    answer: Id,
    return_function: Id,
    clauses: []const Clause,
    forward_function: ?Id = null,
    state: []const Id = &.{},
    effects: []const Id = &.{},
};
pub const Capture = struct {
    fields: []const Id,
    owned_regions: []const Id = &.{},
    borrowed_regions: []const Id = &.{},
    use: Use = .linear,
};
pub const Constructor = struct {
    function: Id,
    capture: Id,
    schema: Id,
};
pub const ScopeCatalog = struct {
    captures: []const Capture = &.{},
    /// Nominal region binders. Every installation has a distinct runtime identity.
    region_count: Id = 0,
    resources: []const Resource = &.{},
};
/// Only these executable functions may introduce or eliminate a representation.
pub const Resource = struct { representation: Id, introducers: []const Id, eliminators: []const Id };
pub const Roots = struct { profile: u64 = 1, entry: Id, result: Id, failure: Id };
pub const Program = struct {
    roots: Roots,
    schemas: []const Schema,
    constants: []const Literal,
    effects: []const Effect,
    functions: []const Function,
    blocks: []const Block,
    handlers: []const Handler = &.{},
    scopes: ScopeCatalog = .{},
    constructors: []const Constructor = &.{},
};
