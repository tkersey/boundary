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

fn addRunArtifact(b: *std.Build, artifact: *std.Build.Step.Compile) *std.Build.Step.Run {
    const run = b.addRunArtifact(artifact);
    if (b.args) |args| run.addArgs(args);
    return run;
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
    const root_tests = b.addTest(.{ .root_module = ability });
    test_step.dependOn(&addRunArtifact(b, root_tests).step);

    const program_api_tests_mod = b.createModule(.{
        .root_source_file = b.path("test/program_api_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    program_api_tests_mod.addImport("ability", ability);
    const program_api_tests = b.addTest(.{ .root_module = program_api_tests_mod });
    test_step.dependOn(&addRunArtifact(b, program_api_tests).step);

    const examples = [_]struct {
        name: []const u8,
        path: []const u8,
        step: []const u8,
        desc: []const u8,
    }{
        .{ .name = "ability-state-basic", .path = "examples/state_basic.zig", .step = "run-state-basic", .desc = "Run the state effect example." },
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
            run_step.dependOn(&addRunArtifact(b, exe).step);
        } else {
            run_step.dependOn(&exe.step);
        }
    }

    const lint_step = b.step("lint", "Lint source code.");
    var builder = zlinter.builder(b, .{});
    builder.addPaths(.{
        .include = &.{
            b.path("build.zig"),
            b.path("src/root.zig"),
            b.path("src/ability_shared.zig"),
            b.path("src/program_api.zig"),
            b.path("src/lowering_api.zig"),
            b.path("src/internal/lexical_support.zig"),
            b.path("src/effect/state.zig"),
            b.path("src/effect/reader.zig"),
            b.path("src/effect/writer.zig"),
            b.path("src/effect/optional.zig"),
            b.path("src/effect/exception.zig"),
            b.path("src/effect/resource.zig"),
            b.path("src/effect/generated_family.zig"),
            b.path("examples/state_basic.zig"),
            b.path("examples/custom_approval_workflow.zig"),
            b.path("test/program_api_test.zig"),
        },
        .exclude = &.{},
    });
    inline for (@typeInfo(zlinter.BuiltinLintRule).@"enum".fields) |field| {
        const rule: zlinter.BuiltinLintRule = @enumFromInt(field.value);
        builder.addRule(.{ .builtin = rule }, .{});
    }
    lint_step.dependOn(builder.build());
}
