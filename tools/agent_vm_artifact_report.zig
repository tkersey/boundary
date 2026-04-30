const ability_agent_vm = @import("ability_agent_vm");
const std = @import("std");
const tool_build_options = @import("tool_build_options");

const usage_text =
    "usage: agent-vm-artifact-report --artifact <path>\n" ++
    "       agent-vm-artifact-report --version\n" ++
    "\n" ++
    "Runs one ArtifactV1 payload under the fixed no-host conformance profile.\n" ++
    "\n" ++
    "flags:\n" ++
    "  --artifact <path>  classify one ArtifactV1 payload\n" ++
    "  --version          print the tool version\n" ++
    "  --help, -h         print this help\n";

/// Maximum ArtifactV1 payload size accepted by the fixed conformance profile.
pub const max_artifact_bytes = 16 * 1024 * 1024;

const report_options: ability_agent_vm.runtime.RunOptions = .{
    .max_artifact_bytes = max_artifact_bytes,
    .max_host_calls = 0,
    .max_log_entries = 0,
    .max_log_bytes = 0,
    .data_value_bounds = .{
        .max_depth = 64,
        .max_nodes = 4096,
        .max_bytes = 1 << 20,
    },
};

/// Top-level classification for an ArtifactV1 payload under the fixed profile.
pub const VerdictStatus = enum {
    compatible,
    incompatible,
    invalid,
    unsupported,
};

/// Human-readable report verdict returned by the conformance classifier.
pub const Verdict = struct {
    status: VerdictStatus,
    code: []const u8,
    detail: []const u8,

    fn success(self: @This()) bool {
        return self.status == .compatible;
    }
};

/// Result of reading an artifact path for the report classifier.
pub const ArtifactReadResult = union(enum) {
    bytes: []u8,
    verdict: Verdict,
};

/// Parsed command-line form for the report tool.
pub const ParseArgsResult = union(enum) {
    artifact_path: []const u8,
    help,
    invalid: []const u8,
    unknown_arg: []const u8,
    version,
};

fn writeEscapedDiagnosticValue(writer: anytype, value: []const u8) !void {
    try writer.writeByte('\'');
    for (value) |byte| switch (byte) {
        '\'' => try writer.writeAll("\\'"),
        '\\' => try writer.writeAll("\\\\"),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        0...8, 11, 12, 14...31, 127 => try writer.print("\\x{x:0>2}", .{byte}),
        else => try writer.writeByte(byte),
    };
    try writer.writeByte('\'');
}

/// Parse the report tool's fixed `--artifact <path>` CLI contract.
pub fn parseArgs(args: []const []const u8) ParseArgsResult {
    if (args.len == 0) return .{ .invalid = "missing required --artifact <path>" };
    if (args.len == 2 and (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h"))) return .help;
    if (args.len == 2 and std.mem.eql(u8, args[1], "--version")) return .version;
    if (args.len == 1) return .{ .invalid = "missing required --artifact <path>" };
    if (!std.mem.eql(u8, args[1], "--artifact")) return .{ .unknown_arg = args[1] };
    if (args.len < 3 or std.mem.startsWith(u8, args[2], "--")) return .{ .invalid = "missing required --artifact <path>" };
    if (args.len > 3) return .{ .invalid = "unexpected argument after --artifact <path>" };
    return .{ .artifact_path = args[2] };
}

fn noHostAdapter() ability_agent_vm.host.Adapter {
    return .{
        .ctx = null,
        .dispatchFn = struct {
            fn dispatch(
                _: ?*anyopaque,
                _: std.mem.Allocator,
                _: *const ability_agent_vm.host.Request,
            ) anyerror!ability_agent_vm.host.Response {
                return error.UnsupportedHostCall;
            }
        }.dispatch,
    };
}

fn artifactSizeExceededVerdict() Verdict {
    return .{
        .status = .incompatible,
        .code = "resource_exhausted",
        .detail = "artifact size exceeds fixed conformance profile limit max_artifact_bytes=16777216",
    };
}

/// Read one ArtifactV1 payload unless its file size already exceeds the fixed profile.
pub fn readArtifactForReport(
    io: std.Io,
    allocator: std.mem.Allocator,
    path: []const u8,
) anyerror!ArtifactReadResult {
    const stat = try std.Io.Dir.cwd().statFile(io, path, .{});
    if (stat.size > max_artifact_bytes) return .{ .verdict = artifactSizeExceededVerdict() };

    const bytes = std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        allocator,
        .limited(max_artifact_bytes + 1),
    ) catch |err| switch (err) {
        error.StreamTooLong => return .{ .verdict = artifactSizeExceededVerdict() },
        else => return err,
    };
    return .{ .bytes = bytes };
}

/// Classify one ArtifactV1 byte stream under the fixed no-host profile.
pub fn fixedProfileVerdict(allocator: std.mem.Allocator, bytes: []const u8) anyerror!Verdict {
    var result = ability_agent_vm.runtime.runArtifactWithOptions(
        allocator,
        bytes,
        noHostAdapter(),
        report_options,
    ) catch |err| switch (err) {
        error.DataValueTooDeep, error.DataValueTooManyNodes, error.DataValueTooManyBytes => return .{
            .status = .incompatible,
            .code = "data_value_bounds",
            .detail = dataValueBoundsDetail(err),
        },
        else => return err,
    };
    defer result.deinit(allocator);

    return switch (result) {
        .completed => |completed| blk: {
            if (completed.logs.len != 0) break :blk .{
                .status = .unsupported,
                .code = "host_log",
                .detail = "artifact produced host interaction logs",
            };
            break :blk .{
                .status = .compatible,
                .code = "ok",
                .detail = "artifact completed without host calls or user artifacts",
            };
        },
        .failed => |failure| classifyFailure(failure.failure),
        .rejected => |failure| classifyRejected(failure.failure),
    };
}

fn classifyFailure(failure: ability_agent_vm.host.Failure) Verdict {
    if (std.mem.eql(u8, failure.code, "resource_exhausted") and
        std.mem.eql(u8, failure.message, "artifact host-call budget exceeded"))
    {
        return .{
            .status = .unsupported,
            .code = "host_call",
            .detail = "artifact requires host calls and is outside no-host conformance",
        };
    }
    if (std.mem.eql(u8, failure.code, "resource_exhausted")) {
        return .{
            .status = .incompatible,
            .code = "resource_exhausted",
            .detail = stableFailureDetail(failure.message),
        };
    }
    return .{
        .status = .incompatible,
        .code = "runtime_failure",
        .detail = stableFailureDetail(failure.message),
    };
}

fn classifyRejected(failure: ability_agent_vm.host.Failure) Verdict {
    if (std.mem.eql(u8, failure.code, "invalid_artifact")) {
        return .{
            .status = .invalid,
            .code = "invalid_artifact",
            .detail = stableArtifactDecoderDetail(failure.message),
        };
    }
    return .{
        .status = .incompatible,
        .code = "runtime_rejected",
        .detail = stableFailureDetail(failure.message),
    };
}

fn stableArtifactDecoderDetail(message: []const u8) []const u8 {
    if (std.mem.eql(u8, message, "EndOfStream")) return "EndOfStream";
    if (std.mem.eql(u8, message, "ArtifactTooLarge")) return "ArtifactTooLarge";
    if (std.mem.eql(u8, message, "BadMagic")) return "BadMagic";
    if (std.mem.eql(u8, message, "BuildFingerprintMismatch")) return "BuildFingerprintMismatch";
    if (std.mem.eql(u8, message, "DuplicateCapabilityId")) return "DuplicateCapabilityId";
    if (std.mem.eql(u8, message, "DuplicateCapabilityOpId")) return "DuplicateCapabilityOpId";
    if (std.mem.eql(u8, message, "DuplicateDirectorySection")) return "DuplicateDirectorySection";
    if (std.mem.eql(u8, message, "InvalidToolId")) return "InvalidToolId";
    if (std.mem.eql(u8, message, "InvalidBuildFingerprint")) return "InvalidBuildFingerprint";
    if (std.mem.eql(u8, message, "InvalidDirectoryBounds")) return "InvalidDirectoryBounds";
    if (std.mem.eql(u8, message, "InvalidEntryFunctionIndex")) return "InvalidEntryFunctionIndex";
    if (std.mem.eql(u8, message, "InvalidProgramPlan")) return "InvalidProgramPlan";
    if (std.mem.eql(u8, message, "InvalidHashKind")) return "InvalidHashKind";
    if (std.mem.eql(u8, message, "InvalidRequiredSection")) return "InvalidRequiredSection";
    if (std.mem.eql(u8, message, "NonZeroReserved")) return "NonZeroReserved";
    if (std.mem.eql(u8, message, "StringRefOutOfBounds")) return "StringRefOutOfBounds";
    if (std.mem.eql(u8, message, "UnsortedDirectorySection")) return "UnsortedDirectorySection";
    if (std.mem.eql(u8, message, "UnsupportedEntryParameters")) return "UnsupportedEntryParameters";
    if (std.mem.eql(u8, message, "UnsupportedVersion")) return "UnsupportedVersion";
    if (std.mem.eql(u8, message, "ArtifactHashMismatch")) return "ArtifactHashMismatch";
    if (std.mem.eql(u8, message, "UnsupportedExecutableCodec")) return "UnsupportedExecutableCodec";
    if (std.mem.eql(u8, message, "UnsupportedExecInstruction")) return "UnsupportedExecInstruction";
    return "ArtifactV1 decoder rejected artifact with an unclassified error";
}

fn stableFailureDetail(message: []const u8) []const u8 {
    if (std.mem.eql(u8, message, "artifact completed value payload budget exceeded")) return "artifact completed value payload budget exceeded";
    if (std.mem.eql(u8, message, "artifact block budget exceeded")) return "artifact block budget exceeded";
    if (std.mem.eql(u8, message, "artifact instruction budget exceeded")) return "artifact instruction budget exceeded";
    if (std.mem.eql(u8, message, "artifact call-depth budget exceeded")) return "artifact call-depth budget exceeded";
    if (std.mem.eql(u8, message, "artifact after-frame budget exceeded")) return "artifact after-frame budget exceeded";
    if (std.mem.eql(u8, message, "artifact host-log budget exceeded")) return "artifact host-log budget exceeded";
    if (std.mem.eql(u8, message, "artifact host-log byte budget exceeded")) return "artifact host-log byte budget exceeded";
    if (std.mem.eql(u8, message, "artifact host-log payload budget exceeded")) return "artifact host-log payload budget exceeded";
    if (std.mem.eql(u8, message, "artifact host-request payload budget exceeded")) return "artifact host-request payload budget exceeded";
    if (std.mem.eql(u8, message, "artifact output snapshot payload budget exceeded")) return "artifact output snapshot payload budget exceeded";
    if (std.mem.eql(u8, message, "host reply schema_version must be 1")) return "host reply schema_version must be 1";
    if (std.mem.eql(u8, message, "host reply request_id must echo the request")) return "host reply request_id must echo the request";
    if (std.mem.eql(u8, message, "host reply tool_id must echo the request")) return "host reply tool_id must echo the request";
    if (std.mem.eql(u8, message, "host reply call_id must echo the request")) return "host reply call_id must echo the request";
    if (std.mem.eql(u8, message, "host reply control is incompatible with the op mode")) return "host reply control is incompatible with the op mode";
    if (std.mem.eql(u8, message, "host reply value does not match the declared codec")) return "host reply value does not match the declared codec";
    if (std.mem.eql(u8, message, "host output snapshot count must match the declared outputs")) return "host output snapshot count must match the declared outputs";
    if (std.mem.eql(u8, message, "host output snapshot labels must match the declared outputs")) return "host output snapshot labels must match the declared outputs";
    if (std.mem.eql(u8, message, "host output snapshot value does not match the declared codec")) return "host output snapshot value does not match the declared codec";
    return "runtime failed under the fixed conformance profile with an unclassified error";
}

fn dataValueBoundsDetail(err: anyerror) []const u8 {
    return switch (err) {
        error.DataValueTooDeep => "DataValue exceeds fixed conformance profile max_depth=64",
        error.DataValueTooManyNodes => "DataValue exceeds fixed conformance profile max_nodes=4096",
        error.DataValueTooManyBytes => "DataValue exceeds fixed conformance profile max_bytes=1048576",
        else => @errorName(err),
    };
}

fn writeVerdict(writer: anytype, verdict: Verdict) !void {
    try writer.print(
        "agent-vm-artifact-report verdict={s} code={s} detail=\"{s}\"\n",
        .{ @tagName(verdict.status), verdict.code, verdict.detail },
    );
}

/// Report CLI entry point.
pub fn main(init: std.process.Init) anyerror!void {
    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    switch (parseArgs(args)) {
        .help => {
            var stdout_buffer: [512]u8 = undefined;
            var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
            try stdout_writer.interface.writeAll(usage_text);
            try stdout_writer.interface.flush();
            return;
        },
        .version => {
            var stdout_buffer: [64]u8 = undefined;
            var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
            try stdout_writer.interface.print("agent-vm-artifact-report {s}\n", .{tool_build_options.version});
            try stdout_writer.interface.flush();
            return;
        },
        .invalid => |message| {
            std.debug.print("agent-vm-artifact-report: {s}\n{s}", .{ message, usage_text });
            std.process.exit(2);
        },
        .unknown_arg => |arg| {
            var stderr_buffer: [512]u8 = undefined;
            var stderr_writer = std.Io.File.stderr().writerStreaming(init.io, &stderr_buffer);
            const stderr = &stderr_writer.interface;
            try stderr.writeAll("agent-vm-artifact-report: unknown argument ");
            try writeEscapedDiagnosticValue(stderr, arg);
            try stderr.writeAll("; expected --artifact <path>\n");
            try stderr.writeAll(usage_text);
            try stderr.flush();
            std.process.exit(2);
        },
        .artifact_path => |path| {
            const read_result = readArtifactForReport(init.io, allocator, path) catch |err| {
                var stderr_buffer: [512]u8 = undefined;
                var stderr_writer = std.Io.File.stderr().writerStreaming(init.io, &stderr_buffer);
                const stderr = &stderr_writer.interface;
                try stderr.writeAll("agent-vm-artifact-report: artifact file could not be read: ");
                try writeEscapedDiagnosticValue(stderr, path);
                try stderr.print(" ({s}). Pass an existing ArtifactV1 file with --artifact <path>, or use `zig build run-agent-vm-artifact-report -Dagent-vm-artifact=<path>`.\n", .{@errorName(err)});
                try stderr.flush();
                std.process.exit(2);
            };

            const verdict = switch (read_result) {
                .bytes => |bytes| blk: {
                    defer allocator.free(bytes);
                    break :blk try fixedProfileVerdict(allocator, bytes);
                },
                .verdict => |verdict| verdict,
            };
            var stdout_buffer: [512]u8 = undefined;
            var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
            try writeVerdict(&stdout_writer.interface, verdict);
            try stdout_writer.interface.flush();
            if (!verdict.success()) std.process.exit(1);
        },
    }
}

test "diagnostic values escape control characters" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    try writeEscapedDiagnosticValue(&output.writer, "bad\npath\x1b[31m");
    const bytes = try output.toOwnedSlice();
    defer std.testing.allocator.free(bytes);

    try std.testing.expectEqualStrings("'bad\\npath\\x1b[31m'", bytes);
}

test "ArtifactV1 decoder detail preserves invalid required section failures" {
    try std.testing.expectEqualStrings(
        "InvalidRequiredSection",
        stableArtifactDecoderDetail("InvalidRequiredSection"),
    );
}
