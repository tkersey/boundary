// Copyright (c) 2026 Boundary contributors. MIT license.
//! Portable stable activation views. No runtime handles or supplied analysis facts.
const g = @import("graph.zig");
const p = @import("program.zig");
pub const Binding = struct { slot: p.Id, value: g.Value };
pub const Owner = struct { scope: p.Id, slot: p.Id };
pub const Activation = struct {
    position: p.Id,
    scope: p.Id,
    /// Strictly increasing slot order, containing only retained initialized values.
    bindings: []const Binding,
    /// Inner scopes before outer scopes; establishment order within each scope.
    owners: []const Owner,
};
pub const Node = struct {
    record: g.Node,
    /// Present exactly for control and continuation nodes; reached with that node.
    activation: ?Activation = null,
};
pub const Status = enum(u8) {
    active = 0,
    yielded = 1,
    parked = 2,
    unwinding = 3,
    completed = 4,
    failed = 5,
    cancelled = 6,
};
pub const State = struct {
    program_identity: [32]u8,
    status: Status,
    roots: g.Roots,
    nodes: []const Node,
    blobs: []const g.Blob = &.{},
};
