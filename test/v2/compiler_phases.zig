//! Runtime measurements of the public compiler and pure codecs. No evaluator.
const std = @import("std");
const boundary = @import("boundary");
const data = boundary.data_v2;
const options = @import("phase_options");
const Stage = boundary.computation.CompileStage;
const Phases = struct {
    authoring_ns: u64 = 0,
    source_copy_ns: u64 = 0,
    source_check_ns: u64 = 0,
    lowering_ns: u64 = 0,
    target_check_ns: u64 = 0,
    direct_optimization_ns: u64 = 0,
    canonicalization_ns: u64 = 0,
    image_emission_ns: u64 = 0,
    image_decode_ns: u64 = 0,
    snapshot_emission_ns: u64 = 0,
    snapshot_decode_ns: u64 = 0,
    input_encode_ns: u64 = 0,
    input_decode_ns: u64 = 0,
    outcome_encode_ns: u64 = 0,
    outcome_decode_ns: u64 = 0,
};
const Observer = struct {
    io: std.Io,
    phases: *Phases,
    previous: ?Stage = null,
    started: std.Io.Timestamp = undefined,
    fn enter(context: *anyopaque, stage: Stage) void {
        const self: *@This() = @ptrCast(@alignCast(context));
        const now = std.Io.Clock.awake.now(self.io);
        if (self.previous) |previous| {
            const duration: u64 = @intCast(self.started.durationTo(now).nanoseconds);
            switch (previous) {
                .source_copy => self.phases.source_copy_ns += duration,
                .source_check => self.phases.source_check_ns += duration,
                .lowering => self.phases.lowering_ns += duration,
                .target_check => self.phases.target_check_ns += duration,
                .direct_optimization => self.phases.direct_optimization_ns += duration,
                .canonicalization => self.phases.canonicalization_ns += duration,
                .complete => {},
            }
        }
        self.previous = stage;
        self.started = now;
    }
};
fn elapsed(io: std.Io, start: std.Io.Timestamp) u64 {
    return @intCast(start.durationTo(std.Io.Clock.awake.now(io)).nanoseconds);
}
const Measurement = struct { phases: Phases, image_bytes: usize, image_sha256: [64]u8, snapshot_bytes: usize, input_bytes: usize, outcome_bytes: usize };
fn measure(io: std.Io, storage: []u8) !Measurement {
    var scratch = std.heap.FixedBufferAllocator.init(storage);
    const a = scratch.allocator();
    var phases: Phases = .{};
    var start = std.Io.Clock.awake.now(io);
    var builder = boundary.computation.Builder.init(a);
    defer builder.deinit();
    const module = try switch (options.kind) {
        0 => boundary.computation.examples.deep(&builder),
        1 => boundary.computation.examples.choicesAll(&builder),
        2 => boundary.computation.examples.stateLocal(&builder),
        3 => boundary.computation.examples.resourceScalar(&builder),
        4 => boundary.computation.examples.queensDfs(&builder),
        5 => boundary.computation.examples.installations(&builder, 1),
        6 => boundary.computation.examples.installations(&builder, 8),
        7 => boundary.computation.examples.installations(&builder, 64),
        else => return error.UnknownWorkload,
    };
    phases.authoring_ns = elapsed(io, start);
    var observer: Observer = .{ .io = io, .phases = &phases };
    var compiled = try boundary.program.compileObserved(a, module, .{ .observer = .{ .context = &observer, .enter = Observer.enter } });
    defer compiled.deinit();
    start = std.Io.Clock.awake.now(io);
    const image = try a.alloc(u8, try data.image.encodedLength(compiled.program));
    _ = try compiled.encode(a, image);
    phases.image_emission_ns = elapsed(io, start);
    start = std.Io.Clock.awake.now(io);
    var decoded = try data.image.decode(a, image);
    defer decoded.deinit();
    phases.image_decode_ns = elapsed(io, start);
    // This is a fully admitted initial logical control State, built using pure
    // data APIs. Codec measurements make no claim of a historical transition.
    const initial: data.graph.State = .{ .program_identity = try data.image.identity(compiled.program), .status = .active, .roots = .{ .current = .{ .id = 0 } }, .nodes = &.{.{ .control = .{ .block = compiled.program.functions[@intCast(compiled.program.roots.entry)].entry, .arguments = &.{} } }} };
    try data.state_admission.validate(a, compiled.program, initial);
    start = std.Io.Clock.awake.now(io);
    const emitted = try data.snapshot.emit(a, initial, a, null);
    var normalized = emitted.normalized;
    defer normalized.deinit();
    phases.snapshot_emission_ns = elapsed(io, start);
    start = std.Io.Clock.awake.now(io);
    var saved = try data.snapshot.decodeGraph(a, emitted.bytes);
    defer saved.deinit();
    phases.snapshot_decode_ns = elapsed(io, start);
    const input: data.protocol.Input = .{ .mode = .run, .image = image, .instance = .{ .state = emitted.bytes }, .control = .{ .continue_value = null } };
    start = std.Io.Clock.awake.now(io);
    const pki = try a.alloc(u8, try data.protocol.encodedLength(data.protocol.Input, input));
    _ = try data.protocol.encode(data.protocol.Input, a, input, pki);
    phases.input_encode_ns = elapsed(io, start);
    start = std.Io.Clock.awake.now(io);
    _ = try data.protocol.decode(data.protocol.Input, a, pki);
    phases.input_decode_ns = elapsed(io, start);
    const outcome: data.protocol.Outcome = .{ .progressed = emitted.bytes };
    start = std.Io.Clock.awake.now(io);
    const pko = try a.alloc(u8, try data.protocol.encodedLength(data.protocol.Outcome, outcome));
    _ = try data.protocol.encode(data.protocol.Outcome, a, outcome, pko);
    phases.outcome_encode_ns = elapsed(io, start);
    start = std.Io.Clock.awake.now(io);
    _ = try data.protocol.decode(data.protocol.Outcome, a, pko);
    phases.outcome_decode_ns = elapsed(io, start);
    return .{ .phases = phases, .image_bytes = image.len, .image_sha256 = std.fmt.bytesToHex(data.wire.digest(image), .lower), .snapshot_bytes = emitted.bytes.len, .input_bytes = pki.len, .outcome_bytes = pko.len };
}
pub fn main(init: std.process.Init) !void {
    const storage = try init.gpa.alloc(u8, 16 << 20);
    defer init.gpa.free(storage);
    for (0..5) |_| _ = try measure(init.io, storage);
    var measurements: [21]Measurement = undefined;
    for (&measurements) |*measurement| measurement.* = try measure(init.io, storage);
    for (measurements[1..]) |measurement| if (!std.mem.eql(u8, &measurement.image_sha256, &measurements[0].image_sha256)) return error.NondeterministicImage;
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &output_buffer);
    try std.json.Stringify.value(.{ .kind = options.kind, .warmups = 5, .scratch_capacity = storage.len, .measurements = measurements }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
