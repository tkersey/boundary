const family = @import("family.zig");
/// Additive reader-effect family built on top of the core shift/reset runtime.
pub const reader = @import("reader.zig");
/// Additive state-effect family built on top of the core shift/reset runtime.
pub const state = @import("state.zig");

test {
    _ = family;
    _ = reader;
    _ = state;
}
