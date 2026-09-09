// Copyright (c) 2026 Boundary contributors. MIT license.
//! Pure build-time CLI: one BPI1 on stdin, one canonical BPI2 on stdout.
const std = @import("std");
const legacy = @import("boundary_bpi1");
const data = @import("boundary_data_v2");

pub fn main(init: std.process.Init) !void {
    var arguments = std.process.Args.Iterator.init(init.minimal.args);
    defer arguments.deinit();
    _ = arguments.skip();
    if (arguments.next()) |argument| {
        if (std.mem.eql(u8, argument, "--value")) return convertValue(init, &arguments);
        if (!std.mem.eql(u8, argument, "--help") or arguments.next() != null) return error.UnexpectedArgument;
        var buffer: [512]u8 = undefined;
        var output = std.Io.File.stdout().writer(init.io, &buffer);
        try output.interface.writeAll("Usage: bpi1-lift < program.bpi1 > program.bpi2\nbpi1-lift --value PROGRAM.bpi1 to-v1|to-v2 initial|result|failure|payload:N|resume:N < value > converted-value\nAccepts admitted evaluator-semantics 1, 2, or 3. Does not accept PST1.\n");
        try output.interface.flush();
        return;
    }
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().reader(init.io, &input_buffer);
    const bytes = try input.interface.allocRemaining(init.gpa, .unlimited);
    defer init.gpa.free(bytes);
    var lifted = try legacy.lift(init.gpa, bytes);
    defer lifted.deinit();
    const buffer = try init.gpa.alloc(u8, try data.image.encodedLength(lifted.program));
    defer init.gpa.free(buffer);
    const encoded = try data.image.encode(init.gpa, lifted.program, buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &output_buffer);
    try output.interface.writeAll(encoded);
    try output.interface.flush();
}

fn convertValue(init: std.process.Init, arguments: *std.process.Args.Iterator) !void {
    const path = arguments.next() orelse return error.ExpectedProgramPath;
    const direction = arguments.next() orelse return error.ExpectedDirection;
    const selector = arguments.next() orelse return error.ExpectedValueContract;
    if (arguments.next() != null) return error.UnexpectedArgument;
    const to_v1 = std.mem.eql(u8, direction, "to-v1");
    if (!to_v1 and !std.mem.eql(u8, direction, "to-v2")) return error.InvalidDirection;
    const image = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .unlimited);
    defer init.gpa.free(image);
    var decoded = try legacy.decode(init.gpa, image);
    defer decoded.deinit();
    const catalogs = decoded.program.catalogs;
    const schema = if (std.mem.eql(u8, selector, "initial")) catalogs.initial_args_schema_id else if (std.mem.eql(u8, selector, "result")) catalogs.result_schema_id else if (std.mem.eql(u8, selector, "failure")) catalogs.failure_schema_id else blk: {
        const colon = std.mem.indexOfScalar(u8, selector, ':') orelse return error.InvalidValueContract;
        const ordinal = try std.fmt.parseInt(u32, selector[colon + 1 ..], 10);
        const effect = try legacy.image.evaluatorEffect(decoded.program, ordinal);
        if (std.mem.eql(u8, selector[0..colon], "payload")) break :blk effect.payload_schema;
        if (std.mem.eql(u8, selector[0..colon], "resume")) break :blk effect.resume_schema;
        return error.InvalidValueContract;
    };
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().reader(init.io, &input_buffer);
    const bytes = try input.interface.allocRemaining(init.gpa, .unlimited);
    defer init.gpa.free(bytes);
    const converted = if (to_v1) try legacy.types.toV1(init.gpa, catalogs.schemas, schema, bytes) else try legacy.types.toV2(init.gpa, catalogs.schemas, schema, bytes);
    defer init.gpa.free(converted);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &output_buffer);
    try output.interface.writeAll(converted);
    try output.interface.flush();
}
