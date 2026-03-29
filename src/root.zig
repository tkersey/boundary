const compat_api = @import("compat.zig");
const durable_api = @import("durable.zig");
const effect_ir = @import("effect_ir");
const effect_root = @import("effect/root.zig");
const interpreter_api = @import("interpreter");
const public_lowering = @import("public_lowering.zig");
const with_api = @import("with_api.zig");

/// Transitional compatibility namespace for the prior root-kernel front door.
pub const compat = compat_api;
/// Public lexical effect namespace.
pub const effect = effect_root;
/// Public durable session helpers over the interpreter core.
pub const durable = durable_api;
/// Public Effect IR helpers.
pub const ir = effect_ir;
/// Public explicit interpreter state and step helpers.
pub const interpreter = interpreter_api;
/// Public additive lowering namespace over the retained open-row/effect-ir path.
pub const lowering = public_lowering;

/// Build the public lexical metadata type.
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

/// Transitional top-level compatibility alias.
pub const Runtime = compat.Runtime;
/// Transitional top-level compatibility alias.
pub const RuntimeError = compat.RuntimeError;
/// Transitional top-level compatibility alias.
pub const ErrorWitnessV1 = compat.ErrorWitnessV1;
/// Transitional top-level compatibility alias.
pub const Decl = compat.Decl;
/// Transitional top-level compatibility alias.
pub const Op = compat.Op;
/// Transitional top-level compatibility alias.
pub const Decision = compat.Decision;
/// Transitional top-level compatibility alias.
pub const Program = compat.Program;
/// Transitional top-level compatibility alias.
pub const run = compat.run;

test {
    _ = With;
    _ = Decl;
    _ = Decision;
    _ = ErrorWitnessV1;
    _ = Op;
    _ = Program;
    _ = Runtime;
    _ = RuntimeError;
    _ = compat;
    _ = durable;
    _ = effect;
    _ = interpreter;
    _ = ir;
    _ = lowering;
    _ = with;
    _ = run;
}
