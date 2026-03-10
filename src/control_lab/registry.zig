const std = @import("std");

/// Semantic role each control-lab witness demonstrates.
pub const SemanticRole = enum {
    driver_discontinue,
    escape_redelimit,
    pending_loop,
    terminal_cancel,
};

/// Public surface each witness uses.
pub const Surface = enum {
    additive_driver,
    escaped_owner,
    pending_owner,
};

/// Machine-readable witness entry for the control lab.
pub const Witness = struct {
    witness_id: []const u8,
    title: []const u8,
    semantic_role: SemanticRole,
    surface: Surface,
    summary: []const u8,
    docs_anchor: []const u8,
    expected_transcript: []const u8,
    perf_sensitive: bool,
};

/// Curated v1 witness set for the control lab.
pub const witnesses = [_]Witness{
    .{
        .witness_id = "pending_loop",
        .title = "Ordinary pending loop",
        .semantic_role = .pending_loop,
        .surface = .pending_owner,
        .summary = "Yields three requests and resolves them with proceed().",
        .docs_anchor = "#pending-loop",
        .expected_transcript =
        \\yield=1
        \\yield=2
        \\yield=3
        \\done=3
        \\
        ,
        .perf_sensitive = false,
    },
    .{
        .witness_id = "terminal_cancel",
        .title = "Terminal cancellation",
        .semantic_role = .terminal_cancel,
        .surface = .pending_owner,
        .summary = "Cancels a pending owner and terminates the reset.",
        .docs_anchor = "#terminal-cancel",
        .expected_transcript =
        \\cancelled=yes resumed=0
        \\
        ,
        .perf_sensitive = false,
    },
    .{
        .witness_id = "driver_discontinue",
        .title = "Additive driver discontinue",
        .semantic_role = .driver_discontinue,
        .surface = .additive_driver,
        .summary = "Uses shift.driver to surface a user-owned discontinue path.",
        .docs_anchor = "#driver-discontinue",
        .expected_transcript =
        \\aborted=yes trace=[enter, before-abort]
        \\
        ,
        .perf_sensitive = false,
    },
    .{
        .witness_id = "escape_redelimit",
        .title = "Escaped owner re-delimits resumed work",
        .semantic_role = .escape_redelimit,
        .surface = .escaped_owner,
        .summary = "Escapes a pending owner, resumes it later, and suspends again under the same delimiter.",
        .docs_anchor = "#escape-redelimit",
        .expected_transcript =
        \\first_request=41
        \\escaped=yes
        \\second_request=42
        \\result=43
        \\
        ,
        .perf_sensitive = true,
    },
};

/// Human-readable label for a witness surface.
pub fn surfaceLabel(surface: Surface) []const u8 {
    return switch (surface) {
        .pending_owner => "pending-owner",
        .additive_driver => "additive-driver",
        .escaped_owner => "escaped-owner",
    };
}

/// Look up one witness by its stable id.
pub fn findWitness(id: []const u8) ?Witness {
    for (witnesses) |witness| {
        if (std.mem.eql(u8, witness.witness_id, id)) return witness;
    }
    return null;
}
