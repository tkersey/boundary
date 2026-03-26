const program_api = @import("program_api.zig");

/// Public `Ops` declaration.
pub const Ops = enum(u8) {
    reserved,

    /// Public `Transform` declaration.
    pub const Transform = program_api.ops.Transform;
    /// Public `Choice` declaration.
    pub const Choice = program_api.ops.Choice;
    /// Public `Abort` declaration.
    pub const Abort = program_api.ops.Abort;
};
