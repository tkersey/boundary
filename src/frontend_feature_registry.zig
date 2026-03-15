/// Coverage status for one canonical authored-body capability.
pub const Status = enum {
    covered,
    missing,
    replay_limited,
};

/// One authored-body capability row.
pub const Feature = struct {
    feature_id: []const u8,
    surface: []const u8,
    status: Status,
    source: []const u8,
    note: []const u8,
};

/// Generator-owned truth surface for the canonical authored-body layer.
pub const features = [_]Feature{
    .{
        .feature_id = "program.explicit_shell",
        .surface = "canonical_frontend",
        .status = .covered,
        .source = "src/frontend.zig",
        .note = "The canonical frontend already exposes an explicit Program shell for authored bodies.",
    },
    .{
        .feature_id = "program.typed_handler_protocols",
        .surface = "canonical_frontend",
        .status = .covered,
        .source = "src/frontend.zig",
        .note = "The canonical frontend still checks prompt-mode-specific handler protocol shapes at comptime.",
    },
    .{
        .feature_id = "program.only_reset_surface",
        .surface = "canonical_root",
        .status = .covered,
        .source = "src/root.zig",
        .note = "The canonical root now requires an explicit frontend Program at reset time.",
    },
    .{
        .feature_id = "execution.non_replay_prefix_safety",
        .surface = "canonical_frontend",
        .status = .covered,
        .source = "src/frontend.zig",
        .note = "Canonical authored bodies now execute without prefix replay on the public frontend path.",
    },
    .{
        .feature_id = "execution.large_resume_payloads",
        .surface = "canonical_frontend",
        .status = .covered,
        .source = "src/frontend.zig",
        .note = "Resume payloads now use allocator-backed storage rather than a fixed frontend byte bound.",
    },
    .{
        .feature_id = "execution.unbounded_operation_depth",
        .surface = "canonical_frontend",
        .status = .covered,
        .source = "src/frontend.zig",
        .note = "Recorded authored-body operations now use allocator-backed storage rather than a fixed frontend depth bound.",
    },
    .{
        .feature_id = "effect.lowered_authoring",
        .surface = "canonical_effect",
        .status = .covered,
        .source = "src/effect/algebraic.zig",
        .note = "Canonical effect families now route their hidden operation programs through the shared internal algebraic engine while preserving exact Cap/ctx sealing.",
    },
    .{
        .feature_id = "algebraic.lowered_authoring",
        .surface = "canonical_algebraic",
        .status = .covered,
        .source = "src/algebraic.zig",
        .note = "Canonical algebraic builders now wrap the shared internal algebraic engine while preserving the public custom-ops surface.",
    },
};
