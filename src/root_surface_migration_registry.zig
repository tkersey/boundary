/// Migration status for one canonical root export during the lowered-first cut.
pub const Status = enum {
    removed_from_public_root,
    retained_public,
};

/// One root-surface migration record.
pub const Entry = struct {
    symbol: []const u8,
    current_path: []const u8,
    target_path: []const u8,
    status: Status,
    note: []const u8,
};

/// Generator-owned migration truth for the canonical root surface.
pub const entries = [_]Entry{
    .{
        .symbol = "Prompt",
        .current_path = "shift.Prompt",
        .target_path = "src/internal/prompt_support.zig:Prompt",
        .status = .removed_from_public_root,
        .note = "The top-level prompt shell is removed from the public root. Repo-owned proof surfaces now reach it through direct imports of `src/internal/prompt_support.zig` only.",
    },
    .{
        .symbol = "PromptMode",
        .current_path = "shift.PromptMode",
        .target_path = "src/internal/prompt_support.zig:PromptMode",
        .status = .removed_from_public_root,
        .note = "The top-level prompt-mode enum is removed from the public root. Repo-owned proof surfaces now reach it through direct imports of `src/internal/prompt_support.zig` only.",
    },
    .{
        .symbol = "ResumeOrReturn",
        .current_path = "shift.ResumeOrReturn",
        .target_path = "shift.Decision",
        .status = .removed_from_public_root,
        .note = "The top-level zero-or-one-resume decision type is removed from the public root. Public choice code now uses `shift.Decision`, and repo-owned prompt-protocol proofs use direct imports of `src/internal/prompt_support.zig:ResumeOrReturn`.",
    },
    .{
        .symbol = "Runtime",
        .current_path = "shift.Runtime",
        .target_path = "shift.Runtime",
        .status = .retained_public,
        .note = "Runtime remains the public lowered-first runtime handle.",
    },
    .{
        .symbol = "RuntimeError",
        .current_path = "shift.RuntimeError",
        .target_path = "shift.RuntimeError",
        .status = .retained_public,
        .note = "RuntimeError remains the public lowered-first runtime misuse and semantic-contract surface.",
    },
    .{
        .symbol = "Decision",
        .current_path = "shift.Decision",
        .target_path = "shift.Decision",
        .status = .retained_public,
        .note = "Decision remains the public zero-or-one-resume helper for the root front door.",
    },
    .{
        .symbol = "Decl",
        .current_path = "shift.Decl",
        .target_path = "shift.Decl",
        .status = .retained_public,
        .note = "Decl remains the public declaration namespace for built-ins and custom family declarations.",
    },
    .{
        .symbol = "Op",
        .current_path = "shift.Op",
        .target_path = "shift.Op",
        .status = .retained_public,
        .note = "Op remains the public closed-world operation descriptor namespace.",
    },
    .{
        .symbol = "Program",
        .current_path = "shift.Program",
        .target_path = "shift.Program",
        .status = .retained_public,
        .note = "Program remains the reusable authored-body surface at the root.",
    },
    .{
        .symbol = "run",
        .current_path = "shift.run",
        .target_path = "shift.run",
        .status = .retained_public,
        .note = "run remains the only public execution entrypoint for authored programs.",
    },
    .{
        .symbol = "ordinary",
        .current_path = "shift.ordinary",
        .target_path = "src/internal/source_lowering.zig",
        .status = .removed_from_public_root,
        .note = "Source lowering now lives behind internal tooling entrypoints only.",
    },
    .{
        .symbol = "effect",
        .current_path = "shift.effect",
        .target_path = "src/internal/family_builder.zig",
        .status = .removed_from_public_root,
        .note = "The old effect lane is removed from the public root; repo-owned tooling reaches family-building helpers through internal modules only.",
    },
    .{
        .symbol = "algebraic",
        .current_path = "shift.algebraic",
        .target_path = "src/internal/family_builder.zig",
        .status = .removed_from_public_root,
        .note = "The old algebraic lane is removed from the public root; closed-world family declaration lives behind `shift.Decl.family` and internal helpers.",
    },
    .{
        .symbol = "With",
        .current_path = "shift.With",
        .target_path = "src/internal/lexical_runtime.zig:With",
        .status = .removed_from_public_root,
        .note = "The old lexical companion meta surface is removed from the public root and retained only behind internal proof helpers.",
    },
    .{
        .symbol = "with",
        .current_path = "shift.with",
        .target_path = "src/internal/lexical_runtime.zig:with",
        .status = .removed_from_public_root,
        .note = "The old lexical execution entrypoint is removed from the public root and retained only behind internal proof helpers.",
    },
    .{
        .symbol = "frontend",
        .current_path = "shift.frontend",
        .target_path = "src/internal/prompt_support.zig:frontend",
        .status = .removed_from_public_root,
        .note = "The explicit program frontend is removed from the public root. Repo-owned proof surfaces now reach it through direct imports of `src/internal/prompt_support.zig:frontend` only.",
    },
    .{
        .symbol = "reset",
        .current_path = "shift.reset",
        .target_path = "src/internal/prompt_support.zig:run",
        .status = .removed_from_public_root,
        .note = "The top-level reset helper is removed from the public root. Repo-owned prompt-protocol proofs now use direct imports of `src/internal/prompt_support.zig:run` instead.",
    },
};
