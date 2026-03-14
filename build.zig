const std = @import("std");
const zlinter = @import("zlinter");

fn addRuntimeAssembly(b: *std.Build, module: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    switch (target.result.cpu.arch) {
        .x86_64 => module.addAssemblyFile(b.path("src/runtime/x86_64_switch.S")),
        .aarch64 => module.addAssemblyFile(b.path("src/runtime/aarch64_switch.S")),
        else => {},
    }
}

fn createShiftConsumerModule(
    b: *std.Build,
    path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    shift_mod: *std.Build.Module,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("shift", shift_mod);
    return mod;
}

/// Configure build, test, lint, example, and benchmark entrypoints for shift.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const bench_optimize: std.builtin.OptimizeMode = .ReleaseFast;

    const shift_mod = b.addModule("shift", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    addRuntimeAssembly(b, shift_mod, target);
    const witnesses_mod = b.createModule(.{
        .root_source_file = b.path("src/witnesses.zig"),
        .target = target,
        .optimize = optimize,
    });
    witnesses_mod.addImport("shift", shift_mod);
    const formal_core_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/formal_core_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    const reference_eval_mod = b.createModule(.{
        .root_source_file = b.path("src/reference_eval.zig"),
        .target = target,
        .optimize = optimize,
    });
    const reference_machine_mod = b.createModule(.{
        .root_source_file = b.path("src/reference_machine.zig"),
        .target = target,
        .optimize = optimize,
    });

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
    addRuntimeAssembly(b, lib_check.root_module, target);
    check_step.dependOn(&lib_check.step);

    const root_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    addRuntimeAssembly(b, root_tests.root_module, target);
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
    const witness_tests = b.addTest(.{
        .root_module = witness_mod,
    });
    const run_witness_tests = b.addRunArtifact(witness_tests);
    test_step.dependOn(&run_witness_tests.step);

    const backend_parity_mod = b.createModule(.{
        .root_source_file = b.path("test/backend_parity_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const backend_parity_manifest_mod = b.createModule(.{
        .root_source_file = b.path("test/backend_parity_manifest.zig"),
        .target = target,
        .optimize = optimize,
    });
    const parity_kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/parity_kernel.zig"),
        .target = target,
        .optimize = optimize,
    });
    const backend_state_expect_mod = b.createModule(.{
        .root_source_file = b.path("test/backend_parity_state_expectations.zig"),
        .target = target,
        .optimize = optimize,
    });
    backend_parity_manifest_mod.addImport("formal_core_registry", formal_core_registry_mod);
    backend_state_expect_mod.addImport("parity_kernel", parity_kernel_mod);
    backend_parity_mod.addImport("shift", shift_mod);
    backend_parity_mod.addImport("backend_parity_manifest", backend_parity_manifest_mod);
    backend_parity_mod.addImport("backend_parity_state_expectations", backend_state_expect_mod);
    backend_parity_mod.addImport("parity_kernel", parity_kernel_mod);
    const parity_machine_mod = b.createModule(.{
        .root_source_file = b.path("src/parity_machine.zig"),
        .target = target,
        .optimize = optimize,
    });
    parity_machine_mod.addImport("parity_kernel", parity_kernel_mod);
    backend_parity_mod.addImport("parity_machine", parity_machine_mod);
    backend_parity_mod.addImport("witnesses_src", witnesses_mod);
    backend_parity_mod.addImport("example_algebraic_abortive_validation", createShiftConsumerModule(b, "examples/algebraic_abortive_validation.zig", target, optimize, shift_mod));
    backend_parity_mod.addImport("example_algebraic_artifact_search", createShiftConsumerModule(b, "examples/algebraic_artifact_search.zig", target, optimize, shift_mod));
    backend_parity_mod.addImport("example_early_exit", createShiftConsumerModule(b, "examples/early_exit.zig", target, optimize, shift_mod));
    backend_parity_mod.addImport("example_exception_basic", createShiftConsumerModule(b, "examples/exception_basic.zig", target, optimize, shift_mod));
    backend_parity_mod.addImport("example_generator", createShiftConsumerModule(b, "examples/generator.zig", target, optimize, shift_mod));
    backend_parity_mod.addImport("example_nested_workflow", createShiftConsumerModule(b, "examples/nested_workflow.zig", target, optimize, shift_mod));
    backend_parity_mod.addImport("example_optional_basic", createShiftConsumerModule(b, "examples/optional_basic.zig", target, optimize, shift_mod));
    backend_parity_mod.addImport("example_reader_basic", createShiftConsumerModule(b, "examples/reader_basic.zig", target, optimize, shift_mod));
    backend_parity_mod.addImport("example_resource_basic", createShiftConsumerModule(b, "examples/resource_basic.zig", target, optimize, shift_mod));
    backend_parity_mod.addImport("example_resume_or_return", createShiftConsumerModule(b, "examples/resume_or_return.zig", target, optimize, shift_mod));
    backend_parity_mod.addImport("example_state_basic", createShiftConsumerModule(b, "examples/state_basic.zig", target, optimize, shift_mod));
    backend_parity_mod.addImport("example_writer_basic", createShiftConsumerModule(b, "examples/writer_basic.zig", target, optimize, shift_mod));
    backend_parity_mod.addImport("survey_resume_transform_executes", createShiftConsumerModule(b, "test/one_shot_survey/protocol_resume_transform_executes.zig", target, optimize, shift_mod));
    const backend_parity_tests = b.addTest(.{
        .root_module = backend_parity_mod,
    });
    const run_backend_parity_tests = b.addRunArtifact(backend_parity_tests);
    const backend_parity_step = b.step("backend-parity", "Run proof-only parity checks against the stackful runtime surface.");
    backend_parity_step.dependOn(&run_backend_parity_tests.step);

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
    const formal_core_step = b.step("formal-core", "Check the implementation-derived formal core anchors.");
    formal_core_step.dependOn(&formal_core_cmd.step);
    test_step.dependOn(&formal_core_cmd.step);

    const formal_core_write_cmd = b.addRunArtifact(formal_core_render_exe);
    formal_core_write_cmd.addArg("write");
    const formal_core_write_step = b.step("formal-core-write", "Refresh the generated formal core artifact.");
    formal_core_write_step.dependOn(&formal_core_write_cmd.step);

    const readme_contract_cmd = b.addSystemCommand(&.{ "sh", "test/readme_contract/run.sh" });
    const readme_contract_step = b.step("readme-contract", "Check README contract anchors and commands.");
    readme_contract_step.dependOn(&readme_contract_cmd.step);
    test_step.dependOn(&readme_contract_cmd.step);

    const construction_boundary_cmd = b.addSystemCommand(&.{ "sh", "test/effect_construction_boundary/run.sh" });
    const construction_boundary_step = b.step("effect-construction-boundary", "Check that effect families route through the generalized substrate.");
    construction_boundary_step.dependOn(&construction_boundary_cmd.step);
    test_step.dependOn(&construction_boundary_cmd.step);

    const size_check_mod = b.createModule(.{
        .root_source_file = b.path("test/size_check.zig"),
        .target = target,
        .optimize = optimize,
    });
    size_check_mod.addImport("shift", shift_mod);
    const size_tests = b.addTest(.{
        .root_module = size_check_mod,
    });
    const run_size_tests = b.addRunArtifact(size_tests);
    const size_step = b.step("size-check", "Run size and layout invariants.");
    size_step.dependOn(&run_size_tests.step);
    test_step.dependOn(&run_size_tests.step);

    const compile_fail_cmd = b.addSystemCommand(&.{ "sh", "test/compile_fail/run.sh" });
    const compile_fail_step = b.step("compile-fail", "Verify compile-fail misuse fixtures.");
    compile_fail_step.dependOn(&compile_fail_cmd.step);
    test_step.dependOn(&compile_fail_cmd.step);

    const one_shot_survey_cmd = b.addSystemCommand(&.{ "sh", "test/one_shot_survey/run.sh" });
    const one_shot_survey_step = b.step("one-shot-survey", "Run the current plain-Zig one-shot survey contract.");
    one_shot_survey_step.dependOn(&one_shot_survey_cmd.step);
    test_step.dependOn(&one_shot_survey_cmd.step);

    const example_proof_cmd = b.addSystemCommand(&.{ "sh", "test/example_proof/run.sh" });
    const example_proof_step = b.step("example-proof", "Run exact-output proof for all examples.");
    example_proof_step.dependOn(&example_proof_cmd.step);
    test_step.dependOn(&example_proof_cmd.step);

    const examples = [_]struct {
        name: []const u8,
        src: []const u8,
        step_name: []const u8,
        step_desc: []const u8,
    }{
        .{
            .name = "algebraic_abortive_validation",
            .src = "examples/algebraic_abortive_validation.zig",
            .step_name = "run-algebraic-abortive-validation",
            .step_desc = "Run the algebraic abortive-validation example.",
        },
        .{
            .name = "algebraic_artifact_search",
            .src = "examples/algebraic_artifact_search.zig",
            .step_name = "run-algebraic-artifact-search",
            .step_desc = "Run the algebraic artifact-search example.",
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
            .name = "generator",
            .src = "examples/generator.zig",
            .step_name = "run-generator",
            .step_desc = "Run the generator example.",
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

        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = mod,
        });
        b.installArtifact(exe);
        check_step.dependOn(&exe.step);

        const run = b.addRunArtifact(exe);
        run.step.dependOn(b.getInstallStep());
        const run_step = b.step(example.step_name, example.step_desc);
        run_step.dependOn(&run.step);
    }

    const shift_bench_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = bench_optimize,
    });
    addRuntimeAssembly(b, shift_bench_mod, target);

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
            .step_name = "bench-effect-matrix",
            .step_desc = "Compare every shipped effect family against its chosen comparator lane.",
        },
        .{
            .name = "shift-algebraic-builder-decompose-bench",
            .src = "bench/algebraic_builder_decompose_bench.zig",
            .step_name = "bench-algebraic-decompose",
            .step_desc = "Decompose public algebraic builder shell and full-path costs.",
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
        const bench_exe = b.addExecutable(.{
            .name = bench_spec.name,
            .root_module = bench_mod,
        });
        b.installArtifact(bench_exe);
        const bench_run = b.addRunArtifact(bench_exe);
        bench_run.step.dependOn(b.getInstallStep());
        const bench_step = b.step(bench_spec.step_name, bench_spec.step_desc);
        bench_step.dependOn(&bench_run.step);
    }

    const bench_artifact_write_cmd = b.addSystemCommand(&.{ "sh", "bench/state_effect_artifact.sh", "write" });
    const bench_artifact_write_step = b.step("bench-state-effect-write", "Refresh the checked state-effect benchmark artifact.");
    bench_artifact_write_step.dependOn(&bench_artifact_write_cmd.step);

    const bench_artifact_check_cmd = b.addSystemCommand(&.{ "sh", "bench/state_effect_artifact.sh", "check" });
    const bench_artifact_check_step = b.step("bench-state-effect-check", "Check the state-effect benchmark artifact against the current clean tree.");
    bench_artifact_check_step.dependOn(&bench_artifact_check_cmd.step);

    const bench_matrix_write_cmd = b.addSystemCommand(&.{ "sh", "bench/effect_family_matrix_artifact.sh", "write" });
    const bench_matrix_write_step = b.step("bench-effect-matrix-write", "Refresh the checked effect-family matrix benchmark artifact.");
    bench_matrix_write_step.dependOn(&bench_matrix_write_cmd.step);

    const bench_matrix_check_cmd = b.addSystemCommand(&.{ "sh", "bench/effect_family_matrix_artifact.sh", "check" });
    const bench_matrix_check_step = b.step("bench-effect-matrix-check", "Check the effect-family matrix benchmark artifact against the current clean tree.");
    bench_matrix_check_step.dependOn(&bench_matrix_check_cmd.step);

    const lint_step = b.step("lint", "Lint source code.");
    lint_step.dependOn(step: {
        var builder = zlinter.builder(b, .{});
        inline for (@typeInfo(zlinter.BuiltinLintRule).@"enum".fields) |field| {
            builder.addRule(.{ .builtin = @enumFromInt(field.value) }, .{});
        }
        break :step builder.build();
    });
}
