/// Semantic manifest entry for one active witness in the current rung.
pub const WitnessEntry = struct {
    witness_id: []const u8,
    law_anchor: []const u8,
    evaluator_case: ?[]const u8,
    runtime_case: []const u8,
    required_transcript: []const u8,
    forbidden_transcript: ?[]const u8,
};

/// Active witness manifest for the current semantic rung.
pub const entries = [_]WitnessEntry{
    .{
        .witness_id = "static_redelim",
        .law_anchor = "research_laws.md#1-static-delimitation",
        .evaluator_case = "reference_eval.static_redelim",
        .runtime_case = "witnesses.static_redelim",
        .required_transcript = "outer-handler-enter\n" ++
            "after-outer-shift\n" ++
            "inner-handler\n" ++
            "outer-handler-exit\n" ++
            "final=12\n",
        .forbidden_transcript = "outer-handler-enter\n" ++
            "after-outer-shift\n" ++
            "outer-handler-exit\n" ++
            "final=12\n",
    },
    .{
        .witness_id = "multi_prompt",
        .law_anchor = "research_laws.md#2-prompt-identity-is-real",
        .evaluator_case = "reference_eval.multi_prompt",
        .runtime_case = "witnesses.multi_prompt",
        .required_transcript = "outer-before-inner\n" ++
            "inner-before\n" ++
            "outer-handler\n" ++
            "inner-after\n" ++
            "outer-after-inner\n" ++
            "final=42\n",
        .forbidden_transcript = "outer-before-inner\n" ++
            "inner-before\n" ++
            "inner-after\n" ++
            "outer-after-inner\n" ++
            "final=42\n",
    },
    .{
        .witness_id = "generator",
        .law_anchor = "generator practical witness",
        .evaluator_case = null,
        .runtime_case = "witnesses.generator",
        .required_transcript = "yield=1\n" ++
            "yield=2\n" ++
            "yield=3\n" ++
            "done=3\n",
        .forbidden_transcript = null,
    },
};

/// Find a manifest entry by witness id.
pub fn find(witness_id: []const u8) ?WitnessEntry {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.witness_id, witness_id)) return entry;
    }
    return null;
}

const std = @import("std");
