//! Separate pure-data test entry point; never imported by the production module.
test {
    _ = @import("root.zig");
    _ = @import("tests.zig");
    _ = @import("adversarial_tests.zig");
    _ = @import("compact_tests.zig");
    _ = @import("activation_structure_tests.zig");
    _ = @import("analysis_sets_tests.zig");
    _ = @import("activation_flow_tests.zig");
}
