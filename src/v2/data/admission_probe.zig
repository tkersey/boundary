//! Test-only program admission and untrusted borrow-analysis witness adapter.
//! Every borrowed field below belongs to main's arena through serialization.
//! Output begins only after parsing, full admission, analysis and JSON allocation.
const std = @import("std");
const p = @import("program.zig");
const a = @import("admission.zig");
const borrow = @import("borrow_flow.zig");
const record = @import("record.zig");
const wire = @import("wire.zig");
const canonical = @import("canonical.zig");
const image = @import("image.zig");

const Path = struct { step: borrow.Step, tail: usize };
const Trace = struct {
    block: p.Id,
    slot: p.Id,
    path: usize,
    ambient: ?borrow.Ambient,
    body_result: bool,
};
const Query = struct {
    start: p.Id,
    path: usize,
    target: ?Trace,
    writes: ?p.Id,
    sources: []const borrow.Source,
};
const Requirements = struct { start: p.Id, constraints: []const borrow.Constraint };
const RequestedQuery = struct { start: p.Id, path: []const borrow.Step };

fn rawProgram(allocator: std.mem.Allocator, input: []const u8) !p.Program {
    var reader: wire.Reader = .{ .input = input };
    const program = try record.read(p.Program, &reader, allocator);
    try reader.finish();
    try a.program(allocator, program);
    return program;
}

fn scopedReturns(flow: *borrow.Flow) !void {
    for (flow.program.blocks) |block| {
        const body = switch (block.terminator) {
            .handle => |v| v.body,
            .with_region => |v| v.body,
            .protect => |v| v.body,
            else => continue,
        };
        const schema = try @import("contracts.zig").slotSchema(block, body);
        for (flow.program.constructors) |constructor| {
            if (constructor.schema != schema) continue;
            const function = flow.program.functions[@intCast(constructor.function)];
            _ = try flow.returned(function.entry);
        }
    }
}

fn requestedPath(flow: *borrow.Flow, steps: []const borrow.Step) !usize {
    var tail: usize = 0;
    var offset = steps.len;
    while (offset != 0) {
        offset -= 1;
        const step = steps[offset];
        switch (step) {
            .environment => |value| if (value.constructor >= flow.program.constructors.len) return error.InvalidReference,
            .handler_state => |value| if (value.handler >= flow.program.handlers.len) return error.InvalidReference,
            .use_site => |value| if (value.schema >= flow.program.schemas.len) return error.InvalidReference,
            .body_result => |value| if (value >= flow.program.schemas.len) return error.InvalidReference,
            else => {},
        }
        var found: ?usize = null;
        for (flow.paths.items, 0..) |path, index| {
            if (path.tail == tail and std.meta.eql(path.step, step)) {
                found = index + 1;
                break;
            }
        }
        if (found) |index| {
            tail = index;
        } else {
            try flow.paths.append(flow.allocator, .{ .step = step, .tail = tail });
            tail = flow.paths.items.len;
        }
    }
    return tail;
}

fn witness(allocator: std.mem.Allocator, input: []const u8, program: p.Program, requested: ?[]const RequestedQuery) ![]const u8 {
    const facts = try a.schemas(allocator, program.schemas);
    var flow = try borrow.Flow.init(allocator, program, facts.exportable);
    for (program.functions) |function| _ = try flow.required(function.entry);
    try scopedReturns(&flow);
    if (requested) |queries| {
        for (program.blocks, 0..) |_, index| _ = try flow.required(index);
        for (queries) |query| {
            if (query.start >= program.blocks.len) return error.InvalidReference;
            _ = try flow.returnedAt(query.start, try requestedPath(&flow, query.path));
        }
    }
    const paths = try allocator.alloc(Path, flow.paths.items.len);
    for (flow.paths.items, paths) |path, *output|
        output.* = .{ .step = path.step, .tail = path.tail };
    const queries = try allocator.alloc(Query, flow.queries.items.len);
    for (flow.queries.items, queries) |query, *output| output.* = .{
        .start = query.start,
        .path = query.path,
        .target = if (query.target) |target| .{
            .block = target.block,
            .slot = target.slot,
            .path = target.path,
            .ambient = target.ambient,
            .body_result = target.body_result,
        } else null,
        .writes = query.writes,
        .sources = query.sources.items,
    };
    const requirements = try allocator.alloc(Requirements, flow.requirements.items.len);
    for (flow.requirements.items, requirements) |item, *output|
        output.* = .{ .start = item.start, .constraints = item.constraints.items };
    return std.json.Stringify.valueAlloc(allocator, .{
        .program_bytes = input,
        .paths = paths,
        .queries = queries,
        .requirements = requirements,
    }, .{ .emit_strings_as_arrays = true });
}

fn tags(comptime T: type, io: std.Io) !void {
    inline for (@typeInfo(T).@"enum".fields) |field|
        try std.Io.File.stdout().writeStreamingAll(io, field.name ++ "\n");
}

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    defer args.deinit();
    _ = args.skip();
    const mode = args.next() orelse return error.ExpectedMode;
    if (std.mem.eql(u8, mode, "opcodes")) {
        if (args.next() != null) return error.InvalidArguments;
        return tags(p.Opcode, init.io);
    }
    if (std.mem.eql(u8, mode, "terminators")) {
        if (args.next() != null) return error.InvalidArguments;
        return tags(std.meta.Tag(p.Terminator), init.io);
    }
    if (!std.mem.eql(u8, mode, "program") and !std.mem.eql(u8, mode, "borrow") and !std.mem.eql(u8, mode, "graph-borrow") and
        !std.mem.eql(u8, mode, "canonical") and !std.mem.eql(u8, mode, "normalize") and
        !std.mem.eql(u8, mode, "image") and !std.mem.eql(u8, mode, "state"))
        return error.InvalidMode;
    const path = args.next() orelse return error.ExpectedInput;
    const query_path = if (std.mem.eql(u8, mode, "graph-borrow")) args.next() orelse return error.ExpectedQueries else null;
    const state_path = if (std.mem.eql(u8, mode, "state")) args.next() orelse return error.ExpectedState else null;
    if (args.next() != null) return error.InvalidArguments;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    const input = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        path,
        allocator,
        .limited(64 * 1024 * 1024),
    );
    if (std.mem.eql(u8, mode, "image")) {
        var decoded = try image.decode(allocator, input);
        defer decoded.deinit();
        const output = try image.encode(allocator, decoded.program, try allocator.alloc(u8, try image.encodedLength(decoded.program)));
        try std.Io.File.stdout().writeStreamingAll(init.io, output);
        return;
    }
    const program = try rawProgram(allocator, input);
    if (state_path) |state_file| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, state_file, allocator, .limited(64 * 1024 * 1024));
        var reader: wire.Reader = .{ .input = try wire.unframe(.pst, bytes) };
        const state = try record.read(@import("graph.zig").State, &reader, allocator);
        try reader.finish();
        try @import("state_admission.zig").validate(allocator, program, state);
        try std.Io.File.stdout().writeStreamingAll(init.io, bytes);
        return;
    }
    if (std.mem.eql(u8, mode, "canonical")) try canonical.require(allocator, program);
    if (std.mem.eql(u8, mode, "normalize")) {
        var normalized = try canonical.normalize(allocator, program);
        defer normalized.deinit();
        var size: wire.Writer = .{};
        try record.write(p.Program, normalized.program, &size);
        const output = try allocator.alloc(u8, size.position);
        var writer: wire.Writer = .{ .output = output };
        try record.write(p.Program, normalized.program, &writer);
        try std.Io.File.stdout().writeStreamingAll(init.io, output);
        return;
    }
    const requested = if (query_path) |query_file| blk: {
        const json = try std.Io.Dir.cwd().readFileAlloc(init.io, query_file, allocator, .limited(16 * 1024 * 1024));
        const parsed = try std.json.parseFromSlice([]const RequestedQuery, allocator, json, .{});
        break :blk @as(?[]const RequestedQuery, parsed.value);
    } else null;
    const output = if (std.mem.eql(u8, mode, "borrow") or query_path != null)
        try witness(allocator, input, program, requested)
    else
        input;
    try std.Io.File.stdout().writeStreamingAll(init.io, output);
}
