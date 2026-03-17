const ordinary = @import("ordinary_zig_registry");
const ordinary_zig_lowering = @import("ordinary_zig_lowering");
const std = @import("std");

test "ordinary Zig registry keeps the exact wave-one case count" {
    try std.testing.expectEqual(@as(usize, 8), ordinary.cases.len);
    for (ordinary.cases) |case| {
        try std.testing.expect(case.status == .canonical);
    }
}

test "ordinary Zig lowering rejects unsupported fixture ids" {
    const unsupported_fixture = struct {
        /// Stable unsupported ordinary-Zig case id.
        pub const ordinary_case_id = "ordinary.recursion";
    };

    try std.testing.expectError(error.UnsupportedOrdinaryCase, ordinary_zig_lowering.lowerFixture(std.testing.allocator, unsupported_fixture));
}

test "ordinary Zig lowering rejects non-canonical source paths for known cases" {
    var lowered = try ordinary_zig_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "ordinary.branch_resume",
        .source_path = "test/ordinary_zig_corpus/fixtures/helper_call_resume.zig",
        .entry_symbol = "run",
        .surface_kind = .ordinary_case,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("non_canonical_source_path", lowered.diagnostics[0].code);
}

test "ordinary Zig lowering rejects the wrong entry function for supported examples" {
    var lowered = try ordinary_zig_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "example.define_basic",
        .source_path = "examples/define_basic.zig",
        .entry_symbol = "runCounter",
        .surface_kind = .example,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("unsupported_shape", lowered.diagnostics[0].code);
}

test "ordinary Zig lowering rejects the wrong witness entry in shared witness sources" {
    var lowered = try ordinary_zig_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "witness.atm_resume_transform",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runResumeOrReturnResume",
        .surface_kind = .witness,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("unsupported_shape", lowered.diagnostics[0].code);
}

test "ordinary Zig lowering exposes a public experimental root surface" {
    const shift = @import("shift");

    try std.testing.expect(@hasDecl(shift, "ordinary"));
}
