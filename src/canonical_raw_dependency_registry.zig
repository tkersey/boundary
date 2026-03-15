/// Current migration state for one canonical surface that still depends on raw execution.
pub const Status = enum {
    lowered_canonical,
    raw_execution_dependency,
    resolved,
};

/// One canonical surface dependency record.
pub const Entry = struct {
    surface_id: []const u8,
    surface: []const u8,
    status: Status,
    source: []const u8,
    note: []const u8,
};

/// Generator-owned truth surface for canonical raw execution dependencies.
pub const entries = [_]Entry{
    .{
        .surface_id = "root.execution",
        .surface = "canonical_root",
        .status = .raw_execution_dependency,
        .source = "src/root.zig",
        .note = "Canonical root reset and shift still call raw execution directly.",
    },
    .{
        .surface_id = "effect.internal_execution",
        .surface = "canonical_effect",
        .status = .raw_execution_dependency,
        .source = "src/effect/algebraic.zig",
        .note = "Effect execution helpers still call raw reset and shift directly.",
    },
    .{
        .surface_id = "effect.kernel_execution",
        .surface = "canonical_effect",
        .status = .raw_execution_dependency,
        .source = "src/effect/kernel.zig",
        .note = "Kernel-backed effect execution still captures through raw shift.",
    },
    .{
        .surface_id = "algebraic.internal_execution",
        .surface = "canonical_algebraic",
        .status = .raw_execution_dependency,
        .source = "src/algebraic.zig",
        .note = "Public algebraic builders still execute via raw reset and shift.",
    },
    .{
        .surface_id = "survey.runtime_success",
        .surface = "one_shot_survey",
        .status = .lowered_canonical,
        .source = "test/one_shot_survey/protocol_resume_transform_executes.zig",
        .note = "The runtime-success survey fixture executes through the lowered runtime seam instead of raw root execution.",
    },
    .{
        .surface_id = "examples.runtime_execution",
        .surface = "public_examples",
        .status = .resolved,
        .source = "examples/*.zig",
        .note = "Public examples now delegate to the lowered runtime seam instead of the old root execution contract.",
    },
    .{
        .surface_id = "witnesses.runtime_execution",
        .surface = "witnesses",
        .status = .resolved,
        .source = "src/witnesses.zig",
        .note = "Witness runners now delegate to the lowered runtime seam instead of the old root execution contract.",
    },
    .{
        .surface_id = "shipped_benches.runtime_execution",
        .surface = "bench",
        .status = .raw_execution_dependency,
        .source = "bench/no_capture_bench.zig",
        .note = "Shipped root benches still benchmark the old raw root execution contract.",
    },
};
