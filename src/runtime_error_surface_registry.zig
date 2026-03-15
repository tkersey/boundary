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

/// Generator-owned truth surface for the current public runtime error surface.
pub const variants = [_]ErrorVariant{
    .{
        .name = "MissingPrompt",
        .status = .retained,
        .rationale = "The lowered-only public runtime still needs a missing-delimiter failure.",
    },
    .{
        .name = "CrossThread",
        .status = .retained,
        .rationale = "Runtime ownership remains thread-affine even after the stackful backend is gone.",
    },
    .{
        .name = "RuntimeBusy",
        .status = .retained,
        .rationale = "Active-runtime teardown misuse remains a public runtime concern.",
    },
    .{
        .name = "RuntimeDestroyed",
        .status = .retained,
        .rationale = "Destroyed-runtime misuse remains a public runtime concern.",
    },
    .{
        .name = "NonDiagonalComplete",
        .status = .retained,
        .rationale = "Non-diagonal completion is still part of the public shift/reset semantic contract.",
    },
    .{
        .name = "AlreadyResolved",
        .status = .retained,
        .rationale = "The canonical runtime now owns its own error set, but this compatibility variant remains exported for now.",
    },
    .{
        .name = "NestedNonDiagonalCapture",
        .status = .retained,
        .rationale = "The canonical runtime now owns its own error set, but this compatibility variant remains exported for now.",
    },
};
