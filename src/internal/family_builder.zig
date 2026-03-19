pub const Definition = @import("../effect/define.zig").Definition;
pub const ops = @import("../effect/define.zig").ops;

pub fn build(comptime spec: anytype) type {
    return @import("../effect/root.zig").Define(spec);
}
