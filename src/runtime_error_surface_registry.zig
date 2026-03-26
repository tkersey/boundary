const error_witness = @import("error_witness");

/// Current public runtime error-surface status.
pub const Status = enum {
    retained,
    retired,
};

/// One public error variant and its current status.
pub const ErrorVariant = struct {
    name: []const u8,
    status: Status,
    rationale: []const u8,
};

fn retainedVariant(comptime tag: error_witness.RuntimeErrorTag) ErrorVariant {
    return .{
        .name = error_witness.runtimeErrorTagName(tag),
        .status = .retained,
        .rationale = switch (tag) {
            .missing_prompt => "The lowered-only public runtime still needs a missing-delimiter failure.",
            .cross_thread => "Runtime ownership remains thread-affine even after the stackful backend is gone.",
            .runtime_busy => "Active-runtime teardown misuse remains a public runtime concern.",
            .runtime_destroyed => "Destroyed-runtime misuse remains a public runtime concern.",
            .non_diagonal_complete => "Non-diagonal completion is still part of the public shift/reset semantic contract.",
            .frontend_suspend => "Replay-driven explicit frontend operations still use suspend as part of the lowered public execution contract.",
            .program_contract_violation => "Explicit frontend program-shape violations still remain observable through the lowered public execution contract.",
        },
    };
}

/// Public retained runtime error variants.
pub const retained_variants = [_]ErrorVariant{
    retainedVariant(.missing_prompt),
    retainedVariant(.cross_thread),
    retainedVariant(.runtime_busy),
    retainedVariant(.runtime_destroyed),
    retainedVariant(.non_diagonal_complete),
    retainedVariant(.frontend_suspend),
    retainedVariant(.program_contract_violation),
};

/// Public retired runtime error variants.
pub const retired_variants = [_]ErrorVariant{
    .{
        .name = "AlreadyResolved",
        .status = .retired,
        .rationale = "This one-shot raw continuation misuse no longer belongs to the canonical lowered runtime surface.",
    },
    .{
        .name = "NestedNonDiagonalCapture",
        .status = .retired,
        .rationale = "This stackful capture detail no longer belongs to the canonical lowered runtime surface.",
    },
};
