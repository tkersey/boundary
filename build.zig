// zlinter-disable require_doc_comment
const std = @import("std");
const zlinter = @import("zlinter");

const CoreModules = struct {
    portable_core: *std.Build.Module,
    lowered_machine: *std.Build.Module,
    prompt_contract: *std.Build.Module,
    frontend: *std.Build.Module,
    effect_ir: *std.Build.Module,
    helper_body_ir: *std.Build.Module,
    internal_kernel: *std.Build.Module,
    internal_program_plan: *std.Build.Module,
    interpreter: *std.Build.Module,
    lowering_api: *std.Build.Module,
    parity_scenarios: *std.Build.Module,
};

const TestArgs = struct {
    filters: []const []const u8,
    passthrough: []const []const u8,
};

fn parseTestArgs(b: *std.Build) TestArgs {
    const args = b.args orelse return .{
        .filters = &.{},
        .passthrough = &.{},
    };

    var filters: std.ArrayList([]const u8) = .empty;
    var passthrough: std.ArrayList([]const u8) = .empty;

    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--test-filter")) {
            index += 1;
            if (index >= args.len or args[index].len == 0) {
                std.process.fatal("Expected a non-empty pattern after '--test-filter'.", .{});
            }
            filters.append(b.allocator, args[index]) catch |err|
                std.process.fatal("unable to store test filter: {s}", .{@errorName(err)});
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--test-filter=")) {
            const pattern = arg["--test-filter=".len..];
            if (pattern.len == 0) {
                std.process.fatal("Expected '--test-filter=' to include a non-empty pattern.", .{});
            }
            filters.append(b.allocator, pattern) catch |err|
                std.process.fatal("unable to store test filter: {s}", .{@errorName(err)});
            continue;
        }
        if (std.mem.eql(u8, arg, "--seed")) {
            index += 1;
            if (index >= args.len or args[index].len == 0) {
                std.process.fatal("Expected an unsigned 32-bit integer after '--seed'.", .{});
            }
            _ = std.fmt.parseUnsigned(u32, args[index], 0) catch
                std.process.fatal("Expected '--seed' to contain an unsigned 32-bit integer; got '{s}'.", .{args[index]});
            passthrough.append(b.allocator, b.fmt("--seed={s}", .{args[index]})) catch |err|
                std.process.fatal("unable to store test runner seed: {s}", .{@errorName(err)});
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--seed=")) {
            const seed = arg["--seed=".len..];
            if (seed.len == 0) {
                std.process.fatal("Expected '--seed=' to include an unsigned 32-bit integer.", .{});
            }
            _ = std.fmt.parseUnsigned(u32, seed, 0) catch
                std.process.fatal("Expected '--seed' to contain an unsigned 32-bit integer; got '{s}'.", .{seed});
            passthrough.append(b.allocator, arg) catch |err|
                std.process.fatal("unable to store test runner seed: {s}", .{@errorName(err)});
            continue;
        }
        if (std.mem.eql(u8, arg, "--cache-dir")) {
            index += 1;
            if (index >= args.len or args[index].len == 0) {
                std.process.fatal("Expected a path after '--cache-dir'.", .{});
            }
            passthrough.append(b.allocator, b.fmt("--cache-dir={s}", .{args[index]})) catch |err|
                std.process.fatal("unable to store test runner cache directory: {s}", .{@errorName(err)});
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--cache-dir=")) {
            if (arg["--cache-dir=".len..].len == 0) {
                std.process.fatal("Expected '--cache-dir=' to include a path.", .{});
            }
            passthrough.append(b.allocator, arg) catch |err|
                std.process.fatal("unable to store test runner cache directory: {s}", .{@errorName(err)});
            continue;
        }
        if (std.mem.eql(u8, arg, "--max-warnings")) {
            index += 1;
            if (index >= args.len or args[index].len == 0) {
                std.process.fatal("Expected a non-empty limit after '--max-warnings'.", .{});
            }
            _ = std.fmt.parseUnsigned(usize, args[index], 10) catch
                std.process.fatal("Expected '--max-warnings' to contain an unsigned integer; got '{s}'.", .{args[index]});
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--max-warnings=")) {
            const limit = arg["--max-warnings=".len..];
            if (limit.len == 0) {
                std.process.fatal("Expected '--max-warnings=' to include a non-empty limit.", .{});
            }
            _ = std.fmt.parseUnsigned(usize, limit, 10) catch
                std.process.fatal("Expected '--max-warnings' to contain an unsigned integer; got '{s}'.", .{limit});
            continue;
        }
        passthrough.append(b.allocator, arg) catch |err|
            std.process.fatal("unable to store test runner argument: {s}", .{@errorName(err)});
    }

    return .{
        .filters = filters.toOwnedSlice(b.allocator) catch |err|
            std.process.fatal("unable to finalize test filters: {s}", .{@errorName(err)}),
        .passthrough = passthrough.toOwnedSlice(b.allocator) catch |err|
            std.process.fatal("unable to finalize test runner arguments: {s}", .{@errorName(err)}),
    };
}

fn addRunArtifactWithArgs(
    b: *std.Build,
    artifact: *std.Build.Step.Compile,
    args: []const []const u8,
) *std.Build.Step.Run {
    const run = b.addRunArtifact(artifact);
    if (args.len != 0) run.addArgs(args);
    return run;
}

fn addTestArtifact(
    b: *std.Build,
    test_step: *std.Build.Step,
    root_module: *std.Build.Module,
    test_args: TestArgs,
) void {
    const tests = b.addTest(.{ .root_module = root_module, .filters = test_args.filters });
    test_step.dependOn(&addRunArtifactWithArgs(b, tests, test_args.passthrough).step);
}

fn addCompileFailArtifact(
    b: *std.Build,
    compile_fail_step: *std.Build.Step,
    root_module: *std.Build.Module,
    expected_error: []const u8,
) void {
    const tests = b.addTest(.{ .root_module = root_module });
    tests.expect_errors = .{ .contains = expected_error };
    compile_fail_step.dependOn(&tests.step);
}

fn addZigPathCoverageGuard(b: *std.Build, lint_step: *std.Build.Step) void {
    const guard = b.addSystemCommand(&.{
        "sh",
        "-c",
        \\set -eu
        \\tmp="${TMPDIR:-/tmp}/ability-zig-paths-$$"
        \\trap 'rm -f "$tmp.actual" "$tmp.expected"' EXIT
        \\find src examples test bench -type f -name '*.zig' | sort > "$tmp.actual"
        \\grep -E '^(src|examples|test|bench)/.*\.zig$' repo_zig_paths.txt | sort > "$tmp.expected"
        \\diff -u "$tmp.expected" "$tmp.actual"
    });
    lint_step.dependOn(&guard.step);
}

fn addCoreModules(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) CoreModules {
    const portable_core = b.createModule(.{
        .root_source_file = b.path("src/portable_core.zig"),
        .target = target,
        .optimize = optimize,
    });
    const effect_ir = b.createModule(.{
        .root_source_file = b.path("src/effect_ir.zig"),
        .target = target,
        .optimize = optimize,
    });
    const parity_scenarios = b.createModule(.{
        .root_source_file = b.path("src/parity_scenarios.zig"),
        .target = target,
        .optimize = optimize,
    });
    const helper_body_ir = b.createModule(.{
        .root_source_file = b.path("src/private_modules/helper_body_ir_build.zig"),
        .target = target,
        .optimize = optimize,
    });
    const program_frontend = b.createModule(.{
        .root_source_file = b.path("src/program_frontend.zig"),
        .target = target,
        .optimize = optimize,
    });
    program_frontend.addImport("effect_ir", effect_ir);
    program_frontend.addImport("helper_body_ir", helper_body_ir);
    program_frontend.addImport("parity_scenarios", parity_scenarios);
    const internal_program_plan = b.createModule(.{
        .root_source_file = b.path("src/internal_program_plan.zig"),
        .target = target,
        .optimize = optimize,
    });
    internal_program_plan.addImport("effect_ir", effect_ir);
    internal_program_plan.addImport("program_frontend", program_frontend);
    helper_body_ir.addImport("internal_program_plan", internal_program_plan);
    helper_body_ir.addImport("effect_ir", effect_ir);

    const internal_kernel = b.createModule(.{
        .root_source_file = b.path("src/private_modules/internal_kernel_build.zig"),
        .target = target,
        .optimize = optimize,
    });
    internal_kernel.addImport("internal_program_plan", internal_program_plan);
    internal_kernel.addImport("parity_scenarios", parity_scenarios);

    const lowered_machine = b.createModule(.{
        .root_source_file = b.path("src/private_modules/lowered_machine_build.zig"),
        .target = target,
        .optimize = optimize,
    });
    lowered_machine.addImport("internal_kernel", internal_kernel);
    lowered_machine.addImport("portable_core", portable_core);
    lowered_machine.addImport("parity_scenarios", parity_scenarios);

    const prompt_contract = b.createModule(.{
        .root_source_file = b.path("src/prompt_contract.zig"),
        .target = target,
        .optimize = optimize,
    });
    prompt_contract.addImport("portable_core", portable_core);

    const frontend = b.createModule(.{
        .root_source_file = b.path("src/frontend.zig"),
        .target = target,
        .optimize = optimize,
    });
    frontend.addImport("lowered_machine", lowered_machine);
    frontend.addImport("portable_core", portable_core);
    frontend.addImport("prompt_contract_support", prompt_contract);

    const interpreter = b.createModule(.{
        .root_source_file = b.path("src/interpreter.zig"),
        .target = target,
        .optimize = optimize,
    });
    interpreter.addImport("internal_kernel", internal_kernel);

    const lowering_api = b.createModule(.{
        .root_source_file = b.path("src/lowering_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    lowering_api.addImport("lowered_machine", lowered_machine);
    lowering_api.addImport("internal_program_plan", internal_program_plan);

    return .{
        .portable_core = portable_core,
        .lowered_machine = lowered_machine,
        .prompt_contract = prompt_contract,
        .frontend = frontend,
        .effect_ir = effect_ir,
        .helper_body_ir = helper_body_ir,
        .internal_kernel = internal_kernel,
        .internal_program_plan = internal_program_plan,
        .interpreter = interpreter,
        .lowering_api = lowering_api,
        .parity_scenarios = parity_scenarios,
    };
}

fn wireAbilityImports(mod: *std.Build.Module, core: CoreModules) void {
    mod.addImport("portable_core", core.portable_core);
    mod.addImport("lowered_machine", core.lowered_machine);
    mod.addImport("prompt_contract_support", core.prompt_contract);
    mod.addImport("frontend_support", core.frontend);
    mod.addImport("effect_ir", core.effect_ir);
    mod.addImport("helper_body_ir", core.helper_body_ir);
    mod.addImport("internal_kernel", core.internal_kernel);
    mod.addImport("internal_program_plan", core.internal_program_plan);
    mod.addImport("interpreter", core.interpreter);
    mod.addImport("lowering_api", core.lowering_api);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const bench_optimize: std.builtin.OptimizeMode = .ReleaseFast;
    const test_args = parseTestArgs(b);
    const core = addCoreModules(b, target, optimize);

    const ability_shared = b.createModule(.{
        .root_source_file = b.path("src/ability_shared.zig"),
        .target = target,
        .optimize = optimize,
    });
    wireAbilityImports(ability_shared, core);

    const ability = b.addModule("ability", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    ability.addImport("ability_shared", ability_shared);

    const lib_check = b.addLibrary(.{
        .linkage = .static,
        .name = "ability",
        .root_module = ability,
    });
    b.installArtifact(lib_check);

    const test_step = b.step("test", "Run the ability test suite.");
    addTestArtifact(b, test_step, ability, test_args);
    addTestArtifact(b, test_step, ability_shared, test_args);
    addTestArtifact(b, test_step, core.effect_ir, test_args);
    addTestArtifact(b, test_step, core.frontend, test_args);
    addTestArtifact(b, test_step, core.internal_kernel, test_args);
    addTestArtifact(b, test_step, core.internal_program_plan, test_args);
    addTestArtifact(b, test_step, core.lowered_machine, test_args);
    addTestArtifact(b, test_step, core.portable_core, test_args);

    const ir_api_tests_mod = b.createModule(.{
        .root_source_file = b.path("src/ir_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    ir_api_tests_mod.addImport("effect_ir", core.effect_ir);
    ir_api_tests_mod.addImport("internal_kernel", core.internal_kernel);
    ir_api_tests_mod.addImport("internal_program_plan", core.internal_program_plan);
    addTestArtifact(b, test_step, ir_api_tests_mod, test_args);

    const synthetic_root_tests_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/synthetic_ability_root.zig"),
        .target = target,
        .optimize = optimize,
    });
    synthetic_root_tests_mod.addImport("ability_shared", ability_shared);
    addTestArtifact(b, test_step, synthetic_root_tests_mod, test_args);

    const program_api_tests_mod = b.createModule(.{
        .root_source_file = b.path("test/program_api_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const plan_native_resource_mod = b.createModule(.{
        .root_source_file = b.path("examples/plan_native_resource.zig"),
        .target = target,
        .optimize = optimize,
    });
    plan_native_resource_mod.addImport("ability", ability);
    program_api_tests_mod.addImport("ability", ability);
    program_api_tests_mod.addImport("plan_native_resource", plan_native_resource_mod);
    const program_api_tests = b.addTest(.{ .root_module = program_api_tests_mod, .filters = test_args.filters });
    test_step.dependOn(&addRunArtifactWithArgs(b, program_api_tests, test_args.passthrough).step);

    const contract_matrix_mod = b.createModule(.{
        .root_source_file = b.path("test/plan_native_contract_matrix_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    contract_matrix_mod.addImport("ability", ability);
    const contract_matrix_tests = b.addTest(.{ .root_module = contract_matrix_mod, .filters = test_args.filters });
    test_step.dependOn(&addRunArtifactWithArgs(b, contract_matrix_tests, test_args.passthrough).step);

    const public_optional_tests_mod = b.createModule(.{
        .root_source_file = b.path("test/public_optional_bound_program_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    public_optional_tests_mod.addImport("ability", ability);
    const public_optional_tests = b.addTest(.{ .root_module = public_optional_tests_mod, .filters = test_args.filters });
    test_step.dependOn(&addRunArtifactWithArgs(b, public_optional_tests, test_args.passthrough).step);

    const compile_fail_step = b.step("compile-fail", "Check expected public ProgramPlan compile diagnostics.");
    test_step.dependOn(compile_fail_step);
    const compile_fail_specs = [_]struct {
        path: []const u8,
        expected_error: []const u8,
    }{
        .{
            .path = "test/compile_fail/missing_reachable_return_error_decl.zig",
            .expected_error = "Body.compiled_plan reachable return_error is not declared in Body.Error: Rejected",
        },
        .{
            .path = "test/compile_fail/invalid_result_cleanup_with_outputs.zig",
            .expected_error = "Body.deinitResult with Body.Outputs must have type fn (std.mem.Allocator, value) void; release outputs separately with Body.deinitOutputs",
        },
        .{
            .path = "test/compile_fail/value_schema_variant_mismatch.zig",
            .expected_error = "Body.value_schema_types does not match Body.compiled_plan.value_variants[1]",
        },
        .{
            .path = "test/compile_fail/invalid_sum_extract_destination.zig",
            .expected_error = "Body.compiled_plan failed ProgramPlan.validate: InvalidSumPayloadDestination",
        },
        .{
            .path = "test/compile_fail/encode_args_tuple_field_mismatch.zig",
            .expected_error = "expected i32, found bool",
        },
        .{
            .path = "test/compile_fail/missing_output_collector.zig",
            .expected_error = "Body.Outputs requires Body.collectOutputs",
        },
        .{
            .path = "test/compile_fail/invalid_output_cleanup_hook.zig",
            .expected_error = "Body.deinitOutputs must have type fn (std.mem.Allocator, outputs) void",
        },
        .{
            .path = "test/compile_fail/missing_nested_with_target.zig",
            .expected_error = "UnsupportedNestedWith",
        },
        .{
            .path = "test/compile_fail/nested_with_wrong_function_index.zig",
            .expected_error = "UnsupportedNestedWith",
        },
        .{
            .path = "test/compile_fail/nested_with_result_codec_mismatch.zig",
            .expected_error = "UnsupportedResultCodec",
        },
        .{
            .path = "test/compile_fail/schema_lower_binding_product_ref.zig",
            .expected_error = "needs an explicit ProgramPlan schema-index map; v1 supports scalar refs only",
        },
    };
    inline for (compile_fail_specs) |spec| {
        const compile_fail_mod = b.createModule(.{
            .root_source_file = b.path(spec.path),
            .target = target,
            .optimize = optimize,
        });
        compile_fail_mod.addImport("ability", ability);
        addCompileFailArtifact(b, compile_fail_step, compile_fail_mod, spec.expected_error);
    }

    const examples = [_]struct {
        name: []const u8,
        path: []const u8,
        step: []const u8,
        desc: []const u8,
    }{
        .{ .name = "ability-state-basic", .path = "examples/state_basic.zig", .step = "run-state-basic", .desc = "Run the state effect example." },
        .{ .name = "ability-typed-program-plan", .path = "examples/typed_program_plan.zig", .step = "run-typed-program-plan", .desc = "Run the typed ProgramPlan example." },
        .{ .name = "ability-plan-native-optional", .path = "examples/plan_native_optional.zig", .step = "run-plan-native-optional", .desc = "Run the plan-native optional example." },
        .{ .name = "ability-plan-native-state-reader", .path = "examples/plan_native_state_reader.zig", .step = "run-plan-native-state-reader", .desc = "Run the plan-native state/reader example." },
        .{ .name = "ability-plan-native-writer", .path = "examples/plan_native_writer.zig", .step = "run-plan-native-writer", .desc = "Run the plan-native writer example." },
        .{ .name = "ability-plan-native-exception", .path = "examples/plan_native_exception.zig", .step = "run-plan-native-exception", .desc = "Run the plan-native exception example." },
        .{ .name = "ability-plan-native-resource", .path = "examples/plan_native_resource.zig", .step = "run-plan-native-resource", .desc = "Run the plan-native resource example." },
        .{ .name = "ability-custom-approval-workflow", .path = "examples/custom_approval_workflow.zig", .step = "run-custom-approval-workflow", .desc = "Run the custom approval workflow example." },
    };
    inline for (examples) |example| {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path(example.path),
            .target = target,
            .optimize = optimize,
        });
        exe_mod.addImport("ability", ability);
        const exe = b.addExecutable(.{ .name = example.name, .root_module = exe_mod });
        const run_step = b.step(example.step, example.desc);
        if (target.query.isNative()) {
            run_step.dependOn(&addRunArtifactWithArgs(b, exe, if (b.args) |args| args else &.{}).step);
        } else {
            run_step.dependOn(&exe.step);
        }
    }

    const bench_check_step = b.step("bench-check", "Compile retained benchmark programs.");
    test_step.dependOn(bench_check_step);

    const ability_bench = b.createModule(.{
        .root_source_file = b.path("src/bench_support.zig"),
        .target = target,
        .optimize = bench_optimize,
    });
    wireAbilityImports(ability_bench, core);

    const bench_specs = [_]struct {
        name: []const u8,
        path: []const u8,
        step: []const u8,
        desc: []const u8,
    }{
        .{ .name = "ability-abortive-effect-decompose-bench", .path = "bench/abortive_effect_decompose_bench.zig", .step = "bench-abortive-effect-decompose", .desc = "Run the abortive effect decomposition benchmark." },
        .{ .name = "ability-algebraic-builder-decompose-bench", .path = "bench/algebraic_builder_decompose_bench.zig", .step = "bench-algebraic-builder-decompose", .desc = "Run the algebraic builder decomposition benchmark." },
        .{ .name = "ability-direct-first-suspend-bench", .path = "bench/direct_first_suspend_bench.zig", .step = "bench-first-suspend", .desc = "Run the direct-style first-suspend benchmark." },
        .{ .name = "ability-effect-family-matrix-bench", .path = "bench/effect_family_matrix_bench.zig", .step = "bench-family-matrix", .desc = "Compare every retained effect family against its comparator lane." },
        .{ .name = "ability-direct-no-capture-bench", .path = "bench/no_capture_bench.zig", .step = "bench", .desc = "Run the direct-style no-capture benchmark." },
        .{ .name = "ability-resource-effect-decompose-bench", .path = "bench/resource_effect_decompose_bench.zig", .step = "bench-resource-effect-decompose", .desc = "Run the resource effect decomposition benchmark." },
        .{ .name = "ability-state-effect-bench", .path = "bench/state_effect_bench.zig", .step = "bench-state-effect", .desc = "Compare the additive state effect against the raw prompt baseline." },
        .{ .name = "ability-writer-effect-decompose-bench", .path = "bench/writer_effect_decompose_bench.zig", .step = "bench-writer-effect-decompose", .desc = "Run the writer effect decomposition benchmark." },
    };
    inline for (bench_specs) |bench| {
        const bench_mod = b.createModule(.{
            .root_source_file = b.path(bench.path),
            .target = target,
            .optimize = bench_optimize,
        });
        bench_mod.addImport("ability", ability_bench);
        bench_mod.addImport("lowered_machine", core.lowered_machine);
        const bench_exe = b.addExecutable(.{ .name = bench.name, .root_module = bench_mod });
        bench_check_step.dependOn(&bench_exe.step);
        const bench_run_step = b.step(bench.step, bench.desc);
        if (target.query.isNative()) {
            bench_run_step.dependOn(&b.addRunArtifact(bench_exe).step);
        } else {
            bench_run_step.dependOn(&bench_exe.step);
        }
    }

    const zprof_hotspots_step = b.step("zprof-hotspots", "Profile writer/resource allocator hotspots with zprof.");
    if (b.lazyDependency("zprof", .{
        .target = target,
        .optimize = bench_optimize,
    })) |zprof_dep| {
        const zprof_hotspots_mod = b.createModule(.{
            .root_source_file = b.path("bench/zprof_hotspots.zig"),
            .target = target,
            .optimize = bench_optimize,
        });
        zprof_hotspots_mod.addImport("ability", ability_bench);
        zprof_hotspots_mod.addImport("zprof", zprof_dep.module("zprof"));
        const zprof_hotspots_exe = b.addExecutable(.{ .name = "ability-zprof-hotspots", .root_module = zprof_hotspots_mod });
        zprof_hotspots_step.dependOn(&b.addRunArtifact(zprof_hotspots_exe).step);
    }

    const lint_step = b.step("lint", "Lint source code.");
    addZigPathCoverageGuard(b, lint_step);
    var builder = zlinter.builder(b, .{});
    builder.addPaths(.{
        .include = &.{
            b.path("build.zig"),
            b.path("src"),
            b.path("examples"),
            b.path("test"),
            b.path("bench"),
        },
        .exclude = &.{},
    });
    inline for (@typeInfo(zlinter.BuiltinLintRule).@"enum".fields) |field| {
        const rule: zlinter.BuiltinLintRule = @enumFromInt(field.value);
        builder.addRule(.{ .builtin = rule }, .{});
    }
    const saved_global_cache_path = b.graph.global_cache_root.path;
    if (saved_global_cache_path) |path| {
        if (!std.Io.Dir.path.isAbsolute(path)) {
            b.graph.global_cache_root.path = b.pathFromRoot(path);
        }
    }
    defer b.graph.global_cache_root.path = saved_global_cache_path;
    lint_step.dependOn(builder.build());
}
