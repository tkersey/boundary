const family = @import("family.zig");
/// Optional-resumption effect family built on top of the core shift/reset runtime.
pub const optional = @import("optional.zig");
/// Additive reader-effect family built on top of the core shift/reset runtime.
pub const reader = @import("reader.zig");
/// Additive state-effect family built on top of the core shift/reset runtime.
pub const state = @import("state.zig");

test {
    _ = family;
    _ = optional;
    _ = reader;
    _ = state;
}
