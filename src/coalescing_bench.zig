// Copyright (c) 2026 Boundary contributors. MIT license.
//! Measured source/lowering/encoding/cold-admission costs; no performance policy.
const std = @import("std");
const builtin = @import("builtin");
const source = @import("source.zig");
const data = @import("boundary_data");
const cases = @import("authoring_cases.zig");
const Meter = @import("coalescing_allocation_meter.zig").Meter;
const Phase = struct {
    ns: u64,
    allocations: usize,
    allocated_bytes: usize,
    peak_requested_bytes: usize,
};
const Sample = struct {
    source: Phase,
    compile: Phase,
    encode: Phase,
    cold_admit: Phase,
    compiler_stages_ns: [std.meta.fields(source.CompileStage).len]u64,
    bytes: usize,
    sha256: [64]u8,
    work: u64,
    functions: usize,
    constructors: usize,
};
const Trace = struct {
    io: std.Io,
    last: std.Io.Timestamp,
    stage: source.CompileStage = .source_copy,
    ns: [std.meta.fields(source.CompileStage).len]u64 = @splat(0),
    fn enter(context: *anyopaque, next: source.CompileStage) void {
        const self: *Trace = @ptrCast(@alignCast(context));
        const now = std.Io.Clock.awake.now(self.io);
        self.ns[@intFromEnum(self.stage)] += @intCast(self.last.durationTo(now).nanoseconds);
        self.last = now;
        self.stage = next;
    }
};
fn phase(io: std.Io, start: std.Io.Timestamp, meter: Meter) Phase {
    return .{ .ns = @intCast(start.durationTo(std.Io.Clock.awake.now(io)).nanoseconds), .allocations = meter.calls, .allocated_bytes = meter.allocated, .peak_requested_bytes = meter.peak };
}
fn measure(init: std.process.Init, kind: cases.Kind, mode: data.coalescing.Mode) !Sample {
    var source_meter: Meter = .{ .parent = init.gpa };
    var compile_meter: Meter = .{ .parent = init.gpa };
    var encode_meter: Meter = .{ .parent = init.gpa };
    var admit_meter: Meter = .{ .parent = init.gpa };
    const result = try sample(init.io, kind, mode, &source_meter, &compile_meter, &encode_meter, &admit_meter);
    if (source_meter.live != 0 or compile_meter.live != 0 or
        encode_meter.live != 0 or admit_meter.live != 0) return error.UnreleasedMeasuredStorage;
    return result;
}
fn sample(io: std.Io, kind: cases.Kind, mode: data.coalescing.Mode, source_meter: *Meter, compile_meter: *Meter, encode_meter: *Meter, admit_meter: *Meter) !Sample {
    const start = std.Io.Clock.awake.now(io);
    var builder = source.Builder.init(source_meter.allocator());
    defer builder.deinit();
    const module = try cases.build(&builder, kind);
    const authored = phase(io, start, source_meter.*);
    var stats: data.coalescing.Statistics = .{};
    const lowering = std.Io.Clock.awake.now(io);
    var trace: Trace = .{ .io = io, .last = lowering };
    var compiled = try source.lowerObserved(compile_meter.allocator(), module, .{
        .coalescing = .{ .mode = mode, .statistics = &stats },
        .observer = .{ .context = &trace, .enter = Trace.enter },
    });
    defer compiled.deinit();
    const lowered = phase(io, lowering, compile_meter.*);
    const encoding = std.Io.Clock.awake.now(io);
    const a = encode_meter.allocator();
    const bytes = try a.alloc(u8, try data.program_image.encodedLength(compiled.program));
    defer a.free(bytes);
    _ = try compiled.encode(a, bytes);
    const encoded = phase(io, encoding, encode_meter.*);
    const admission = std.Io.Clock.awake.now(io);
    const admitted = try data.program_image.Admitted.decode(admit_meter.allocator(), bytes);
    defer admitted.deinit();
    return .{ .source = authored, .compile = lowered, .encode = encoded, .cold_admit = phase(io, admission, admit_meter.*), .compiler_stages_ns = trace.ns, .bytes = bytes.len, .sha256 = std.fmt.bytesToHex(data.wire.digest(bytes), .lower), .work = stats.work.units, .functions = compiled.program.functions.len, .constructors = compiled.program.constructors.len };
}
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const kind = std.meta.stringToEnum(cases.Kind, args.next() orelse return error.MissingFixture) orelse return error.InvalidFixture;
    const mode = std.meta.stringToEnum(data.coalescing.Mode, args.next() orelse return error.MissingMode) orelse return error.InvalidMode;
    if (args.next() != null) return error.UnexpectedArgument;
    for (0..3) |_| _ = try measure(init, kind, mode);
    var samples: [9]Sample = undefined;
    for (&samples) |*row| row.* = try measure(init, kind, mode);
    for (samples) |row| if (!std.mem.eql(u8, &samples[0].sha256, &row.sha256))
        return error.NondeterministicImage;
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{ .fixture = kind, .mode = mode, .warmups = 3, .zig = builtin.zig_version_string, .optimization = @tagName(builtin.mode), .architecture = @tagName(builtin.cpu.arch), .os = @tagName(builtin.os.tag), .stage_names = std.meta.fieldNames(source.CompileStage), .samples = samples }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
