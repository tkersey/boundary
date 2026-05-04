const generated = @import("generated_family.zig");

/// Stable compile-time manifest for one generated effect family.
pub const Definition = generated.Definition;
/// Internal op-descriptor namespace used by generated effect-family definitions.
pub const ops = generated.ops;

/// Build one sealed generated effect family from a declarative comptime spec.
pub const Define = generated.Build;
