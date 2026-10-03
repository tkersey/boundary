//! Synthetic affine economics. Requested bytes exclude allocator metadata/RSS.
const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const Meter = @import("meter").Meter;
const fixture = @import("affine_capture.zig");

const Row = struct { case: []const u8, mode: []const u8, private_words: usize, capture_words: usize, image_bytes: usize, image_digest: [32]u8, construction_peak: usize, construction_allocated: usize, admission_peak: usize, prepared_bytes: usize, invocation_peak: usize, checkpoint_max: usize, transitions: usize };
fn measure(init: std.process.Init, name: []const u8, original: data.activation.Program, constructor_id: ?usize, args: []const u8, expected: []const u8, rows: *std.ArrayList(Row)) !void {
    const a = init.gpa;
    for (0..3) |arm| {
        if (arm == 1 and constructor_id == null and !@hasDecl(data.affine_state, "runTarget")) continue;
        var construction: Meter = .{ .parent = a };
        var owned = if (arm == 0) try data.coalescing.run(construction.allocator(), original, .{}) else if (arm == 1) blk: {
            if (constructor_id) |id| break :blk try data.affine_state.run(construction.allocator(), original, id, null, 1000000, .{});
            if (@hasDecl(data.affine_state, "runTarget")) break :blk try data.affine_state.runTarget(construction.allocator(), original, data.affine_state.directTarget(original, 1).?, null, 1000000, .{});
            unreachable;
        } else try data.closed_compilation.run(construction.allocator(), original, .{ .contract = .semantic });
        defer owned.deinit();
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(owned.program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, owned.program, bytes);
        const storage = try a.alloc(u8, 64 << 20);
        defer a.free(storage);
        var workspace = world.Workspace.init(storage);
        var prepared = try world.Prepared.init(workspace.allocator(), bytes);
        const admission_peak = workspace.peak_payload;
        const prepared_bytes = try prepared.storageBytes();
        prepared.deinit();
        var execution: Meter = .{ .parent = a };
        var outcome = try world.invocation.invoke(execution.allocator(), .{ .image = bytes, .instance = .{ .initial_args = args }, .quantum = 1 });
        defer outcome.deinit();
        var checkpoint_max: usize = 0;
        var transitions: usize = 1;
        while (outcome.record == .progressed) {
            const state = outcome.record.progressed orelse return error.MissingState;
            checkpoint_max = @max(checkpoint_max, state.len);
            var next = try world.invocation.invoke(execution.allocator(), .{ .image = bytes, .instance = .{ .state = state }, .quantum = 1 });
            outcome.deinit();
            outcome = next;
            next = undefined;
            transitions += 1;
            if (transitions > 10000) return error.NoCompletion;
        }
        if (outcome.record != .completed) return error.WrongOutcome;
        if (!std.mem.eql(u8, expected, outcome.record.completed)) return error.WrongResult;
        var capture_words: usize = 0;
        for (owned.program.constructors) |constructor| capture_words += owned.program.scopes.captures[@intCast(constructor.capture)].fields.len;
        const entry = owned.program.functions[@intCast(owned.program.roots.entry)].entry;
        const worker = if (owned.program.constructors.len != 0) owned.program.constructors[0].function else owned.program.blocks[@intCast(entry)].terminator.call.function;
        try rows.append(a, .{ .case = name, .private_words = owned.program.functions[@intCast(worker)].inputs.len - 2, .mode = if (arm == 0) "p01-baseline" else if (arm == 1) "affine-only" else "semantic-pipeline", .capture_words = capture_words, .image_bytes = bytes.len, .image_digest = data.wire.digest(bytes), .construction_peak = construction.peak, .construction_allocated = construction.allocated, .admission_peak = admission_peak, .prepared_bytes = prepared_bytes, .invocation_peak = execution.peak, .checkpoint_max = checkpoint_max, .transitions = transitions });
    }
}
pub fn main(init: std.process.Init) !void {
    var rows: std.ArrayList(Row) = .empty;
    defer rows.deinit(init.gpa);
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const storage = arena.allocator();
    var args: [33]u8 = undefined;
    for ([_]u64{ 1, 2, 4, 8 }, 0..) |value, i| std.mem.writeInt(u64, args[i * 8 ..][0..8], value, .little);
    args[32] = 31;
    var p0: u64 = 1;
    var q0: u64 = 2;
    var r0: u64 = 4;
    for (0..31) |_| {
        const old = p0;
        p0 = q0;
        q0 = r0;
        r0 = old ^ 8 ^ 0xa5;
    }
    var expected: [8]u8 = undefined;
    std.mem.writeInt(u64, &expected, p0 ^ q0 ^ 8 ^ 0xa5, .little);
    try measure(init, "recurrent-31", comptime fixture.recurrentFixture(), 0, &args, &expected, &rows);
    for ([_]usize{ 8, 32, 128 }) |n| {
        var program = try fixture.parityFixture(storage, n);
        const blocks = try storage.dupe(data.activation.Block, program.blocks);
        blocks[0].instructions = &.{};
        blocks[0].terminator = .{ .call = .{ .function = 1, .arguments = program.functions[0].inputs, .next = program.blocks[0].terminator.apply.next } };
        program.blocks = blocks;
        program.constructors = &.{};
        const input = try storage.alloc(u8, (n + 1) * 8 + 1);
        var parity: u64 = 0;
        for (0..n) |i| {
            std.mem.writeInt(u64, input[i * 8 ..][0..8], i + 1, .little);
            parity ^= i + 1;
        }
        std.mem.writeInt(u64, input[n * 8 ..][0..8], 0xa5, .little);
        input[input.len - 1] = 1;
        std.mem.writeInt(u64, &expected, parity ^ 0xa5, .little);
        try measure(init, try storage.print("direct-parity-{d}", .{n}), program, null, input, &expected, &rows);
    }
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{ .scope = "synthetic repeated affine cycle and direct parameter scaling; one-step fresh invocation includes checkpoint overlap; compiler pass bytes exclude fixed fixture allocations; requested bytes exclude allocator metadata/RSS; no timing claim", .rows = rows.items }, .{}, &out.interface);
    try out.interface.writeByte('\n');
    try out.interface.flush();
}
