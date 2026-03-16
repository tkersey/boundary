const algebraic_abortive_validation = @import("example_algebraic_abortive_validation");
const algebraic_artifact_search = @import("example_algebraic_artifact_search");
const define_basic = @import("example_define_basic");
const early_exit = @import("example_early_exit");
const exception_basic = @import("example_exception_basic");
const generator = @import("example_generator");
const nested_workflow = @import("example_nested_workflow");
const optional_basic = @import("example_optional_basic");
const reader_basic = @import("example_reader_basic");
const resource_basic = @import("example_resource_basic");
const resume_or_return = @import("example_resume_or_return");
const state_basic = @import("example_state_basic");
const std = @import("std");
const writer_basic = @import("example_writer_basic");

fn expectExample(comptime Runner: type, comptime fixture_rel: []const u8) !void {
    var buffer: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try Runner.run(&writer);
    try std.testing.expectEqualStrings(@embedFile(fixture_rel), writer.buffered());
}

test "example proof fixtures stay exact" {
    try expectExample(algebraic_abortive_validation, "example_proof/fixtures/algebraic_abortive_validation.txt");
    try expectExample(algebraic_artifact_search, "example_proof/fixtures/algebraic_artifact_search.txt");
    try expectExample(define_basic, "example_proof/fixtures/define_basic.txt");
    try expectExample(early_exit, "example_proof/fixtures/early_exit.txt");
    try expectExample(exception_basic, "example_proof/fixtures/exception_basic.txt");
    try expectExample(generator, "example_proof/fixtures/generator.txt");
    try expectExample(nested_workflow, "example_proof/fixtures/nested_workflow.txt");
    try expectExample(optional_basic, "example_proof/fixtures/optional_basic.txt");
    try expectExample(reader_basic, "example_proof/fixtures/reader_basic.txt");
    try expectExample(resource_basic, "example_proof/fixtures/resource_basic.txt");
    try expectExample(resume_or_return, "example_proof/fixtures/resume_or_return.txt");
    try expectExample(state_basic, "example_proof/fixtures/state_basic.txt");
    try expectExample(writer_basic, "example_proof/fixtures/writer_basic.txt");
}
