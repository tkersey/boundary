const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const data = b.addModule("boundary_data", .{
        .root_source_file = b.path("src/data/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // This exit constructs only the separately importable pure contract module.
    if (b.option(bool, "data-only", "Construct only boundary_data") orelse false) return;
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/data/test_root.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });
    const data_step = b.step("check-data", "Check canonical records and pure admission");
    data_step.dependOn(&b.addRunArtifact(tests).step);
    const boundary = b.addModule("boundary", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data", .module = data }},
    });
    const linker = b.addExecutable(.{ .name = "boundary-link", .root_module = b.createModule(.{
        .root_source_file = b.path("tools/component_link.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data", .module = data }},
    }) });
    const installed_linker = b.addInstallArtifact(linker, .{});
    b.step("build-compiler", "Build the source-independent BMO1 linker")
        .dependOn(&installed_linker.step);
    const component_example = b.addExecutable(.{ .name = "component-example", .root_module = b.createModule(.{
        .root_source_file = b.path("tools/component_example.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    const component_checks = b.addSystemCommand(&.{"node"});
    component_checks.addFileArg(b.path("test/components.mjs"));
    component_checks.addArtifactArg(linker);
    component_checks.addArtifactArg(component_example);
    component_checks.has_side_effects = true;
    const component_step = b.step("check-components", "Check object admission and source-independent composition");
    component_step.dependOn(&component_checks.step);
    const component_data_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/data/component_tests.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    }) });
    component_step.dependOn(&b.addRunArtifact(component_data_tests).step);
    const component_source_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/test_root.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data", .module = data }},
    }), .filters = &.{ "component", "public linker", "combinator" } });
    component_step.dependOn(&b.addRunArtifact(component_source_tests).step);
    const authoring = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/test_root.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data", .module = data }},
    }) });
    const stable_lowering = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/test_root.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data", .module = data }},
    }), .filters = &.{
        "installation lowering", "stable join",   "stable bindings", "construction owns",
        "staged examples lower", "lexical scope", "stable lowering", "stable source analysis",
        "stable admission",
    } });
    b.step("check-stable-lowering", "Check direct stable-slot construction")
        .dependOn(&b.addRunArtifact(stable_lowering).step);
    const facts_profile = b.addExecutable(.{ .name = "source-facts-profile", .root_module = b.createModule(.{
        .root_source_file = b.path("src/facts_profile.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .imports = &.{.{ .name = "boundary_data", .module = data }},
    }) });
    b.step("profile-source-facts", "Measure source checking with compact set counters")
        .dependOn(&b.addRunArtifact(facts_profile).step);
    const compact_fixtures = b.step("emit-program-images", "Emit current compact Program images");
    const compact_emit = b.addExecutable(.{ .name = "emit-compact-fixture", .root_module = b.createModule(.{
        .root_source_file = b.path("test/v2/emit_compact.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    compact_fixtures.dependOn(&b.addInstallArtifact(compact_emit, .{}).step);
    const compact_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const compact_wasm_data = b.createModule(.{
        .root_source_file = b.path("src/data/root.zig"),
        .target = compact_target,
        .optimize = .ReleaseSmall,
    });
    const compact_wasm = b.addExecutable(.{ .name = "compact-codec-probe", .root_module = b.createModule(.{
        .root_source_file = b.path("test/v2/compact_wasm.zig"),
        .target = compact_target,
        .optimize = .ReleaseSmall,
        .imports = &.{.{ .name = "boundary_data", .module = compact_wasm_data }},
    }) });
    compact_wasm.entry = .disabled;
    compact_wasm.rdynamic = true;
    compact_wasm.export_memory = true;
    compact_wasm.stack_size = 65536;
    const program_wasm_run = b.addSystemCommand(&.{"node"});
    program_wasm_run.addFileArg(b.path("test/v2/program_wasm.mjs"));
    program_wasm_run.addFileArg(compact_wasm.getEmittedBin());
    program_wasm_run.addFileArg(compact_emit.getEmittedBin());
    b.step("check-program-image-wasm", "Compare BPI3 native and wasm32 bytes and identity")
        .dependOn(&program_wasm_run.step);
    const state_wasm_run = b.addSystemCommand(&.{"node"});
    state_wasm_run.addFileArg(b.path("test/v2/state_wasm.mjs"));
    state_wasm_run.addFileArg(compact_wasm.getEmittedBin());
    b.step("check-state-image-wasm", "Check PST3 canonical graph bytes on wasm32")
        .dependOn(&state_wasm_run.step);
    const invocation_wasm_run = b.addSystemCommand(&.{"node"});
    invocation_wasm_run.addFileArg(b.path("test/v2/invocation_wasm.mjs"));
    invocation_wasm_run.addFileArg(compact_wasm.getEmittedBin());
    b.step("check-invocation-wasm", "Check current envelope bytes and request identity on wasm32")
        .dependOn(&invocation_wasm_run.step);
    for ([_][]const u8{ "install", "mixed", "irregular" }) |kind| {
        for ([_]usize{ 8, 64, 128, 256 }) |count| {
            const run = b.addRunArtifact(compact_emit);
            run.addArgs(&.{ b.fmt("{d}", .{count}), kind });
            compact_fixtures.dependOn(&b.addInstallFileWithDir(run.captureStdOut(.{}), .prefix, b.fmt("{s}-{d}.bpi3", .{ kind, count })).step);
        }
    }
    const authoring_cases = b.addExecutable(.{ .name = "authoring-cases", .root_module = b.createModule(.{
        .root_source_file = b.path("src/authoring_cases.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data", .module = data }},
    }) });
    b.step("build-authoring-cases", "Build structured authoring execution cases")
        .dependOn(&b.addInstallArtifact(authoring_cases, .{}).step);
    const client = b.addExecutable(.{ .name = "authoring-client", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/authoring_client.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    b.step("emit-authoring-client", "Emit the public authoring usability client")
        .dependOn(&b.addRunArtifact(client).step);
    const structured = b.addExecutable(.{ .name = "structured-branch", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/structured_branch.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    b.step("emit-structured-branch", "Emit the public structured runtime branch")
        .dependOn(&b.addRunArtifact(structured).step);
    const one_effect = b.addExecutable(.{ .name = "one-effect", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/one_effect.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    b.step("emit-one-effect", "Compile and inspect a complete public authoring example").dependOn(&b.addRunArtifact(one_effect).step);
    b.step("check-authoring", "Check staged typed construction and lowering")
        .dependOn(&b.addRunArtifact(authoring).step);
    const economy = b.step("check-economy", "Check code and constant sharing and emit executable economy workloads");
    economy.dependOn(&b.addRunArtifact(authoring).step);
    const compiler_options = b.addOptions();
    compiler_options.addOption(usize, "kind", b.option(usize, "economy-kind", "Matched compiler workload: 0 effect, 1 arithmetic") orelse 0);
    const compiler_module = b.createModule(.{ .root_source_file = b.path("test/v2/economy_v2.zig"), .target = b.graph.host, .optimize = optimize, .imports = &.{.{ .name = "boundary", .module = boundary }} });
    compiler_module.addOptions("economy_options", compiler_options);
    const compiler_executable = b.addExecutable(.{ .name = "economy-compiler", .root_module = compiler_module });
    b.step("emit-economy-compiler", "Compile a matched public authoring workload and emit its image").dependOn(&b.addRunArtifact(compiler_executable).step);
    for ([_]usize{ 0, 1, 8, 64 }) |count| {
        const configuration = b.addOptions();
        configuration.addOption(usize, "installations", count);
        const module = b.createModule(.{ .root_source_file = b.path("test/v2/emit_economy.zig"), .target = b.graph.host, .optimize = optimize, .imports = &.{.{ .name = "boundary", .module = boundary }} });
        module.addOptions("economy_options", configuration);
        const emit = b.addExecutable(.{ .name = b.fmt("emit-economy-{d}", .{count}), .root_module = module });
        const bytes = b.addRunArtifact(emit).captureStdOut(.{});
        economy.dependOn(&b.addInstallFileWithDir(bytes, .prefix, b.fmt("economy-{d}.bpi3", .{count})).step);
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
    b.step("emit-scalar", "Emit a typed scalar BPI3 example to stdout")
        .dependOn(&b.addRunArtifact(example).step);
    const source_fixtures = b.step("emit-examples", "Emit higher-order source examples and BPI3 images");
    const oracle = b.addSystemCommand(&.{"node"});
    oracle.addFileArg(b.path("test/v2/source_oracle.mjs"));
    const source_emitter = b.addExecutable(.{ .name = "source-example", .root_module = b.createModule(.{
        .root_source_file = b.path("test/v2/emit_source.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    for ([_][]const u8{ "lexical", "deep", "recursive", "choices-all", "choices-first", "generator", "state-local", "state-shared", "resource-scalar", "resource-pair", "answers", "scoped-reader", "writer-raise", "scheduler", "queens-dfs", "queens-bfs", "cell-order", "nested", "shallow", "injection", "indexed", "abort-custody", "unwind", "reentrant", "cloned", "clause-abort", "bounded-values", "scalar-contracts", "ownership", "shallow-resumptions", "shallow-injection", "handle-operand-order", "protect-operand-order", "successor-state", "clause-payload", "yielding-cleanup", "borrow-operands", "cleanup-disposal", "cleanup-disposal-running", "cleanup-disposal-failure", "cleanup-disposal-owned", "product-projection" }, 0..) |name, index| {
        for ([_][]const u8{ "json", "bpi3" }) |format| {
            const run = b.addRunArtifact(source_emitter);
            run.addArgs(&.{ b.fmt("{d}", .{index}), format });
            const file = run.captureStdOut(.{});
            source_fixtures.dependOn(&b.addInstallFileWithDir(file, .prefix, b.fmt("source-{s}.{s}", .{ name, format })).step);
            if (std.mem.eql(u8, format, "json")) oracle.addFileArg(file);
        }
    }
    oracle.has_side_effects = true;
    const semantics = b.step("check-semantics", "Check higher-order source semantics without World");
    semantics.dependOn(&oracle.step);
    semantics.dependOn(&oracleScopeChecks(b, boundary, optimize).step);
    semantics.dependOn(&borrowReturnChecks(b, boundary, optimize).step);
    semantics.dependOn(&b.addRunArtifact(authoring).step);
    const exact_json = b.addSystemCommand(&.{ "node", "--test" });
    exact_json.addFileArg(b.path("test/v2/exact_json.test.mjs"));
    semantics.dependOn(&exact_json.step);
    const aggregate = b.step("check", "Check current authoring, data, source semantics and component linking");
    const lazy_hyper = b.addExecutable(.{ .name = "lazy-hyper", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/lazy_hyper.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    const lazy_run = b.addRunArtifact(lazy_hyper);
    b.step("emit-lazy-hyper", "Emit the unused divergent hyperfunction peer witness")
        .dependOn(&lazy_run.step);
    const lazy_check = b.addRunArtifact(lazy_hyper);
    _ = lazy_check.captureStdOut(.{});
    aggregate.dependOn(&lazy_check.step);
    const unused_invocation = b.addRunArtifact(lazy_hyper);
    unused_invocation.addArg("unused-invocation");
    b.step("emit-unused-hyper-invocation", "Emit an undemanded divergent invocation")
        .dependOn(&unused_invocation.step);
    const reciprocal = b.addExecutable(.{ .name = "reciprocal-hyper", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/reciprocal_hyper.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    b.step("emit-reciprocal-hyper", "Emit state-based reciprocal non-tail calls")
        .dependOn(&b.addRunArtifact(reciprocal).step);
    const reciprocal_check = b.addRunArtifact(reciprocal);
    _ = reciprocal_check.captureStdOut(.{});
    aggregate.dependOn(&reciprocal_check.step);
    const algebra = b.addExecutable(.{ .name = "hyper-algebra", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/hyper_algebra.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    const algebra_images = b.step("emit-hyper-algebra", "Emit the public pure hyperfunction algebra cases");
    for ([_][]const u8{
        "constant",     "project", "identity",   "distinct",    "compose", "product", "sum", "stream",
        "unused_fault", "fault",   "ana_config", "ana_capture",
    }) |mode| {
        const run = b.addRunArtifact(algebra);
        run.addArg(mode);
        algebra_images.dependOn(&b.addInstallFileWithDir(run.captureStdOut(.{}), .prefix, b.fmt("hyper/{s}.bpi3", .{mode})).step);
    }
    aggregate.dependOn(algebra_images);
    const generated = b.addExecutable(.{ .name = "hyper-generated", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/hyper_generated.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    const generated_install = b.addInstallArtifact(generated, .{});
    b.step("build-hyper-generated", "Build bounded pure-construction test emitter")
        .dependOn(&generated_install.step);
    const generated_check = b.addRunArtifact(generated);
    generated_check.addArgs(&.{ "193", "5" });
    _ = generated_check.captureStdOut(.{});
    aggregate.dependOn(&generated_check.step);
    const fold = b.addExecutable(.{ .name = "hyper-fold", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/hyper_fold.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    const fold_images = b.step("emit-hyper-fold", "Emit runtime two-input hyperfunction and direct folds");
    for ([_][]const u8{ "hyper", "direct", "materialized", "stats", "stats-direct", "stats-materialized" }) |mode| {
        const run = b.addRunArtifact(fold);
        run.addArg(mode);
        fold_images.dependOn(&b.addInstallFileWithDir(run.captureStdOut(.{}), .prefix, b.fmt("fold/{s}", .{mode})).step);
    }
    aggregate.dependOn(fold_images);
    const tail = b.addExecutable(.{ .name = "hyper-tail", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/hyper_tail.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    const tail_images = b.step("emit-hyper-tail", "Emit history-free reciprocal and direct countdowns");
    for ([_][]const u8{ "hyper", "direct" }) |mode| {
        const run = b.addRunArtifact(tail);
        run.addArg(mode);
        tail_images.dependOn(&b.addInstallFileWithDir(run.captureStdOut(.{}), .prefix, b.fmt("tail/{s}", .{mode})).step);
    }
    aggregate.dependOn(tail_images);
    const adaptive = b.addExecutable(.{ .name = "hyper-adaptive", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/hyper_adaptive.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    const adaptive_objects = b.step("emit-hyper-adaptive", "Emit independent adaptive hyperfunction objects");
    adaptive_objects.dependOn(&installed_linker.step);
    for ([_][]const u8{ "producer", "producer-reversed", "consumer", "consumer-invert", "support", "entry" }) |mode| {
        const run = b.addRunArtifact(adaptive);
        run.addArg(mode);
        adaptive_objects.dependOn(&b.addInstallFileWithDir(run.captureStdOut(.{}), .prefix, b.fmt("adaptive/{s}.bmo1", .{mode})).step);
    }
    aggregate.dependOn(adaptive_objects);
    const hyper_multi = b.addExecutable(.{ .name = "hyper-multishot", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/hyper_multishot.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    const multi_images = b.step("emit-hyper-multishot", "Emit clone-safe recursive participant witness");
    const multi_run = b.addRunArtifact(hyper_multi);
    multi_images.dependOn(&b.addInstallFileWithDir(multi_run.captureStdOut(.{}), .prefix, "hyper-multishot.bpi3").step);
    const multi_reentrant = b.addRunArtifact(hyper_multi);
    multi_reentrant.addArg("reentrant");
    multi_images.dependOn(&b.addInstallFileWithDir(multi_reentrant.captureStdOut(.{}), .prefix, "hyper-reentrant.bpi3").step);
    aggregate.dependOn(multi_images);
    const demand = b.addExecutable(.{ .name = "hyper-demand", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/hyper_demand.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    b.step("emit-hyper-demand", "Emit lexical internal-demand interpretation")
        .dependOn(&b.addRunArtifact(demand).step);
    const demand_check = b.addRunArtifact(demand);
    _ = demand_check.captureStdOut(.{});
    aggregate.dependOn(&demand_check.step);
    const exchange = b.addExecutable(.{ .name = "owned-exchange", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/owned_exchange.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    const exchange_images = b.step("emit-owned-exchange", "Emit owned exchange and local disposal witnesses");
    for ([_][]const u8{ "dispose", "normal" }) |mode| {
        const run = b.addRunArtifact(exchange);
        if (std.mem.eql(u8, mode, "normal")) run.addArg(mode);
        exchange_images.dependOn(&b.addInstallFileWithDir(run.captureStdOut(.{}), .prefix, b.fmt("exchange/{s}.bpi3", .{mode})).step);
    }
    aggregate.dependOn(exchange_images);
    const composed = b.addExecutable(.{ .name = "composed-exchange", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/composed_exchange.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    const composed_images = b.step("emit-composed-exchange", "Emit owned three-part exchange composition");
    for ([_][]const u8{ "dispose", "finish", "right-finish" }) |mode| {
        const run = b.addRunArtifact(composed);
        if (!std.mem.eql(u8, mode, "dispose")) run.addArg(mode);
        composed_images.dependOn(&b.addInstallFileWithDir(run.captureStdOut(.{}), .prefix, b.fmt("composed/{s}.bpi3", .{mode})).step);
    }
    aggregate.dependOn(composed_images);
    const composed_negative = b.addSystemCommand(&.{ "node", "test/composed_exchange_negative.mjs" });
    composed_negative.addArtifactArg(composed);
    composed_images.dependOn(&composed_negative.step);
    const exchange_negative = b.addSystemCommand(&.{"node"});
    exchange_negative.addFileArg(b.path("test/owned_exchange_negative.mjs"));
    exchange_negative.addArtifactArg(exchange);
    aggregate.dependOn(&exchange_negative.step);
    const hyper_reference = b.addSystemCommand(&.{ "node", "--test" });
    hyper_reference.addFileArg(b.path("test/hyperfunction_reference.test.mjs"));
    aggregate.dependOn(&hyper_reference.step);
    aggregate.dependOn(data_step);
    aggregate.dependOn(component_step);
    aggregate.dependOn(&program_wasm_run.step);
    aggregate.dependOn(&state_wasm_run.step);
    aggregate.dependOn(&invocation_wasm_run.step);
    aggregate.dependOn(semantics);
    aggregate.dependOn(economy);
    aggregate.dependOn(source_fixtures);
    const client_check = b.addRunArtifact(client);
    _ = client_check.captureStdOut(.{});
    aggregate.dependOn(&client_check.step);
    const public_example_check = b.addRunArtifact(one_effect);
    _ = public_example_check.captureStdOut(.{});
    aggregate.dependOn(&public_example_check.step);
    const assets_tests = b.addSystemCommand(&.{ "node", "--test" });
    assets_tests.addFileArg(b.path("test/v2/assets.test.mjs"));
    assets_tests.has_side_effects = true;
    b.step("check-assets", "Check source identity and bounded archive/container integrity")
        .dependOn(&assets_tests.step);
    aggregate.dependOn(&assets_tests.step);
    const capacity_example = b.addExecutable(.{ .name = "emit-capacity", .root_module = b.createModule(.{
        .root_source_file = b.path("test/v2/emit_capacity.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    const capacity_bytes = b.addRunArtifact(capacity_example).captureStdOut(.{});
    const capacity_install = b.addInstallFileWithDir(capacity_bytes, .prefix, "capacity.bpi3");
    b.step("emit-capacity-fixture", "Emit the public typed arena-exhaustion program").dependOn(&capacity_install.step);
    aggregate.dependOn(&capacity_install.step);
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
