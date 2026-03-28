/// Build-safe identifier for one shipped custom open-row example.
pub const CustomExampleKind = enum {
    abort_basic,
    abortive_validation,
    artifact_search,
    choice_basic,
    generator,
    transform_basic,
    workflow,
};

/// One shipped custom open-row example row shared across build and proof surfaces.
pub const CustomExample = struct {
    kind: CustomExampleKind,
    name: []const u8,
    source_path: []const u8,
    example_case_id: []const u8,
    fixture_name: []const u8,
    run_step_name: []const u8,
    run_step_desc: []const u8,
    user_defined_case_id: ?[]const u8 = null,
};

/// The shipped custom open-row corpus.
pub const custom_examples = [_]CustomExample{
    .{
        .kind = .transform_basic,
        .name = "open_row_transform_basic",
        .source_path = "examples/open_row_transform_basic.zig",
        .example_case_id = "example.open_row_transform_basic",
        .fixture_name = "open_row_transform_basic.txt",
        .run_step_name = "run-open-row-transform-basic",
        .run_step_desc = "Run the open-row transform example.",
        .user_defined_case_id = "user_defined.transform",
    },
    .{
        .kind = .choice_basic,
        .name = "open_row_choice_basic",
        .source_path = "examples/open_row_choice_basic.zig",
        .example_case_id = "example.open_row_choice_basic",
        .fixture_name = "open_row_choice_basic.txt",
        .run_step_name = "run-open-row-choice-basic",
        .run_step_desc = "Run the open-row choice example.",
        .user_defined_case_id = "user_defined.choice",
    },
    .{
        .kind = .abort_basic,
        .name = "open_row_abort_basic",
        .source_path = "examples/open_row_abort_basic.zig",
        .example_case_id = "example.open_row_abort_basic",
        .fixture_name = "open_row_abort_basic.txt",
        .run_step_name = "run-open-row-abort-basic",
        .run_step_desc = "Run the open-row abort example.",
        .user_defined_case_id = "user_defined.abort",
    },
    .{
        .kind = .workflow,
        .name = "open_row_workflow",
        .source_path = "examples/open_row_workflow.zig",
        .example_case_id = "example.open_row_workflow",
        .fixture_name = "open_row_workflow.txt",
        .run_step_name = "run-open-row-workflow",
        .run_step_desc = "Run the open-row workflow example.",
    },
    .{
        .kind = .abortive_validation,
        .name = "open_row_abortive_validation",
        .source_path = "examples/open_row_abortive_validation.zig",
        .example_case_id = "example.open_row_abortive_validation",
        .fixture_name = "open_row_abortive_validation.txt",
        .run_step_name = "run-open-row-abortive-validation",
        .run_step_desc = "Run the open-row abortive-validation example.",
    },
    .{
        .kind = .artifact_search,
        .name = "open_row_artifact_search",
        .source_path = "examples/open_row_artifact_search.zig",
        .example_case_id = "example.open_row_artifact_search",
        .fixture_name = "open_row_artifact_search.txt",
        .run_step_name = "run-open-row-artifact-search",
        .run_step_desc = "Run the open-row artifact-search example.",
    },
    .{
        .kind = .generator,
        .name = "open_row_generator",
        .source_path = "examples/open_row_generator.zig",
        .example_case_id = "example.open_row_generator",
        .fixture_name = "open_row_generator.txt",
        .run_step_name = "run-open-row-generator",
        .run_step_desc = "Run the open-row generator example.",
    },
};

/// Find one shipped custom example row by its example case id.
pub fn findExampleCase(case_id: []const u8) ?*const CustomExample {
    for (&custom_examples) |*row| {
        if (std.mem.eql(u8, row.example_case_id, case_id)) return row;
    }
    return null;
}

/// Find one shipped custom example row by its user-defined case id.
pub fn findUserDefinedCase(case_id: []const u8) ?*const CustomExample {
    for (&custom_examples) |*row| {
        if (row.user_defined_case_id) |current| {
            if (std.mem.eql(u8, current, case_id)) return row;
        }
    }
    return null;
}

const std = @import("std");
