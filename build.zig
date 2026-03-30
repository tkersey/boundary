const shipped_open_row_corpus = @import("src/shipped_open_row_corpus_registry.zig");
const std = @import("std");
const zlinter = @import("zlinter");

const ShiftConsumerDeps = struct {
    lowered_runtime_mod: ?*std.Build.Module,
    shift_mod: *std.Build.Module,
};

const ShiftPromptFixtureDeps = struct {
    prompt_support_mod: *std.Build.Module,
    shift_mod: *std.Build.Module,
    with_api_mod: *std.Build.Module,
};

fn absolutizeGraphDirPath(b: *std.Build, maybe_path: ?[]const u8) ?[]const u8 {
    const path = maybe_path orelse return null;
    if (std.fs.path.isAbsolute(path)) return path;
    return std.fs.path.resolve(b.allocator, &.{path}) catch |err|
        std.process.fatal("failed to resolve build graph path '{s}': {s}", .{ path, @errorName(err) });
}

fn absolutizeZlinterRuntimePaths(b: *std.Build) void {
    b.graph.global_cache_root.path = absolutizeGraphDirPath(b, b.graph.global_cache_root.path);
    b.graph.zig_lib_directory.path = absolutizeGraphDirPath(b, b.graph.zig_lib_directory.path);
}

fn createShiftConsumerModule(
    b: *std.Build,
    path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    deps: ShiftConsumerDeps,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("shift", deps.shift_mod);
    if (deps.lowered_runtime_mod) |runtime_mod| mod.addImport("private_lowered_runtime", runtime_mod);
    return mod;
}

fn createShiftPromptFixtureModule(
    b: *std.Build,
    path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    deps: ShiftPromptFixtureDeps,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("shift", deps.shift_mod);
    mod.addImport("prompt_support", deps.prompt_support_mod);
    mod.addImport("with_api", deps.with_api_mod);
    return mod;
}

fn createBridgeExampleModule(
    b: *std.Build,
    path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    import: struct {
        name: []const u8,
        mod: *std.Build.Module,
    },
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport(import.name, import.mod);
    return mod;
}

fn createPlainModule(
    b: *std.Build,
    path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
    });
}

fn assertOwnedCompileFailFixtures(b: *std.Build, dir_path: []const u8, fixture_table: anytype) void {
    var owned = std.StringHashMap(void).init(b.allocator);
    defer owned.deinit();

    inline for (fixture_table) |fixture| {
        owned.put(std.fs.path.basename(fixture.path), {}) catch std.process.fatal("unable to record compile-fail fixture", .{});
    }

    var dir = std.fs.cwd().openDir(b.pathFromRoot(dir_path), .{ .iterate = true }) catch
        std.process.fatal("unable to open compile-fail fixture directory", .{});
    defer dir.close();

    var iterator = dir.iterate();
    while (iterator.next() catch std.process.fatal("unable to iterate compile-fail fixture directory", .{})) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;
        if (!owned.contains(entry.name)) {
            std.process.fatal("unowned compile-fail fixture: {s}/{s}", .{ dir_path, entry.name });
        }
    }
}

fn canonicalSourceHash(b: *std.Build, path: []const u8) [32]u8 {
    const bytes = std.fs.cwd().readFileAlloc(b.allocator, b.pathFromRoot(path), 1 << 20) catch
        std.process.fatal("unable to read canonical source-lowering source", .{});
    defer b.allocator.free(bytes);

    const normalized = normalizeSourceForHashAlloc(b.allocator, bytes) catch
        std.process.fatal("unable to normalize canonical source-lowering source", .{});
    defer b.allocator.free(normalized);

    var digest = std.mem.zeroes([32]u8);
    std.crypto.hash.Blake3.hash(normalized, &digest, .{});
    return digest;
}

fn normalizeSourceForHashAlloc(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var in_string = false;
    var escaped = false;
    var idx: usize = 0;
    while (idx < source.len) : (idx += 1) {
        const byte = source[idx];
        if (in_string) {
            try out.append(allocator, byte);
            if (escaped) {
                escaped = false;
            } else if (byte == '\\') {
                escaped = true;
            } else if (byte == '"') {
                in_string = false;
            }
            continue;
        }

        if (byte == '"') {
            in_string = true;
            try out.append(allocator, byte);
            continue;
        }
        if (byte == '/' and idx + 1 < source.len and source[idx + 1] == '/') {
            idx += 2;
            while (idx < source.len and source[idx] != '\n') : (idx += 1) {}
            continue;
        }
        if (std.ascii.isWhitespace(byte)) continue;
        try out.append(allocator, byte);
    }

    return try out.toOwnedSlice(allocator);
}

/// Configure build, test, lint, example, and benchmark entrypoints for shift.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const bench_optimize: std.builtin.OptimizeMode = .ReleaseFast;

    absolutizeZlinterRuntimePaths(b);

    const shift_mod = b.addModule("shift", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const portable_core_mod = b.createModule(.{
        .root_source_file = b.path("src/portable_core.zig"),
        .target = target,
        .optimize = optimize,
    });
    const error_witness_mod = b.createModule(.{
        .root_source_file = b.path("src/error_witness.zig"),
        .target = target,
        .optimize = optimize,
    });
    const prompt_contract_support_mod = b.createModule(.{
        .root_source_file = b.path("src/prompt_contract.zig"),
        .target = target,
        .optimize = optimize,
    });
    const frontend_support_mod = b.createModule(.{
        .root_source_file = b.path("src/frontend.zig"),
        .target = target,
        .optimize = optimize,
    });
    prompt_contract_support_mod.addImport("portable_core", portable_core_mod);
    frontend_support_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    frontend_support_mod.addImport("portable_core", portable_core_mod);
    shift_mod.addImport("portable_core", portable_core_mod);
    shift_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    shift_mod.addImport("frontend_support", frontend_support_mod);
    shift_mod.addImport("error_witness", error_witness_mod);
    const witnesses_mod = b.createModule(.{
        .root_source_file = b.path("src/witnesses.zig"),
        .target = target,
        .optimize = optimize,
    });
    const formal_core_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/formal_core_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    const parity_scenarios_mod = b.createModule(.{
        .root_source_file = b.path("src/parity_scenarios.zig"),
        .target = target,
        .optimize = optimize,
    });
    parity_scenarios_mod.addImport("formal_core_registry", formal_core_registry_mod);
    shift_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const lowered_machine_mod = b.createModule(.{
        .root_source_file = b.path("src/lowered_machine.zig"),
        .target = target,
        .optimize = optimize,
    });
    lowered_machine_mod.addImport("portable_core", portable_core_mod);
    const effect_ir_mod = b.createModule(.{
        .root_source_file = b.path("src/effect_ir.zig"),
        .target = target,
        .optimize = optimize,
    });
    const helper_body_ir_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/helper_body_ir.zig"),
        .target = target,
        .optimize = optimize,
    });
    const source_graph_engine_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/source_graph_engine.zig"),
        .target = target,
        .optimize = optimize,
    });
    const internal_program_plan_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/program_plan.zig"),
        .target = target,
        .optimize = optimize,
    });
    internal_program_plan_mod.addImport("effect_ir", effect_ir_mod);
    helper_body_ir_mod.addImport("internal_program_plan", internal_program_plan_mod);
    const source_graph_comptime_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/source_graph_comptime.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_graph_comptime_mod.addImport("source_graph_engine", source_graph_engine_mod);
    const source_graph_embed_mod = b.createModule(.{
        .root_source_file = b.path("source_graph_embed.zig"),
        .target = target,
        .optimize = optimize,
    });
    const internal_kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/kernel.zig"),
        .target = target,
        .optimize = optimize,
    });
    internal_kernel_mod.addImport("parity_scenarios", parity_scenarios_mod);
    internal_kernel_mod.addImport("internal_program_plan", internal_program_plan_mod);
    const interpreter_mod = b.createModule(.{
        .root_source_file = b.path("src/interpreter.zig"),
        .target = target,
        .optimize = optimize,
    });
    interpreter_mod.addImport("parity_scenarios", parity_scenarios_mod);
    interpreter_mod.addImport("internal_kernel", internal_kernel_mod);
    shift_mod.addImport("effect_ir", effect_ir_mod);
    shift_mod.addImport("internal_kernel", internal_kernel_mod);
    shift_mod.addImport("internal_program_plan", internal_program_plan_mod);
    shift_mod.addImport("interpreter", interpreter_mod);
    shift_mod.addImport("source_graph_engine", source_graph_engine_mod);
    shift_mod.addImport("source_graph_comptime", source_graph_comptime_mod);
    lowered_machine_mod.addImport("parity_scenarios", parity_scenarios_mod);
    lowered_machine_mod.addImport("internal_kernel", internal_kernel_mod);
    lowered_machine_mod.addImport("interpreter", interpreter_mod);
    const authoring_lowerer_options = b.addOptions();
    const lowerer_opts_marker = true;
    authoring_lowerer_options.addOption([]const u8, "package_root", b.pathFromRoot("."));
    authoring_lowerer_options.addOption(bool, "authoring_lowerer_options_marker", lowerer_opts_marker);
    authoring_lowerer_options.addOption([32]u8, "hash_local_mutation_resume", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/local_mutation_resume.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_branch_resume", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/branch_resume.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_loop_resume", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/loop_resume.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_helper_call_resume", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/helper_call_resume.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_nested_prompt_static_redelim", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/nested_prompt_static_redelim.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_typed_error_try", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/typed_error_try.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_defer_resume", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/defer_resume.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_errdefer_error", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/errdefer_error.zig"));
    inline for (shipped_open_row_corpus.custom_examples) |row| {
        switch (row.kind) {
            .transform_basic => authoring_lowerer_options.addOption([32]u8, "hash_define_basic", canonicalSourceHash(b, row.source_path)),
            .choice_basic => authoring_lowerer_options.addOption([32]u8, "hash_define_choice_basic", canonicalSourceHash(b, row.source_path)),
            .abort_basic => authoring_lowerer_options.addOption([32]u8, "hash_define_abort_basic", canonicalSourceHash(b, row.source_path)),
            .workflow => authoring_lowerer_options.addOption([32]u8, "hash_front_door_workflow", canonicalSourceHash(b, row.source_path)),
            .abortive_validation => authoring_lowerer_options.addOption([32]u8, "hash_algebraic_abortive_validation", canonicalSourceHash(b, row.source_path)),
            .artifact_search => authoring_lowerer_options.addOption([32]u8, "hash_algebraic_artifact_search", canonicalSourceHash(b, row.source_path)),
            .generator => authoring_lowerer_options.addOption([32]u8, "hash_generator", canonicalSourceHash(b, row.source_path)),
        }
    }
    authoring_lowerer_options.addOption([32]u8, "hash_early_exit", canonicalSourceHash(b, "examples/early_exit.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_resume_or_return", canonicalSourceHash(b, "examples/resume_or_return.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_nested_workflow", canonicalSourceHash(b, "examples/nested_workflow.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_state_basic", canonicalSourceHash(b, "examples/state_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_reader_basic", canonicalSourceHash(b, "examples/reader_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_optional_basic", canonicalSourceHash(b, "examples/optional_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_exception_basic", canonicalSourceHash(b, "examples/exception_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_resource_basic", canonicalSourceHash(b, "examples/resource_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_writer_basic", canonicalSourceHash(b, "examples/writer_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_witness_sources", canonicalSourceHash(b, "src/witness_sources.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_witnesses", canonicalSourceHash(b, "src/witnesses.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_algebraic_abortive_validation", canonicalSourceHash(b, "test/direct_style_bridge/open_row_abortive_validation.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_algebraic_artifact_search", canonicalSourceHash(b, "test/direct_style_bridge/open_row_artifact_search.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_atm_resume_transform", canonicalSourceHash(b, "test/direct_style_bridge/atm_resume_transform.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_direct_return", canonicalSourceHash(b, "test/direct_style_bridge/direct_return.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_early_exit", canonicalSourceHash(b, "test/direct_style_bridge/early_exit.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_exception_basic", canonicalSourceHash(b, "test/direct_style_bridge/exception_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_generator", canonicalSourceHash(b, "test/direct_style_bridge/open_row_generator.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_multi_prompt", canonicalSourceHash(b, "test/direct_style_bridge/multi_prompt.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_nested_workflow", canonicalSourceHash(b, "test/direct_style_bridge/nested_workflow.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_optional_basic", canonicalSourceHash(b, "test/direct_style_bridge/optional_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_reader_basic", canonicalSourceHash(b, "test/direct_style_bridge/reader_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_resource_basic", canonicalSourceHash(b, "test/direct_style_bridge/resource_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_resume_or_return", canonicalSourceHash(b, "test/direct_style_bridge/resume_or_return.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_resume_or_return_resume", canonicalSourceHash(b, "test/direct_style_bridge/resume_or_return_resume.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_resume_or_return_return_now", canonicalSourceHash(b, "test/direct_style_bridge/resume_or_return_return_now.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_state_basic", canonicalSourceHash(b, "test/direct_style_bridge/state_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_static_redelim", canonicalSourceHash(b, "test/direct_style_bridge/static_redelim.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_writer_basic", canonicalSourceHash(b, "test/direct_style_bridge/writer_basic.zig"));
    const authoring_build_options_mod = authoring_lowerer_options.createModule();
    source_graph_embed_mod.addImport("authoring_build_options", authoring_build_options_mod);
    source_graph_embed_mod.addImport("source_graph_engine", source_graph_engine_mod);
    source_graph_embed_mod.addImport("source_graph_comptime", source_graph_comptime_mod);
    const authoring_lowerer_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/authoring_lowerer.zig"),
        .target = target,
        .optimize = optimize,
    });
    authoring_lowerer_mod.addImport("authoring_build_options", authoring_build_options_mod);
    authoring_lowerer_mod.addImport("effect_ir", effect_ir_mod);
    authoring_lowerer_mod.addImport("lowered_machine", lowered_machine_mod);
    authoring_lowerer_mod.addImport("parity_scenarios", parity_scenarios_mod);
    authoring_lowerer_mod.addImport("source_graph_engine", source_graph_engine_mod);
    frontend_support_mod.addImport("lowered_machine", lowered_machine_mod);
    shift_mod.addImport("effect_ir", effect_ir_mod);
    shift_mod.addImport("lowered_machine", lowered_machine_mod);
    witnesses_mod.addImport("lowered_machine", lowered_machine_mod);
    witnesses_mod.addImport("frontend_support", frontend_support_mod);
    witnesses_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    const prompt_support_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/prompt_support.zig"),
        .target = target,
        .optimize = optimize,
    });
    prompt_support_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    prompt_support_mod.addImport("frontend_support", frontend_support_mod);
    const with_api_mod = b.createModule(.{
        .root_source_file = b.path("src/with_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    with_api_mod.addImport("portable_core", portable_core_mod);
    with_api_mod.addImport("frontend_support", frontend_support_mod);
    with_api_mod.addImport("lowered_machine", lowered_machine_mod);
    with_api_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    const program_frontend_mod = b.createModule(.{
        .root_source_file = b.path("src/program_frontend.zig"),
        .target = target,
        .optimize = optimize,
    });
    program_frontend_mod.addImport("effect_ir", effect_ir_mod);
    program_frontend_mod.addImport("helper_body_ir", helper_body_ir_mod);
    program_frontend_mod.addImport("parity_scenarios", parity_scenarios_mod);
    internal_program_plan_mod.addImport("program_frontend", program_frontend_mod);
    internal_program_plan_mod.addImport("helper_body_ir", helper_body_ir_mod);
    shift_mod.addImport("program_frontend", program_frontend_mod);
    shift_mod.addImport("authoring_build_options", authoring_build_options_mod);
    shift_mod.addImport("source_graph_embed", source_graph_embed_mod);
    authoring_lowerer_mod.addImport("program_frontend", program_frontend_mod);
    shift_mod.addImport("authoring_lowerer", authoring_lowerer_mod);
    const lexical_runtime_internal_mod = b.createModule(.{
        .root_source_file = b.path("src/lexical_runtime_internal.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_runtime_internal_mod.addImport("portable_core", portable_core_mod);
    lexical_runtime_internal_mod.addImport("frontend_support", frontend_support_mod);
    lexical_runtime_internal_mod.addImport("lowered_machine", lowered_machine_mod);
    lexical_runtime_internal_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    const witness_sources_mod = b.createModule(.{
        .root_source_file = b.path("src/witness_sources.zig"),
        .target = target,
        .optimize = optimize,
    });
    witness_sources_mod.addImport("lowered_machine", lowered_machine_mod);
    witness_sources_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
    witness_sources_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    witness_sources_mod.addImport("frontend_support", frontend_support_mod);
    witnesses_mod.addImport("witness_sources", witness_sources_mod);
    const bridge_manifest_mod = b.createModule(.{
        .root_source_file = b.path("src/direct_style_bridge_manifest.zig"),
        .target = target,
        .optimize = optimize,
    });
    bridge_manifest_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const program_bridge_mod = b.createModule(.{
        .root_source_file = b.path("src/program_bridge.zig"),
        .target = target,
        .optimize = optimize,
    });
    program_bridge_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    program_bridge_mod.addImport("parity_scenarios", parity_scenarios_mod);
    program_bridge_mod.addImport("program_frontend", program_frontend_mod);
    program_bridge_mod.addImport("authoring_lowerer", authoring_lowerer_mod);
    const private_lowered_runtime_mod = b.createModule(.{
        .root_source_file = b.path("src/private_lowered_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    private_lowered_runtime_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    private_lowered_runtime_mod.addImport("lowered_machine", lowered_machine_mod);
    private_lowered_runtime_mod.addImport("parity_scenarios", parity_scenarios_mod);
    private_lowered_runtime_mod.addImport("program_bridge", program_bridge_mod);
    const source_lowering_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/source_lowering_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_registry_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const shipped_open_row_corpus_mod = b.createModule(.{
        .root_source_file = b.path("src/shipped_open_row_corpus_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    const source_lowering_mod = b.createModule(.{
        .root_source_file = b.path("src/source_lowering.zig"),
        .target = target,
        .optimize = optimize,
    });
    const source_lowering_options = b.addOptions();
    source_lowering_options.addOption([]const u8, "package_root", b.pathFromRoot("."));
    source_lowering_mod.addOptions("build_options", source_lowering_options);
    source_lowering_mod.addImport("effect_ir", effect_ir_mod);
    source_lowering_mod.addImport("program_frontend", program_frontend_mod);
    source_lowering_mod.addImport("source_lowering_registry", source_lowering_registry_mod);
    source_lowering_mod.addImport("parity_scenarios", parity_scenarios_mod);
    source_lowering_mod.addImport("lowered_machine", lowered_machine_mod);
    source_lowering_mod.addImport("error_witness", error_witness_mod);
    source_lowering_mod.addImport("authoring_lowerer", authoring_lowerer_mod);
    source_lowering_mod.addImport("shipped_open_row_corpus_registry", shipped_open_row_corpus_mod);
    shift_mod.addImport("source_lowering", source_lowering_mod);
    const src_lower_cov_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/source_lowering_coverage_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    src_lower_cov_registry_mod.addImport("formal_core_registry", formal_core_registry_mod);
    src_lower_cov_registry_mod.addImport("shipped_open_row_corpus_registry", shipped_open_row_corpus_mod);
    witnesses_mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);
    const reference_eval_mod = b.createModule(.{
        .root_source_file = b.path("src/reference_eval.zig"),
        .target = target,
        .optimize = optimize,
    });
    reference_eval_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const reference_machine_mod = b.createModule(.{
        .root_source_file = b.path("src/reference_machine.zig"),
        .target = target,
        .optimize = optimize,
    });
    reference_machine_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const parity_kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/parity_kernel.zig"),
        .target = target,
        .optimize = optimize,
    });
    parity_kernel_mod.addImport("internal_kernel", internal_kernel_mod);
    parity_kernel_mod.addImport("interpreter", interpreter_mod);
    parity_kernel_mod.addImport("lowered_machine", lowered_machine_mod);
    parity_kernel_mod.addImport("parity_scenarios", parity_scenarios_mod);
    reference_machine_mod.addImport("parity_kernel", parity_kernel_mod);

    const check_step = b.step("check", "Compile the shift module and examples.");
    b.default_step.dependOn(check_step);

    const lib_check = b.addObject(.{
        .name = "shift",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lib_check.root_module.addImport("effect_ir", effect_ir_mod);
    lib_check.root_module.addImport("interpreter", interpreter_mod);
    lib_check.root_module.addImport("lowered_machine", lowered_machine_mod);
    lib_check.root_module.addImport("portable_core", portable_core_mod);
    lib_check.root_module.addImport("parity_scenarios", parity_scenarios_mod);
    lib_check.root_module.addImport("internal_kernel", internal_kernel_mod);
    lib_check.root_module.addImport("internal_program_plan", internal_program_plan_mod);
    lib_check.root_module.addImport("authoring_lowerer", authoring_lowerer_mod);
    lib_check.root_module.addImport("authoring_build_options", authoring_build_options_mod);
    lib_check.root_module.addImport("program_frontend", program_frontend_mod);
    lib_check.root_module.addImport("source_graph_engine", source_graph_engine_mod);
    lib_check.root_module.addImport("source_graph_comptime", source_graph_comptime_mod);
    lib_check.root_module.addImport("source_graph_embed", source_graph_embed_mod);
    lib_check.root_module.addImport("source_lowering", source_lowering_mod);
    lib_check.root_module.addImport("error_witness", error_witness_mod);
    check_step.dependOn(&lib_check.step);

    const root_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    root_tests.root_module.addImport("effect_ir", effect_ir_mod);
    root_tests.root_module.addImport("interpreter", interpreter_mod);
    root_tests.root_module.addImport("lowered_machine", lowered_machine_mod);
    root_tests.root_module.addImport("portable_core", portable_core_mod);
    root_tests.root_module.addImport("parity_scenarios", parity_scenarios_mod);
    root_tests.root_module.addImport("internal_kernel", internal_kernel_mod);
    root_tests.root_module.addImport("internal_program_plan", internal_program_plan_mod);
    root_tests.root_module.addImport("authoring_lowerer", authoring_lowerer_mod);
    root_tests.root_module.addImport("authoring_build_options", authoring_build_options_mod);
    root_tests.root_module.addImport("program_frontend", program_frontend_mod);
    root_tests.root_module.addImport("source_graph_engine", source_graph_engine_mod);
    root_tests.root_module.addImport("source_graph_comptime", source_graph_comptime_mod);
    root_tests.root_module.addImport("source_graph_embed", source_graph_embed_mod);
    root_tests.root_module.addImport("source_lowering", source_lowering_mod);
    root_tests.root_module.addImport("error_witness", error_witness_mod);
    root_tests.root_module.addImport("prompt_contract_support", prompt_contract_support_mod);
    root_tests.root_module.addImport("frontend_support", frontend_support_mod);
    const run_root_tests = b.addRunArtifact(root_tests);
    const test_step = b.step("test", "Run the default shift proof surface.");
    test_step.dependOn(&run_root_tests.step);

    const witness_mod = b.createModule(.{
        .root_source_file = b.path("test/witness_corpus_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    witness_mod.addImport("shift", shift_mod);
    witness_mod.addImport("reference_eval", reference_eval_mod);
    witness_mod.addImport("reference_machine", reference_machine_mod);
    witness_mod.addImport("witnesses", witnesses_mod);
    witness_mod.addImport("formal_core_registry", formal_core_registry_mod);
    witness_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const witness_tests = b.addTest(.{
        .root_module = witness_mod,
    });
    const run_witness_tests = b.addRunArtifact(witness_tests);
    test_step.dependOn(&run_witness_tests.step);

    const runtime_contract_mod = b.createModule(.{
        .root_source_file = b.path("test/runtime_contract_suite.zig"),
        .target = target,
        .optimize = optimize,
    });
    runtime_contract_mod.addImport("shift", shift_mod);
    runtime_contract_mod.addImport("prompt_support", prompt_support_mod);
    runtime_contract_mod.addImport("runtime_contract_registry", b.createModule(.{
        .root_source_file = b.path("src/runtime_contract_registry.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const survey_runtime_mod = b.createModule(.{
        .root_source_file = b.path("test/one_shot_survey/protocol_resume_transform_executes.zig"),
        .target = target,
        .optimize = optimize,
    });
    runtime_contract_mod.addImport("survey_resume_transform_executes", survey_runtime_mod);
    const runtime_contract_tests = b.addTest(.{
        .root_module = runtime_contract_mod,
    });
    const run_runtime_contract_tests = b.addRunArtifact(runtime_contract_tests);
    const runtime_contract_step = b.step("runtime-contract-suite", "Run executable lowered-runtime contract cases for the remaining runtime obligations.");
    runtime_contract_step.dependOn(&run_runtime_contract_tests.step);
    test_step.dependOn(&run_runtime_contract_tests.step);
    const compat_runtime_contract_step = b.step("compat-runtime-contract-check", "Check that legacy Runtime misuse semantics still hold through the compat shell.");
    compat_runtime_contract_step.dependOn(&run_runtime_contract_tests.step);

    const prompt_token_contract_mod = b.createModule(.{
        .root_source_file = b.path("test/prompt_token_contract_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    prompt_token_contract_mod.addImport("portable_core", portable_core_mod);
    prompt_token_contract_mod.addImport("prompt_support", prompt_support_mod);
    const prompt_token_tests = b.addTest(.{
        .root_module = prompt_token_contract_mod,
    });
    const run_prompt_token_tests = b.addRunArtifact(prompt_token_tests);
    const prompt_token_contract_step = b.step("prompt-token-contract-check", "Check explicit prompt-token construction and source-backed token allocation.");
    prompt_token_contract_step.dependOn(&run_prompt_token_tests.step);
    test_step.dependOn(&run_prompt_token_tests.step);
    const durable_session_mod = b.createModule(.{
        .root_source_file = b.path("test/durable_session_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    durable_session_mod.addImport("shift", shift_mod);
    const durable_session_tests = b.addTest(.{
        .root_module = durable_session_mod,
    });
    const run_durable_session_tests = b.addRunArtifact(durable_session_tests);
    const durable_session_resume_step = b.step("durable-session-resume-check", "Check append-only durable session replay over the interpreter core.");
    durable_session_resume_step.dependOn(&run_durable_session_tests.step);
    test_step.dependOn(&run_durable_session_tests.step);

    const backend_parity_mod = b.createModule(.{
        .root_source_file = b.path("test/backend_parity_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const kernel_parity_witness_mod = b.createModule(.{
        .root_source_file = b.path("test/kernel_parity_witness_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const backend_parity_manifest_mod = b.createModule(.{
        .root_source_file = b.path("test/backend_parity_manifest.zig"),
        .target = target,
        .optimize = optimize,
    });
    backend_parity_manifest_mod.addImport("formal_core_registry", formal_core_registry_mod);
    backend_parity_manifest_mod.addImport("parity_scenarios", parity_scenarios_mod);
    backend_parity_mod.addImport("shift", shift_mod);
    backend_parity_mod.addImport("backend_parity_manifest", backend_parity_manifest_mod);
    backend_parity_mod.addImport("parity_kernel", parity_kernel_mod);
    backend_parity_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const parity_machine_mod = b.createModule(.{
        .root_source_file = b.path("src/parity_machine.zig"),
        .target = target,
        .optimize = optimize,
    });
    parity_machine_mod.addImport("parity_kernel", parity_kernel_mod);
    parity_machine_mod.addImport("parity_scenarios", parity_scenarios_mod);
    backend_parity_mod.addImport("parity_machine", parity_machine_mod);
    backend_parity_mod.addImport("witnesses_src", witnesses_mod);
    backend_parity_mod.addImport("example_open_row_abort_basic", createShiftConsumerModule(b, "examples/open_row_abort_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_open_row_abortive_validation", createShiftConsumerModule(b, "examples/open_row_abortive_validation.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_open_row_artifact_search", createShiftConsumerModule(b, "examples/open_row_artifact_search.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_open_row_choice_basic", createShiftConsumerModule(b, "examples/open_row_choice_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_early_exit", createShiftConsumerModule(b, "examples/early_exit.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_exception_basic", createShiftConsumerModule(b, "examples/exception_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_open_row_generator", createShiftConsumerModule(b, "examples/open_row_generator.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_open_row_transform_basic", createShiftConsumerModule(b, "examples/open_row_transform_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_open_row_workflow", createShiftConsumerModule(b, "examples/open_row_workflow.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_nested_workflow", createShiftConsumerModule(b, "examples/nested_workflow.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_optional_basic", createShiftConsumerModule(b, "examples/optional_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_reader_basic", createShiftConsumerModule(b, "examples/reader_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_resource_basic", createShiftConsumerModule(b, "examples/resource_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_resume_or_return", createShiftConsumerModule(b, "examples/resume_or_return.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_state_basic", createShiftConsumerModule(b, "examples/state_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_writer_basic", createShiftConsumerModule(b, "examples/writer_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("survey_resume_transform_executes", createShiftConsumerModule(b, "test/one_shot_survey/protocol_resume_transform_executes.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    const backend_parity_tests = b.addTest(.{
        .root_module = backend_parity_mod,
    });
    const run_backend_parity_tests = b.addRunArtifact(backend_parity_tests);
    kernel_parity_witness_mod.addImport("backend_parity_manifest", backend_parity_manifest_mod);
    kernel_parity_witness_mod.addImport("parity_kernel", parity_kernel_mod);
    kernel_parity_witness_mod.addImport("parity_machine", parity_machine_mod);
    kernel_parity_witness_mod.addImport("witnesses_src", witnesses_mod);
    const kernel_parity_witness_tests = b.addTest(.{
        .root_module = kernel_parity_witness_mod,
    });
    const run_parity_witness_tests = b.addRunArtifact(kernel_parity_witness_tests);
    const backend_parity_step = b.step("kernel-parity-check", "Check the hidden lowered proof engine beneath the root execution kernel.");
    backend_parity_step.dependOn(&run_backend_parity_tests.step);
    backend_parity_step.dependOn(&run_parity_witness_tests.step);

    const proof_fixture_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_proof_fixtures.zig"),
        .target = target,
        .optimize = optimize,
    });
    proof_fixture_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const proof_fixture_exe = b.addExecutable(.{
        .name = "shift-proof-fixture-render",
        .root_module = proof_fixture_mod,
    });
    const proof_fixture_check_cmd = b.addRunArtifact(proof_fixture_exe);
    proof_fixture_check_cmd.addArg("check");
    const proof_fixture_check_step = b.step("proof-fixtures-check", "Check generated proof fixtures against the canonical scenario registry.");
    proof_fixture_check_step.dependOn(&proof_fixture_check_cmd.step);
    const proof_fixture_write_cmd = b.addRunArtifact(proof_fixture_exe);
    proof_fixture_write_cmd.addArg("write");
    const proof_fixture_write_step = b.step("proof-fixtures-write", "Refresh generated proof fixtures from the canonical scenario registry.");
    proof_fixture_write_step.dependOn(&proof_fixture_write_cmd.step);

    const authoring_lower_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_authoring_lowerings.zig"),
        .target = target,
        .optimize = optimize,
    });
    authoring_lower_mod.addImport("program_frontend", program_frontend_mod);
    const authoring_lower_exe = b.addExecutable(.{
        .name = "shift-authoring-lowering-render",
        .root_module = authoring_lower_mod,
    });
    const authoring_lower_check_cmd = b.addRunArtifact(authoring_lower_exe);
    authoring_lower_check_cmd.addArg("check");
    const authoring_lower_check_step = b.step("authoring-lowering-check", "Check lowered structured-program snapshots.");
    authoring_lower_check_step.dependOn(&authoring_lower_check_cmd.step);
    const authoring_lower_write_cmd = b.addRunArtifact(authoring_lower_exe);
    authoring_lower_write_cmd.addArg("write");
    const authoring_lower_write_step = b.step("authoring-lowering-write", "Refresh lowered structured-program snapshots.");
    authoring_lower_write_step.dependOn(&authoring_lower_write_cmd.step);

    const formal_core_render_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_formal_core.zig"),
        .target = target,
        .optimize = optimize,
    });
    formal_core_render_mod.addImport("formal_core_registry", formal_core_registry_mod);
    formal_core_render_mod.addImport("witnesses", witnesses_mod);
    const formal_core_render_exe = b.addExecutable(.{
        .name = "shift-formal-core-render",
        .root_module = formal_core_render_mod,
    });
    const formal_core_cmd = b.addRunArtifact(formal_core_render_exe);
    formal_core_cmd.addArg("check");
    const formal_core_step = b.step("formal-core", "Check the implementation-derived formal core against the root-kernel contract.");
    formal_core_step.dependOn(&formal_core_cmd.step);
    test_step.dependOn(&formal_core_cmd.step);

    const formal_core_write_cmd = b.addRunArtifact(formal_core_render_exe);
    formal_core_write_cmd.addArg("write");
    const formal_core_write_step = b.step("formal-core-write", "Refresh the generated formal core artifact.");
    formal_core_write_step.dependOn(&formal_core_write_cmd.step);

    const readme_contract_cmd = b.addSystemCommand(&.{ "sh", "test/readme_contract/run.sh" });
    const readme_contract_step = b.step("readme-contract", "Check README kernel-contract anchors and tombstone coverage.");
    readme_contract_step.dependOn(&readme_contract_cmd.step);
    test_step.dependOn(&readme_contract_cmd.step);

    const construction_boundary_cmd = b.addSystemCommand(&.{ "sh", "test/effect_construction_boundary/run.sh" });
    const construction_boundary_step = b.step("effect-construction-boundary", "Check that effect families route through the generalized substrate.");
    construction_boundary_step.dependOn(&construction_boundary_cmd.step);
    test_step.dependOn(&construction_boundary_cmd.step);

    const shared_engine_boundary_cmd = b.addSystemCommand(&.{ "sh", "test/shared_algebraic_engine_boundary/run.sh" });
    const shared_engine_boundary_step = b.step("shared-declaration-engine-boundary", "Check that surviving declaration surfaces share one internal declaration engine.");
    shared_engine_boundary_step.dependOn(&shared_engine_boundary_cmd.step);
    test_step.dependOn(&shared_engine_boundary_cmd.step);

    const size_check_mod = b.createModule(.{
        .root_source_file = b.path("test/size_check.zig"),
        .target = target,
        .optimize = optimize,
    });
    size_check_mod.addImport("shift", shift_mod);
    size_check_mod.addImport("prompt_support", prompt_support_mod);
    const size_tests = b.addTest(.{
        .root_module = size_check_mod,
    });
    const run_size_tests = b.addRunArtifact(size_tests);
    const size_step = b.step("size-check", "Run size and layout invariants.");
    test_step.dependOn(&run_size_tests.step);
    size_step.dependOn(&run_size_tests.step);

    const structured_program_mod = b.createModule(.{
        .root_source_file = b.path("test/structured_program_suite.zig"),
        .target = target,
        .optimize = optimize,
    });
    structured_program_mod.addImport("shift", shift_mod);
    structured_program_mod.addImport("program_frontend", program_frontend_mod);
    structured_program_mod.addImport("parity_kernel", parity_kernel_mod);
    structured_program_mod.addImport("parity_scenarios", parity_scenarios_mod);
    structured_program_mod.addImport("example_early_exit", createShiftConsumerModule(b, "examples/early_exit.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    structured_program_mod.addImport("example_exception_basic", createShiftConsumerModule(b, "examples/exception_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    structured_program_mod.addImport("example_nested_workflow", createShiftConsumerModule(b, "examples/nested_workflow.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    structured_program_mod.addImport("example_optional_basic", createShiftConsumerModule(b, "examples/optional_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    structured_program_mod.addImport("example_reader_basic", createShiftConsumerModule(b, "examples/reader_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    structured_program_mod.addImport("example_resume_or_return", createShiftConsumerModule(b, "examples/resume_or_return.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    structured_program_mod.addImport("example_state_basic", createShiftConsumerModule(b, "examples/state_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    const structured_program_tests = b.addTest(.{
        .root_module = structured_program_mod,
    });
    const run_structured_program_tests = b.addRunArtifact(structured_program_tests);
    const structured_program_step = b.step("structured-program-suite", "Run internal structured-program lowering and execution checks.");
    structured_program_step.dependOn(&authoring_lower_check_cmd.step);
    structured_program_step.dependOn(&run_structured_program_tests.step);

    const boundary_mod = b.createModule(.{
        .root_source_file = b.path("test/program_frontend_boundary_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    boundary_mod.addImport("program_frontend", program_frontend_mod);
    survey_runtime_mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);
    const runtime_route_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime_route_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    const runtime_stack_baseline_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime_stack_baseline.zig"),
        .target = target,
        .optimize = optimize,
    });
    runtime_stack_baseline_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    runtime_stack_baseline_mod.addImport("example_open_row_abortive_validation", createShiftConsumerModule(b, "examples/open_row_abortive_validation.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_open_row_artifact_search", createShiftConsumerModule(b, "examples/open_row_artifact_search.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_open_row_generator", createShiftConsumerModule(b, "examples/open_row_generator.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("witnesses_src", witnesses_mod);
    runtime_stack_baseline_mod.addImport("example_early_exit", createShiftConsumerModule(b, "examples/early_exit.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_exception_basic", createShiftConsumerModule(b, "examples/exception_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_nested_workflow", createShiftConsumerModule(b, "examples/nested_workflow.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_optional_basic", createShiftConsumerModule(b, "examples/optional_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_reader_basic", createShiftConsumerModule(b, "examples/reader_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_resource_basic", createShiftConsumerModule(b, "examples/resource_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_resume_or_return", createShiftConsumerModule(b, "examples/resume_or_return.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_state_basic", createShiftConsumerModule(b, "examples/state_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_writer_basic", createShiftConsumerModule(b, "examples/writer_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    const bridge_mod = b.createModule(.{
        .root_source_file = b.path("test/direct_style_bridge_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    bridge_mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);
    bridge_mod.addImport("program_bridge", program_bridge_mod);
    bridge_mod.addImport("direct_style_bridge_open_row_abortive_validation", createBridgeExampleModule(b, "test/direct_style_bridge/open_row_abortive_validation.zig", target, optimize, .{ .name = "example_open_row_abortive_validation", .mod = createShiftConsumerModule(b, "examples/open_row_abortive_validation.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_open_row_artifact_search", createBridgeExampleModule(b, "test/direct_style_bridge/open_row_artifact_search.zig", target, optimize, .{ .name = "example_open_row_artifact_search", .mod = createShiftConsumerModule(b, "examples/open_row_artifact_search.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_early_exit", createBridgeExampleModule(b, "test/direct_style_bridge/early_exit.zig", target, optimize, .{ .name = "example_early_exit", .mod = createShiftConsumerModule(b, "examples/early_exit.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_open_row_generator", createBridgeExampleModule(b, "test/direct_style_bridge/open_row_generator.zig", target, optimize, .{ .name = "example_open_row_generator", .mod = createShiftConsumerModule(b, "examples/open_row_generator.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_nested_workflow", createBridgeExampleModule(b, "test/direct_style_bridge/nested_workflow.zig", target, optimize, .{ .name = "example_nested_workflow", .mod = createShiftConsumerModule(b, "examples/nested_workflow.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_resource_basic", createBridgeExampleModule(b, "test/direct_style_bridge/resource_basic.zig", target, optimize, .{ .name = "example_resource_basic", .mod = createShiftConsumerModule(b, "examples/resource_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_resume_or_return", createBridgeExampleModule(b, "test/direct_style_bridge/resume_or_return.zig", target, optimize, .{ .name = "example_resume_or_return", .mod = createShiftConsumerModule(b, "examples/resume_or_return.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_state_basic", createBridgeExampleModule(b, "test/direct_style_bridge/state_basic.zig", target, optimize, .{ .name = "example_state_basic", .mod = createShiftConsumerModule(b, "examples/state_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_reader_basic", createBridgeExampleModule(b, "test/direct_style_bridge/reader_basic.zig", target, optimize, .{ .name = "example_reader_basic", .mod = createShiftConsumerModule(b, "examples/reader_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_optional_basic", createBridgeExampleModule(b, "test/direct_style_bridge/optional_basic.zig", target, optimize, .{ .name = "example_optional_basic", .mod = createShiftConsumerModule(b, "examples/optional_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_exception_basic", createBridgeExampleModule(b, "test/direct_style_bridge/exception_basic.zig", target, optimize, .{ .name = "example_exception_basic", .mod = createShiftConsumerModule(b, "examples/exception_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_writer_basic", createBridgeExampleModule(b, "test/direct_style_bridge/writer_basic.zig", target, optimize, .{ .name = "example_writer_basic", .mod = createShiftConsumerModule(b, "examples/writer_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    const bridge_boundary_mod = b.createModule(.{
        .root_source_file = b.path("test/direct_style_bridge_boundary_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    bridge_boundary_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    bridge_boundary_mod.addImport("direct_style_bridge_early_exit", createBridgeExampleModule(b, "test/direct_style_bridge/early_exit.zig", target, optimize, .{ .name = "example_early_exit", .mod = createShiftConsumerModule(b, "examples/early_exit.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_boundary_mod.addImport("program_bridge", program_bridge_mod);
    bridge_boundary_mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);
    const boundary_tests = b.addTest(.{
        .root_module = boundary_mod,
    });
    const bridge_tests = b.addTest(.{
        .root_module = bridge_mod,
    });
    const bridge_boundary_tests = b.addTest(.{
        .root_module = bridge_boundary_mod,
    });
    const run_boundary_tests = b.addRunArtifact(boundary_tests);
    const run_bridge_tests = b.addRunArtifact(bridge_tests);
    run_bridge_tests.setName("hidden direct-style bridge parity runner");
    const run_bridge_boundary_tests = b.addRunArtifact(bridge_boundary_tests);
    const boundary_step = b.step("direct-style-boundary", "Run explicit boundary checks for unsupported raw direct-style lowering.");
    boundary_step.dependOn(&run_bridge_tests.step);
    boundary_step.dependOn(&run_boundary_tests.step);
    boundary_step.dependOn(&run_bridge_boundary_tests.step);

    const source_lowering_corpus_mod = b.createModule(.{
        .root_source_file = b.path("test/source_lowering_corpus_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_corpus_mod.addImport("source_lowering_registry", source_lowering_registry_mod);
    source_lowering_corpus_mod.addImport("source_lowering", source_lowering_mod);
    source_lowering_corpus_mod.addImport("lowered_machine", lowered_machine_mod);
    source_lowering_corpus_mod.addImport("parity_scenarios", parity_scenarios_mod);
    source_lowering_corpus_mod.addImport("source_fixture_branch_resume", createPlainModule(b, "test/source_lowering_corpus/fixtures/branch_resume.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_defer_resume", createPlainModule(b, "test/source_lowering_corpus/fixtures/defer_resume.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_errdefer_error", createPlainModule(b, "test/source_lowering_corpus/fixtures/errdefer_error.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_helper_call_resume", createPlainModule(b, "test/source_lowering_corpus/fixtures/helper_call_resume.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_local_mutation_resume", createPlainModule(b, "test/source_lowering_corpus/fixtures/local_mutation_resume.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_loop_resume", createPlainModule(b, "test/source_lowering_corpus/fixtures/loop_resume.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_nested_prompt_static_redelim", createPlainModule(b, "test/source_lowering_corpus/fixtures/nested_prompt_static_redelim.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_typed_error_try", createPlainModule(b, "test/source_lowering_corpus/fixtures/typed_error_try.zig", target, optimize));
    const src_lower_corpus_tests = b.addTest(.{
        .root_module = source_lowering_corpus_mod,
    });
    const run_src_lower_corpus_tests = b.addRunArtifact(src_lower_corpus_tests);

    const source_lowering_boundary_mod = b.createModule(.{
        .root_source_file = b.path("test/source_lowering_boundary_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_boundary_mod.addImport("source_lowering_registry", source_lowering_registry_mod);
    source_lowering_boundary_mod.addImport("source_lowering", source_lowering_mod);
    source_lowering_boundary_mod.addImport("shift", shift_mod);
    const src_lower_boundary_tests = b.addTest(.{
        .root_module = source_lowering_boundary_mod,
    });
    const run_src_lower_boundary_tests = b.addRunArtifact(src_lower_boundary_tests);

    const source_lowering_promoted_mod = b.createModule(.{
        .root_source_file = b.path("test/source_lowering_promoted_cohort_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_promoted_mod.addImport("source_lowering", source_lowering_mod);
    source_lowering_promoted_mod.addImport("parity_scenarios", parity_scenarios_mod);
    source_lowering_promoted_mod.addImport("promoted_example_early_exit", createShiftConsumerModule(b, "examples/early_exit.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_open_row_abort_basic", createShiftConsumerModule(b, "examples/open_row_abort_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_open_row_abortive_validation", createShiftConsumerModule(b, "examples/open_row_abortive_validation.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_open_row_artifact_search", createShiftConsumerModule(b, "examples/open_row_artifact_search.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_open_row_choice_basic", createShiftConsumerModule(b, "examples/open_row_choice_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_open_row_generator", createShiftConsumerModule(b, "examples/open_row_generator.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_open_row_transform_basic", createShiftConsumerModule(b, "examples/open_row_transform_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_open_row_workflow", createShiftConsumerModule(b, "examples/open_row_workflow.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_resume_or_return", createShiftConsumerModule(b, "examples/resume_or_return.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_nested_workflow", createShiftConsumerModule(b, "examples/nested_workflow.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_state_basic", createShiftConsumerModule(b, "examples/state_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_reader_basic", createShiftConsumerModule(b, "examples/reader_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_optional_basic", createShiftConsumerModule(b, "examples/optional_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_exception_basic", createShiftConsumerModule(b, "examples/exception_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_resource_basic", createShiftConsumerModule(b, "examples/resource_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_writer_basic", createShiftConsumerModule(b, "examples/writer_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = null }));
    const src_lower_promoted_tests = b.addTest(.{
        .root_module = source_lowering_promoted_mod,
    });
    const run_src_lower_promoted_tests = b.addRunArtifact(src_lower_promoted_tests);

    const source_lowering_completion_mod = b.createModule(.{
        .root_source_file = b.path("test/source_lowering_completion_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_completion_mod.addImport("source_lowering", source_lowering_mod);
    source_lowering_completion_mod.addImport("parity_scenarios", parity_scenarios_mod);
    source_lowering_completion_mod.addImport("example_resource_basic", createShiftConsumerModule(b, "examples/resource_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = null }));
    source_lowering_completion_mod.addImport("example_writer_basic", createShiftConsumerModule(b, "examples/writer_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = null }));
    const src_lower_completion_tests = b.addTest(.{
        .root_module = source_lowering_completion_mod,
    });
    const run_src_lower_completion_tests = b.addRunArtifact(src_lower_completion_tests);

    const open_row_lowering_mod = b.createModule(.{
        .root_source_file = b.path("test/open_row_lowering_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    open_row_lowering_mod.addImport("effect_ir", effect_ir_mod);
    open_row_lowering_mod.addImport("source_lowering", source_lowering_mod);
    open_row_lowering_mod.addImport("program_frontend", program_frontend_mod);
    open_row_lowering_mod.addImport("shift", shift_mod);
    open_row_lowering_mod.addImport("example_open_row_linear_helper_body", createShiftConsumerModule(b, "examples/open_row_linear_helper_body.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_state_writer", createShiftConsumerModule(b, "examples/open_row_state_writer.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_recursive_writer", createShiftConsumerModule(b, "examples/open_row_recursive_writer.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_recursive_cross_writer", createShiftConsumerModule(b, "examples/open_row_recursive_cross_writer.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    const open_row_lowering_tests = b.addTest(.{
        .root_module = open_row_lowering_mod,
    });
    const run_open_row_lowering_tests = b.addRunArtifact(open_row_lowering_tests);

    const source_ownership_probe_mod = b.createModule(.{
        .root_source_file = b.path("test/source_ownership_probe_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_ownership_probe_mod.addImport("shift", shift_mod);
    const source_ownership_probe_tests = b.addTest(.{
        .root_module = source_ownership_probe_mod,
    });
    const run_src_ownership_probe_tests = b.addRunArtifact(source_ownership_probe_tests);

    const src_lower_witness_mod = b.createModule(.{
        .root_source_file = b.path("test/source_lowering_witness_completion_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    src_lower_witness_mod.addImport("source_lowering", source_lowering_mod);
    src_lower_witness_mod.addImport("parity_scenarios", parity_scenarios_mod);
    src_lower_witness_mod.addImport("witness_sources", witness_sources_mod);
    const src_lower_witness_tests = b.addTest(.{
        .root_module = src_lower_witness_mod,
    });
    const run_src_lower_witness_tests = b.addRunArtifact(src_lower_witness_tests);

    const src_lower_reject_mod = b.createModule(.{
        .root_source_file = b.path("test/source_lowering_rejection_corpus_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    src_lower_reject_mod.addImport("source_lowering", source_lowering_mod);
    const src_lower_reject_tests = b.addTest(.{
        .root_module = src_lower_reject_mod,
    });
    const run_src_lower_reject_tests = b.addRunArtifact(src_lower_reject_tests);

    const source_lowering_contract_cmd = b.addSystemCommand(&.{ "sh", "test/source_lowering_contract/run.sh" });

    const source_lowering_matrix_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_source_lowering_matrix.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_matrix_mod.addImport("source_lowering_registry", source_lowering_registry_mod);
    const source_lowering_matrix_exe = b.addExecutable(.{
        .name = "shift-source-lowering-matrix",
        .root_module = source_lowering_matrix_mod,
    });
    const src_lower_matrix_check = b.addRunArtifact(source_lowering_matrix_exe);
    src_lower_matrix_check.addArg("check");
    const src_lower_matrix_chk_step = b.step("source-lowering-matrix-check", "Check the source-lowering matrix artifact.");
    src_lower_matrix_chk_step.dependOn(&src_lower_matrix_check.step);
    const src_lower_matrix_write = b.addRunArtifact(source_lowering_matrix_exe);
    src_lower_matrix_write.addArg("write");
    const src_lower_matrix_wr_step = b.step("source-lowering-matrix-write", "Refresh the source-lowering matrix artifact.");
    src_lower_matrix_wr_step.dependOn(&src_lower_matrix_write.step);

    const source_lowering_tool_mod = b.createModule(.{
        .root_source_file = b.path("tools/shift_source_lower.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_tool_mod.addImport("source_lowering", source_lowering_mod);
    source_lowering_tool_mod.addImport("lowered_machine", lowered_machine_mod);
    source_lowering_tool_mod.addImport("error_witness", error_witness_mod);
    const source_lowering_tool_exe = b.addExecutable(.{
        .name = "shift-source-lower",
        .root_module = source_lowering_tool_mod,
    });
    const source_lowering_tool_install = b.addInstallArtifact(source_lowering_tool_exe, .{});
    const source_lowering_tool_step = b.step("source-lower", "Build the internal source-lowering tool.");
    source_lowering_tool_step.dependOn(&source_lowering_tool_exe.step);
    source_lowering_tool_step.dependOn(&source_lowering_tool_install.step);
    const src_lower_tool_contract = b.addSystemCommand(&.{ "sh", "test/source_lowering_tool_contract/run.sh" });
    src_lower_tool_contract.step.dependOn(&source_lowering_tool_install.step);
    const src_lower_tool_contract_step = b.step("source-lowering-tool-contract", "Check internal source-lowering tool rejected and accepted emission contracts.");
    src_lower_tool_contract_step.dependOn(&src_lower_tool_contract.step);
    const src_lower_err_wit_cmd = b.addSystemCommand(&.{ "sh", "test/source_lowering_error_witness/run.sh" });
    src_lower_err_wit_cmd.step.dependOn(&source_lowering_tool_install.step);
    const src_lower_err_wit_step = b.step("source-lowering-error-witness-check", "Check that the source-lowering tool emits the checked public witness surface.");
    src_lower_err_wit_step.dependOn(&src_lower_err_wit_cmd.step);
    const dur_migrate_tool_mod = b.createModule(.{
        .root_source_file = b.path("tools/shift_durable_migrate.zig"),
        .target = target,
        .optimize = optimize,
    });
    dur_migrate_tool_mod.addImport("shift", shift_mod);
    const dur_migrate_tool_exe = b.addExecutable(.{
        .name = "shift-durable-migrate",
        .root_module = dur_migrate_tool_mod,
    });
    const dur_migrate_tool_install = b.addInstallArtifact(dur_migrate_tool_exe, .{});
    const dur_migrate_tool_step = b.step("durable-migration-tool", "Build the durable migration tool.");
    dur_migrate_tool_step.dependOn(&dur_migrate_tool_exe.step);
    dur_migrate_tool_step.dependOn(&dur_migrate_tool_install.step);
    const dur_migrate_contract = b.addSystemCommand(&.{ "sh", "test/durable_migration_tool/run.sh" });
    dur_migrate_contract.step.dependOn(&dur_migrate_tool_install.step);
    const dur_migrate_contract_step = b.step("durable-migration-tool-contract", "Check durable migration inspect and upgrade behavior through the tool surface.");
    dur_migrate_contract_step.dependOn(&dur_migrate_contract.step);
    test_step.dependOn(&dur_migrate_contract.step);
    const public_error_api_ban_cmd = b.addSystemCommand(&.{ "sh", "test/public_error_api_ban/run.sh" });
    const public_error_api_ban_step = b.step("public-error-api-ban", "Fail closed if retired public root spellings reappear.");
    public_error_api_ban_step.dependOn(&public_error_api_ban_cmd.step);
    const public_root_snapshot_mod = b.createModule(.{
        .root_source_file = b.path("tools/check_public_root_contract_snapshot.zig"),
        .target = target,
        .optimize = optimize,
    });
    const public_root_snapshot_exe = b.addExecutable(.{
        .name = "shift-public-root-contract-snapshot",
        .root_module = public_root_snapshot_mod,
    });
    const public_root_snapshot_cmd = b.addRunArtifact(public_root_snapshot_exe);
    const public_root_snapshot_step = b.step("public-root-contract-snapshot-check", "Check the root-kernel public tombstone snapshot.");
    public_root_snapshot_step.dependOn(&public_root_snapshot_cmd.step);
    const interpreter_portability_mod = b.createModule(.{
        .root_source_file = b.path("tools/check_interpreter_portability.zig"),
        .target = target,
        .optimize = optimize,
    });
    const interpreter_portability_exe = b.addExecutable(.{
        .name = "shift-interpreter-portability-check",
        .root_module = interpreter_portability_mod,
    });
    const interpreter_portability_cmd = b.addRunArtifact(interpreter_portability_exe);
    const interpreter_portability_step = b.step("interpreter-portability-check", "Fail closed if the interpreter core takes on TLS or thread-affinity assumptions.");
    interpreter_portability_step.dependOn(&interpreter_portability_cmd.step);
    const portable_core_mod_check = b.createModule(.{
        .root_source_file = b.path("tools/check_portable_core.zig"),
        .target = target,
        .optimize = optimize,
    });
    const portable_core_exe = b.addExecutable(.{
        .name = "shift-portable-core-check",
        .root_module = portable_core_mod_check,
    });
    const portable_core_cmd = b.addRunArtifact(portable_core_exe);
    const portable_core_step = b.step("portable-core-check", "Fail closed if the portable core takes on TLS or thread-affinity assumptions.");
    portable_core_step.dependOn(&portable_core_cmd.step);
    const retired_lane_inventory_mod = b.createModule(.{
        .root_source_file = b.path("tools/check_retired_lane_inventory.zig"),
        .target = target,
        .optimize = optimize,
    });
    const retired_lane_inventory_exe = b.addExecutable(.{
        .name = "shift-retired-lane-inventory",
        .root_module = retired_lane_inventory_mod,
    });
    const retired_lane_inventory_cmd = b.addRunArtifact(retired_lane_inventory_exe);
    const retired_lane_inventory_step = b.step("retired-lane-inventory-check", "Check that retired lane vocabulary stays out of proof-facing files.");
    retired_lane_inventory_step.dependOn(&retired_lane_inventory_cmd.step);
    const error_witness_equivalence_cmd = b.addSystemCommand(&.{ "sh", "test/error_witness_equivalence/run.sh" });
    error_witness_equivalence_cmd.step.dependOn(&source_lowering_tool_install.step);
    const error_witness_equivalence_step = b.step("error-witness-equivalence-check", "Check that canonical source-lowering witnesses expose an equivalent public runtime/setup witness surface across example cases.");
    error_witness_equivalence_step.dependOn(&error_witness_equivalence_cmd.step);

    test_step.dependOn(src_lower_err_wit_step);
    test_step.dependOn(public_error_api_ban_step);
    test_step.dependOn(public_root_snapshot_step);
    test_step.dependOn(interpreter_portability_step);
    test_step.dependOn(portable_core_step);
    test_step.dependOn(retired_lane_inventory_step);
    test_step.dependOn(error_witness_equivalence_step);

    const source_lowering_coverage_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_source_lowering_coverage_matrix.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_coverage_mod.addImport("source_lowering_coverage_registry", src_lower_cov_registry_mod);
    const source_lowering_coverage_exe = b.addExecutable(.{
        .name = "shift-source-lowering-coverage-matrix",
        .root_module = source_lowering_coverage_mod,
    });
    const src_lower_cov_check = b.addRunArtifact(source_lowering_coverage_exe);
    src_lower_cov_check.addArg("check");
    const src_lower_cov_chk_step = b.step("source-lowering-coverage-check", "Check the source-lowering coverage matrix artifact.");
    src_lower_cov_chk_step.dependOn(&src_lower_cov_check.step);
    const src_lower_cov_write = b.addRunArtifact(source_lowering_coverage_exe);
    src_lower_cov_write.addArg("write");
    const src_lower_cov_wr_step = b.step("source-lowering-coverage-matrix-write", "Refresh the source-lowering coverage matrix artifact.");
    src_lower_cov_wr_step.dependOn(&src_lower_cov_write.step);

    const lowering_equivalence_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_lowering_equivalence_report.zig"),
        .target = target,
        .optimize = optimize,
    });
    lowering_equivalence_mod.addImport("source_lowering", source_lowering_mod);
    lowering_equivalence_mod.addImport("source_lowering_coverage_registry", src_lower_cov_registry_mod);
    lowering_equivalence_mod.addImport("source_lowering_registry", source_lowering_registry_mod);
    lowering_equivalence_mod.addImport("parity_scenarios", parity_scenarios_mod);
    lowering_equivalence_mod.addImport("lowered_machine", lowered_machine_mod);
    lowering_equivalence_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    lowering_equivalence_mod.addImport("program_bridge", program_bridge_mod);
    lowering_equivalence_mod.addImport("shipped_open_row_corpus_registry", shipped_open_row_corpus_mod);
    const lowering_equivalence_exe = b.addExecutable(.{
        .name = "shift-lowering-equivalence-report",
        .root_module = lowering_equivalence_mod,
    });
    const lower_eq_check = b.addRunArtifact(lowering_equivalence_exe);
    lower_eq_check.addArg("check");
    const lower_eq_chk_step = b.step("lowering-equivalence-report-check", "Check the legacy-named lowering admission report artifact.");
    lower_eq_chk_step.dependOn(&lower_eq_check.step);
    const lower_eq_write = b.addRunArtifact(lowering_equivalence_exe);
    lower_eq_write.addArg("write");
    const lower_eq_wr_step = b.step("lowering-equivalence-report-write", "Refresh the legacy-named lowering admission report artifact.");
    lower_eq_wr_step.dependOn(&lower_eq_write.step);

    const lowering_rejection_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_lowering_rejection_report.zig"),
        .target = target,
        .optimize = optimize,
    });
    lowering_rejection_mod.addImport("source_lowering", source_lowering_mod);
    const lowering_rejection_exe = b.addExecutable(.{
        .name = "shift-lowering-rejection-report",
        .root_module = lowering_rejection_mod,
    });
    const lower_reject_check = b.addRunArtifact(lowering_rejection_exe);
    lower_reject_check.addArg("check");
    const lower_reject_chk_step = b.step("lowering-rejection-report-check", "Check the lowering rejection report artifact.");
    lower_reject_chk_step.dependOn(&lower_reject_check.step);
    const lower_reject_write = b.addRunArtifact(lowering_rejection_exe);
    lower_reject_write.addArg("write");
    const lower_reject_wr_step = b.step("lowering-rejection-report-write", "Refresh the lowering rejection report artifact.");
    lower_reject_wr_step.dependOn(&lower_reject_write.step);

    const witness_admission_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/witness_admission_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    witness_admission_registry_mod.addImport("formal_core_registry", formal_core_registry_mod);
    bridge_manifest_mod.addImport("witness_admission_registry", witness_admission_registry_mod);
    bridge_boundary_mod.addImport("witness_admission_registry", witness_admission_registry_mod);
    const witness_admission_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_witness_admission_matrix.zig"),
        .target = target,
        .optimize = optimize,
    });
    witness_admission_mod.addImport("witness_admission_registry", witness_admission_registry_mod);
    const witness_admission_exe = b.addExecutable(.{
        .name = "shift-witness-admission-matrix",
        .root_module = witness_admission_mod,
    });
    const witness_admission_check_cmd = b.addRunArtifact(witness_admission_exe);
    witness_admission_check_cmd.addArg("check");
    const witness_admission_check_step = b.step("witness-admission-matrix-check", "Check the witness admission matrix.");
    witness_admission_check_step.dependOn(&witness_admission_check_cmd.step);
    const witness_admission_write_cmd = b.addRunArtifact(witness_admission_exe);
    witness_admission_write_cmd.addArg("write");
    const witness_admission_write_step = b.step("witness-admission-matrix-write", "Refresh the witness admission matrix.");
    witness_admission_write_step.dependOn(&witness_admission_write_cmd.step);

    const source_lowering_gauntlet_step = b.step("kernel-source-lowering-check", "Check the internal source-lowering proof surface beneath the root execution kernel.");
    source_lowering_gauntlet_step.dependOn(&run_src_lower_corpus_tests.step);
    source_lowering_gauntlet_step.dependOn(&run_src_lower_boundary_tests.step);
    source_lowering_gauntlet_step.dependOn(&run_src_lower_promoted_tests.step);
    source_lowering_gauntlet_step.dependOn(&run_src_lower_completion_tests.step);
    source_lowering_gauntlet_step.dependOn(&run_open_row_lowering_tests.step);
    source_lowering_gauntlet_step.dependOn(&run_src_ownership_probe_tests.step);
    source_lowering_gauntlet_step.dependOn(&run_src_lower_witness_tests.step);
    source_lowering_gauntlet_step.dependOn(&run_src_lower_reject_tests.step);
    source_lowering_gauntlet_step.dependOn(&source_lowering_contract_cmd.step);
    source_lowering_gauntlet_step.dependOn(&src_lower_matrix_check.step);
    source_lowering_gauntlet_step.dependOn(&src_lower_tool_contract.step);
    source_lowering_gauntlet_step.dependOn(lower_eq_chk_step);
    source_lowering_gauntlet_step.dependOn(lower_reject_chk_step);
    test_step.dependOn(source_lowering_gauntlet_step);

    const scorecard_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_surface_truth_scorecard.zig"),
        .target = target,
        .optimize = optimize,
    });
    scorecard_mod.addImport("program_frontend", program_frontend_mod);
    scorecard_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    scorecard_mod.addImport("source_lowering_registry", source_lowering_registry_mod);
    scorecard_mod.addImport("source_lowering_coverage_registry", src_lower_cov_registry_mod);
    const scorecard_exe = b.addExecutable(.{
        .name = "shift-surface-truth-scorecard",
        .root_module = scorecard_mod,
    });
    const scorecard_check_cmd = b.addRunArtifact(scorecard_exe);
    scorecard_check_cmd.addArg("check");
    const scorecard_check_step = b.step("surface-truth-scorecard-check", "Check the machine-readable surface-truth scorecard.");
    scorecard_check_step.dependOn(&scorecard_check_cmd.step);
    const scorecard_write_cmd = b.addRunArtifact(scorecard_exe);
    scorecard_write_cmd.addArg("write");
    const scorecard_write_step = b.step("surface-truth-scorecard-write", "Refresh the machine-readable surface-truth scorecard.");
    scorecard_write_step.dependOn(&scorecard_write_cmd.step);

    const route_matrix_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_runtime_route_matrix.zig"),
        .target = target,
        .optimize = optimize,
    });
    route_matrix_mod.addImport("runtime_route_registry", runtime_route_registry_mod);
    const route_matrix_exe = b.addExecutable(.{
        .name = "shift-runtime-route-matrix",
        .root_module = route_matrix_mod,
    });
    const route_matrix_check_cmd = b.addRunArtifact(route_matrix_exe);
    route_matrix_check_cmd.addArg("check");
    const route_matrix_check_step = b.step("runtime-route-matrix-check", "Check the runtime route matrix artifact.");
    route_matrix_check_step.dependOn(&route_matrix_check_cmd.step);
    const route_matrix_write_cmd = b.addRunArtifact(route_matrix_exe);
    route_matrix_write_cmd.addArg("write");
    const route_matrix_write_step = b.step("runtime-route-matrix-write", "Refresh the runtime route matrix artifact.");
    route_matrix_write_step.dependOn(&route_matrix_write_cmd.step);

    const obligation_matrix_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime_obligation_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    const obligation_matrix_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_runtime_obligation_matrix.zig"),
        .target = target,
        .optimize = optimize,
    });
    obligation_matrix_mod.addImport("runtime_obligation_registry", obligation_matrix_registry_mod);
    const obligation_matrix_exe = b.addExecutable(.{
        .name = "shift-runtime-obligation-matrix",
        .root_module = obligation_matrix_mod,
    });
    const obligation_matrix_check_cmd = b.addRunArtifact(obligation_matrix_exe);
    obligation_matrix_check_cmd.addArg("check");
    const obligation_matrix_check_step = b.step("runtime-obligation-matrix-check", "Check the runtime obligation matrix artifact.");
    obligation_matrix_check_step.dependOn(&obligation_matrix_check_cmd.step);
    const obligation_matrix_write_cmd = b.addRunArtifact(obligation_matrix_exe);
    obligation_matrix_write_cmd.addArg("write");
    const obligation_matrix_write_step = b.step("runtime-obligation-matrix-write", "Refresh the runtime obligation matrix artifact.");
    obligation_matrix_write_step.dependOn(&obligation_matrix_write_cmd.step);

    const error_surface_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime_error_surface_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    error_surface_registry_mod.addImport("error_witness", error_witness_mod);
    const error_surface_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_runtime_error_surface_matrix.zig"),
        .target = target,
        .optimize = optimize,
    });
    error_surface_mod.addImport("runtime_error_surface_registry", error_surface_registry_mod);
    const error_surface_exe = b.addExecutable(.{
        .name = "shift-runtime-error-surface-matrix",
        .root_module = error_surface_mod,
    });
    const error_surface_check_cmd = b.addRunArtifact(error_surface_exe);
    error_surface_check_cmd.addArg("check");
    const error_surface_check_step = b.step("runtime-error-surface-matrix-check", "Check the public runtime error surface matrix.");
    error_surface_check_step.dependOn(&error_surface_check_cmd.step);
    const error_surface_write_cmd = b.addRunArtifact(error_surface_exe);
    error_surface_write_cmd.addArg("write");
    const error_surface_write_step = b.step("runtime-error-surface-matrix-write", "Refresh the public runtime error surface matrix.");
    error_surface_write_step.dependOn(&error_surface_write_cmd.step);

    const lexical_witness_runners_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_witness_support.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_witness_runners_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
    const structured_witness_runner_mod = b.createModule(.{
        .root_source_file = b.path("test/structured_witness_runner_suite.zig"),
        .target = target,
        .optimize = optimize,
    });
    structured_witness_runner_mod.addImport("lexical_witness_runners", lexical_witness_runners_mod);
    structured_witness_runner_mod.addImport("parity_kernel", parity_kernel_mod);
    structured_witness_runner_mod.addImport("program_frontend", program_frontend_mod);
    const structured_witness_tests = b.addTest(.{
        .root_module = structured_witness_runner_mod,
    });
    const run_structured_witness_tests = b.addRunArtifact(structured_witness_tests);
    structured_program_step.dependOn(&run_structured_witness_tests.step);
    test_step.dependOn(&run_structured_witness_tests.step);

    const bridge_witness_runner_mod = b.createModule(.{
        .root_source_file = b.path("test/direct_style_bridge_witness_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    bridge_witness_runner_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    bridge_witness_runner_mod.addImport("lexical_witness_runners", lexical_witness_runners_mod);
    bridge_witness_runner_mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);
    const bridge_witness_tests = b.addTest(.{
        .root_module = bridge_witness_runner_mod,
    });
    const run_bridge_witness_tests = b.addRunArtifact(bridge_witness_tests);
    test_step.dependOn(&run_bridge_witness_tests.step);

    const lexical_witness_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_witness_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_witness_mod.addImport("shift", shift_mod);
    lexical_witness_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
    lexical_witness_mod.addImport("parity_scenarios", parity_scenarios_mod);
    lexical_witness_mod.addImport("lexical_witness_runners", lexical_witness_runners_mod);
    const lexical_witness_tests = b.addTest(.{
        .root_module = lexical_witness_mod,
    });
    const run_lexical_witness_tests = b.addRunArtifact(lexical_witness_tests);
    const lexical_witness_step = b.step("lexical-witness-suite", "Run the lexical witness proof surface.");
    lexical_witness_step.dependOn(&run_lexical_witness_tests.step);
    test_step.dependOn(&run_lexical_witness_tests.step);

    const lexical_with_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_with_mod.addImport("shift", lexical_runtime_internal_mod);
    const lexical_with_tests = b.addTest(.{
        .root_module = lexical_with_mod,
    });
    const run_lexical_with_tests = b.addRunArtifact(lexical_with_tests);
    const lexical_with_step = b.step("lexical-with-suite", "Run the lexical descriptor/runtime helper proof surface.");
    lexical_with_step.dependOn(&run_lexical_with_tests.step);
    test_step.dependOn(&run_lexical_with_tests.step);
    const cleanup_contract_step = b.step("cleanup-contract-check", "Check cleanup-stack and resource cleanup contracts through the existing lexical/resource proof surface.");
    cleanup_contract_step.dependOn(&run_lexical_with_tests.step);

    const shipped_frontier_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/shipped_surface_frontier_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    const shipped_frontier_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_shipped_surface_frontier_matrix.zig"),
        .target = target,
        .optimize = optimize,
    });
    shipped_frontier_mod.addImport("shipped_surface_frontier_registry", shipped_frontier_registry_mod);
    const shipped_frontier_exe = b.addExecutable(.{
        .name = "shift-shipped-surface-frontier-matrix",
        .root_module = shipped_frontier_mod,
    });
    const shipped_frontier_check_cmd = b.addRunArtifact(shipped_frontier_exe);
    shipped_frontier_check_cmd.addArg("check");
    const shipped_frontier_check_step = b.step("shipped-surface-frontier-matrix-check", "Check the shipped-surface frontier matrix.");
    shipped_frontier_check_step.dependOn(&shipped_frontier_check_cmd.step);
    const shipped_frontier_write_cmd = b.addRunArtifact(shipped_frontier_exe);
    shipped_frontier_write_cmd.addArg("write");
    const shipped_frontier_write_step = b.step("shipped-surface-frontier-matrix-write", "Refresh the shipped-surface frontier matrix.");
    shipped_frontier_write_step.dependOn(&shipped_frontier_write_cmd.step);

    const no_raw_repo_refs_cmd = b.addSystemCommand(&.{ "sh", "test/no_raw_repo_refs/run.sh" });
    const no_raw_repo_refs_step = b.step("no-raw-repo-refs-check", "Fail closed when repo-facing raw runtime references remain.");
    no_raw_repo_refs_step.dependOn(&no_raw_repo_refs_cmd.step);

    const frontend_feature_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/frontend_feature_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    const frontend_feature_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_frontend_feature_matrix.zig"),
        .target = target,
        .optimize = optimize,
    });
    frontend_feature_mod.addImport("frontend_feature_registry", frontend_feature_registry_mod);
    const frontend_feature_exe = b.addExecutable(.{
        .name = "shift-frontend-feature-matrix",
        .root_module = frontend_feature_mod,
    });
    const frontend_feature_check_cmd = b.addRunArtifact(frontend_feature_exe);
    frontend_feature_check_cmd.addArg("check");
    const frontend_feature_check_step = b.step("frontend-feature-matrix-check", "Check the canonical frontend feature matrix.");
    frontend_feature_check_step.dependOn(&frontend_feature_check_cmd.step);
    const frontend_feature_write_cmd = b.addRunArtifact(frontend_feature_exe);
    frontend_feature_write_cmd.addArg("write");
    const frontend_feature_write_step = b.step("frontend-feature-matrix-write", "Refresh the canonical frontend feature matrix.");
    frontend_feature_write_step.dependOn(&frontend_feature_write_cmd.step);

    const shipped_backend_cmd = b.addSystemCommand(&.{ "sh", "test/shipped_backend_contract/run.sh" });
    shipped_backend_cmd.setName("hidden shipped backend contract runner");
    const shipped_backend_step = b.step("shipped-backend-contract", "Check the shipped backend contract guard.");
    shipped_backend_step.dependOn(&shipped_backend_cmd.step);

    test_step.dependOn(&authoring_lower_check_cmd.step);
    test_step.dependOn(&run_bridge_tests.step);
    test_step.dependOn(&run_boundary_tests.step);
    test_step.dependOn(&run_bridge_boundary_tests.step);
    test_step.dependOn(&run_structured_program_tests.step);
    test_step.dependOn(&shipped_backend_cmd.step);

    const compile_fail_step = b.step("compile-fail", "Verify compile-fail misuse fixtures.");
    const one_shot_success_fixtures = [_]struct {
        name: []const u8,
        path: []const u8,
    }{
        .{ .name = "one-shot-protocol-resume-transform", .path = "test/one_shot_survey/protocol_resume_transform_compiles.zig" },
        .{ .name = "one-shot-protocol-erroring-resume-transform", .path = "test/one_shot_survey/protocol_erroring_resume_transform_compiles.zig" },
        .{ .name = "one-shot-protocol-direct-return", .path = "test/one_shot_survey/protocol_direct_return_compiles.zig" },
        .{ .name = "one-shot-protocol-erroring-direct-return", .path = "test/one_shot_survey/protocol_erroring_direct_return_compiles.zig" },
        .{ .name = "one-shot-protocol-resume-or-return", .path = "test/one_shot_survey/protocol_resume_or_return_compiles.zig" },
        .{ .name = "one-shot-protocol-erroring-resume-or-return", .path = "test/one_shot_survey/protocol_erroring_resume_or_return_compiles.zig" },
    };
    inline for (one_shot_success_fixtures) |fixture| {
        const fixture_mod = createShiftPromptFixtureModule(b, fixture.path, target, optimize, .{
            .shift_mod = shift_mod,
            .prompt_support_mod = prompt_support_mod,
            .with_api_mod = with_api_mod,
        });
        const fixture_check = b.addObject(.{
            .name = fixture.name,
            .root_module = fixture_mod,
        });
        const fixture_check_step = b.step(fixture.name, "Compile one plain-Zig one-shot survey success fixture.");
        fixture_check_step.dependOn(&fixture_check.step);
    }
    const one_shot_runtime_mod = b.createModule(.{
        .root_source_file = b.path("test/one_shot_survey/runtime_success_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    one_shot_runtime_mod.addImport("survey_resume_transform_executes", survey_runtime_mod);
    const one_shot_runtime_tests = b.addTest(.{
        .root_module = one_shot_runtime_mod,
    });
    const run_one_shot_runtime_tests = b.addRunArtifact(one_shot_runtime_tests);
    const one_shot_survey_step = b.step("one-shot-survey", "Run the current plain-Zig one-shot survey contract.");
    inline for (one_shot_success_fixtures) |fixture| {
        const fixture_mod = createShiftPromptFixtureModule(b, fixture.path, target, optimize, .{
            .shift_mod = shift_mod,
            .prompt_support_mod = prompt_support_mod,
            .with_api_mod = with_api_mod,
        });
        const fixture_check = b.addObject(.{
            .name = fixture.name ++ "-aggregate",
            .root_module = fixture_mod,
        });
        one_shot_survey_step.dependOn(&fixture_check.step);
        test_step.dependOn(&fixture_check.step);
    }
    one_shot_survey_step.dependOn(&run_one_shot_runtime_tests.step);
    test_step.dependOn(&run_one_shot_runtime_tests.step);

    const compile_fail_fixtures = [_]struct {
        name: []const u8,
        path: []const u8,
        expected: []const u8,
    }{
        .{ .name = "cf-retired-program", .path = "test/compile_fail/retired_program_fails.zig", .expected = "has no member named 'Transform'" },
        .{ .name = "cf-retired-decl", .path = "test/compile_fail/retired_decl_fails.zig", .expected = "has no member named 'Choice'" },
        .{ .name = "cf-retired-op", .path = "test/compile_fail/retired_op_fails.zig", .expected = "has no member named 'Abort'" },
        .{ .name = "cf-retired-ops", .path = "test/compile_fail/retired_ops_fails.zig", .expected = "has no member named 'Row'" },
        .{ .name = "cf-retired-runwith", .path = "test/compile_fail/retired_runwith_fails.zig", .expected = "has no member named 'mergeRows'" },
        .{ .name = "cf-retired-rowspec", .path = "test/compile_fail/retired_rowspec_fails.zig", .expected = "has no member named 'effects'" },
        .{ .name = "cf-retired-mergerowspecs", .path = "test/compile_fail/retired_mergerowspecs_fails.zig", .expected = "has no member named 'handlers'" },
        .{ .name = "cf-resume-value-mismatch", .path = "test/compile_fail/resume_value_mismatch.zig", .expected = ".resumeValue must have type fn () Resume or fn () ResetError(ErrorSet)!Resume" },
        .{ .name = "cf-collect-closed-outputs-const-mutating-finish", .path = "test/compile_fail/collect_closed_outputs_const_mutating_finish_fails.zig", .expected = "cast discards const qualifier" },
        .{ .name = "cf-one-shot-missing-after-resume", .path = "test/one_shot_survey/missing_after_resume_fails.zig", .expected = "must declare afterResume" },
        .{ .name = "cf-one-shot-missing-resume-or-return", .path = "test/one_shot_survey/missing_resume_or_return_fails.zig", .expected = "must declare resumeOrReturn" },
        .{ .name = "cf-one-shot-wrong-after-resume", .path = "test/one_shot_survey/wrong_after_resume_type_fails.zig", .expected = ".afterResume must have type fn (InAnswer) OutAnswer or fn (InAnswer) ResetError(ErrorSet)!OutAnswer" },
        .{ .name = "cf-one-shot-wrong-ror-type", .path = "test/one_shot_survey/wrong_resume_or_return_type_fails.zig", .expected = ".resumeOrReturn must have type fn () ResumeOrReturn or fn () ResetError(ErrorSet)!ResumeOrReturn" },
        .{ .name = "cf-one-shot-wrong-ror-after", .path = "test/one_shot_survey/wrong_resume_or_return_after_resume_fails.zig", .expected = ".afterResume must have type fn (InAnswer) OutAnswer or fn (InAnswer) ResetError(ErrorSet)!OutAnswer" },
        .{ .name = "cf-one-shot-direct-return-mode-mismatch", .path = "test/one_shot_survey/direct_return_mode_mismatch_fails.zig", .expected = "must declare directReturn" },
        .{ .name = "cf-one-shot-legacy-alias", .path = "test/one_shot_survey/legacy_continuation_alias_recheck_fails.zig", .expected = "has no member named 'Continuation'" },
        .{ .name = "cf-one-shot-legacy-store", .path = "test/one_shot_survey/legacy_continuation_store_recheck_fails.zig", .expected = "has no member named 'Continuation'" },
    };
    assertOwnedCompileFailFixtures(b, "test/compile_fail", compile_fail_fixtures);
    inline for (compile_fail_fixtures) |fixture| {
        const fixture_mod = createShiftPromptFixtureModule(b, fixture.path, target, optimize, .{
            .shift_mod = shift_mod,
            .prompt_support_mod = prompt_support_mod,
            .with_api_mod = with_api_mod,
        });
        const fixture_check = b.addObject(.{
            .name = fixture.name,
            .root_module = fixture_mod,
        });
        fixture_check.expect_errors = .{ .contains = fixture.expected };
        compile_fail_step.dependOn(&fixture_check.step);
        test_step.dependOn(&fixture_check.step);
    }

    const example_proof_mod = b.createModule(.{
        .root_source_file = b.path("test/example_proof_suite.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_proof_mod.addImport("example_open_row_abort_basic", createShiftConsumerModule(b, "examples/open_row_abort_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    example_proof_mod.addImport("example_open_row_abortive_validation", createShiftConsumerModule(b, "examples/open_row_abortive_validation.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    example_proof_mod.addImport("example_open_row_artifact_search", createShiftConsumerModule(b, "examples/open_row_artifact_search.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    example_proof_mod.addImport("example_open_row_choice_basic", createShiftConsumerModule(b, "examples/open_row_choice_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    example_proof_mod.addImport("example_open_row_generator", createShiftConsumerModule(b, "examples/open_row_generator.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    example_proof_mod.addImport("example_open_row_state_writer", createShiftConsumerModule(b, "examples/open_row_state_writer.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    example_proof_mod.addImport("example_open_row_transform_basic", createShiftConsumerModule(b, "examples/open_row_transform_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    example_proof_mod.addImport("example_open_row_workflow", createShiftConsumerModule(b, "examples/open_row_workflow.zig", target, optimize, .{ .shift_mod = shift_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    const example_proof_tests = b.addTest(.{
        .root_module = example_proof_mod,
    });
    const run_example_proof_tests = b.addRunArtifact(example_proof_tests);
    const example_proof_step = b.step("example-proof", "Run exact-output proof for the shipped checked example corpus.");
    example_proof_step.dependOn(&proof_fixture_check_cmd.step);
    example_proof_step.dependOn(&run_example_proof_tests.step);
    test_step.dependOn(&proof_fixture_check_cmd.step);
    test_step.dependOn(&run_example_proof_tests.step);

    const examples = [_]struct {
        name: []const u8,
        src: []const u8,
        step_name: []const u8,
        step_desc: []const u8,
    }{
        .{
            .name = "durable_session_demo",
            .src = "examples/durable_session_demo.zig",
            .step_name = "durable-session-demo",
            .step_desc = "Run the append-only durable session demo.",
        },
        .{
            .name = "early_exit",
            .src = "examples/early_exit.zig",
            .step_name = "run-early-exit",
            .step_desc = "Run the direct-return example.",
        },
        .{
            .name = "exception_basic",
            .src = "examples/exception_basic.zig",
            .step_name = "run-exception-basic",
            .step_desc = "Run the direct-return exception effect example.",
        },
        .{
            .name = "nested_workflow",
            .src = "examples/nested_workflow.zig",
            .step_name = "run-nested-workflow",
            .step_desc = "Run the nested workflow example.",
        },
        .{
            .name = "optional_basic",
            .src = "examples/optional_basic.zig",
            .step_name = "run-optional-basic",
            .step_desc = "Run the optional-resumption effect example.",
        },
        .{
            .name = "resume_or_return",
            .src = "examples/resume_or_return.zig",
            .step_name = "run-resume-or-return",
            .step_desc = "Run the optional-resumption example.",
        },
        .{
            .name = "open_row_state_writer",
            .src = "examples/open_row_state_writer.zig",
            .step_name = "run-open-row-state-writer",
            .step_desc = "Run the checked state-plus-writer example (legacy proof label).",
        },
        .{
            .name = "reader_basic",
            .src = "examples/reader_basic.zig",
            .step_name = "run-reader-basic",
            .step_desc = "Run the additive reader-effect example.",
        },
        .{
            .name = "resource_basic",
            .src = "examples/resource_basic.zig",
            .step_name = "run-resource-basic",
            .step_desc = "Run the bracketed resource effect example.",
        },
        .{
            .name = "writer_basic",
            .src = "examples/writer_basic.zig",
            .step_name = "run-writer-basic",
            .step_desc = "Run the append-only writer effect example.",
        },
        .{
            .name = "state_basic",
            .src = "examples/state_basic.zig",
            .step_name = "run-state-basic",
            .step_desc = "Run the additive state-effect example.",
        },
    };

    inline for (examples) |example| {
        const mod = b.createModule(.{
            .root_source_file = b.path(example.src),
            .target = target,
            .optimize = optimize,
        });
        mod.addImport("shift", shift_mod);
        mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);

        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = mod,
        });
        b.installArtifact(exe);
        check_step.dependOn(&exe.step);

        const run = b.addRunArtifact(exe);
        const run_step = b.step(example.step_name, example.step_desc);
        run_step.dependOn(&run.step);
    }

    inline for (shipped_open_row_corpus.custom_examples) |example| {
        const mod = b.createModule(.{
            .root_source_file = b.path(example.source_path),
            .target = target,
            .optimize = optimize,
        });
        mod.addImport("shift", shift_mod);
        mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);

        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = mod,
        });
        b.installArtifact(exe);
        check_step.dependOn(&exe.step);

        const run = b.addRunArtifact(exe);
        const run_step = b.step(example.run_step_name, example.run_step_desc);
        run_step.dependOn(&run.step);
    }

    const shift_bench_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = bench_optimize,
    });
    shift_bench_mod.addImport("lowered_machine", lowered_machine_mod);
    const bench_specs = [_]struct {
        name: []const u8,
        src: []const u8,
        step_name: []const u8,
        step_desc: []const u8,
    }{
        .{
            .name = "shift-direct-no-capture-bench",
            .src = "bench/no_capture_bench.zig",
            .step_name = "bench",
            .step_desc = "Run the direct-style no-capture benchmark.",
        },
        .{
            .name = "shift-direct-first-suspend-bench",
            .src = "bench/direct_first_suspend_bench.zig",
            .step_name = "bench-first-suspend",
            .step_desc = "Run the direct-style first-suspend benchmark.",
        },
        .{
            .name = "shift-state-effect-bench",
            .src = "bench/state_effect_bench.zig",
            .step_name = "bench-state-effect",
            .step_desc = "Compare the additive state effect against the raw prompt baseline.",
        },
        .{
            .name = "shift-effect-family-matrix-bench",
            .src = "bench/effect_family_matrix_bench.zig",
            .step_name = "bench-family-matrix",
            .step_desc = "Compare every shipped declaration family against its chosen comparator lane.",
        },
        .{
            .name = "shift-algebraic-builder-decompose-bench",
            .src = "bench/algebraic_builder_decompose_bench.zig",
            .step_name = "bench-family-builder-decompose",
            .step_desc = "Decompose family-builder shell and full-path costs.",
        },
        .{
            .name = "shift-writer-effect-decompose-bench",
            .src = "bench/writer_effect_decompose_bench.zig",
            .step_name = "bench-writer-decompose",
            .step_desc = "Decompose writer-effect storage and finalization costs.",
        },
        .{
            .name = "shift-resource-effect-decompose-bench",
            .src = "bench/resource_effect_decompose_bench.zig",
            .step_name = "bench-resource-decompose",
            .step_desc = "Decompose resource-effect acquire and cleanup costs.",
        },
        .{
            .name = "shift-abortive-effect-decompose-bench",
            .src = "bench/abortive_effect_decompose_bench.zig",
            .step_name = "bench-abortive-decompose",
            .step_desc = "Decompose heavier abortive optional and exception costs.",
        },
    };

    inline for (bench_specs) |bench_spec| {
        const bench_mod = b.createModule(.{
            .root_source_file = b.path(bench_spec.src),
            .target = target,
            .optimize = bench_optimize,
        });
        bench_mod.addImport("shift", shift_bench_mod);
        bench_mod.addImport("lowered_machine", lowered_machine_mod);
        const bench_exe = b.addExecutable(.{
            .name = bench_spec.name,
            .root_module = bench_mod,
        });
        const bench_run = b.addRunArtifact(bench_exe);
        const bench_step = b.step(bench_spec.step_name, bench_spec.step_desc);
        bench_step.dependOn(&bench_run.step);
    }

    const runtime_backend_bench_mod = b.createModule(.{
        .root_source_file = b.path("bench/runtime_backend_matrix_bench.zig"),
        .target = target,
        .optimize = bench_optimize,
    });
    runtime_backend_bench_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    runtime_backend_bench_mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);
    runtime_backend_bench_mod.addImport("runtime_stack_baseline", runtime_stack_baseline_mod);
    const runtime_backend_bench_exe = b.addExecutable(.{
        .name = "shift-runtime-backend-matrix-bench",
        .root_module = runtime_backend_bench_mod,
    });
    const runtime_backend_bench_run = b.addRunArtifact(runtime_backend_bench_exe);
    const runtime_backend_bench_step = b.step("bench-runtime-backends", "Compare the current stack runtime against the lowered runtime over the supported bridge corpus.");
    runtime_backend_bench_step.dependOn(&runtime_backend_bench_run.step);

    const bench_artifact_write_cmd = b.addSystemCommand(&.{ "sh", "bench/state_effect_artifact.sh", "write" });
    const bench_artifact_write_step = b.step("bench-state-effect-write", "Refresh the checked state-effect benchmark artifact.");
    bench_artifact_write_step.dependOn(&bench_artifact_write_cmd.step);

    const bench_artifact_check_cmd = b.addSystemCommand(&.{ "sh", "bench/state_effect_artifact.sh", "check" });
    const bench_artifact_check_step = b.step("bench-state-effect-check", "Check the state-effect benchmark artifact against the current clean tree.");
    bench_artifact_check_step.dependOn(&bench_artifact_check_cmd.step);

    const bench_matrix_write_cmd = b.addSystemCommand(&.{ "sh", "bench/effect_family_matrix_artifact.sh", "write" });
    const bench_matrix_write_step = b.step("bench-family-matrix-write", "Refresh the checked family-matrix benchmark artifact.");
    bench_matrix_write_step.dependOn(&bench_matrix_write_cmd.step);

    const bench_matrix_check_cmd = b.addSystemCommand(&.{ "sh", "bench/effect_family_matrix_artifact.sh", "check" });
    const bench_matrix_check_step = b.step("bench-family-matrix-check", "Check the family-matrix benchmark artifact against the current clean tree.");
    bench_matrix_check_step.dependOn(&bench_matrix_check_cmd.step);

    const bench_matrix_stability_cmd = b.addSystemCommand(&.{ "sh", "bench/effect_matrix_stability.sh" });
    const bench_matrix_stability_step = b.step("bench-family-matrix-stability", "Run repeated clean-tree family-matrix stability characterization.");
    bench_matrix_stability_step.dependOn(&bench_matrix_stability_cmd.step);

    const runtime_backend_write_cmd = b.addSystemCommand(&.{ "sh", "bench/runtime_backend_matrix_artifact.sh", "write" });
    const runtime_backend_write_step = b.step("bench-runtime-backends-write", "Refresh the checked runtime backend comparison artifact.");
    runtime_backend_write_step.dependOn(&runtime_backend_write_cmd.step);

    const runtime_backend_check_cmd = b.addSystemCommand(&.{ "sh", "bench/runtime_backend_matrix_artifact.sh", "check" });
    const runtime_backend_check_step = b.step("bench-runtime-backends-check", "Check the runtime backend comparison artifact against the current clean tree.");
    runtime_backend_check_step.dependOn(&runtime_backend_check_cmd.step);

    const runtime_backend_stability_cmd = b.addSystemCommand(&.{ "sh", "bench/runtime_backend_stability.sh" });
    const runtime_backend_stability_step = b.step("bench-runtime-backends-stability", "Run repeated clean-tree lowered-vs-stack backend stability characterization.");
    runtime_backend_stability_step.dependOn(&runtime_backend_stability_cmd.step);

    const lint_step = b.step("lint", "Lint source code.");
    lint_step.dependOn(step: {
        const saved_verbose = b.verbose;
        b.verbose = true;
        defer b.verbose = saved_verbose;
        var builder = zlinter.builder(b, .{});
        builder.addPaths(.{
            .exclude = &.{
                b.path(".zig-cache"),
                b.path(".zig-global-cache"),
                b.path("src/error_witness.zig"),
                b.path("src/op_compat.zig"),
                // Public API intentionally exposes lower-case type-callable entrypoints here.
                b.path("src/public_ir.zig"),
                b.path("src/public_lowering.zig"),
                b.path("src/program_api_compat.zig"),
                b.path("src/program_api.zig"),
                // Root re-exports the same lower-case public entrypoints.
                b.path("src/root.zig"),
            },
        });
        inline for (@typeInfo(zlinter.BuiltinLintRule).@"enum".fields) |field| {
            const rule: zlinter.BuiltinLintRule = @enumFromInt(field.value);
            builder.addRule(.{ .builtin = rule }, .{});
        }
        break :step builder.build();
    });
}
