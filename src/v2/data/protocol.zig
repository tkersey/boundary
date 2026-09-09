// Copyright (c) 2026 Boundary contributors. MIT license.
//! Portable Process records. Invocation, allocation policy, and execution live in World.
const std = @import("std");
const wire = @import("wire.zig");
const record = @import("record.zig");
const schema = @import("schema.zig");
pub const Error = schema.Error || error{ InvalidRequest, InvalidResult, InvalidControl };
pub const Mode = enum(u8) { advance = 0, run = 1 };
pub const InstanceTag = enum(u8) { initial_args = 0, state = 1 };
pub const Instance = union(InstanceTag) { initial_args: []const u8, state: []const u8 };
pub const ReasonTag = enum(u8) { text = 0, bytes = 1 };
pub const Reason = union(ReasonTag) { text: []const u8, bytes: []const u8 };
pub const ControlTag = enum(u8) { continue_value = 0, cancel = 1 };
pub const Control = union(ControlTag) { continue_value: ?[]const u8, cancel: Reason };
pub const Input = struct { mode: Mode, image: []const u8, instance: Instance, control: Control };
pub const Bound = struct {
    bytes: u64 = 0,
    provenance: enum(u8) { not_observed = 0, exact = 1, lower_bound = 2 } = .not_observed,
};
pub const Capacity = struct {
    arena: enum(u8) { input = 0, working = 1, output = 2, memory = 3 },
    input: Bound = .{},
    working: Bound = .{},
    output: Bound = .{},
    memory_pages: Bound = .{},
};
pub const OutcomeTag = enum(u8) { progressed = 0, requested = 1, yielded = 2, completed = 3, failed = 4, cancelled = 5, needs_capacity = 6 };
pub const Outcome = union(OutcomeTag) {
    progressed: []const u8,
    requested: struct { state: []const u8, request: []const u8 },
    yielded: []const u8,
    completed: []const u8,
    failed: struct { value: []const u8, cleanup_failures: []const u8 = &.{0}, cancellation: ?Reason = null },
    cancelled: struct { reason: Reason, cleanup_failures: []const u8 = &.{0} },
    needs_capacity: Capacity,
};
pub const Request = struct {
    program_identity: [32]u8,
    pending_state_digest: [32]u8,
    residual_contract_digest: [32]u8,
    continuation_binding_digest: [32]u8,
    semantic_identity: []const u8,
    payload_schema: []const u8,
    resume_schema: []const u8,
    payload: []const u8,
    request_identity: [32]u8,
};
pub const Result = struct {
    request_identity: [32]u8,
    resume_schema_digest: [32]u8,
    value: []const u8,
};

fn family(comptime T: type) wire.Family {
    return if (T == Input) .pki else if (T == Outcome) .pko else if (T == Request) .erq else if (T == Result) .ers else @compileError("not a Process record");
}

pub fn encodedLength(comptime T: type, value: T) Error!usize {
    var measure: wire.Writer = .{};
    try record.write(T, value, &measure);
    return std.math.add(usize, wire.header_length, measure.position) catch error.InvalidLength;
}

/// Canonical record output borrows the caller's buffer; it contains no native addresses.
pub fn encode(comptime T: type, allocator: std.mem.Allocator, value: T, output: []u8) Error![]const u8 {
    if (T == Input) try validateInput(value);
    if (T == Request) try validateRequest(allocator, value);
    if (T == Outcome) try validateOutcome(value);
    const length = try encodedLength(T, value);
    if (output.len < length) return error.Capacity;
    if (record.overlaps(T, value, output[0..length])) return error.InvalidBuffers;
    var writer: wire.Writer = .{ .output = output[0..length] };
    try writer.put(wire.magic(family(T)));
    try writer.fixed(u16, 2);
    try writer.fixed(u16, 0);
    try writer.fixed(u64, length - wire.header_length);
    try record.write(T, value, &writer);
    return output[0..writer.position];
}

/// Slices borrow input. The fixed record shapes allocate no nested record arrays.
pub fn decode(comptime T: type, allocator: std.mem.Allocator, input: []const u8) Error!T {
    const body = try wire.unframe(family(T), input);
    var reader: wire.Reader = .{ .input = body };
    var empty: [0]u8 = .{};
    var record_allocator = std.heap.FixedBufferAllocator.init(&empty);
    const value = try record.read(T, &reader, record_allocator.allocator());
    try reader.finish();
    if (T == Input) try validateInput(value);
    if (T == Request) try validateRequest(allocator, value);
    if (T == Outcome) try validateOutcome(value);
    return value;
}

fn validateInput(input: Input) Error!void {
    if (input.control == .cancel) {
        if (input.instance != .state) return error.InvalidControl;
        switch (input.control.cancel) {
            .text => |text| if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8,
            .bytes => {},
        }
    } else if (input.instance == .initial_args and input.control.continue_value != null) return error.InvalidControl;
}

fn validateOutcome(outcome: Outcome) Error!void {
    const failures = switch (outcome) {
        .failed => |failed| blk: {
            if (failed.cancellation) |reason| if (reason == .text and !std.unicode.utf8ValidateSlice(reason.text)) return error.InvalidUtf8;
            break :blk failed.cleanup_failures;
        },
        .cancelled => |cancelled| blk: {
            if (cancelled.reason == .text and !std.unicode.utf8ValidateSlice(cancelled.reason.text)) return error.InvalidUtf8;
            break :blk cancelled.cleanup_failures;
        },
        else => return,
    };
    var reader: wire.Reader = .{ .input = failures };
    const count = try reader.count();
    if (count > failures.len - reader.position) return error.Truncated;
    for (0..count) |_| _ = try reader.bytes();
    try reader.finish();
}

pub fn requestIdentity(request: Request) [32]u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("boundary.effect-request/v2");
    wire.hashField(&hash, &request.program_identity);
    wire.hashField(&hash, &request.pending_state_digest);
    wire.hashField(&hash, &request.residual_contract_digest);
    wire.hashField(&hash, &request.continuation_binding_digest);
    wire.hashField(&hash, request.semantic_identity);
    wire.hashField(&hash, request.payload_schema);
    wire.hashField(&hash, request.resume_schema);
    wire.hashField(&hash, request.payload);
    return hash.finalResult();
}

pub fn contractIdentity(name: []const u8, payload_schema: []const u8, resume_schema: []const u8) [32]u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("boundary.residual-contract/v2");
    wire.hashField(&hash, name);
    wire.hashField(&hash, payload_schema);
    wire.hashField(&hash, resume_schema);
    return hash.finalResult();
}

pub fn continuationIdentity(program: [32]u8, state: [32]u8, source_block: u64, resume_schema: [32]u8) [32]u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("boundary.continuation-binding/v2");
    wire.hashField(&hash, &program);
    wire.hashField(&hash, &state);
    var buffer: [10]u8 = undefined;
    var writer: wire.Writer = .{ .output = &buffer };
    writer.natural(source_block) catch unreachable; // Exact u64 varint capacity.
    wire.hashField(&hash, buffer[0..writer.position]);
    wire.hashField(&hash, &resume_schema);
    return hash.finalResult();
}

fn validateRequest(allocator: std.mem.Allocator, request: Request) Error!void {
    if (request.semantic_identity.len == 0 or !std.unicode.utf8ValidateSlice(request.semantic_identity)) return error.InvalidRequest;
    if (!std.mem.eql(u8, &request.residual_contract_digest, &contractIdentity(request.semantic_identity, request.payload_schema, request.resume_schema))) return error.InvalidRequest;
    if (!std.mem.eql(u8, &request.request_identity, &requestIdentity(request))) return error.InvalidRequest;
    var payload = try schema.decode(allocator, request.payload_schema);
    defer payload.deinit();
    var resume_schema = try schema.decode(allocator, request.resume_schema);
    defer resume_schema.deinit();
    try schema.validateValue(allocator, payload.descriptor, request.payload);
}

/// Binding validation precedes the caller's program-relative resume-value check.
pub fn validateResult(allocator: std.mem.Allocator, request: Request, result: Result) Error!void {
    try validateRequest(allocator, request);
    if (!std.mem.eql(u8, &result.request_identity, &request.request_identity) or
        !std.mem.eql(u8, &result.resume_schema_digest, &wire.digest(request.resume_schema))) return error.InvalidResult;
    var resumed = try schema.decode(allocator, request.resume_schema);
    defer resumed.deinit();
    try schema.validateValue(allocator, resumed.descriptor, result.value);
}

test "requests bind every field and results bind the parked request" {
    var payload_buffer: [64]u8 = undefined;
    var resume_buffer: [64]u8 = undefined;
    const payload_schema = try schema.encode(std.testing.allocator, &.{.u64}, 0, &payload_buffer);
    const resume_schema = try schema.encode(std.testing.allocator, &.{.boolean}, 0, &resume_buffer);
    var request: Request = .{
        .program_identity = .{1} ** 32,
        .pending_state_digest = .{2} ** 32,
        .residual_contract_digest = contractIdentity("example", payload_schema, resume_schema),
        .continuation_binding_digest = .{3} ** 32,
        .semantic_identity = "example",
        .payload_schema = payload_schema,
        .resume_schema = resume_schema,
        .payload = &.{ 0, 0, 0, 0, 0, 0, 0, 0 },
        .request_identity = undefined,
    };
    request.request_identity = requestIdentity(request);
    var output: [512]u8 = undefined;
    const bytes = try encode(Request, std.testing.allocator, request, &output);
    const decoded = try decode(Request, std.testing.allocator, bytes);
    var result: Result = .{ .request_identity = decoded.request_identity, .resume_schema_digest = wire.digest(decoded.resume_schema), .value = &.{1} };
    try validateResult(std.testing.allocator, decoded, result);
    result.request_identity[0] ^= 1;
    try std.testing.expectError(error.InvalidResult, validateResult(std.testing.allocator, decoded, result));
    request.pending_state_digest[0] ^= 1;
    try std.testing.expectError(error.InvalidRequest, encode(Request, std.testing.allocator, request, &output));
}

test "cancel requires saved State and never accepts an initial result" {
    var buffer: [256]u8 = undefined;
    const input: Input = .{ .mode = .run, .image = &.{}, .instance = .{ .initial_args = &.{} }, .control = .{ .cancel = .{ .text = "stop" } } };
    try std.testing.expectError(error.InvalidControl, encode(Input, std.testing.allocator, input, &buffer));
}

test "protocol encoder rejects nested overlapping bytes without mutation" {
    var buffer = [_]u8{0xa5} ** 256;
    const input: Input = .{ .mode = .run, .image = buffer[20..30], .instance = .{ .initial_args = &.{} }, .control = .{ .continue_value = null } };
    try std.testing.expectError(error.InvalidBuffers, encode(Input, std.testing.allocator, input, &buffer));
    for (buffer) |byte| try std.testing.expectEqual(@as(u8, 0xa5), byte);
}
