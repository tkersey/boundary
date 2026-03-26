const program_api = @import("program_api.zig");

pub const Op = enum(u8) {
    _,

    pub const Transform = program_api.ops.Transform;
    pub const Choice = program_api.ops.Choice;
    pub const Abort = program_api.ops.Abort;
};
