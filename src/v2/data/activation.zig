// Copyright (c) 2026 Boundary contributors. MIT license.
//! Stable-activation executable records. Slices borrow immutable owner storage.
//! A slot belongs to a function; an activation version gives it dynamic identity.
//! These records are not a certificate of admission.
const contract = @import("program.zig");
pub const Id = contract.Id;

pub const Layout = struct {
    /// Exactly one schema per logical binding, including instruction temporaries.
    slots: []const Id,
};

pub const Function = struct {
    entry: Id,
    /// Ordered destinations for actual call arguments, never a live environment.
    inputs: []const Id,
    layout: Layout,
    result: Id,
    effects: []const Id = &.{},
    regions: []const Id = &.{},
};

pub const Source = union(enum) { slot: Id, returned };
pub const Assignment = struct { destination: Id, source: Source };
pub const Edge = struct {
    block: Id,
    /// Simultaneous assignments read the predecessor view. Identity transfers
    /// are omitted; unmentioned bindings remain in the same activation view.
    assignments: []const Assignment = &.{},
};

pub const Instruction = struct {
    destination: Id,
    opcode: contract.Opcode,
    operands: []const Id = &.{},
    immediate: Id = 0,
    failures: []const contract.InstructionFailure = &.{},
};

pub const Perform = struct {
    effect: Id,
    capability: ?Id = null,
    payload: Id,
    bodies: []const Id = &.{},
    use_site_capabilities: []const Id = &.{},
    next: Edge,
};

pub const Terminator = union(contract.TerminatorTag) {
    return_value: Id,
    jump: Edge,
    branch: struct { condition: Id, when_true: Edge, when_false: Edge },
    switch_variant: struct { value: Id, cases: []const Edge },
    unpack_product: struct { value: Id, destinations: []const Id, next: Edge },
    call: struct { function: Id, arguments: []const Id, next: Edge },
    perform: Perform,
    yield_value: Edge,
    fail: Id,
    apply: struct { computation: Id, arguments: []const Id, next: Edge },
    handle: struct {
        handler: Id,
        body: Id,
        arguments: []const Id,
        state: []const Id,
        next: Edge,
    },
    resume_value: struct { resumption: Id, argument: Id, next: Edge },
    resume_with: struct {
        resumption: Id,
        argument: Id,
        handler: Id,
        state: []const Id = &.{},
        next: Edge,
    },
    resume_computation: struct { resumption: Id, computation: Id, next: Edge },
    forward: Perform,
    dispose: struct { owned: Id, next: Edge },
    protect: struct {
        body: Id,
        cleanup: Id,
        arguments: []const Id,
        resource: ?Id = null,
        loan_region: ?Id = null,
        next: Edge,
    },
    with_region: struct { region: Id, body: Id, arguments: []const Id, next: Edge },
};

pub const Block = struct {
    function: Id,
    instructions: []const Instruction,
    terminator: Terminator,
};

pub const Program = struct {
    roots: contract.Roots,
    schemas: []const contract.Schema,
    constants: []const contract.Literal,
    effects: []const contract.Effect,
    functions: []const Function,
    blocks: []const Block,
    handlers: []const contract.Handler = &.{},
    scopes: contract.ScopeCatalog = .{},
    constructors: []const contract.Constructor = &.{},
};
