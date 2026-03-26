const program_api = @import("program_api.zig");

pub const Op = enum(u8) {
    _,

    pub fn transform(comptime name: [:0]const u8, comptime PayloadType: type, comptime ResumeType: type) type {
        return program_api.ops.transform(name, PayloadType, ResumeType);
    }

    pub fn choice(comptime name: [:0]const u8, comptime PayloadType: type, comptime ResumeType: type) type {
        return program_api.ops.choice(name, PayloadType, ResumeType);
    }

    pub fn abort(comptime name: [:0]const u8, comptime PayloadType: type) type {
        return program_api.ops.abort(name, PayloadType);
    }
};
