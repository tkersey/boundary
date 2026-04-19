const boundary_support = @import("lexical_with_named_body_boundary_support.zig");
const shift = @import("shift");

fn FailureProbeType() type {
    const runtime_ptr: *shift.Runtime = @ptrFromInt(@alignOf(shift.Runtime));
    return @TypeOf(shift.withAt(
        @src(),
        runtime_ptr,
        .{
            .state = shift.effect.state.use(@as(i32, 0)),
        },
        shift.NamedBody(
            "test/lexical_with_named_body_boundary_support.zig",
            "unsupportedLoopBody",
            boundary_support.ExecResult(i32),
            boundary_support.unsupportedLoopBody,
        ),
    ));
}

const FailureProbe = FailureProbeType();

/// Force the repo-owned NamedBody boundary fixture to instantiate at compile time.
pub fn main() void {
    _ = FailureProbe;
}
