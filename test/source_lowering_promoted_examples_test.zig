const support = @import("source_lowering_promoted_support.zig");

test "public example source-lowering cases stay source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.open_row_transform_basic",
        .source_path = "examples/open_row_transform_basic.zig",
        .surface_kind = .example,
        .scenario_id = .define_basic,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.open_row_choice_basic",
        .source_path = "examples/open_row_choice_basic.zig",
        .surface_kind = .example,
        .scenario_id = .define_choice_basic,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.open_row_abort_basic",
        .source_path = "examples/open_row_abort_basic.zig",
        .surface_kind = .example,
        .scenario_id = .define_abort_basic,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.open_row_workflow",
        .source_path = "examples/open_row_workflow.zig",
        .surface_kind = .example,
        .scenario_id = .front_door_workflow,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.open_row_abortive_validation",
        .source_path = "examples/open_row_abortive_validation.zig",
        .surface_kind = .example,
        .scenario_id = .algebraic_abortive_validation,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.open_row_artifact_search",
        .source_path = "examples/open_row_artifact_search.zig",
        .surface_kind = .example,
        .scenario_id = .algebraic_artifact_search,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.open_row_generator",
        .source_path = "examples/open_row_generator.zig",
        .surface_kind = .example,
        .scenario_id = .generator,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.early_exit",
        .source_path = "examples/early_exit.zig",
        .surface_kind = .example,
        .scenario_id = .early_exit,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.resume_or_return",
        .source_path = "examples/resume_or_return.zig",
        .surface_kind = .example,
        .scenario_id = .resume_or_return,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.nested_workflow",
        .source_path = "examples/nested_workflow.zig",
        .surface_kind = .example,
        .scenario_id = .nested_workflow_publish,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.exception_basic",
        .source_path = "examples/exception_basic.zig",
        .surface_kind = .example,
        .scenario_id = .exception_basic,
    });
}

test "built-in effect source-lowering cases stay source-backed and canonical" {
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.state_basic",
        .source_path = "examples/state_basic.zig",
        .surface_kind = .example,
        .scenario_id = .state_basic,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.reader_basic",
        .source_path = "examples/reader_basic.zig",
        .surface_kind = .example,
        .scenario_id = .reader_basic,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.optional_basic",
        .source_path = "examples/optional_basic.zig",
        .surface_kind = .example,
        .scenario_id = .optional_basic,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.exception_basic",
        .source_path = "examples/exception_basic.zig",
        .surface_kind = .example,
        .scenario_id = .exception_basic,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.resource_basic",
        .source_path = "examples/resource_basic.zig",
        .surface_kind = .example,
        .scenario_id = .resource_basic,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "example.writer_basic",
        .source_path = "examples/writer_basic.zig",
        .surface_kind = .example,
        .scenario_id = .writer_basic,
    });

    try support.expectCanonicalSourceCase(.{
        .case_id = "effect.state_basic",
        .source_path = "examples/state_basic.zig",
        .surface_kind = .effect,
        .scenario_id = .state_basic,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "effect.reader_basic",
        .source_path = "examples/reader_basic.zig",
        .surface_kind = .effect,
        .scenario_id = .reader_basic,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "effect.optional_basic",
        .source_path = "examples/optional_basic.zig",
        .surface_kind = .effect,
        .scenario_id = .optional_basic,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "effect.exception_basic",
        .source_path = "examples/exception_basic.zig",
        .surface_kind = .effect,
        .scenario_id = .exception_basic,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "effect.resource_basic",
        .source_path = "examples/resource_basic.zig",
        .surface_kind = .effect,
        .scenario_id = .resource_basic,
    });
    try support.expectCanonicalSourceCase(.{
        .case_id = "effect.writer_basic",
        .source_path = "examples/writer_basic.zig",
        .surface_kind = .effect,
        .scenario_id = .writer_basic,
    });
}
