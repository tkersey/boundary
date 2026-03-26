const op_api = @import("op_api.zig");

pub const Op = enum(u8) {
    reserved,

    pub const transform = op_api.Transform;
    pub const choice = op_api.Choice;
    pub const abort = op_api.Abort;
};
