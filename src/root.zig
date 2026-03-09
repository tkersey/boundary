/// Low-level continuation substrate and scope primitives.
pub const raw = @import("raw.zig");
/// PL-facing alias for building typed effect surfaces.
pub const EffectSpec = @import("control_spec.zig").ControlSpec;
/// Compatibility alias for the lower-level effect-surface generator.
pub const ControlSpec = EffectSpec;

test {
    _ = raw;
    _ = EffectSpec;
    _ = ControlSpec;
}
