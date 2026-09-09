//! Separate pure-data test entry point; never imported by the production module.
test {
    _ = @import("root.zig");
    _ = @import("tests.zig");
    _ = @import("adversarial_tests.zig");
}
