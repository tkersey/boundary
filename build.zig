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
    loaded_execution: *std.Build.Module,
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
        \\tmp="${TMPDIR:-/tmp}/boundary-zig-paths-$$"
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

    const loaded_execution = b.createModule(.{
        .root_source_file = b.path("src/program/loaded_execution.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_execution.addImport("internal_program_plan", internal_program_plan);

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
        .loaded_execution = loaded_execution,
        .interpreter = interpreter,
        .lowering_api = lowering_api,
        .parity_scenarios = parity_scenarios,
    };
}

fn wireBoundaryImports(mod: *std.Build.Module, core: CoreModules) void {
    mod.addImport("portable_core", core.portable_core);
    mod.addImport("lowered_machine", core.lowered_machine);
    mod.addImport("prompt_contract_support", core.prompt_contract);
    mod.addImport("frontend_support", core.frontend);
    mod.addImport("effect_ir", core.effect_ir);
    mod.addImport("helper_body_ir", core.helper_body_ir);
    mod.addImport("internal_kernel", core.internal_kernel);
    mod.addImport("internal_program_plan", core.internal_program_plan);
    mod.addImport("loaded_execution", core.loaded_execution);
    mod.addImport("interpreter", core.interpreter);
    mod.addImport("lowering_api", core.lowering_api);
    mod.addImport("parity_scenarios", core.parity_scenarios);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const bench_optimize: std.builtin.OptimizeMode = .ReleaseFast;
    const test_args = parseTestArgs(b);
    const core = addCoreModules(b, target, optimize);
    const host_core = addCoreModules(b, b.graph.host, optimize);

    const boundary_shared = b.createModule(.{
        .root_source_file = b.path("src/boundary_shared.zig"),
        .target = target,
        .optimize = optimize,
    });
    wireBoundaryImports(boundary_shared, core);

    const protocol_mod = b.createModule(.{
        .root_source_file = b.path("src/protocol.zig"),
        .target = target,
        .optimize = optimize,
    });
    wireBoundaryImports(protocol_mod, core);

    const host_protocol_mod = b.createModule(.{
        .root_source_file = b.path("src/protocol.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    wireBoundaryImports(host_protocol_mod, host_core);

    const protocol_artifacts_mod = b.createModule(.{
        .root_source_file = b.path("src/protocol_artifacts.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    wireBoundaryImports(protocol_artifacts_mod, host_core);
    protocol_artifacts_mod.addImport("protocol", host_protocol_mod);

    const boundary = b.addModule("boundary", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    boundary.addImport("boundary_shared", boundary_shared);

    const lib_check = b.addLibrary(.{
        .linkage = .static,
        .name = "boundary",
        .root_module = boundary,
    });
    b.installArtifact(lib_check);

    const test_step = b.step("test", "Run the boundary test suite.");
    addTestArtifact(b, test_step, boundary, test_args);
    addTestArtifact(b, test_step, boundary_shared, test_args);
    addTestArtifact(b, test_step, core.effect_ir, test_args);
    addTestArtifact(b, test_step, core.frontend, test_args);
    addTestArtifact(b, test_step, core.internal_kernel, test_args);
    addTestArtifact(b, test_step, core.internal_program_plan, test_args);
    addTestArtifact(b, test_step, core.loaded_execution, test_args);
    addTestArtifact(b, test_step, core.lowered_machine, test_args);
    addTestArtifact(b, test_step, core.portable_core, test_args);
    addTestArtifact(b, test_step, protocol_mod, test_args);
    addTestArtifact(b, test_step, protocol_artifacts_mod, test_args);

    const protocol_manifest_step = b.step("check-boundary-protocol-manifest", "Check Boundary v0 protocol manifest encoding and fingerprint.");
    addTestArtifact(b, protocol_manifest_step, host_protocol_mod, test_args);

    const protocol_artifacts_exe = b.addExecutable(.{
        .name = "boundary-protocol-artifacts",
        .root_module = protocol_artifacts_mod,
    });

    const update_public_surface_step = b.step("update-boundary-public-surface", "Update Boundary v0 public-surface snapshot.");
    update_public_surface_step.dependOn(&addRunArtifactWithArgs(b, protocol_artifacts_exe, &.{"update-public-surface"}).step);

    const public_surface_step = b.step("check-boundary-public-surface", "Check Boundary v0 public-surface snapshot for drift.");
    public_surface_step.dependOn(&addRunArtifactWithArgs(b, protocol_artifacts_exe, &.{"check-public-surface"}).step);

    const update_corpus_step = b.step("update-boundary-conformance-corpus", "Update Boundary v0 conformance corpus artifacts.");
    update_corpus_step.dependOn(&addRunArtifactWithArgs(b, protocol_artifacts_exe, &.{"update-corpus"}).step);

    const corpus_step = b.step("check-boundary-conformance-corpus", "Check Boundary v0 conformance corpus artifacts.");
    corpus_step.dependOn(&addRunArtifactWithArgs(b, protocol_artifacts_exe, &.{"check-corpus"}).step);

    const format_drift_step = b.step("check-boundary-format-drift", "Check Boundary v0 format and public-surface drift.");
    format_drift_step.dependOn(&addRunArtifactWithArgs(b, protocol_artifacts_exe, &.{"check-format-drift"}).step);

    const adversarial_codecs_step = b.step("check-boundary-adversarial-codecs", "Check Boundary v0 adversarial codec guardrails.");
    adversarial_codecs_step.dependOn(&addRunArtifactWithArgs(b, protocol_artifacts_exe, &.{"check-adversarial-codecs"}).step);

    const budgets_step = b.step("check-boundary-v0-budgets", "Check Boundary v0 structural budgets.");
    budgets_step.dependOn(&addRunArtifactWithArgs(b, protocol_artifacts_exe, &.{"check-budgets"}).step);

    const proof_receipts_step = b.step("emit-boundary-proof-receipts", "Emit Boundary v0 proof receipts.");
    proof_receipts_step.dependOn(protocol_manifest_step);
    proof_receipts_step.dependOn(public_surface_step);
    proof_receipts_step.dependOn(format_drift_step);
    proof_receipts_step.dependOn(corpus_step);
    proof_receipts_step.dependOn(adversarial_codecs_step);
    proof_receipts_step.dependOn(budgets_step);
    const proof_receipts_run = addRunArtifactWithArgs(b, protocol_artifacts_exe, &.{
        "emit-proof-receipts",
        "--out-dir",
        b.getInstallPath(.prefix, "protocol/boundary/proof-receipts"),
    });
    proof_receipts_run.step.dependOn(protocol_manifest_step);
    proof_receipts_run.step.dependOn(public_surface_step);
    proof_receipts_run.step.dependOn(format_drift_step);
    proof_receipts_run.step.dependOn(corpus_step);
    proof_receipts_run.step.dependOn(adversarial_codecs_step);
    proof_receipts_run.step.dependOn(budgets_step);
    proof_receipts_step.dependOn(&proof_receipts_run.step);

    const dist_boundary_protocol_step = b.step("dist-boundary-protocol", "Build the Boundary v0.5.0 protocol distribution.");
    const dist_boundary_protocol_run = addRunArtifactWithArgs(b, protocol_artifacts_exe, &.{
        "dist",
        "--out-dir",
        b.getInstallPath(.prefix, "dist/boundary-v0.5.0-protocol"),
    });
    dist_boundary_protocol_run.step.dependOn(proof_receipts_step);
    dist_boundary_protocol_step.dependOn(&dist_boundary_protocol_run.step);

    const executable_module_step = b.step("check-boundary-executable-module", "Check executable Certified Boundary Module v2 image foundations.");
    const executable_module_args = TestArgs{
        .filters = &.{"executable plan image"},
        .passthrough = &.{},
    };
    addTestArtifact(b, executable_module_step, boundary, executable_module_args);
    addTestArtifact(b, executable_module_step, boundary_shared, executable_module_args);

    const executable_plan_step = b.step("check-boundary-executable-plan-validation", "Check executable-plan image payload and full-module validation.");
    addTestArtifact(b, executable_plan_step, boundary, executable_module_args);
    addTestArtifact(b, executable_plan_step, boundary_shared, executable_module_args);
    const executable_plan_args = TestArgs{
        .filters = &.{"certified boundary module reference full image and loaded module projections validate"},
        .passthrough = &.{},
    };
    const executable_plan_validation_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    executable_plan_validation_mod.addImport("boundary", boundary);
    const executable_plan_tests = b.addTest(.{ .root_module = executable_plan_validation_mod, .filters = executable_plan_args.filters });
    executable_plan_step.dependOn(&addRunArtifactWithArgs(b, executable_plan_tests, executable_plan_args.passthrough).step);

    const loaded_value_step = b.step("check-boundary-loaded-value", "Check portable loaded value image encoding and validation.");
    const loaded_value_args = TestArgs{
        .filters = &.{"loaded value image"},
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_value_step, core.loaded_execution, loaded_value_args);
    addTestArtifact(b, loaded_value_step, boundary_shared, loaded_value_args);

    const loaded_session_step = b.step("check-boundary-loaded-session", "Check loaded module session surface and profile compatibility.");
    const loaded_session_args = TestArgs{
        .filters = &.{"loaded"},
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_session_step, core.loaded_execution, loaded_session_args);
    addTestArtifact(b, loaded_session_step, boundary_shared, loaded_session_args);
    const loaded_evidence_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_evidence_mod.addImport("boundary", boundary);
    const loaded_evidence_tests = b.addTest(.{ .root_module = loaded_evidence_mod, .filters = loaded_session_args.filters });
    loaded_session_step.dependOn(&addRunArtifactWithArgs(b, loaded_evidence_tests, loaded_session_args.passthrough).step);

    const loaded_v2_step = b.step("check-boundary-loaded-v2", "Check Boundary portable_v2 loaded execution profile gates.");
    const loaded_v2_args = TestArgs{
        .filters = &.{"portable v2"},
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_v2_step, core.loaded_execution, loaded_v2_args);
    const loaded_v2_core_evidence_mod = b.createModule(.{
        .root_source_file = b.path("src/program/evidence.zig"),
        .target = target,
        .optimize = optimize,
    });
    wireBoundaryImports(loaded_v2_core_evidence_mod, core);
    const loaded_v2_core_evidence_tests = b.addTest(.{ .root_module = loaded_v2_core_evidence_mod, .filters = loaded_v2_args.filters });
    loaded_v2_step.dependOn(&addRunArtifactWithArgs(b, loaded_v2_core_evidence_tests, loaded_v2_args.passthrough).step);
    const loaded_v2_evidence_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_v2_evidence_mod.addImport("boundary", boundary);
    const loaded_v2_evidence_tests = b.addTest(.{ .root_module = loaded_v2_evidence_mod, .filters = loaded_v2_args.filters });
    loaded_v2_step.dependOn(&addRunArtifactWithArgs(b, loaded_v2_evidence_tests, loaded_v2_args.passthrough).step);

    const loaded_profile_codecs_step = b.step("check-boundary-loaded-profile-codecs", "Check loaded profile instruction and value codec gates.");
    const profile_codec_core_args = TestArgs{
        .filters = &.{
            "loaded execution profile",
            "loaded value image",
        },
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_profile_codecs_step, core.loaded_execution, profile_codec_core_args);
    const loaded_profile_codecs_args = TestArgs{
        .filters = &.{
            "certified boundary module reference full image and loaded module projections validate",
            "loaded executable portable v2 gates reachable arithmetic before session construction",
            "loaded executable portable v2 uses portable word semantics",
        },
        .passthrough = &.{},
    };
    const loaded_profile_codecs_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_profile_codecs_mod.addImport("boundary", boundary);
    const loaded_profile_codecs_tests = b.addTest(.{ .root_module = loaded_profile_codecs_mod, .filters = loaded_profile_codecs_args.filters });
    loaded_profile_codecs_step.dependOn(&addRunArtifactWithArgs(b, loaded_profile_codecs_tests, loaded_profile_codecs_args.passthrough).step);

    const loaded_reachability_step = b.step("check-boundary-loaded-reachability", "Check reachability-scoped loaded execution compatibility gates.");
    const loaded_reachability_core_args = TestArgs{
        .filters = &.{
            "loaded reachability ignores unsupported dead helper semantics and codecs",
            "loaded portable v2 rejects unsupported helper parking shape before mutable session construction",
        },
        .passthrough = &.{},
    };
    const loaded_reachability_core_mod = b.createModule(.{
        .root_source_file = b.path("src/program/evidence.zig"),
        .target = target,
        .optimize = optimize,
    });
    wireBoundaryImports(loaded_reachability_core_mod, core);
    const loaded_reachability_core_tests = b.addTest(.{ .root_module = loaded_reachability_core_mod, .filters = loaded_reachability_core_args.filters });
    loaded_reachability_step.dependOn(&addRunArtifactWithArgs(b, loaded_reachability_core_tests, loaded_reachability_core_args.passthrough).step);
    const loaded_reachability_args = TestArgs{
        .filters = &.{
            "certified boundary module reference full image and loaded module projections validate",
            "loaded executable portable v2 gates reachable arithmetic before session construction",
            "loaded executable ignores dead helper call sites for residual imports",
            "loaded executable rejects choice operation mode",
        },
        .passthrough = &.{},
    };
    const loaded_reachability_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_reachability_mod.addImport("boundary", boundary);
    const loaded_reachability_tests = b.addTest(.{ .root_module = loaded_reachability_mod, .filters = loaded_reachability_args.filters });
    loaded_reachability_step.dependOn(&addRunArtifactWithArgs(b, loaded_reachability_tests, loaded_reachability_args.passthrough).step);

    const loaded_continuation_step = b.step("check-boundary-loaded-continuation", "Check portable loaded session continuation images.");
    const loaded_continuation_args = TestArgs{
        .filters = &.{"loaded session image"},
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_continuation_step, core.loaded_execution, loaded_continuation_args);
    addTestArtifact(b, loaded_continuation_step, boundary_shared, loaded_continuation_args);

    const loaded_session_image_step = b.step("check-boundary-loaded-session-image", "Check loaded session image validation regressions.");
    const loaded_session_image_args = TestArgs{
        .filters = &.{
            "loaded session image roundtrips failure state and rejects trailing bytes",
            "loaded session image binds declared failure ref to diagnostic summary",
            "loaded session image rejects status-inconsistent fuel ledger",
            "loaded session image v2 rejects present continuation with zero frames",
            "loaded session image binds fingerprinted identity fields",
        },
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_session_image_step, core.loaded_execution, loaded_session_image_args);

    const loaded_forged_session_step = b.step("check-boundary-loaded-forged-session-image", "Check forged loaded session image rejection regressions.");
    const loaded_forged_session_args = TestArgs{
        .filters = &.{
            "loaded session image rejects forged session fingerprint",
            "loaded session image rejects forged result fingerprint",
            "loaded session image v2 binds pending continuation fingerprint to continuation image",
            "loaded session image rejects malformed embedded value images",
            "loaded session image rejects embedded value ref mismatch",
        },
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_forged_session_step, core.loaded_execution, loaded_forged_session_args);
    const forged_session_evidence_args = TestArgs{
        .filters = &.{
            "loaded executable portable v2 restores helper frame parked on residual request",
            "loaded malformed rejects forged v2 continuation frame topology",
        },
        .passthrough = &.{},
    };
    const loaded_forged_session_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_forged_session_mod.addImport("boundary", boundary);
    const loaded_forged_session_tests = b.addTest(.{ .root_module = loaded_forged_session_mod, .filters = forged_session_evidence_args.filters });
    loaded_forged_session_step.dependOn(&addRunArtifactWithArgs(b, loaded_forged_session_tests, forged_session_evidence_args.passthrough).step);

    const loaded_resource_ledger_step = b.step("check-boundary-loaded-resource-ledger", "Check loaded session fuel and allocation ledger regressions.");
    const loaded_resource_ledger_args = TestArgs{
        .filters = &.{
            "loaded session image rejects status-inconsistent fuel ledger",
            "loaded session image rejects oversized owned value byte lengths before allocation",
            "loaded session allocation ledger uses checked arithmetic",
            "loaded session image rejects v2-only state hidden inside v1 image",
        },
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_resource_ledger_step, core.loaded_execution, loaded_resource_ledger_args);
    const ledger_evidence_args = TestArgs{
        .filters = &.{
            "loaded executable portable v2 gates reachable arithmetic before session construction",
            "loaded executable portable v2 accepts canonical entry arguments",
        },
        .passthrough = &.{},
    };
    const loaded_resource_ledger_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_resource_ledger_mod.addImport("boundary", boundary);
    const loaded_resource_ledger_tests = b.addTest(.{ .root_module = loaded_resource_ledger_mod, .filters = ledger_evidence_args.filters });
    loaded_resource_ledger_step.dependOn(&addRunArtifactWithArgs(b, loaded_resource_ledger_tests, ledger_evidence_args.passthrough).step);

    const loaded_frame_stack_step = b.step("check-boundary-loaded-frame-stack", "Check portable loaded helper frame stack parking and restoration.");
    const loaded_frame_stack_args = TestArgs{
        .filters = &.{
            "frame stack",
            "nested helper parking restores canonical result",
            "continuation frame topology",
        },
        .passthrough = &.{},
    };
    const loaded_frame_stack_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_frame_stack_mod.addImport("boundary", boundary);
    const loaded_frame_stack_tests = b.addTest(.{ .root_module = loaded_frame_stack_mod, .filters = loaded_frame_stack_args.filters });
    loaded_frame_stack_step.dependOn(&addRunArtifactWithArgs(b, loaded_frame_stack_tests, loaded_frame_stack_args.passthrough).step);

    const loaded_parity_step = b.step("check-boundary-generated-loaded-parity", "Check generated Program.Session and LoadedModule.Session canonical parity.");
    const loaded_parity_required_step = b.step("check-boundary-loaded-parity", "Check generated Program.Session and LoadedModule.Session canonical parity.");
    const loaded_parity_args = TestArgs{
        .filters = &.{"generated-loaded parity"},
        .passthrough = &.{},
    };
    const loaded_parity_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_parity_mod.addImport("boundary", boundary);
    const loaded_parity_tests = b.addTest(.{ .root_module = loaded_parity_mod, .filters = loaded_parity_args.filters });
    const loaded_parity_run = addRunArtifactWithArgs(b, loaded_parity_tests, loaded_parity_args.passthrough);
    loaded_parity_step.dependOn(&loaded_parity_run.step);
    loaded_parity_required_step.dependOn(&loaded_parity_run.step);

    const loaded_import_bindings_step = b.step("check-boundary-loaded-import-bindings", "Check exact loaded residual import/site binding regressions.");
    const loaded_import_bindings_args = TestArgs{
        .filters = &.{
            "loaded executable binds residual imports by site index",
            "loaded executable ignores dead helper call sites for residual imports",
            "loaded executable portable v2 executes two sequential residual requests",
            "generated-loaded parity canonical request bytes and i32 result",
        },
        .passthrough = &.{},
    };
    const loaded_import_bindings_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_import_bindings_mod.addImport("boundary", boundary);
    const loaded_import_bindings_tests = b.addTest(.{ .root_module = loaded_import_bindings_mod, .filters = loaded_import_bindings_args.filters });
    loaded_import_bindings_step.dependOn(&addRunArtifactWithArgs(b, loaded_import_bindings_tests, loaded_import_bindings_args.passthrough).step);

    const loaded_response_safety_step = b.step("check-boundary-loaded-response-safety", "Check loaded response rejection preserves parked session state.");
    const loaded_response_safety_args = TestArgs{
        .filters = &.{
            "loaded executable portable v2 executes two sequential residual requests",
            "loaded executable portable v2 restores helper frame parked on residual request",
            "generated-loaded parity structured sum response extracts product result",
        },
        .passthrough = &.{},
    };
    const loaded_response_safety_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_response_safety_mod.addImport("boundary", boundary);
    const loaded_response_safety_tests = b.addTest(.{ .root_module = loaded_response_safety_mod, .filters = loaded_response_safety_args.filters });
    loaded_response_safety_step.dependOn(&addRunArtifactWithArgs(b, loaded_response_safety_tests, loaded_response_safety_args.passthrough).step);

    const loaded_malformed_step = b.step("check-boundary-loaded-malformed", "Check malformed loaded module/value/session/response rejection.");
    const loaded_malformed_args = TestArgs{
        .filters = &.{
            "loaded value image rejects",
            "loaded session image rejects",
            "loaded session image v2 rejects",
            "loaded session image roundtrips failure state and rejects trailing bytes",
            "loaded malformed",
        },
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_malformed_step, core.loaded_execution, loaded_malformed_args);
    const loaded_malformed_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_malformed_mod.addImport("boundary", boundary);
    const loaded_malformed_tests = b.addTest(.{ .root_module = loaded_malformed_mod, .filters = loaded_malformed_args.filters });
    loaded_malformed_step.dependOn(&addRunArtifactWithArgs(b, loaded_malformed_tests, loaded_malformed_args.passthrough).step);

    const loaded_payload_result_step = b.step("check-boundary-loaded-payload-result-images", "Check loaded payload and result image binding regressions.");
    const loaded_payload_result_args = TestArgs{
        .filters = &.{
            "loaded session image rejects forged result fingerprint",
            "certified boundary module reference full image and loaded module projections validate",
            "loaded executable session parks unit payload residual request",
        },
        .passthrough = &.{},
    };
    addTestArtifact(b, loaded_payload_result_step, core.loaded_execution, loaded_payload_result_args);
    const loaded_payload_result_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_payload_result_mod.addImport("boundary", boundary);
    const loaded_payload_result_tests = b.addTest(.{ .root_module = loaded_payload_result_mod, .filters = loaded_payload_result_args.filters });
    loaded_payload_result_step.dependOn(&addRunArtifactWithArgs(b, loaded_payload_result_tests, loaded_payload_result_args.passthrough).step);

    const loaded_fuzz_step = b.step("check-boundary-loaded-fuzz", "Check deterministic malformed loaded execution fuzz seeds.");
    const loaded_fuzz_args = TestArgs{
        .filters = &.{"loaded fuzz"},
        .passthrough = &.{},
    };
    const loaded_fuzz_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    loaded_fuzz_mod.addImport("boundary", boundary);
    const loaded_fuzz_tests = b.addTest(.{ .root_module = loaded_fuzz_mod, .filters = loaded_fuzz_args.filters });
    loaded_fuzz_step.dependOn(&addRunArtifactWithArgs(b, loaded_fuzz_tests, loaded_fuzz_args.passthrough).step);

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
        .root_source_file = b.path("src/internal/synthetic_boundary_root.zig"),
        .target = target,
        .optimize = optimize,
    });
    synthetic_root_tests_mod.addImport("boundary_shared", boundary_shared);
    addTestArtifact(b, test_step, synthetic_root_tests_mod, test_args);

    const agent_loop_tests_mod = b.createModule(.{
        .root_source_file = b.path("examples/agent_loop.zig"),
        .target = target,
        .optimize = optimize,
    });
    agent_loop_tests_mod.addImport("boundary", boundary);
    addTestArtifact(b, test_step, agent_loop_tests_mod, test_args);

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
    const custom_approval_mod = b.createModule(.{
        .root_source_file = b.path("examples/custom_approval_workflow.zig"),
        .target = target,
        .optimize = optimize,
    });
    custom_approval_mod.addImport("boundary", boundary);
    plan_native_resource_mod.addImport("boundary", boundary);
    program_api_tests_mod.addImport("boundary", boundary);
    program_api_tests_mod.addImport("custom_approval_workflow", custom_approval_mod);
    program_api_tests_mod.addImport("plan_native_resource", plan_native_resource_mod);
    const program_api_tests = b.addTest(.{ .root_module = program_api_tests_mod, .filters = test_args.filters });
    test_step.dependOn(&addRunArtifactWithArgs(b, program_api_tests, test_args.passthrough).step);

    const evidence_kernel_tests_mod = b.createModule(.{
        .root_source_file = b.path("test/evidence_kernel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    evidence_kernel_tests_mod.addImport("boundary", boundary);
    const evidence_kernel_tests = b.addTest(.{ .root_module = evidence_kernel_tests_mod, .filters = test_args.filters });
    test_step.dependOn(&addRunArtifactWithArgs(b, evidence_kernel_tests, test_args.passthrough).step);

    const contract_matrix_mod = b.createModule(.{
        .root_source_file = b.path("test/plan_native_contract_matrix_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    contract_matrix_mod.addImport("boundary", boundary);
    const contract_matrix_tests = b.addTest(.{ .root_module = contract_matrix_mod, .filters = test_args.filters });
    test_step.dependOn(&addRunArtifactWithArgs(b, contract_matrix_tests, test_args.passthrough).step);

    const public_optional_tests_mod = b.createModule(.{
        .root_source_file = b.path("test/public_optional_bound_program_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    public_optional_tests_mod.addImport("boundary", boundary);
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
            .expected_error = "schema.LowerBinding requires a schema ref for product/sum resume type 'schema_lower_binding_product_ref.ProductPayload'",
        },
        .{
            .path = "test/compile_fail/schema_refs_scalar_entry.zig",
            .expected_error = "is scalar and must not carry a schema index",
        },
        .{
            .path = "test/compile_fail/schema_refs_duplicate_type.zig",
            .expected_error = "schema.SchemaRefs has duplicate entry for type 'schema_refs_duplicate_type.ProductPayload'",
        },
        .{
            .path = "test/compile_fail/schema_refs_unsupported_type.zig",
            .expected_error = "schema.SchemaRefs unsupported type '*const i32': UnsupportedCodecType",
        },
        .{
            .path = "test/compile_fail/schema_registry_duplicate_structured_type.zig",
            .expected_error = "schema.Registry has duplicate structured type 'schema_registry_duplicate_structured_type.ProductPayload'",
        },
        .{
            .path = "test/compile_fail/schema_registry_missing_nested_ref.zig",
            .expected_error = "schema.Registry missing nested structured type 'schema_registry_missing_nested_ref.InnerPayload' referenced by 'schema_registry_missing_nested_ref.OuterPayload'",
        },
        .{
            .path = "test/compile_fail/schema_registry_unsupported_type.zig",
            .expected_error = "schema.Registry unsupported type '*const i32': UnsupportedCodecType",
        },
        .{
            .path = "test/compile_fail/schema_protocol_empty_label.zig",
            .expected_error = "schema.Protocol requires a non-empty label",
        },
        .{
            .path = "test/compile_fail/schema_protocol_duplicate_op_name.zig",
            .expected_error = "schema.Protocol has duplicate op name 'exists'",
        },
        .{
            .path = "test/compile_fail/schema_protocol_empty_op_name.zig",
            .expected_error = "schema.Protocol op name must be non-empty",
        },
        .{
            .path = "test/compile_fail/schema_protocol_missing_product_ref.zig",
            .expected_error = "schema.LowerBinding requires a schema ref for product/sum payload type 'schema_protocol_missing_product_ref.ProductPayload'",
        },
        .{
            .path = "test/compile_fail/schema_protocol_missing_sum_ref.zig",
            .expected_error = "schema.LowerBinding requires a schema ref for product/sum resume type 'schema_protocol_missing_sum_ref.Decision'",
        },
        .{
            .path = "test/compile_fail/schema_protocol_operation_missing_product_ref.zig",
            .expected_error = "schema.Protocol operation requires a schema ref for product/sum payload type 'schema_protocol_operation_missing_product_ref.ProductPayload'",
        },
        .{
            .path = "test/compile_fail/schema_protocol_operation_missing_sum_result_ref.zig",
            .expected_error = "schema.Protocol operation requires a schema ref for product/sum result type 'schema_protocol_operation_missing_sum_result_ref.Decision'",
        },
        .{
            .path = "test/compile_fail/schema_protocol_transform_result.zig",
            .expected_error = "schema.Protocol transform operation does not accept Result",
        },
        .{
            .path = "test/compile_fail/semantic_protocol_payload_mismatch.zig",
            .expected_error = "semantic builder protocol call payload type mismatch",
        },
        .{
            .path = "test/compile_fail/semantic_protocol_resume_mismatch.zig",
            .expected_error = "semantic builder protocol call destination/resume type mismatch",
        },
        .{
            .path = "test/compile_fail/semantic_invalid_branch_target.zig",
            .expected_error = "semantic builder block not found: missing",
        },
        .{
            .path = "test/compile_fail/semantic_local_type_mismatch.zig",
            .expected_error = "semantic builder constString destination must be string",
        },
        .{
            .path = "test/compile_fail/semantic_empty_site_label.zig",
            .expected_error = "semantic builder protocol call label must be non-empty",
        },
        .{
            .path = "test/compile_fail/semantic_schema_registry_duplicate_tables.zig",
            .expected_error = "semantic builder derives value_schemas from schemas; omit the explicit table",
        },
        .{
            .path = "test/compile_fail/custom_protocol_coverage_omitted_operation.zig",
            .expected_error = "Program.protocol coverage omitted reachable operation site",
        },
        .{
            .path = "test/compile_fail/protocol_coverage_omitted_operation.zig",
            .expected_error = "Program.protocol coverage omitted reachable operation site",
        },
        .{
            .path = "test/compile_fail/protocol_coverage_omitted_after.zig",
            .expected_error = "Program.protocol coverage omitted reachable after site",
        },
        .{
            .path = "test/compile_fail/protocol_coverage_duplicate_site.zig",
            .expected_error = "Program.protocol coverage listed duplicate operation site",
        },
        .{
            .path = "test/compile_fail/protocol_coverage_foreign_site.zig",
            .expected_error = "Program.protocol coverage descriptor belongs to another program",
        },
        .{
            .path = "test/compile_fail/provider_harness_duplicate_handler.zig",
            .expected_error = "Program.Exchange.ProviderHarness listed duplicate operation handler",
        },
        .{
            .path = "test/compile_fail/provider_harness_forged_semantic_body.zig",
            .expected_error = "Program.Exchange.ProviderHarness function-backed entries must declare host_intrinsic semantic body",
        },
        .{
            .path = "test/compile_fail/provider_harness_forged_program_mapping.zig",
            .expected_error = "Program.Exchange.ProviderHarness program-backed entries must be declared with ProviderHandler.program",
        },
        .{
            .path = "test/compile_fail/provider_program_payload_arg_mismatch.zig",
            .expected_error = "provider Program payload_to_args argument schema does not match request payload/current-value schema",
        },
        .{
            .path = "test/compile_fail/provider_program_mapper_fingerprint_reserved.zig",
            .expected_error = "provider Program mapper_fingerprint is reserved until provider-program custom mapper execution is implemented",
        },
        .{
            .path = "test/compile_fail/provider_program_structured_schema_mismatch.zig",
            .expected_error = "provider Program payload_to_args argument schema does not match request payload/current-value schema",
        },
        .{
            .path = "test/compile_fail/provider_program_transform_return_now.zig",
            .expected_error = "provider Program result_to_return_now requires a return-now operation offer",
        },
        .{
            .path = "test/compile_fail/provider_program_metadata_mapping_reserved.zig",
            .expected_error = "provider Program payload_and_metadata_to_args is reserved until provider-program metadata argument execution is implemented",
        },
        .{
            .path = "test/compile_fail/provider_program_outcome_union_reserved.zig",
            .expected_error = "provider Program result_to_outcome_union is reserved until provider-program outcome-union execution is implemented",
        },
        .{
            .path = "test/compile_fail/protocol_request_foreign_site.zig",
            .expected_error = "Program.protocol descriptor belongs to another program",
        },
        .{
            .path = "test/compile_fail/protocol_target_response_abort_resume.zig",
            .expected_error = "Program.Handler.TargetResponse abort rejects resume",
        },
        .{
            .path = "test/compile_fail/protocol_target_response_transform_return_now.zig",
            .expected_error = "Program.Handler.TargetResponse transform rejects return_now",
        },
        .{
            .path = "test/compile_fail/interpreter_invalid_transform_return_now.zig",
            .expected_error = "Program.Handler.returnNow is invalid for this operation site",
        },
        .{
            .path = "test/compile_fail/interpreter_duplicate_handler.zig",
            .expected_error = "Program.Interpreter listed duplicate handler for site",
        },
        .{
            .path = "test/compile_fail/interpreter_duplicate_protocol_operation_handler.zig",
            .expected_error = "Program.Interpreter listed duplicate protocol operation handler",
        },
        .{
            .path = "test/compile_fail/interpreter_elimination_missing_protocol_operation.zig",
            .expected_error = "Program.Interpreter elimination omitted emitted protocol operation",
        },
        .{
            .path = "test/compile_fail/interpreter_effect_row_foreign_program.zig",
            .expected_error = "Program.Interpreter effectRow expected owning Program type",
        },
        .{
            .path = "test/compile_fail/interpreter_plain_operation_reinterpret.zig",
            .expected_error = "plain operation handlers cannot return reinterpret outcomes",
        },
        .{
            .path = "test/compile_fail/interpreter_protocol_handler_nested_mutable_payload.zig",
            .expected_error = "Program.Handler protocol request payload contains mutable string-list storage",
        },
        .{
            .path = "test/compile_fail/interpreter_protocol_handler_mutable_payload.zig",
            .expected_error = "cannot assign to constant",
        },
        .{
            .path = "test/compile_fail/interpreter_reinterpreted_mutable_payload.zig",
            .expected_error = "cannot assign to constant",
        },
        .{
            .path = "test/compile_fail/interpreter_foreign_site.zig",
            .expected_error = "Program.Handler site descriptor belongs to another program",
        },
        .{
            .path = "test/compile_fail/interpreter_forged_semantic_body.zig",
            .expected_error = "Program.Interpreter function-backed entries must declare host_intrinsic semantic body",
        },
        .{
            .path = "test/compile_fail/interpreter_coverage_omitted_operation.zig",
            .expected_error = "Program.Interpreter coverage omitted reachable operation site",
        },
        .{
            .path = "test/compile_fail/interpreter_coverage_omitted_after.zig",
            .expected_error = "Program.Interpreter coverage omitted reachable after site",
        },
        .{
            .path = "test/compile_fail/interpreter_coverage_fake_interpreter.zig",
            .expected_error = "Program.protocol expected a Program.Interpreter type",
        },
        .{
            .path = "test/compile_fail/reinterpret_mapper_invalid_source_outcome.zig",
            .expected_error = "Program.Handler.reinterpret mapper resume must return Program.Handler.SourceOutcome(SourceSite)",
        },
        .{
            .path = "test/compile_fail/reinterpret_mapper_invalid_resume_param.zig",
            .expected_error = "Program.Handler.reinterpret mapper resume parameter must match target protocol operation type",
        },
        .{
            .path = "test/compile_fail/reinterpret_mapper_invalid_return_param.zig",
            .expected_error = "Program.Handler.reinterpret mapper returnNow parameter must match target protocol operation type",
        },
        .{
            .path = "test/compile_fail/boundary_target_schema_mismatch.zig",
            .expected_error = "Boundary Target world-port schema mismatch",
        },
        .{
            .path = "test/compile_fail/boundary_target_direct_world_port_schema_witness.zig",
            .expected_error = "Boundary Target world-port source-map entry is missing schema witness",
        },
        .{
            .path = "test/compile_fail/boundary_target_operation_identity_mismatch.zig",
            .expected_error = "Boundary Target world-port schema mismatch",
        },
        .{
            .path = "test/compile_fail/boundary_target_world_port_absent_coordinate.zig",
            .expected_error = "BoundaryClosure.Elaboration world port shape coordinates do not match a residual Program site",
        },
        .{
            .path = "test/compile_fail/boundary_target_world_port_coordinate_mismatch.zig",
            .expected_error = "BoundaryClosure.Elaboration world port shape coordinates do not match a residual Program site",
        },
        .{
            .path = "test/compile_fail/boundary_target_missing_residual_program.zig",
            .expected_error = "Boundary Target requires .residual_program or .root; no residual target generation path is implemented",
        },
        .{
            .path = "test/compile_fail/boundary_target_residual_program_mismatch.zig",
            .expected_error = "Boundary Target residual Program does not match elaborated body certificate",
        },
        .{
            .path = "test/compile_fail/boundary_target_body_policy_mismatch.zig",
            .expected_error = "Boundary Target body policy does not match target policy",
        },
        .{
            .path = "test/compile_fail/boundary_target_program_backed_requirement.zig",
            .expected_error = "BoundaryClosure.Elaboration input rejected residual Program: BoundaryElaborationBlocked",
        },
    };
    inline for (compile_fail_specs) |spec| {
        const compile_fail_mod = b.createModule(.{
            .root_source_file = b.path(spec.path),
            .target = target,
            .optimize = optimize,
        });
        compile_fail_mod.addImport("boundary", boundary);
        addCompileFailArtifact(b, compile_fail_step, compile_fail_mod, spec.expected_error);
    }

    const examples = [_]struct {
        name: []const u8,
        path: []const u8,
        step: []const u8,
        desc: []const u8,
    }{
        .{ .name = "boundary-state-basic", .path = "examples/state_basic.zig", .step = "run-state-basic", .desc = "Run the state effect example." },
        .{ .name = "boundary-typed-program-plan", .path = "examples/typed_program_plan.zig", .step = "run-typed-program-plan", .desc = "Run the typed ProgramPlan example." },
        .{ .name = "boundary-plan-native-optional", .path = "examples/plan_native_optional.zig", .step = "run-plan-native-optional", .desc = "Run the plan-native optional example." },
        .{ .name = "boundary-plan-native-state-reader", .path = "examples/plan_native_state_reader.zig", .step = "run-plan-native-state-reader", .desc = "Run the plan-native state/reader example." },
        .{ .name = "boundary-plan-native-writer", .path = "examples/plan_native_writer.zig", .step = "run-plan-native-writer", .desc = "Run the plan-native writer example." },
        .{ .name = "boundary-plan-native-exception", .path = "examples/plan_native_exception.zig", .step = "run-plan-native-exception", .desc = "Run the plan-native exception example." },
        .{ .name = "boundary-plan-native-resource", .path = "examples/plan_native_resource.zig", .step = "run-plan-native-resource", .desc = "Run the plan-native resource example." },
        .{ .name = "boundary-custom-approval-workflow", .path = "examples/custom_approval_workflow.zig", .step = "run-custom-approval-workflow", .desc = "Run the custom approval workflow example." },
        .{ .name = "boundary-agent-loop", .path = "examples/agent_loop.zig", .step = "run-agent-loop", .desc = "Run the host-driven Program.Session agent loop example." },
        .{ .name = "boundary-continuation-branching", .path = "examples/continuation_branching.zig", .step = "run-continuation-branching", .desc = "Run the Program.Session continuation capsule branching example." },
        .{ .name = "boundary-interpreter-branching", .path = "examples/interpreter_branching.zig", .step = "run-interpreter-branching", .desc = "Run the continuation-aware Program.Interpreter branching example." },
        .{ .name = "boundary-protocol-reinterpretation", .path = "examples/protocol_reinterpretation.zig", .step = "run-protocol-reinterpretation", .desc = "Run the protocol morphism reinterpretation example." },
        .{ .name = "boundary-residualized-approval-policy", .path = "examples/residualized_approval_policy.zig", .step = "run-residualized-approval-policy", .desc = "Run the residualized approval policy example." },
        .{ .name = "boundary-effect-pipeline", .path = "examples/effect_pipeline.zig", .step = "run-effect-pipeline", .desc = "Run the proof-carrying effect pipeline example." },
        .{ .name = "boundary-effect-capability-routing", .path = "examples/effect_capability_routing.zig", .step = "run-effect-capability-routing", .desc = "Run the capability-routed Effect Exchange example." },
        .{ .name = "boundary-effect-capability-attenuation", .path = "examples/effect_capability_attenuation.zig", .step = "run-effect-capability-attenuation", .desc = "Run the Effect Exchange capability attenuation example." },
        .{ .name = "boundary-effect-treaty-direct", .path = "examples/effect_treaty_direct.zig", .step = "run-effect-treaty-direct", .desc = "Run the direct Effect Treaty negotiation example." },
        .{ .name = "boundary-effect-treaty-morphism", .path = "examples/effect_treaty_morphism.zig", .step = "run-effect-treaty-morphism", .desc = "Run the morphism-adapted Effect Treaty negotiation example." },
        .{ .name = "boundary-effect-treaty-replayable", .path = "examples/effect_treaty_replayable.zig", .step = "run-effect-treaty-replayable", .desc = "Run the replay-policy Effect Treaty example." },
        .{ .name = "boundary-provider-harness-direct", .path = "examples/provider_harness_direct.zig", .step = "run-provider-harness-direct", .desc = "Run the direct ProviderHarness treaty execution example." },
        .{ .name = "boundary-provider-harness-morphism", .path = "examples/provider_harness_morphism.zig", .step = "run-provider-harness-morphism", .desc = "Run the morphism ProviderHarness treaty execution example." },
        .{ .name = "boundary-provider-harness-replayable", .path = "examples/provider_harness_replayable.zig", .step = "run-provider-harness-replayable", .desc = "Run the replayable ProviderHarness treaty execution example." },
        .{ .name = "boundary-defunctionalization-boundary", .path = "examples/defunctionalization_boundary.zig", .step = "run-defunctionalization-boundary", .desc = "Run the defunctionalization boundary audit example." },
        .{ .name = "boundary-host-intrinsic-allowlist", .path = "examples/host_intrinsic_allowlist.zig", .step = "run-host-intrinsic-allowlist", .desc = "Run the host intrinsic allowlist example." },
        .{ .name = "boundary-closure-strict", .path = "examples/boundary_closure_strict.zig", .step = "run-boundary-closure-strict", .desc = "Run the strict Boundary Closure Certificate example." },
        .{ .name = "boundary-closure-nested", .path = "examples/boundary_closure_nested.zig", .step = "run-boundary-closure-nested", .desc = "Run the nested Boundary Closure Certificate example." },
        .{ .name = "boundary-closure-world-port", .path = "examples/boundary_closure_world_port.zig", .step = "run-boundary-closure-world-port", .desc = "Run the world-port Boundary Closure Certificate example." },
        .{ .name = "boundary-elaboration-strict", .path = "examples/boundary_elaboration_strict.zig", .step = "run-boundary-elaboration-strict", .desc = "Run the strict Boundary Closure Elaboration example." },
        .{ .name = "boundary-elaboration-nested", .path = "examples/boundary_elaboration_nested.zig", .step = "run-boundary-elaboration-nested", .desc = "Run the nested Boundary Closure Elaboration example." },
        .{ .name = "boundary-elaboration-world-port", .path = "examples/boundary_elaboration_world_port.zig", .step = "run-boundary-elaboration-world-port", .desc = "Run the world-port Boundary Closure Elaboration example." },
        .{ .name = "boundary-world-surface-strict", .path = "examples/world_surface_strict.zig", .step = "run-world-surface-strict", .desc = "Run the strict Certified Boundary Target WorldSurface example." },
        .{ .name = "boundary-world-surface-nested", .path = "examples/world_surface_nested.zig", .step = "run-world-surface-nested", .desc = "Run the scoped root-copy Certified Boundary Target WorldSurface example." },
        .{ .name = "boundary-world-surface-ports", .path = "examples/world_surface_ports.zig", .step = "run-world-surface-ports", .desc = "Run the world-port Certified Boundary Target WorldSurface example." },
        .{ .name = "boundary-module-reference", .path = "examples/boundary_module_reference.zig", .step = "run-boundary-module-reference", .desc = "Run the Certified Boundary Module reference transfer example." },
        .{ .name = "boundary-module-roundtrip", .path = "examples/boundary_module_roundtrip.zig", .step = "run-boundary-module-roundtrip", .desc = "Run the Certified Boundary Module full-image roundtrip example." },
        .{ .name = "boundary-module-loaded-run", .path = "examples/boundary_module_loaded_run.zig", .step = "run-boundary-module-loaded-run", .desc = "Run the LoadedModule fail-closed execution surface example." },
        .{ .name = "boundary-module-agent-transfer", .path = "examples/boundary_module_agent_transfer.zig", .step = "run-boundary-module-agent-transfer", .desc = "Run the agent-shaped Certified Boundary Module transfer example." },
        .{ .name = "boundary-module-inspect", .path = "examples/boundary_module_inspect.zig", .step = "run-boundary-module-inspect", .desc = "Run the LoadedModule inspection helper example." },
        .{ .name = "boundary-module-imports", .path = "examples/boundary_module_imports.zig", .step = "run-boundary-module-imports", .desc = "Run the ImportSurface projection and binding report example." },
        .{ .name = "boundary-module-diagnostics", .path = "examples/boundary_module_diagnostics.zig", .step = "run-boundary-module-diagnostics", .desc = "Run the structured module validation diagnostic example." },
        .{ .name = "boundary-module-compatibility", .path = "examples/boundary_module_compatibility.zig", .step = "run-boundary-module-compatibility", .desc = "Run the module compatibility report example." },
        .{ .name = "boundary-normalization-provider", .path = "examples/boundary_normalization_provider.zig", .step = "run-boundary-normalization-provider", .desc = "Run the provider Boundary Normalization Calculus example." },
        .{ .name = "boundary-normalization-nested", .path = "examples/boundary_normalization_nested.zig", .step = "run-boundary-normalization-nested", .desc = "Run the nested Boundary Normalization Calculus example." },
        .{ .name = "boundary-normalization-ports", .path = "examples/boundary_normalization_ports.zig", .step = "run-boundary-normalization-ports", .desc = "Run the WorldPort Boundary Normalization Calculus example." },
        .{ .name = "boundary-program-provider-direct", .path = "examples/program_provider_direct.zig", .step = "run-program-provider-direct", .desc = "Run the direct program-backed ProviderHarness example." },
        .{ .name = "boundary-program-provider-nested", .path = "examples/program_provider_nested.zig", .step = "run-program-provider-nested", .desc = "Run the nested program-backed ProviderHarness example." },
        .{ .name = "boundary-program-provider-resume", .path = "examples/program_provider_resume.zig", .step = "run-program-provider-resume", .desc = "Run the parked and resumed program-backed ProviderHarness example." },
        .{ .name = "boundary-effect-exchange-mailbox", .path = "examples/effect_exchange_mailbox.zig", .step = "run-effect-exchange-mailbox", .desc = "Run the transport-neutral Effect Exchange mailbox example." },
        .{ .name = "boundary-effect-exchange-restart", .path = "examples/effect_exchange_restart.zig", .step = "run-effect-exchange-restart", .desc = "Run the Effect Exchange capsule restart example." },
        .{ .name = "boundary-linear-effect-sessions", .path = "examples/linear_effect_sessions.zig", .step = "run-linear-effect-sessions", .desc = "Run the Linear Effect Sessions obligation example." },
        .{ .name = "boundary-linear-branch-safety", .path = "examples/linear_branch_safety.zig", .step = "run-linear-branch-safety", .desc = "Run the Linear Effect Sessions branch safety example." },
        .{ .name = "boundary-durable-capsule-replay", .path = "examples/durable_capsule_replay.zig", .step = "run-durable-capsule-replay", .desc = "Run the durable Program.Session capsule image replay example." },
        .{ .name = "boundary-journal-replay", .path = "examples/journal_replay.zig", .step = "run-journal-replay", .desc = "Run the Program.Session interaction journal replay example." },
    };
    inline for (examples) |example| {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path(example.path),
            .target = target,
            .optimize = optimize,
        });
        exe_mod.addImport("boundary", boundary);
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

    const boundary_bench = b.createModule(.{
        .root_source_file = b.path("src/bench_support.zig"),
        .target = target,
        .optimize = bench_optimize,
    });
    wireBoundaryImports(boundary_bench, core);

    const bench_specs = [_]struct {
        name: []const u8,
        path: []const u8,
        step: []const u8,
        desc: []const u8,
    }{
        .{ .name = "boundary-abortive-effect-decompose-bench", .path = "bench/abortive_effect_decompose_bench.zig", .step = "bench-abortive-effect-decompose", .desc = "Run the abortive effect decomposition benchmark." },
        .{ .name = "boundary-algebraic-builder-decompose-bench", .path = "bench/algebraic_builder_decompose_bench.zig", .step = "bench-algebraic-builder-decompose", .desc = "Run the algebraic builder decomposition benchmark." },
        .{ .name = "boundary-direct-first-suspend-bench", .path = "bench/direct_first_suspend_bench.zig", .step = "bench-first-suspend", .desc = "Run the direct-style first-suspend benchmark." },
        .{ .name = "boundary-effect-family-matrix-bench", .path = "bench/effect_family_matrix_bench.zig", .step = "bench-family-matrix", .desc = "Compare every retained effect family against its comparator lane." },
        .{ .name = "boundary-direct-no-capture-bench", .path = "bench/no_capture_bench.zig", .step = "bench", .desc = "Run the direct-style no-capture benchmark." },
        .{ .name = "boundary-resource-effect-decompose-bench", .path = "bench/resource_effect_decompose_bench.zig", .step = "bench-resource-effect-decompose", .desc = "Run the resource effect decomposition benchmark." },
        .{ .name = "boundary-state-effect-bench", .path = "bench/state_effect_bench.zig", .step = "bench-state-effect", .desc = "Compare the additive state effect against the raw prompt baseline." },
        .{ .name = "boundary-writer-effect-decompose-bench", .path = "bench/writer_effect_decompose_bench.zig", .step = "bench-writer-effect-decompose", .desc = "Run the writer effect decomposition benchmark." },
    };
    inline for (bench_specs) |bench| {
        const bench_mod = b.createModule(.{
            .root_source_file = b.path(bench.path),
            .target = target,
            .optimize = bench_optimize,
        });
        bench_mod.addImport("boundary", boundary_bench);
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
        zprof_hotspots_mod.addImport("boundary", boundary_bench);
        zprof_hotspots_mod.addImport("zprof", zprof_dep.module("zprof"));
        const zprof_hotspots_exe = b.addExecutable(.{ .name = "boundary-zprof-hotspots", .root_module = zprof_hotspots_mod });
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
