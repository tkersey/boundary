const std = @import("std");
const zlinter = @import("zlinter");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const bench_optimize: std.builtin.OptimizeMode = .ReleaseFast;

    const shift_mod = b.addModule("shift", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const check_step = b.step("check", "Compile the shift module and linear DSL examples.");
    b.default_step.dependOn(check_step);

    const lib_check = b.addObject(.{
        .name = "shift",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    check_step.dependOn(&lib_check.step);

    const docs_sanity_cmd = b.addSystemCommand(&.{
        "sh",
        "-c",
        "if rg -n '^\\{\"id\":\"lrn-' README.md docs; then echo 'raw learnings JSON found in docs' >&2; exit 1; fi",
    });
    const docs_sanity_step = b.step("docs-sanity", "Fail if markdown docs contain raw learnings JSON.");
    docs_sanity_step.dependOn(&docs_sanity_cmd.step);
    check_step.dependOn(&docs_sanity_cmd.step);

    const compile_fail_cmd = b.addSystemCommand(&.{ "sh", "test/compile_fail/run.sh" });
    const compile_fail_step = b.step("compile-fail", "Verify compile-fail misuse fixtures.");
    compile_fail_step.dependOn(&compile_fail_cmd.step);

    const example_specs = [_]struct {
        name: []const u8,
        src: []const u8,
        step_name: []const u8,
        step_desc: []const u8,
    }{
        .{
            .name = "basic_resume",
            .src = "examples/basic_resume.zig",
            .step_name = "run-basic-resume",
            .step_desc = "Run the basic linear DSL example.",
        },
        .{
            .name = "multi_prompt",
            .src = "examples/multi_prompt.zig",
            .step_name = "run-multi-prompt",
            .step_desc = "Run the same-typed multi-prompt linear DSL example.",
        },
        .{
            .name = "delayed_escape",
            .src = "examples/delayed_escape.zig",
            .step_name = "run-delayed-escape",
            .step_desc = "Run the delayed escape linear DSL example.",
        },
        .{
            .name = "workflow_linear",
            .src = "examples/workflow_linear.zig",
            .step_name = "run-workflow-linear",
            .step_desc = "Run the non-toy workflow linear DSL example.",
        },
    };

    inline for (example_specs) |example| {
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

    const smoke_mod = b.createModule(.{
        .root_source_file = b.path("test/smoke_check.zig"),
        .target = target,
        .optimize = optimize,
    });
    smoke_mod.addImport("shift", shift_mod);
    const smoke_exe = b.addExecutable(.{
        .name = "shift-smoke-check",
        .root_module = smoke_mod,
    });
    const smoke_run = b.addRunArtifact(smoke_exe);
    const test_step = b.step("test", "Run the linear-DSL smoke checks and compile-fail harness.");
    test_step.dependOn(&smoke_run.step);
    test_step.dependOn(&compile_fail_cmd.step);

    const size_mod = b.createModule(.{
        .root_source_file = b.path("test/size_check.zig"),
        .target = target,
        .optimize = optimize,
    });
    size_mod.addImport("shift", shift_mod);
    const size_exe = b.addExecutable(.{
        .name = "shift-size-check",
        .root_module = size_mod,
    });
    const size_run = b.addRunArtifact(size_exe);
    const size_step = b.step("size-check", "Run size and surface invariants.");
    size_step.dependOn(&size_run.step);

    const shift_bench_mod = b.addModule("shift_bench", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = bench_optimize,
    });

    const bench_specs = [_]struct {
        name: []const u8,
        src: []const u8,
        step_name: []const u8,
        step_desc: []const u8,
    }{
        .{
            .name = "shift-run-bench",
            .src = "bench/no_capture_bench.zig",
            .step_name = "bench",
            .step_desc = "Run the no-suspend linear runtime benchmark.",
        },
        .{
            .name = "shift-first-suspend-bench",
            .src = "bench/direct_first_suspend_bench.zig",
            .step_name = "bench-first-suspend",
            .step_desc = "Run the first-suspend linear runtime benchmark.",
        },
        .{
            .name = "shift-delayed-escape-bench",
            .src = "bench/delayed_escape_bench.zig",
            .step_name = "bench-delayed-escape",
            .step_desc = "Run the delayed-escape linear runtime benchmark.",
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
            const skip =
                comptime std.mem.eql(u8, field.name, "declaration_naming") or
                std.mem.eql(u8, field.name, "field_ordering") or
                std.mem.eql(u8, field.name, "require_doc_comment") or
                std.mem.eql(u8, field.name, "no_unused") or
                std.mem.eql(u8, field.name, "no_swallow_error");
            if (!skip) builder.addRule(.{ .builtin = @enumFromInt(field.value) }, .{});
        }
        break :step builder.build();
    });
}
