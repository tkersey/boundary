//! Pair one frozen staged-source artifact with ordinary final compiler bytes.
//! Emitted pass records are untrusted candidates, never proof or certification.
const std = @import("std");
const boundary = @import("boundary");
const data = @import("boundary_data_v2");
const reader = @import("source_input.zig");
const p = data.program;
const diagnostics = boundary.source.Diagnostic;

const Trace = struct {
    allocator: std.mem.Allocator,
    programs: [4]?p.Program = .{ null, null, null, null },

    fn capture(context: *anyopaque, phase: boundary.source.EvidencePhase, program: p.Program) error{OutOfMemory}!void {
        const self: *Trace = @ptrCast(@alignCast(context));
        self.programs[@intFromEnum(phase)] = try boundary.source.own(p.Program, self.allocator, program);
    }
};

fn destination(init: std.process.Init, path: []const u8) ![]u8 {
    const parent = try std.Io.Dir.cwd().realPathFileAlloc(init.io, std.fs.path.dirname(path) orelse ".", init.gpa);
    defer init.gpa.free(parent);
    return std.fs.path.resolve(init.gpa, &.{ parent, std.fs.path.basename(path) });
}

fn sameExistingPath(io: std.Io, left: []const u8, right: []const u8) !bool {
    var left_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var right_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const left_len = std.Io.Dir.cwd().realPathFile(io, left, &left_buffer) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    const right_len = std.Io.Dir.cwd().realPathFile(io, right, &right_buffer) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return std.mem.eql(u8, left_buffer[0..left_len], right_buffer[0..right_len]);
}

fn emitPair(io: std.Io, image_path: []const u8, image: []const u8, witness_path: []const u8, witness: []const u8) !void {
    var image_file = try std.Io.Dir.cwd().createFileAtomic(io, image_path, .{ .replace = true });
    defer image_file.deinit(io);
    var witness_file = try std.Io.Dir.cwd().createFileAtomic(io, witness_path, .{ .replace = true });
    defer witness_file.deinit(io);
    try image_file.file.writeStreamingAll(io, image);
    try witness_file.file.writeStreamingAll(io, witness);
    try image_file.replace(io);
    // A previously absent witness name can now resolve to the new image on a
    // case-insensitive filesystem. Reject before replacing that image again.
    if (try sameExistingPath(io, image_path, witness_path)) return error.AliasedOutputs;
    try witness_file.replace(io);
}

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    defer args.deinit();
    _ = args.skip();
    const source_flag = args.next() orelse return error.ExpectedSource;
    const source_path = args.next() orelse return error.ExpectedSource;
    const image_flag = args.next() orelse return error.ExpectedImage;
    const image_argument = args.next() orelse return error.ExpectedImage;
    const witness_flag = args.next() orelse return error.ExpectedWitness;
    const witness_argument = args.next() orelse return error.ExpectedWitness;
    if (!std.mem.eql(u8, source_flag, "--source") or !std.mem.eql(u8, image_flag, "--image") or
        !std.mem.eql(u8, witness_flag, "--witness") or args.next() != null) return error.InvalidArguments;
    const source_name = try destination(init, source_path);
    defer init.gpa.free(source_name);
    const source_real = try std.Io.Dir.cwd().realPathFileAlloc(init.io, source_path, init.gpa);
    defer init.gpa.free(source_real);
    const image_path = try destination(init, image_argument);
    defer init.gpa.free(image_path);
    const witness_path = try destination(init, witness_argument);
    defer init.gpa.free(witness_path);
    if (std.mem.eql(u8, source_name, image_path) or std.mem.eql(u8, source_name, witness_path) or
        std.mem.eql(u8, source_real, image_path) or std.mem.eql(u8, source_real, witness_path) or
        std.mem.eql(u8, image_path, witness_path)) return error.AliasedOutputs;
    if (try sameExistingPath(init.io, source_path, image_path) or
        try sameExistingPath(init.io, source_path, witness_path) or
        try sameExistingPath(init.io, image_path, witness_path)) return error.AliasedOutputs;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, source_path, init.gpa, .unlimited);
    defer init.gpa.free(bytes);
    var source = try reader.decode(init.gpa, bytes);
    defer source.deinit();
    const decoded_source = try std.json.Stringify.valueAlloc(init.gpa, source.module, .{ .emit_strings_as_arrays = true });
    defer init.gpa.free(decoded_source);
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    var trace: Trace = .{ .allocator = arena.allocator() };
    var diagnostic: diagnostics = .{};
    var compiled = try boundary.source.lowerObserved(init.gpa, source.module, .{
        .diagnostic = &diagnostic,
        .evidence = .{ .context = &trace, .program = Trace.capture },
    });
    defer compiled.deinit();
    const image = try init.gpa.alloc(u8, try data.image.encodedLength(compiled.program));
    defer init.gpa.free(image);
    const encoded = try compiled.encode(init.gpa, image);
    const witness = try std.json.Stringify.valueAlloc(init.gpa, .{
        .format = .@"boundary.translation-witness/v1",
        .source_format = .@"boundary.staged-source/v1",
        .source_bytes = bytes,
        .decoded_source_bytes = decoded_source,
        .image_bytes = encoded,
        .lowered = trace.programs[0].?,
        .custody = trace.programs[1].?,
        .direct = trace.programs[2].?,
        .canonical = trace.programs[3].?,
    }, .{ .emit_strings_as_arrays = true });
    defer init.gpa.free(witness);
    try emitPair(init.io, image_path, encoded, witness_path, witness);
}

test "pass observations own their data beyond compiler and authoring arenas" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var trace: Trace = .{ .allocator = arena.allocator() };
    const expected = blk: {
        var builder = boundary.source.Builder.init(a);
        defer builder.deinit();
        const module = try boundary.source.examples.deep(&builder);
        var compiled = try boundary.source.lowerObserved(a, module, .{
            .evidence = .{ .context = &trace, .program = Trace.capture },
        });
        defer compiled.deinit();
        const bytes = try a.alloc(u8, try data.image.encodedLength(compiled.program));
        errdefer a.free(bytes);
        _ = try compiled.encode(a, bytes);
        break :blk bytes;
    };
    defer a.free(expected);
    for (trace.programs) |program| try data.admission.program(a, program.?);
    const actual = try a.alloc(u8, expected.len);
    defer a.free(actual);
    try std.testing.expectEqualSlices(u8, expected, try data.image.encode(a, trace.programs[3].?, actual));
}

test "a failed final evidence callback releases the canonical output arena" {
    const Fail = struct {
        fn capture(_: *anyopaque, phase: boundary.source.EvidencePhase, _: p.Program) error{OutOfMemory}!void {
            if (phase == .canonical) return error.OutOfMemory;
        }
    };
    var builder = boundary.source.Builder.init(std.testing.allocator);
    defer builder.deinit();
    const module = try boundary.source.examples.lexical(&builder);
    try std.testing.expectError(error.OutOfMemory, boundary.source.lowerObserved(std.testing.allocator, module, .{
        .evidence = .{ .context = &builder, .program = Fail.capture },
    }));
}
