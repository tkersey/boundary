//! Separate staged-authoring test entry point.
test {
    _ = @import("root.zig");
    _ = @import("source/tests.zig");
    _ = @import("source/capture_tests.zig");
    _ = @import("source/projection_tests.zig");
    _ = @import("source/activation_tests.zig");
    _ = @import("source/thread_jumps.zig");
    _ = @import("source/slot_order.zig");
    _ = @import("source/component_tests.zig");
    _ = @import("source/activation_admission_tests.zig");
    _ = @import("authoring_tests.zig");
}
