const program_api = @import("program_api.zig");

/// Public `Decl` declaration.
pub const Decl = enum(u8) {
    reserved,

    /// Public `state` helper.
    pub fn state(comptime StateType: type) @TypeOf(program_api.decl.state(StateType)) {
        return program_api.decl.state(StateType);
    }

    /// Public `reader` helper.
    pub fn reader(comptime EnvType: type) @TypeOf(program_api.decl.reader(EnvType)) {
        return program_api.decl.reader(EnvType);
    }

    /// Public `optional` helper.
    pub fn optional(
        comptime ResumeType: type,
        comptime PolicyType: type,
    ) @TypeOf(program_api.decl.optional(ResumeType, PolicyType)) {
        return program_api.decl.optional(ResumeType, PolicyType);
    }

    /// Public `exception` helper.
    pub fn exception(
        comptime PayloadType: type,
        comptime CatchType: type,
    ) @TypeOf(program_api.decl.exception(PayloadType, CatchType)) {
        return program_api.decl.exception(PayloadType, CatchType);
    }

    /// Public `resource` helper.
    pub fn resource(
        comptime ResourceType: type,
        comptime ManagerType: type,
    ) @TypeOf(program_api.decl.resource(ResourceType, ManagerType)) {
        return program_api.decl.resource(ResourceType, ManagerType);
    }

    /// Public `writer` helper.
    pub fn writer(comptime ItemType: type) @TypeOf(program_api.decl.writer(ItemType)) {
        return program_api.decl.writer(ItemType);
    }

    /// Public `family` helper.
    pub fn family(
        comptime spec: anytype,
        comptime HandlerType: type,
    ) @TypeOf(program_api.decl.family(spec, HandlerType)) {
        return program_api.decl.family(spec, HandlerType);
    }
};
