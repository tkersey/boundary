const parity_scenarios = @import("parity_scenarios");
const std = @import("std");

/// Semantic manifest entry for one active witness in the current rung.
pub const WitnessEntry = struct {
    witness_id: []const u8,
    evaluator_case: ?[]const u8,
    runtime_case: []const u8,
    required_transcript: []const u8,
    forbidden_transcript: ?[]const u8,
};

fn witnessEntry(witness_id: []const u8) WitnessEntry {
    const scenario = parity_scenarios.findWitness(witness_id).?;
    const witness = scenario.witness.?;
    return .{
        .witness_id = witness.witness_id,
        .evaluator_case = witness.evaluator_case,
        .runtime_case = witness.runtime_case,
        .required_transcript = scenario.expected_transcript,
        .forbidden_transcript = witness.forbidden_transcript,
    };
}

/// Active witness manifest derived from the canonical scenario registry.
pub const entries = [_]WitnessEntry{
    witnessEntry("atm_resume_transform"),
    witnessEntry("direct_return"),
    witnessEntry("resume_or_return_return_now"),
    witnessEntry("resume_or_return_resume"),
    witnessEntry("static_redelim"),
    witnessEntry("multi_prompt"),
    witnessEntry("generator"),
};

/// Find a manifest entry by witness id.
pub fn find(witness_id: []const u8) ?WitnessEntry {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.witness_id, witness_id)) return entry;
    }
    return null;
}
