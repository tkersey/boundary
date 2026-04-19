const shift = @import("shift");

/// Match the runtime/error envelope used by the repo-owned NamedBody boundary fixture.
pub fn ExecResult(comptime T: type) type {
    return (shift.RuntimeError || error{ OutOfMemory, BodyOops, ContinueOops, HandlerOops, AfterOops })!T;
}

/// Keep this repo-owned NamedBody outside the retained lowering subset via a loop.
pub fn unsupportedLoopBody(eff: anytype) ExecResult(i32) {
    _ = eff;
    var total: i32 = 0;
    while (total < 1) : (total += 1) {}
    return total;
}
