const formal_core = @import("formal_core_registry");
const std = @import("std");

/// Lexical proof state for one retained kernel witness row.
pub const LexicalStatus = enum {
    explicit_only,
    lexical_proven,
};

/// Kernel-case admission state for one retained witness row.
/// The field name stays `bridge_status` because internal bridge fixtures still consume it.
pub const BridgeStatus = enum {
    blocked,
    supported,
    unknown,
};

/// Canonical closure state for one retained witness row.
pub const CanonicalStatus = enum {
    canonical,
    planned,
};

/// One retained kernel witness admission record.
pub const Entry = struct {
    witness_id: []const u8,
    current_surface: []const u8,
    lexical_target: []const u8,
    law_anchor: []const u8,
    lexical_status: LexicalStatus,
    bridge_status: BridgeStatus,
    canonical_status: CanonicalStatus,
    note: []const u8,
};

/// Generator-owned witness admission truth for the retained kernel witness corpus.
pub const entries = [_]Entry{
    .{
        .witness_id = "atm_resume_transform",
        .current_surface = "proof.witness.atm_resume_transform",
        .lexical_target = "proof.lexical_witness.atm_resume_transform",
        .law_anchor = formal_core.anchorPath(.atm_resume_transform),
        .lexical_status = .lexical_proven,
        .bridge_status = .supported,
        .canonical_status = .canonical,
        .note = "The lexical ATM witness reproduces the canonical transcript and is admitted to the retained kernel witness corpus.",
    },
    .{
        .witness_id = "direct_return",
        .current_surface = "proof.witness.direct_return",
        .lexical_target = "proof.lexical_witness.direct_return",
        .law_anchor = formal_core.anchorPath(.direct_return),
        .lexical_status = .lexical_proven,
        .bridge_status = .supported,
        .canonical_status = .canonical,
        .note = "The lexical direct-return witness is proven against the canonical transcript and admitted to the retained kernel witness corpus.",
    },
    .{
        .witness_id = "resume_or_return_return_now",
        .current_surface = "proof.witness.resume_or_return_return_now",
        .lexical_target = "proof.lexical_witness.resume_or_return_return_now",
        .law_anchor = formal_core.anchorPath(.optional_resumption),
        .lexical_status = .lexical_proven,
        .bridge_status = .supported,
        .canonical_status = .canonical,
        .note = "The lexical return-now witness is proven against the canonical transcript and admitted to the retained kernel witness corpus.",
    },
    .{
        .witness_id = "resume_or_return_resume",
        .current_surface = "proof.witness.resume_or_return_resume",
        .lexical_target = "proof.lexical_witness.resume_or_return_resume",
        .law_anchor = formal_core.anchorPath(.optional_resumption),
        .lexical_status = .lexical_proven,
        .bridge_status = .supported,
        .canonical_status = .canonical,
        .note = "The lexical single-resume witness is proven against the canonical transcript and admitted to the retained kernel witness corpus.",
    },
    .{
        .witness_id = "static_redelim",
        .current_surface = "proof.witness.static_redelim",
        .lexical_target = "proof.lexical_witness.static_redelim",
        .law_anchor = formal_core.anchorPath(.static_redelim),
        .lexical_status = .lexical_proven,
        .bridge_status = .supported,
        .canonical_status = .canonical,
        .note = "The lexical static re-delimitation witness is proven against the canonical transcript and admitted to the retained kernel witness corpus.",
    },
    .{
        .witness_id = "multi_prompt",
        .current_surface = "proof.witness.multi_prompt",
        .lexical_target = "proof.lexical_witness.multi_prompt",
        .law_anchor = formal_core.anchorPath(.multi_prompt_separation),
        .lexical_status = .lexical_proven,
        .bridge_status = .supported,
        .canonical_status = .canonical,
        .note = "The lexical prompt-separation witness is proven against the canonical transcript and admitted to the retained kernel witness corpus.",
    },
    .{
        .witness_id = "generator",
        .current_surface = "proof.witness.generator",
        .lexical_target = "proof.lexical_witness.generator",
        .law_anchor = formal_core.anchorPath(.practical_witnesses),
        .lexical_status = .lexical_proven,
        .bridge_status = .supported,
        .canonical_status = .canonical,
        .note = "The lexical generator witness is proven against the canonical transcript and admitted through the retained kernel generator lane.",
    },
};

/// Find one witness admission record by stable witness id.
pub fn find(witness_id: []const u8) ?*const Entry {
    for (&entries) |*entry| {
        if (std.mem.eql(u8, entry.witness_id, witness_id)) return entry;
    }
    return null;
}
