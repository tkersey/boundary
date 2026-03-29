const lowered_machine = @import("lowered_machine");
const with_api = @import("with_api.zig");

/// Public `Runtime` declaration.
pub const Runtime = lowered_machine.Runtime;
/// Public `RuntimeError` declaration.
pub const RuntimeError = lowered_machine.RuntimeError;
/// Public lexical effect namespace for internal witness-only helpers.
pub const effect = struct {
    /// Public lexical choice-decision helper namespace.
    pub const choice = @import("effect/choice.zig");
    /// Public sealed custom-effect generator.
    pub const Define = @import("effect/define.zig").Define;
    /// Public op-descriptor namespace for witness-local effect definitions.
    pub const ops = @import("effect/define.zig").ops;
    /// Exception effect family built on top of the core shift/reset runtime.
    pub const exception = @import("effect/exception.zig");
    /// Optional-resumption effect family built on top of the core shift/reset runtime.
    pub const optional = @import("effect/optional.zig");
    /// Additive reader-effect family built on top of the core shift/reset runtime.
    pub const reader = @import("effect/reader.zig");
    /// Bracketed resource effect family built on top of the core shift/reset runtime.
    pub const resource = @import("effect/resource.zig");
    /// Additive state-effect family built on top of the core shift/reset runtime.
    pub const state = @import("effect/state.zig");
    /// Append-only writer effect family built on top of the core shift/reset runtime.
    pub const writer = @import("effect/writer.zig");
};

/// Build the public With metadata type.
pub fn With(comptime HandlersType: type, comptime Body: type) type {
    return with_api.With(HandlersType, Body);
}

/// Run the public lexical handler entrypoint.
pub fn with(
    runtime: *Runtime,
    handlers: anytype,
    comptime Body: type,
) with_api.WithFnReturnType(@TypeOf(handlers), Body) {
    return with_api.with(runtime, handlers, Body);
}
