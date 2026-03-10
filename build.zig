const std = @import("std");
const zlinter = @import("zlinter");

fn addRuntimeAssembly(b: *std.Build, module: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    switch (target.result.cpu.arch) {
        .x86_64 => module.addAssemblyFile(b.path("src/runtime/x86_64_switch.S")),
        .aarch64 => module.addAssemblyFile(b.path("src/runtime/aarch64_switch.S")),
        else => {},
    }
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

    const control_lab_registry_mod = b.addModule("control_lab_registry", .{
        .root_source_file = b.path("src/control_lab/registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    const control_lab_scenarios_mod = b.addModule("control_lab_scenarios", .{
        .root_source_file = b.path("src/control_lab/scenarios.zig"),
        .target = target,
        .optimize = optimize,
    });
    control_lab_scenarios_mod.addImport("shift", shift_mod);
    control_lab_scenarios_mod.addImport("control_lab_registry", control_lab_registry_mod);

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
    const test_step = b.step("test", "Run shift unit tests.");
    test_step.dependOn(&run_root_tests.step);

    const example_driver_test_mod = b.createModule(.{
        .root_source_file = b.path("test/example_driver_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_driver_test_mod.addImport("shift", shift_mod);
    const example_driver_tests = b.addTest(.{
        .root_module = example_driver_test_mod,
    });
    const run_example_driver_tests = b.addRunArtifact(example_driver_tests);
    test_step.dependOn(&run_example_driver_tests.step);

    const job_workflow_mod = b.createModule(.{
        .root_source_file = b.path("examples/job_workflow/workflow.zig"),
        .target = target,
        .optimize = optimize,
    });
    job_workflow_mod.addImport("shift", shift_mod);

    const job_workflow_test_mod = b.createModule(.{
        .root_source_file = b.path("test/job_workflow_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    job_workflow_test_mod.addImport("shift", shift_mod);
    job_workflow_test_mod.addImport("job_workflow", job_workflow_mod);
    const job_workflow_tests = b.addTest(.{
        .root_module = job_workflow_test_mod,
    });
    const run_job_workflow_tests = b.addRunArtifact(job_workflow_tests);
    test_step.dependOn(&run_job_workflow_tests.step);

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

    const compile_fail_cmd = b.addSystemCommand(&.{
        "sh",
        "test/compile_fail/run.sh",
    });
    const compile_fail_step = b.step("compile-fail", "Verify compile-fail misuse fixtures.");
    compile_fail_step.dependOn(&compile_fail_cmd.step);
    test_step.dependOn(&compile_fail_cmd.step);

    const docs_sanity_cmd = b.addSystemCommand(&.{
        "sh",
        "-c",
        "if rg -n '^\\{\"id\":\"lrn-' README.md docs; then echo 'raw learnings JSON found in docs' >&2; exit 1; fi",
    });
    const docs_sanity_step = b.step("docs-sanity", "Fail if markdown docs contain raw learnings JSON.");
    docs_sanity_step.dependOn(&docs_sanity_cmd.step);
    check_step.dependOn(&docs_sanity_cmd.step);

    const examples = [_]struct {
        name: []const u8,
        src: []const u8,
        step_name: []const u8,
        step_desc: []const u8,
    }{
        .{
            .name = "effect_state",
            .src = "examples/effect_state.zig",
            .step_name = "run-effect-state",
            .step_desc = "Run the effect-state example.",
        },
        .{
            .name = "generator",
            .src = "examples/generator.zig",
            .step_name = "run-generator",
            .step_desc = "Run the generator example.",
        },
        .{
            .name = "effect_handlers",
            .src = "examples/effect_handlers.zig",
            .step_name = "run-effect-handlers",
            .step_desc = "Run the typed effect-handler example.",
        },
        .{
            .name = "job_workflow",
            .src = "examples/job_workflow/main.zig",
            .step_name = "run-job-workflow",
            .step_desc = "Run the advanced job-workflow example.",
        },
    };

    inline for (examples) |example| {
        const mod = b.createModule(.{
            .root_source_file = b.path(example.src),
            .target = target,
            .optimize = optimize,
        });
        mod.addImport("shift", shift_mod);
        mod.addImport("control_lab_scenarios", control_lab_scenarios_mod);

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

    const control_studio_mod = b.createModule(.{
        .root_source_file = b.path("examples/control_studio/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    control_studio_mod.addImport("shift", shift_mod);
    control_studio_mod.addImport("control_lab_registry", control_lab_registry_mod);
    control_studio_mod.addImport("control_lab_scenarios", control_lab_scenarios_mod);
    const control_studio_exe = b.addExecutable(.{
        .name = "control_studio",
        .root_module = control_studio_mod,
    });
    b.installArtifact(control_studio_exe);
    check_step.dependOn(&control_studio_exe.step);

    const control_studio_run = b.addRunArtifact(control_studio_exe);
    control_studio_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| control_studio_run.addArgs(args);
    const control_studio_run_step = b.step("run-control-studio", "Run the control studio.");
    control_studio_run_step.dependOn(&control_studio_run.step);

    const control_studio_test_mod = b.createModule(.{
        .root_source_file = b.path("test/control_studio_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    control_studio_test_mod.addImport("shift", shift_mod);
    control_studio_test_mod.addImport("control_lab_registry", control_lab_registry_mod);
    control_studio_test_mod.addImport("control_lab_scenarios", control_lab_scenarios_mod);
    const control_studio_tests = b.addTest(.{
        .root_module = control_studio_test_mod,
    });
    const run_control_studio_tests = b.addRunArtifact(control_studio_tests);
    const control_studio_check_step = b.step("control-studio-check", "Verify control studio transcripts and registry coverage.");
    control_studio_check_step.dependOn(&run_control_studio_tests.step);
    test_step.dependOn(&run_control_studio_tests.step);

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

    const lint_step = b.step("lint", "Lint source code.");
    lint_step.dependOn(step: {
        var builder = zlinter.builder(b, .{});
        inline for (@typeInfo(zlinter.BuiltinLintRule).@"enum".fields) |field| {
            builder.addRule(.{ .builtin = @enumFromInt(field.value) }, .{});
        }
        break :step builder.build();
    });
}
