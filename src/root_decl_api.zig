const program_api = @import("program_api.zig");

pub const Decl = enum(u8) {
    _,

    pub fn state(comptime StateType: type) @TypeOf(program_api.decl.state(StateType)) {
        return program_api.decl.state(StateType);
    }

    pub fn reader(comptime EnvType: type) @TypeOf(program_api.decl.reader(EnvType)) {
        return program_api.decl.reader(EnvType);
    }

    pub fn optional(
        comptime ResumeType: type,
        comptime PolicyType: type,
    ) @TypeOf(program_api.decl.optional(ResumeType, PolicyType)) {
        return program_api.decl.optional(ResumeType, PolicyType);
    }

    pub fn exception(
        comptime PayloadType: type,
        comptime CatchType: type,
    ) @TypeOf(program_api.decl.exception(PayloadType, CatchType)) {
        return program_api.decl.exception(PayloadType, CatchType);
    }

    pub fn resource(
        comptime ResourceType: type,
        comptime ManagerType: type,
    ) @TypeOf(program_api.decl.resource(ResourceType, ManagerType)) {
        return program_api.decl.resource(ResourceType, ManagerType);
    }

    pub fn writer(comptime ItemType: type) @TypeOf(program_api.decl.writer(ItemType)) {
        return program_api.decl.writer(ItemType);
    }

    pub fn family(
        comptime spec: anytype,
        comptime HandlerType: type,
    ) @TypeOf(program_api.decl.family(spec, HandlerType)) {
        return program_api.decl.family(spec, HandlerType);
    }
};
