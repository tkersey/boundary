const shift = @import("lexical_runtime_internal");

fn ExecResult(comptime T: type) type {
    return (shift.RuntimeError || error{ OutOfMemory, BodyOops, ContinueOops, HandlerOops, AfterOops })!T;
}

/// Increment state and return the canonical named-body answer.
pub fn namedStateBody(eff: anytype) ExecResult(i32) {
    const before = try eff.state.get();
    try eff.state.set(before + 1);
    const after = try eff.state.get();
    return before + after;
}

fn namedStateHelper(ctx: anytype) ExecResult(void) {
    _ = try ctx.state.get();
}

/// Exercise the renamed effect parameter path while preserving the canonical answer.
pub fn namedStateBodyWithRenamedEffectParam(ctx: anytype) ExecResult(i32) {
    try namedStateHelper(ctx);
    return 9;
}

/// Read from the reader effect and return the doubled environment.
pub fn namedReaderBody(eff: anytype) ExecResult(i32) {
    const env = try eff.reader.ask();
    return env + env;
}

/// Append the canonical writer items and return the terminal answer.
pub fn namedWriterBody(eff: anytype) ExecResult([]const u8) {
    try eff.writer.tell("a");
    try eff.writer.tell("b");
    return "done";
}

/// Return the canonical bool literal through the named-body path.
pub fn namedBoolLiteralBody(_: anytype) ExecResult(bool) {
    return true;
}

/// Return the canonical usize literal through the named-body path.
pub fn namedUsizeLiteralBody(_: anytype) ExecResult(usize) {
    return 1;
}

/// Return the canonical large usize literal through the named-body path.
pub fn namedLargeUsizeLiteralBody(_: anytype) ExecResult(usize) {
    return 5_000_000_000;
}

/// Update bool state through the named-body path.
pub fn namedBoolStateBody(eff: anytype) ExecResult(bool) {
    const enabled = true;
    try eff.state.set(enabled);
    return try eff.state.get();
}
