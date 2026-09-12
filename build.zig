const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const data = b.addModule("boundary_data_v2", .{
        .root_source_file = b.path("src/v2/data/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // This exit constructs only the separately importable pure contract module.
    if (b.option(bool, "data-only", "Construct only boundary_data_v2") orelse false) return;
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/v2/data/test_root.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });
    const data_step = b.step("check-v2-data", "Check v2 canonical records and pure admission");
    data_step.dependOn(&b.addRunArtifact(tests).step);
    const snapshot_probe = b.addExecutable(.{
        .name = "boundary-snapshot-probe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/v2/data/snapshot_probe.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });
    b.step("build-v2-snapshot-probe", "Build the test-only production snapshot codec adapter")
        .dependOn(&b.addInstallArtifact(snapshot_probe, .{}).step);
    const snapshot_conformance = b.addSystemCommand(&.{"node"});
    snapshot_conformance.addFileArg(b.path("test/v2/snapshot_conformance.mjs"));
    snapshot_conformance.addFileArg(snapshot_probe.getEmittedBin());
    snapshot_conformance.has_side_effects = true;
    b.step("check-v2-snapshots", "Compare Lean canonical snapshots with every production node tag")
        .dependOn(&snapshot_conformance.step);
    const protocol_probe = b.addExecutable(.{
        .name = "boundary-protocol-probe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/v2/data/protocol_probe.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });
    b.step("build-v2-protocol-probe", "Build the test-only production protocol codec adapter")
        .dependOn(&b.addInstallArtifact(protocol_probe, .{}).step);
    const protocol_conformance = b.addSystemCommand(&.{"node"});
    protocol_conformance.addFileArg(b.path("test/v2/protocol_conformance.mjs"));
    protocol_conformance.addFileArg(protocol_probe.getEmittedBin());
    protocol_conformance.has_side_effects = true;
    b.step("check-v2-protocol", "Compare Lean protocol admission and digests with production")
        .dependOn(&protocol_conformance.step);
    const admission_probe = b.addExecutable(.{
        .name = "boundary-admission-probe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/v2/data/admission_probe.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });
    b.step("build-v2-admission-probe", "Build the test-only program and borrow-analysis adapter")
        .dependOn(&b.addInstallArtifact(admission_probe, .{}).step);
    const historical = b.addModule("boundary_bpi1", .{
        .root_source_file = b.path("src/v2/legacy/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data_v2", .module = data }},
    });
    const historical_tests = b.addTest(.{ .root_module = historical });
    const historical_step = b.step("check-v2-bpi1", "Check the pure historical BPI1 decoder");
    historical_step.dependOn(&b.addRunArtifact(historical_tests).step);
    const historical_corpus = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("test/v2/bpi1_admission.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{ .{ .name = "boundary_bpi1", .module = historical }, .{ .name = "boundary_data_v2", .module = data } },
    }) });
    historical_step.dependOn(&b.addRunArtifact(historical_corpus).step);
    const lift = b.addExecutable(.{ .name = "bpi1-lift", .root_module = b.createModule(.{
        .root_source_file = b.path("tools/v2/bpi1_lift.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "boundary_bpi1", .module = historical }, .{ .name = "boundary_data_v2", .module = data } },
    }) });
    b.step("build-bpi1-lift", "Build the pure BPI1 to BPI2 command").dependOn(&b.addInstallArtifact(lift, .{}).step);
    const boundary = b.addModule("boundary", .{
        .root_source_file = b.path("src/v2/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data_v2", .module = data }},
    });
    const certification_imports: []const std.Build.Module.Import = &.{
        .{ .name = "boundary", .module = boundary },
        .{ .name = "boundary_data_v2", .module = data },
    };
    const certification_compiler = b.addExecutable(.{
        .name = "boundary-certify-compile",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/v2/certify_compile.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .imports = certification_imports,
        }),
    });
    b.step("build-v2-certification-compiler", "Build the paired staged-source compiler and untrusted pass witness emitter")
        .dependOn(&b.addInstallArtifact(certification_compiler, .{}).step);
    const source_input_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tools/v2/source_input.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = certification_imports,
    }) });
    const certification_inputs = b.step("check-v2-certification-inputs", "Check exact source parsing and paired production image emission");
    certification_inputs.dependOn(&b.addRunArtifact(source_input_tests).step);
    const observer_tests = b.addTest(.{ .root_module = certification_compiler.root_module });
    certification_inputs.dependOn(&b.addRunArtifact(observer_tests).step);
    const exact_json_tests = b.addSystemCommand(&.{ "node", "--test" });
    exact_json_tests.addFileArg(b.path("test/v2/exact_json.test.mjs"));
    exact_json_tests.has_side_effects = true;
    certification_inputs.dependOn(&exact_json_tests.step);
    const authoring = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/v2/test_root.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data_v2", .module = data }},
    }) });
    const one_effect = b.addExecutable(.{ .name = "one-effect", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/one_effect.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    b.step("emit-one-effect", "Compile and inspect a complete public authoring example").dependOn(&b.addRunArtifact(one_effect).step);
    b.step("check-v2-authoring", "Check staged typed construction and lowering")
        .dependOn(&b.addRunArtifact(authoring).step);
    const economy = b.step("check-v2-economy", "Check code and constant sharing and emit executable economy workloads");
    economy.dependOn(&b.addRunArtifact(authoring).step);
    economy.dependOn(&b.addRunArtifact(historical_corpus).step);
    const sizes = b.addExecutable(.{ .name = "economy-image-sizes", .root_module = b.createModule(.{
        .root_source_file = b.path("test/v2/bpi1_admission.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{ .{ .name = "boundary_bpi1", .module = historical }, .{ .name = "boundary_data_v2", .module = data } },
    }) });
    economy.dependOn(&b.addInstallFileWithDir(b.addRunArtifact(sizes).captureStdOut(.{}), .prefix, "economy-image-sizes.json").step);
    const compiler_options = b.addOptions();
    compiler_options.addOption(usize, "kind", b.option(usize, "economy-kind", "Matched compiler workload: 0 effect, 1 arithmetic") orelse 0);
    const compiler_module = b.createModule(.{ .root_source_file = b.path("test/v2/economy_v2.zig"), .target = b.graph.host, .optimize = optimize, .imports = &.{.{ .name = "boundary", .module = boundary }} });
    compiler_module.addOptions("economy_options", compiler_options);
    const compiler_executable = b.addExecutable(.{ .name = "economy-compiler", .root_module = compiler_module });
    b.step("emit-economy-compiler", "Compile a matched public authoring workload and emit its image").dependOn(&b.addRunArtifact(compiler_executable).step);
    const phase_options = b.addOptions();
    phase_options.addOption(usize, "kind", b.option(usize, "compiler-phase-kind", "Compiler/codec workload ordinal 0 through 7") orelse 0);
    const phase_module = b.createModule(.{ .root_source_file = b.path("test/v2/compiler_phases.zig"), .target = b.graph.host, .optimize = optimize, .imports = &.{.{ .name = "boundary", .module = boundary }} });
    phase_module.addOptions("phase_options", phase_options);
    const phase_executable = b.addExecutable(.{ .name = "compiler-phases", .root_module = phase_module });
    b.step("build-v2-compiler-phases", "Build the standalone compiler and codec phase observer").dependOn(&b.addInstallArtifact(phase_executable, .{}).step);
    for ([_]usize{ 0, 1, 8, 64 }) |count| {
        const configuration = b.addOptions();
        configuration.addOption(usize, "installations", count);
        const module = b.createModule(.{ .root_source_file = b.path("test/v2/emit_economy.zig"), .target = b.graph.host, .optimize = optimize, .imports = &.{.{ .name = "boundary", .module = boundary }} });
        module.addOptions("economy_options", configuration);
        const emit = b.addExecutable(.{ .name = b.fmt("emit-economy-{d}", .{count}), .root_module = module });
        const bytes = b.addRunArtifact(emit).captureStdOut(.{});
        economy.dependOn(&b.addInstallFileWithDir(bytes, .prefix, b.fmt("economy-{d}.bpi2", .{count})).step);
    }
    const options = b.addOptions();
    options.addOption(u64, "value", b.option(u64, "example-value", "Authored scalar example value") orelse 42);
    const example_module = b.createModule(.{
        .root_source_file = b.path("test/v2/emit_scalar.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    });
    example_module.addOptions("example_options", options);
    const example = b.addExecutable(.{ .name = "emit-v2-scalar", .root_module = example_module });
    b.step("emit-v2-scalar", "Emit a typed scalar BPI2 example to stdout")
        .dependOn(&b.addRunArtifact(example).step);
    const source_fixtures = b.step("emit-v2-source-fixtures", "Emit higher-order source examples and their portable images");
    const oracle = b.addSystemCommand(&.{"node"});
    oracle.addFileArg(b.path("test/v2/source_oracle.mjs"));
    const source_machine = b.addSystemCommand(&.{"node"});
    source_machine.addFileArg(b.path("test/v2/source_machine.mjs"));
    source_machine.addArg("--sources");
    source_machine.has_side_effects = true;
    const target_machine = b.addSystemCommand(&.{"node"});
    target_machine.addFileArg(b.path("test/v2/target_machine.mjs"));
    target_machine.addFileArg(certification_compiler.getEmittedBin());
    target_machine.addArg("--sources");
    target_machine.has_side_effects = true;
    const borrow_returns = borrowReturnProgram(b, boundary, optimize);
    b.step("build-v2-borrow-returns", "Build the handler-return borrow fixture emitter and checker")
        .dependOn(&b.addInstallArtifact(borrow_returns, .{}).step);
    const program_admission = b.addSystemCommand(&.{"node"});
    program_admission.addFileArg(b.path("test/v2/program_admission.mjs"));
    program_admission.addFileArg(admission_probe.getEmittedBin());
    program_admission.addFileArg(certification_compiler.getEmittedBin());
    program_admission.addFileArg(borrow_returns.getEmittedBin());
    program_admission.has_side_effects = true;
    for ([_][]const u8{ "lexical", "deep", "recursive", "choices-all", "choices-first", "generator", "state-local", "state-shared", "resource-scalar", "resource-pair", "answers", "scoped-reader", "writer-raise", "scheduler", "queens-dfs", "queens-bfs", "cell-order", "nested", "shallow", "injection", "indexed", "abort-custody", "unwind", "reentrant", "cloned", "clause-abort", "bounded-values", "scalar-contracts", "ownership", "shallow-resumptions", "shallow-injection", "handle-operand-order", "protect-operand-order", "successor-state", "clause-payload", "yielding-cleanup", "borrow-operands", "cleanup-disposal", "cleanup-disposal-running", "cleanup-disposal-failure", "cleanup-disposal-owned" }, 0..) |name, index| {
        for ([_]bool{ true, false }) |source| {
            const source_options = b.addOptions();
            source_options.addOption(usize, "example", index);
            source_options.addOption(bool, "source", source);
            const source_module = b.createModule(.{
                .root_source_file = b.path("test/v2/emit_source.zig"),
                .target = b.graph.host,
                .optimize = optimize,
                .imports = &.{.{ .name = "boundary", .module = boundary }},
            });
            source_module.addOptions("source_options", source_options);
            const emit = b.addExecutable(.{ .name = b.fmt("source-{s}-{s}", .{ name, if (source) "json" else "bpi2" }), .root_module = source_module });
            const file = b.addRunArtifact(emit).captureStdOut(.{});
            source_fixtures.dependOn(&b.addInstallFileWithDir(file, .prefix, b.fmt("source-{s}.{s}", .{ name, if (source) "json" else "bpi2" })).step);
            if (source) {
                oracle.addFileArg(file);
                source_machine.addFileArg(file);
                target_machine.addFileArg(file);
                program_admission.addFileArg(file);
            }
        }
    }
    oracle.has_side_effects = true;
    const paired = b.addSystemCommand(&.{"node"});
    paired.addFileArg(b.path("test/v2/certification_inputs.mjs"));
    paired.addFileArg(certification_compiler.getEmittedBin());
    paired.addArg(b.getInstallPath(.prefix, "."));
    paired.step.dependOn(source_fixtures);
    paired.has_side_effects = true;
    certification_inputs.dependOn(&paired.step);
    const projection = b.addSystemCommand(&.{"node"});
    projection.addFileArg(b.path("test/v2/projection_artifacts.mjs"));
    projection.addFileArg(certification_compiler.getEmittedBin());
    projection.addArg(b.pathFromRoot("semantics/v2"));
    projection.has_side_effects = true;
    b.step("check-v2-projection-artifacts", "Check the scalar projection artifact proof slice, not complete profile coverage")
        .dependOn(&projection.step);
    const lexical = b.addSystemCommand(&.{"node"});
    lexical.addFileArg(b.path("test/v2/lexical_artifacts.mjs"));
    lexical.addFileArg(certification_compiler.getEmittedBin());
    lexical.addArg(b.pathFromRoot("semantics/v2"));
    lexical.addArg(b.getInstallPath(.prefix, "."));
    lexical.step.dependOn(source_fixtures);
    lexical.has_side_effects = true;
    b.step("check-v2-lexical-artifacts", "Check exact-byte closure/addition artifacts including authored overflow")
        .dependOn(&lexical.step);
    const semantics = b.step("check-v2-semantics", "Check higher-order source semantics without World");
    semantics.dependOn(&oracle.step);
    semantics.dependOn(&source_machine.step);
    semantics.dependOn(&target_machine.step);
    const source_low_level = b.addSystemCommand(&.{"node"});
    source_low_level.addFileArg(b.path("test/v2/source_low_level.mjs"));
    source_low_level.addFileArg(certification_compiler.getEmittedBin());
    source_low_level.addArg(b.getInstallPath(.prefix, "."));
    source_low_level.step.dependOn(source_fixtures);
    source_low_level.has_side_effects = true;
    semantics.dependOn(&source_low_level.step);
    semantics.dependOn(&oracleScopeChecks(b, boundary, optimize).step);
    semantics.dependOn(&b.addRunArtifact(borrow_returns).step);
    semantics.dependOn(&b.addRunArtifact(authoring).step);
    const formal = b.addSystemCommand(&.{"node"});
    formal.addFileArg(b.path("tools/v2/formal.mjs"));
    formal.has_side_effects = true;
    const formal_step = b.step("check-v2-formal", "Discover and audit Lean declarations, reject trust mutations, and replay the kernel");
    const formal_dependencies = b.addSystemCommand(&.{"node"});
    formal_dependencies.addFileArg(b.path("test/v2/formal_dependencies.mjs"));
    formal_dependencies.addArg(b.pathFromRoot("semantics/v2"));
    formal_dependencies.has_side_effects = true;
    formal_dependencies.step.dependOn(&formal.step);
    formal_step.dependOn(&formal_dependencies.step);
    semantics.dependOn(formal_step);
    source_machine.step.dependOn(formal_step);
    target_machine.step.dependOn(formal_step);
    source_low_level.step.dependOn(formal_step);
    snapshot_conformance.step.dependOn(formal_step);
    semantics.dependOn(&snapshot_conformance.step);
    protocol_conformance.step.dependOn(formal_step);
    semantics.dependOn(&protocol_conformance.step);
    program_admission.step.dependOn(formal_step);
    semantics.dependOn(&program_admission.step);
    b.step("check-v2-program-admission", "Compare program admission and recheck native borrow-analysis witnesses")
        .dependOn(&program_admission.step);
    const source_machine_step = b.step("check-v2-source-machine", "Compare the Lean source transition machine with independent source semantics");
    source_machine_step.dependOn(&source_machine.step);
    source_machine_step.dependOn(&source_low_level.step);
    b.step("check-v2-target-machine", "Compare independent Lean BPI2 execution with source semantics")
        .dependOn(&target_machine.step);
    projection.step.dependOn(formal_step);
    lexical.step.dependOn(&projection.step);
    const aggregate = b.step("check-v2", "Check compiler, source semantics, formal core, data and economy without a runtime");
    aggregate.dependOn(data_step);
    aggregate.dependOn(historical_step);
    aggregate.dependOn(semantics);
    aggregate.dependOn(economy);
    aggregate.dependOn(source_fixtures);
    aggregate.dependOn(certification_inputs);
    aggregate.dependOn(&projection.step);
    aggregate.dependOn(&lexical.step);
    const assets_tests = b.addSystemCommand(&.{ "node", "--test" });
    assets_tests.addFileArg(b.path("test/v2/assets.test.mjs"));
    assets_tests.has_side_effects = true;
    aggregate.dependOn(&assets_tests.step);
    const capacity_example = b.addExecutable(.{ .name = "emit-capacity", .root_module = b.createModule(.{
        .root_source_file = b.path("test/v2/emit_capacity.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    const capacity_bytes = b.addRunArtifact(capacity_example).captureStdOut(.{});
    const capacity_install = b.addInstallFileWithDir(capacity_bytes, .prefix, "capacity.bpi2");
    b.step("emit-v2-capacity-fixture", "Emit the public typed arena-exhaustion program").dependOn(&capacity_install.step);
    aggregate.dependOn(&capacity_install.step);
    const release = b.addSystemCommand(&.{"node"});
    const inspect = b.addExecutable(.{ .name = "bpi2-inspect", .root_module = b.createModule(.{
        .root_source_file = b.path("tools/v2/bpi2_inspect.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data_v2", .module = data }},
    }) });
    b.step("build-bpi2-inspect", "Build the pure BPI2 admission and inspection command").dependOn(&b.addInstallArtifact(inspect, .{}).step);
    release.addFileArg(b.path("tools/v2/release.mjs"));
    release.addArg(b.getInstallPath(.prefix, "."));
    release.addArg(b.getInstallPath(.prefix, "release"));
    release.addFileArg(inspect.getEmittedBin());
    release.step.dependOn(source_fixtures);
    release.has_side_effects = true;
    b.step("emit-boundary-v2-release", "Emit deterministic compiler/data assets without publishing").dependOn(&release.step);
}

fn oracleScopeChecks(
    b: *std.Build,
    boundary: *std.Build.Module,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Run {
    const emitter = b.addExecutable(.{
        .name = "oracle-scopes",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/v2/oracle_scopes.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .imports = &.{.{ .name = "boundary", .module = boundary }},
        }),
    });
    const check = b.addSystemCommand(&.{"node"});
    check.addFileArg(b.path("test/v2/oracle_scopes.mjs"));
    check.addFileArg(b.addRunArtifact(emitter).captureStdOut(.{}));
    check.has_side_effects = true;
    return check;
}

fn borrowReturnProgram(
    b: *std.Build,
    boundary: *std.Build.Module,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = "borrow-returns",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/v2/borrow_returns.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .imports = &.{.{ .name = "boundary", .module = boundary }},
        }),
    });
}
