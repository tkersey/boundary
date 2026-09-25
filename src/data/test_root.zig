//! Separate pure-data test entry point; never imported by the production module.
test {
    _ = @import("root.zig");
    _ = @import("tests.zig");
    _ = @import("compact_sequence_tests.zig");
    _ = @import("activation_structure_tests.zig");
    _ = @import("analysis_sets_tests.zig");
    _ = @import("activation_flow_tests.zig");
    _ = @import("activation_borrow_tests.zig");
    _ = @import("program_image_tests.zig");
    _ = @import("component_tests.zig");
    _ = @import("relocation_tests.zig");
    _ = @import("coalescing_graph_tests.zig");
    _ = @import("coalescing_witness_tests.zig");
    _ = @import("coalescing_view_tests.zig");
    _ = @import("coalescing_candidate_tests.zig");
    _ = @import("coalescing_tests.zig");
    _ = @import("coalescing_recursive_tests.zig");
    _ = @import("state_image_tests.zig");
    _ = @import("invocation_tests.zig");
}
