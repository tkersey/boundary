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
        .feature_id = "program.shift_migration_boundary",
        .surface = "canonical_root",
        .status = .covered,
        .source = "src/root.zig",
        .note = "Canonical shift.shift is now a compile-time migration boundary with guidance to frontend authoring.",
    },
    .{
        .feature_id = "execution.non_replay_prefix_safety",
        .surface = "canonical_frontend",
        .status = .replay_limited,
        .source = "src/frontend.zig",
        .note = "The current replay interpreter can duplicate non-idempotent authored-body prefixes before prompt operations.",
    },
    .{
        .feature_id = "execution.large_resume_payloads",
        .surface = "canonical_frontend",
        .status = .replay_limited,
        .source = "src/frontend.zig",
        .note = "Resume payloads are still bounded by max_resume_bytes in the replay interpreter.",
    },
    .{
        .feature_id = "execution.unbounded_operation_depth",
        .surface = "canonical_frontend",
        .status = .replay_limited,
        .source = "src/frontend.zig",
        .note = "Recorded authored-body operations are still bounded by max_records in the replay interpreter.",
    },
    .{
        .feature_id = "effect.lowered_authoring",
        .surface = "canonical_effect",
        .status = .missing,
        .source = "src/effect/algebraic.zig",
        .note = "Effect families still author ordinary Zig bodies instead of explicit authored-body IR.",
    },
    .{
        .feature_id = "algebraic.lowered_authoring",
        .surface = "canonical_algebraic",
        .status = .missing,
        .source = "src/algebraic.zig",
        .note = "Public algebraic builders still author direct body functions instead of explicit authored-body IR.",
    },
};
