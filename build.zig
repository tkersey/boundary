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
    for ([_][]const u8{ "lexical", "deep", "recursive", "choices-all", "choices-first", "generator", "state-local", "state-shared", "resource-scalar", "resource-pair", "answers", "scoped-reader", "writer-raise", "scheduler", "queens-dfs", "queens-bfs", "cell-order", "nested", "shallow", "injection", "indexed", "abort-custody", "unwind", "reentrant", "cloned", "clause-abort", "bounded-values", "scalar-contracts", "ownership", "shallow-resumptions", "shallow-injection", "handle-operand-order", "protect-operand-order", "successor-state", "clause-payload", "yielding-cleanup", "borrow-operands" }, 0..) |name, index| {
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
            if (source) oracle.addFileArg(file);
        }
    }
    oracle.has_side_effects = true;
    const semantics = b.step("check-v2-semantics", "Check higher-order source semantics without World");
    semantics.dependOn(&oracle.step);
    semantics.dependOn(&oracleScopeChecks(b, boundary, optimize).step);
    semantics.dependOn(&borrowReturnChecks(b, boundary, optimize).step);
    semantics.dependOn(&b.addRunArtifact(authoring).step);
    const formal = b.addSystemCommand(&.{ "lake", "build" });
    formal.setCwd(b.path("semantics/v2"));
    formal.has_side_effects = true;
    const trust = b.addSystemCommand(&.{ "lake", "env", "lean", "Trust.lean" });
    trust.setCwd(b.path("semantics/v2"));
    trust.has_side_effects = true;
    trust.step.dependOn(&formal.step);
    semantics.dependOn(&trust.step);
    const aggregate = b.step("check-v2", "Check compiler, source semantics, formal core, data and economy without a runtime");
    aggregate.dependOn(data_step);
    aggregate.dependOn(historical_step);
    aggregate.dependOn(semantics);
    aggregate.dependOn(economy);
    aggregate.dependOn(source_fixtures);
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

fn borrowReturnChecks(
    b: *std.Build,
    boundary: *std.Build.Module,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Run {
    const tests = b.addExecutable(.{
        .name = "borrow-returns",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/v2/borrow_returns.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .imports = &.{.{ .name = "boundary", .module = boundary }},
        }),
    });
    return b.addRunArtifact(tests);
}
