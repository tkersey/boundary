// Copyright (c) 2026 Boundary contributors. MIT license.
//! Portable definitions and pure admission. This module never executes programs.
pub const wire = @import("wire.zig");
pub const program = @import("program.zig");
pub const admission = @import("admission.zig");
pub const image = @import("image.zig");
pub const graph = @import("graph.zig");
pub const snapshot = @import("snapshot.zig");
pub const scalar = @import("scalar.zig");
pub const protocol = @import("protocol.zig");
pub const schema = @import("schema.zig");
pub const state_admission = @import("state_admission.zig");
pub const traits = @import("traits.zig");
pub const cleanup_contract = @import("cleanup_contract.zig");
pub const direct_clause = @import("direct_clause.zig");
pub const canonical = @import("canonical.zig");

test {
    _ = wire;
    _ = snapshot;
    _ = scalar;
    _ = protocol;
    _ = schema;
}
