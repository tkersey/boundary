const artifact = @import("artifact_api");
const program_plan = @import("internal_program_plan");
const std = @import("std");

const oversized_return_bytes = (1 << 20) + 1;

/// Build-only fixture generator for the public Agent VM conformance suite.
pub fn main(init: std.process.Init) anyerror!void {
    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);
    if (args.len != 5) {
        std.debug.print("usage: generate-agent-vm-conformance-fixtures <no-host> <host-call> <output-snapshot> <oversized-return>\n", .{});
        std.process.exit(2);
    }

    try writeArtifact(init.io, allocator, args[1], try makeReturnStringArtifact(allocator, "ok"));
    try writeArtifact(init.io, allocator, args[2], try makeHostCallArtifact(allocator));
    try writeArtifact(init.io, allocator, args[3], try makeDeclaredOutputArtifact(allocator));

    const oversized = try allocator.alloc(u8, oversized_return_bytes);
    defer allocator.free(oversized);
    @memset(oversized, 'x');
    try writeArtifact(init.io, allocator, args[4], try makeReturnStringArtifact(allocator, oversized));
}

fn writeArtifact(io: std.Io, allocator: std.mem.Allocator, path: []const u8, bytes: []u8) !void {
    defer allocator.free(bytes);
    var atomic_file = try std.Io.Dir.cwd().createFileAtomic(io, path, .{ .replace = true });
    defer atomic_file.deinit(io);
    var buffer: [1024]u8 = undefined;
    var file_writer = atomic_file.file.writer(io, &buffer);
    try file_writer.interface.writeAll(bytes);
    try file_writer.flush();
    try atomic_file.replace(io);
}

fn encodePlan(allocator: std.mem.Allocator, plan: program_plan.ProgramPlan, capabilities: []const artifact.CapabilityV1) ![]u8 {
    return try artifact.encodeProgramPlan(allocator, plan, .{
        .build_fingerprint_blake3_256 = artifact.defaultBuildFingerprint(),
        .capabilities = capabilities,
    });
}

fn makeReturnStringArtifact(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "entry",
        .value_codec = .string,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 2,
    }};
    const locals = [_]program_plan.LocalPlan{.{ .codec = .string }};
    const blocks = [_]program_plan.BlockPlan{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_value }};
    const instructions = [_]program_plan.Instruction{
        .{ .kind = .const_string, .dst = 0, .string_literal = value },
        .{ .kind = .return_value, .operand = 0 },
    };
    const plan: program_plan.ProgramPlan = .{
        .label = "ability_agent_vm.conformance.return_string",
        .ir_hash = 0xA901,
        .entry_index = 0,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &locals,
        .call_args = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    };
    return try encodePlan(allocator, plan, &.{});
}

fn makeHostCallArtifact(allocator: std.mem.Allocator) ![]u8 {
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "entry",
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 0,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 1,
    }};
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "tooling", .first_op = 0, .op_count = 1 }};
    const ops = [_]program_plan.OpPlan{.{ .requirement_index = 0, .op_name = "dispatch", .mode = .transform, .payload_codec = .unit, .resume_codec = .unit }};
    const blocks = [_]program_plan.BlockPlan{.{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_unit }};
    const instructions = [_]program_plan.Instruction{.{ .kind = .call_op, .operand = 0, .aux = std.math.maxInt(u16) }};
    const plan: program_plan.ProgramPlan = .{
        .label = "ability_agent_vm.conformance.host_call",
        .ir_hash = 0xA902,
        .entry_index = 0,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    };
    const capabilities = try artifact.deriveToolCapabilitiesFromPlan(allocator, plan);
    defer artifact.deepFreeCapabilities(allocator, capabilities);
    return try encodePlan(allocator, plan, capabilities);
}

fn makeDeclaredOutputArtifact(allocator: std.mem.Allocator) ![]u8 {
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "entry",
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 1,
        .first_local = 0,
        .local_count = 0,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 0,
    }};
    const outputs = [_]program_plan.OutputPlan{.{ .label = "payload", .codec = .string_list }};
    const blocks = [_]program_plan.BlockPlan{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_unit }};
    const plan: program_plan.ProgramPlan = .{
        .label = "ability_agent_vm.conformance.output_snapshot",
        .ir_hash = 0xA903,
        .entry_index = 0,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &outputs,
        .locals = &.{},
        .call_args = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &.{},
    };
    return try encodePlan(allocator, plan, &.{});
}
