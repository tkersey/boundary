const std = @import("std");
const data = @import("data");
const ir = data.activation;
const flow = data.activation_flow;
const p = data.program;
fn next(state: *u64) u64 {
    state.* = state.* *% 6364136223846793005 +% 1442695040888963407;
    return state.*;
}
fn mask(facts: *const flow.Facts, root: data.analysis_sets.Root) u8 {
    var bits: u8 = 0;
    for (0..6) |slot| if (facts.pool.contains(root, slot)) {
        bits |= @as(u8, 1) << @intCast(slot);
    };
    return bits;
}
fn appendState(hash: *std.crypto.hash.sha2.Sha256, facts: *const flow.Facts, state: flow.State) void {
    hash.update(&.{ mask(facts, state.initialized), mask(facts, state.available), mask(facts, state.obligations) });
}
fn run(allocator: std.mem.Allocator, seed: u64) ![32]u8 {
    var random = seed;
    var operands: [4][2][1]p.Id = undefined;
    var instructions: [4][2]ir.Instruction = undefined;
    var blocks: [4]ir.Block = undefined;
    for (&blocks, 0..) |*block, i| {
        for (&instructions[i], 0..) |*op, j| {
            const choice = next(&random) % 4;
            const from: u64 = if (choice == 3) 4 + next(&random) % 2 else 1 + next(&random) % 3;
            const to: u64 = if (choice == 3) 4 + next(&random) % 2 else 1 + next(&random) % 3;
            operands[i][j][0] = from;
            op.* = if (choice < 2) .{ .opcode = .constant, .destination = to } else .{ .opcode = .move, .destination = to, .operands = &operands[i][j] };
        }
        block.* = .{ .function = 0, .instructions = &instructions[i], .terminator = if (i == 3) .{ .return_value = 1 } else .{ .branch = .{ .condition = 0, .when_true = .{ .block = next(&random) % 4 }, .when_false = .{ .block = next(&random) % 4 } } } };
    }
    const function: ir.Function = .{ .entry = seed % 4, .inputs = if (seed & 4 == 0) &.{ 0, 1, 4 } else &.{ 0, 1, 4, 5 }, .layout = .{ .slots = &.{ 2, 0, 0, 0, 3, 3 } }, .result = 0 };
    const image: ir.Program = .{ .roots = .{ .entry = 0, .result = 0, .failure = 1 }, .functions = (&function)[0..1], .blocks = &blocks, .schemas = &.{ .u64, .unit, .boolean, .{ .internal = .{ .resumption = .{ .effect = 0, .input = 0, .answer = 0, .handled = &.{0}, .mode = .deep, .use = .linear } } } }, .effects = &.{.{ .identity = "read", .payload = 1, .result = 0 }}, .constants = &.{.{ .schema = 0, .bytes = &.{ 1, 0, 0, 0, 0, 0, 0, 0 } }} };
    var facts = try flow.analyze(allocator, image);
    defer facts.deinit();
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    for (facts.entries, 0..) |entry, i| {
        hash.update(&.{@intFromBool(entry != null)});
        if (entry) |present| appendState(&hash, &facts, present);
        for (facts.positions[i]) |state| appendState(&hash, &facts, state);
        for (facts.live[i]) |root| hash.update(&.{mask(&facts, root)});
    }
    return hash.finalResult();
}
pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    for (0..1024) |seed| {
        const result = run(init.gpa, seed);
        if (result) |hash| {
            try std.json.Stringify.value(.{ .seed = seed, .facts = std.fmt.bytesToHex(hash, .lower) }, .{}, &output.interface);
        } else |err| {
            try std.json.Stringify.value(.{ .seed = seed, .error_name = @errorName(err) }, .{}, &output.interface);
        }
        try output.interface.writeByte('\n');
    }
    try output.interface.flush();
}
