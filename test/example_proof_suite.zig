const example_open_row_abort_basic = @import("example_open_row_abort_basic");
const example_open_row_abortive_validation = @import("example_open_row_abortive_validation");
const example_open_row_artifact_search = @import("example_open_row_artifact_search");
const example_open_row_choice_basic = @import("example_open_row_choice_basic");
const example_open_row_generator = @import("example_open_row_generator");
const example_open_row_state_writer = @import("example_open_row_state_writer");
const example_open_row_transform_basic = @import("example_open_row_transform_basic");
const example_open_row_workflow = @import("example_open_row_workflow");
const std = @import("std");

fn expectExample(comptime Runner: type, comptime fixture_rel: []const u8) !void {
    var buffer: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try Runner.run(&writer);
    try std.testing.expectEqualStrings(@embedFile(fixture_rel), writer.buffered());
}

test "example proof fixtures stay exact" {
    try expectExample(example_open_row_transform_basic, "example_proof/fixtures/open_row_transform_basic.txt");
    try expectExample(example_open_row_choice_basic, "example_proof/fixtures/open_row_choice_basic.txt");
    try expectExample(example_open_row_abort_basic, "example_proof/fixtures/open_row_abort_basic.txt");
    try expectExample(example_open_row_workflow, "example_proof/fixtures/open_row_workflow.txt");
    try expectExample(example_open_row_abortive_validation, "example_proof/fixtures/open_row_abortive_validation.txt");
    try expectExample(example_open_row_artifact_search, "example_proof/fixtures/open_row_artifact_search.txt");
    try expectExample(example_open_row_generator, "example_proof/fixtures/open_row_generator.txt");
    try expectExample(example_open_row_state_writer, "example_proof/fixtures/open_row_state_writer.txt");
}
