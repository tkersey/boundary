/// Public `Definition` declaration.
pub const Definition = @import("../effect/define.zig").Definition;
/// Public op-descriptor namespace.
pub const ops = @import("../effect/define.zig").ops;

/// Build this public type.
pub fn Build(comptime spec: anytype) type {
    return @import("../effect/root.zig").Define(spec);
}
