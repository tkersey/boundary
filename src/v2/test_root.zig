//! Separate staged-authoring test entry point.
test {
    _ = @import("root.zig");
    _ = @import("source/tests.zig");
    _ = @import("source/capture_tests.zig");
}
