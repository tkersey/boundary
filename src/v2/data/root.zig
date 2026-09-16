// Copyright (c) 2026 Boundary contributors. MIT license.
//! Portable definitions and pure admission. This module never executes programs.
pub const wire = @import("wire.zig");
pub const program = @import("program.zig");
pub const activation = @import("activation.zig");
pub const analysis_sets = @import("analysis_sets.zig");
pub const activation_structure = @import("activation_structure.zig");
pub const activation_flow = @import("activation_flow.zig");
pub const activation_types = @import("activation_types.zig");
pub const activation_ownership = @import("activation_ownership.zig");
pub const program_image = @import("program_image.zig");
pub const process_state = @import("process_state.zig");
pub const state_image = @import("state_image.zig");
pub const invocation = @import("invocation.zig");
pub const admission = @import("admission.zig");
pub const image = @import("image.zig");
pub const compact_image = @import("compact_image.zig");
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
