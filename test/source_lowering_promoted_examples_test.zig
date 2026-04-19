const support = @import("source_lowering_promoted_support.zig");

test "public example source-lowering case open_row_transform_basic stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.open_row_transform_basic",
        .source_path = "examples/open_row_transform_basic.zig",
        .surface_kind = .example,
        .scenario_id = .define_basic,
    });
}

test "public example source-lowering case open_row_choice_basic stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.open_row_choice_basic",
        .source_path = "examples/open_row_choice_basic.zig",
        .surface_kind = .example,
        .scenario_id = .define_choice_basic,
    });
}

test "public example source-lowering case open_row_abort_basic stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.open_row_abort_basic",
        .source_path = "examples/open_row_abort_basic.zig",
        .surface_kind = .example,
        .scenario_id = .define_abort_basic,
    });
}

test "public example source-lowering case open_row_workflow stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.open_row_workflow",
        .source_path = "examples/open_row_workflow.zig",
        .surface_kind = .example,
        .scenario_id = .front_door_workflow,
    });
}

test "public example source-lowering case open_row_abortive_validation stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.open_row_abortive_validation",
        .source_path = "examples/open_row_abortive_validation.zig",
        .surface_kind = .example,
        .scenario_id = .algebraic_abortive_validation,
    });
}

test "public example source-lowering case open_row_artifact_search stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.open_row_artifact_search",
        .source_path = "examples/open_row_artifact_search.zig",
        .surface_kind = .example,
        .scenario_id = .algebraic_artifact_search,
    });
}

test "public example source-lowering case open_row_generator stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.open_row_generator",
        .source_path = "examples/open_row_generator.zig",
        .surface_kind = .example,
        .scenario_id = .generator,
    });
}

test "public example source-lowering case early_exit stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.early_exit",
        .source_path = "examples/early_exit.zig",
        .surface_kind = .example,
        .scenario_id = .early_exit,
    });
}

test "public example source-lowering case resume_or_return stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.resume_or_return",
        .source_path = "examples/resume_or_return.zig",
        .surface_kind = .example,
        .scenario_id = .resume_or_return,
    });
}

test "public example source-lowering case nested_workflow stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.nested_workflow",
        .source_path = "examples/nested_workflow.zig",
        .surface_kind = .example,
        .scenario_id = .nested_workflow_publish,
    });
}

test "public example source-lowering case exception_basic stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.exception_basic",
        .source_path = "examples/exception_basic.zig",
        .surface_kind = .example,
        .scenario_id = .exception_basic,
    });
}

test "built-in effect source-lowering case state_basic example stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.state_basic",
        .source_path = "examples/state_basic.zig",
        .surface_kind = .example,
        .scenario_id = .state_basic,
    });
}

test "built-in effect source-lowering case reader_basic example stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.reader_basic",
        .source_path = "examples/reader_basic.zig",
        .surface_kind = .example,
        .scenario_id = .reader_basic,
    });
}

test "built-in effect source-lowering case optional_basic example stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.optional_basic",
        .source_path = "examples/optional_basic.zig",
        .surface_kind = .example,
        .scenario_id = .optional_basic,
    });
}

test "built-in effect source-lowering case exception_basic example stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.exception_basic",
        .source_path = "examples/exception_basic.zig",
        .surface_kind = .example,
        .scenario_id = .exception_basic,
    });
}

test "built-in effect source-lowering case resource_basic example stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.resource_basic",
        .source_path = "examples/resource_basic.zig",
        .surface_kind = .example,
        .scenario_id = .resource_basic,
    });
}

test "built-in effect source-lowering case writer_basic example stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.writer_basic",
        .source_path = "examples/writer_basic.zig",
        .surface_kind = .example,
        .scenario_id = .writer_basic,
    });
}

test "built-in effect source-lowering case state_basic effect stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "effect.state_basic",
        .source_path = "examples/state_basic.zig",
        .surface_kind = .effect,
        .scenario_id = .state_basic,
    });
}

test "built-in effect source-lowering case reader_basic effect stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "effect.reader_basic",
        .source_path = "examples/reader_basic.zig",
        .surface_kind = .effect,
        .scenario_id = .reader_basic,
    });
}

test "built-in effect source-lowering case optional_basic effect stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "effect.optional_basic",
        .source_path = "examples/optional_basic.zig",
        .surface_kind = .effect,
        .scenario_id = .optional_basic,
    });
}

test "built-in effect source-lowering case exception_basic effect stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "effect.exception_basic",
        .source_path = "examples/exception_basic.zig",
        .surface_kind = .effect,
        .scenario_id = .exception_basic,
    });
}

test "built-in effect source-lowering case resource_basic effect stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "effect.resource_basic",
        .source_path = "examples/resource_basic.zig",
        .surface_kind = .effect,
        .scenario_id = .resource_basic,
    });
}

test "built-in effect source-lowering case writer_basic effect stays source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "effect.writer_basic",
        .source_path = "examples/writer_basic.zig",
        .surface_kind = .effect,
        .scenario_id = .writer_basic,
    });
}
