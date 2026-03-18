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
        .name = @tagName(tag),
        .status = .retained,
        .rationale = switch (tag) {
            .MissingPrompt => "The lowered-only public runtime still needs a missing-delimiter failure.",
            .CrossThread => "Runtime ownership remains thread-affine even after the stackful backend is gone.",
            .RuntimeBusy => "Active-runtime teardown misuse remains a public runtime concern.",
            .RuntimeDestroyed => "Destroyed-runtime misuse remains a public runtime concern.",
            .NonDiagonalComplete => "Non-diagonal completion is still part of the public shift/reset semantic contract.",
            .FrontendSuspend => "Replay-driven explicit frontend operations still use suspend as part of the lowered public execution contract.",
            .ProgramContractViolation => "Explicit frontend program-shape violations still remain observable through the lowered public execution contract.",
        },
    };
}

pub const retained_variants = [_]ErrorVariant{
    retainedVariant(.MissingPrompt),
    retainedVariant(.CrossThread),
    retainedVariant(.RuntimeBusy),
    retainedVariant(.RuntimeDestroyed),
    retainedVariant(.NonDiagonalComplete),
    retainedVariant(.FrontendSuspend),
    retainedVariant(.ProgramContractViolation),
};

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
