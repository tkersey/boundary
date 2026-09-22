//! Optional stage clocks; no callback enters the compiled Program.
const std = @import("std");
const boundary = @import("boundary");
const source = boundary.computation;
const workload = @import("workload");
const Trace = struct {
    io: std.Io,
    last: std.Io.Timestamp,
    stage: source.CompileStage = .source_copy,
    ns: [7]u64 = @splat(0),
    fn enter(context: *anyopaque, stage: source.CompileStage) void {
        const self: *Trace = @ptrCast(@alignCast(context));
        const now = std.Io.Clock.awake.now(self.io);
        self.ns[@intFromEnum(self.stage)] += @intCast(self.last.durationTo(now).nanoseconds);
        self.last = now;
        self.stage = stage;
    }
};
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const mode = args.next() orelse return error.ExpectedMode;
    if (args.next() != null) return error.UnexpectedArgument;
    var b = source.Builder.init(init.gpa);
    defer b.deinit();
    const start = std.Io.Clock.awake.now(init.io);
    const module = if (std.mem.eql(u8, mode, "hyper")) try workload.emitWorkload(&b, .hyper) else if (std.mem.eql(u8, mode, "direct")) try workload.emitWorkload(&b, .direct) else if (std.mem.eql(u8, mode, "materialized")) try workload.emitWorkload(&b, .materialized) else return error.InvalidMode;
    const authored = std.Io.Clock.awake.now(init.io);
    var trace = Trace{ .io = init.io, .last = authored };
    var compiled = try source.lowerObserved(init.gpa, module, .{ .observer = .{ .context = &trace, .enter = Trace.enter } });
    defer compiled.deinit();
    const lowered = std.Io.Clock.awake.now(init.io);
    const bytes = try init.gpa.alloc(u8, try boundary.data.program_image.encodedLength(compiled.program));
    defer init.gpa.free(bytes);
    _ = try compiled.encode(init.gpa, bytes);
    const encoded = std.Io.Clock.awake.now(init.io);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{ .mode = mode, .authorNs = start.durationTo(authored).nanoseconds, .compileNs = authored.durationTo(lowered).nanoseconds, .encodeNs = lowered.durationTo(encoded).nanoseconds, .stageNs = trace.ns, .imageBytes = bytes.len, .imageSha256 = std.fmt.bytesToHex(boundary.data.wire.digest(bytes), .lower) }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
