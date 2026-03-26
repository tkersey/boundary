const program_api = @import("program_api.zig");

pub const Op = enum(u8) {
    _,

    pub const transform = program_api.ops.transform;
    pub const choice = program_api.ops.choice;
    pub const abort = program_api.ops.abort;
};
