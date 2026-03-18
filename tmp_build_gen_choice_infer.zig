const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const shift_mod = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
    const lowered_machine_mod = b.createModule(.{ .root_source_file = b.path("src/lowered_machine.zig"), .target = target, .optimize = optimize });
    const frontend_support_mod = b.createModule(.{ .root_source_file = b.path("src/frontend.zig"), .target = target, .optimize = optimize });
    const prompt_contract_support_mod = b.createModule(.{ .root_source_file = b.path("src/prompt_contract.zig"), .target = target, .optimize = optimize });
    const error_witness_mod = b.createModule(.{ .root_source_file = b.path("src/error_witness.zig"), .target = target, .optimize = optimize });
    shift_mod.addImport("lowered_machine", lowered_machine_mod);
    shift_mod.addImport("frontend_support", frontend_support_mod);
    shift_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    shift_mod.addImport("error_witness", error_witness_mod);
    frontend_support_mod.addImport("lowered_machine", lowered_machine_mod);
    frontend_support_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    const test_mod = b.createModule(.{ .root_source_file = b.path("test/tmp_generated_choice_program_continuation_inference.zig"), .target = target, .optimize = optimize });
    test_mod.addImport("shift", shift_mod);
    const tests = b.addTest(.{ .root_module = test_mod });
    const run = b.addRunArtifact(tests);
    b.default_step.dependOn(&run.step);
}
