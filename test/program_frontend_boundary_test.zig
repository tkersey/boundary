const program_frontend = @import("program_frontend");
const std = @import("std");

test "program frontend stays explicit and does not pretend to lower raw bodies" {
    try std.testing.expect(@hasDecl(program_frontend, "Program"));
    try std.testing.expect(@hasDecl(program_frontend, "lower"));
    try std.testing.expect(!@hasDecl(program_frontend, "fromBody"));
    try std.testing.expect(!@hasDecl(program_frontend, "fromClosure"));
    try std.testing.expect(!@hasDecl(program_frontend, "lowerBody"));
}

test "program frontend lowers nested workflow publish to the canonical scenario" {
    const lowered = program_frontend.lower(program_frontend.examples.nestedWorkflowPublish());
    try std.testing.expectEqualStrings("nested_workflow", lowered.scenario.case_id);
}
