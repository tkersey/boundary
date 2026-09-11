//! Test-only adapter for independent Lean byte and digest conformance.
const std = @import("std");
const p = @import("program.zig");
const protocol = @import("protocol.zig");
const image = @import("image.zig");
const schema = @import("schema.zig");
const record = @import("record.zig");
const wire = @import("wire.zig");

fn raw(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T {
    var reader: wire.Reader = .{ .input = input };
    const value = try record.read(T, &reader, allocator);
    try reader.finish();
    return value;
}

fn identity(mode: []const u8, allocator: std.mem.Allocator, input: []const u8) ![32]u8 {
    if (std.mem.eql(u8, mode, "sha256")) return wire.digest(input);
    if (std.mem.eql(u8, mode, "program-identity"))
        return image.identity(try raw(p.Program, allocator, input));
    if (std.mem.eql(u8, mode, "continuation-identity")) {
        const Binding = struct {
            program: [32]u8,
            state: [32]u8,
            source_block: u64,
            resume_schema: [32]u8,
        };
        const binding = try raw(Binding, allocator, input);
        return protocol.continuationIdentity(binding.program, binding.state, binding.source_block, binding.resume_schema);
    }
    const request = try raw(protocol.Request, allocator, try wire.unframe(.erq, input));
    if (std.mem.eql(u8, mode, "request-identity")) return protocol.requestIdentity(request);
    if (std.mem.eql(u8, mode, "contract-identity"))
        return protocol.contractIdentity(request.semantic_identity, request.payload_schema, request.resume_schema);
    return error.InvalidMode;
}

fn admitted(
    comptime T: type,
    allocator: std.mem.Allocator,
    input: []const u8,
) ![]const u8 {
    const value = try protocol.decode(T, allocator, input);
    const output = try allocator.alloc(u8, try protocol.encodedLength(T, value));
    return protocol.encode(T, allocator, value, output);
}

fn descriptor(mode: []const u8, allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    const value = if (std.mem.eql(u8, mode, "schema")) blk: {
        const decoded = try schema.decode(allocator, input);
        // All nested arenas use this call's outer arena as their backing owner.
        break :blk decoded.descriptor;
    } else try raw(schema.Descriptor, allocator, input);
    return schema.encodeOwned(allocator, value.types, value.root);
}

fn result(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    const Pair = struct { request: []const u8, result: []const u8 };
    const pair = try raw(Pair, allocator, input);
    const request = try protocol.decode(protocol.Request, allocator, pair.request);
    const resumed = try protocol.decode(protocol.Result, allocator, pair.result);
    try protocol.validateResult(allocator, request, resumed);
    return input;
}

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    defer args.deinit();
    _ = args.skip();
    const mode = args.next() orelse return error.ExpectedMode;
    if (std.mem.eql(u8, mode, "schema-tags")) {
        if (args.next() != null) return error.InvalidArguments;
        inline for (@typeInfo(p.SchemaTag).@"enum".fields) |field|
            try std.Io.File.stdout().writeStreamingAll(init.io, field.name ++ "\n");
        return;
    }
    const path = args.next() orelse return error.ExpectedInput;
    if (args.next() != null) return error.InvalidArguments;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const input = try std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(64 * 1024 * 1024));
    const stdout = std.Io.File.stdout();
    if (std.mem.eql(u8, mode, "input")) {
        try stdout.writeStreamingAll(init.io, try admitted(protocol.Input, a, input));
    } else if (std.mem.eql(u8, mode, "outcome")) {
        try stdout.writeStreamingAll(init.io, try admitted(protocol.Outcome, a, input));
    } else if (std.mem.eql(u8, mode, "request")) {
        try stdout.writeStreamingAll(init.io, try admitted(protocol.Request, a, input));
    } else if (std.mem.eql(u8, mode, "result")) {
        try stdout.writeStreamingAll(init.io, try result(a, input));
    } else if (std.mem.eql(u8, mode, "schema") or std.mem.eql(u8, mode, "schema-normalize")) {
        try stdout.writeStreamingAll(init.io, try descriptor(mode, a, input));
    } else {
        const digest = try identity(mode, a, input);
        try stdout.writeStreamingAll(init.io, &digest);
    }
}
