const ability_agent_vm = @import("ability_agent_vm");
const std = @import("std");
const tool_build_options = @import("tool_build_options");

const usage_text =
    "usage: agent-vm-artifact-report [--json] --artifact <path>\n" ++
    "       agent-vm-artifact-report [--format text|json] --artifact <path>\n" ++
    "       agent-vm-artifact-report --version\n" ++
    "\n" ++
    "Runs one ArtifactV1 payload under the fixed no-host conformance profile.\n" ++
    "\n" ++
    "flags:\n" ++
    "  --artifact <path>  classify one ArtifactV1 payload\n" ++
    "  --format <mode>    output mode: text or json\n" ++
    "  --json             emit a machine-readable JSON verdict\n" ++
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

/// Output mode for the report tool verdict.
pub const OutputFormat = enum {
    json,
    text,
};

/// Result of reading an artifact path for the report classifier.
pub const ArtifactReadResult = union(enum) {
    bytes: []u8,
    verdict: Verdict,
};

/// Parsed report request.
pub const ArtifactRequest = struct {
    path: []const u8,
    format: OutputFormat = .text,
};

const OutputFormatFlag = enum {
    format,
    json,
};

/// Parsed command-line form for the report tool.
pub const ParseArgsResult = union(enum) {
    artifact: ArtifactRequest,
    help,
    invalid: []const u8,
    unexpected_arg: []const u8,
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

    var request: ArtifactRequest = .{ .path = "" };
    var saw_artifact = false;
    var output_format_flag: ?OutputFormatFlag = null;
    var index: usize = 1;
    while (index < args.len) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--artifact")) {
            if (saw_artifact) return .{ .invalid = "duplicate --artifact flag" };
            if (index + 1 >= args.len or isKnownFlag(args[index + 1])) {
                return .{ .invalid = "missing required --artifact <path>" };
            }
            saw_artifact = true;
            request.path = args[index + 1];
            index += 2;
            continue;
        }
        if (std.mem.eql(u8, arg, "--json")) {
            if (output_format_flag) |flag| {
                return .{ .invalid = switch (flag) {
                    .json => "duplicate --json flag",
                    .format => "choose either --json or --format <text|json>, not both",
                } };
            }
            output_format_flag = .json;
            request.format = .json;
            index += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--format")) {
            if (output_format_flag) |flag| {
                return .{ .invalid = switch (flag) {
                    .format => "duplicate --format flag",
                    .json => "choose either --json or --format <text|json>, not both",
                } };
            }
            if (index + 1 >= args.len or std.mem.startsWith(u8, args[index + 1], "--")) {
                return .{ .invalid = "missing required --format <text|json>" };
            }
            const value = args[index + 1];
            request.format = if (std.mem.eql(u8, value, "text"))
                .text
            else if (std.mem.eql(u8, value, "json"))
                .json
            else
                return .{ .invalid = "unsupported --format value; expected text or json" };
            output_format_flag = .format;
            index += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--")) return .{ .unknown_arg = arg };
        return .{ .unexpected_arg = arg };
    }

    if (!saw_artifact) return .{ .invalid = "missing required --artifact <path>" };
    return .{ .artifact = request };
}

fn isKnownFlag(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "--artifact") or
        std.mem.eql(u8, arg, "--format") or
        std.mem.eql(u8, arg, "--json") or
        std.mem.eql(u8, arg, "--help") or
        std.mem.eql(u8, arg, "-h") or
        std.mem.eql(u8, arg, "--version");
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

/// Convert one artifact file-read failure into the stable JSON verdict shape.
pub fn artifactReadFailureVerdict(err: anyerror) Verdict {
    return .{
        .status = .invalid,
        .code = "artifact_read_failed",
        .detail = switch (err) {
            error.FileNotFound => "artifact file could not be read (FileNotFound): pass an existing ArtifactV1 file with --artifact <path>",
            error.AccessDenied => "artifact file could not be read (AccessDenied): pass a readable ArtifactV1 file with --artifact <path>",
            error.IsDir => "artifact file could not be read (IsDir): pass a file path, not a directory, with --artifact <path>",
            else => "artifact file could not be read: pass an existing readable ArtifactV1 file with --artifact <path>",
        },
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
    if (std.mem.eql(u8, message, "EndOfStream")) return "invalid artifact (EndOfStream): artifact ended before all required ArtifactV1 bytes were read; regenerate the artifact from this checkout";
    if (std.mem.eql(u8, message, "ArtifactTooLarge")) return "invalid artifact (ArtifactTooLarge): artifact exceeds the fixed conformance profile; regenerate or inspect it with a larger explicit profile";
    if (std.mem.eql(u8, message, "BadMagic")) return "invalid artifact (BadMagic): file is not an Ability ArtifactV1 payload or is corrupted; pass an artifact generated by this checkout";
    if (std.mem.eql(u8, message, "BuildFingerprintMismatch")) return "invalid artifact (BuildFingerprintMismatch): artifact was generated from different source or build metadata; regenerate it from this checkout";
    if (std.mem.eql(u8, message, "DuplicateCapabilityId")) return "invalid artifact (DuplicateCapabilityId): capability manifest repeats an id; regenerate the artifact with the current encoder";
    if (std.mem.eql(u8, message, "DuplicateCapabilityOpId")) return "invalid artifact (DuplicateCapabilityOpId): capability manifest repeats an op id; regenerate the artifact with the current encoder";
    if (std.mem.eql(u8, message, "DuplicateDirectorySection")) return "invalid artifact (DuplicateDirectorySection): section directory repeats a section; regenerate the artifact with the current encoder";
    if (std.mem.eql(u8, message, "InvalidToolId")) return "invalid artifact (InvalidToolId): capability manifest contains an unsupported tool id; regenerate the artifact with the current encoder";
    if (std.mem.eql(u8, message, "InvalidBuildFingerprint")) return "invalid artifact (InvalidBuildFingerprint): build fingerprint is malformed; regenerate the artifact with the current encoder";
    if (std.mem.eql(u8, message, "InvalidDirectoryBounds")) return "invalid artifact (InvalidDirectoryBounds): section directory points outside the payload or overlaps; regenerate the artifact";
    if (std.mem.eql(u8, message, "InvalidEntryFunctionIndex")) return "invalid artifact (InvalidEntryFunctionIndex): entry function is outside the decoded program plan; regenerate the artifact";
    if (std.mem.eql(u8, message, "InvalidProgramPlan")) return "invalid artifact (InvalidProgramPlan): embedded ProgramPlan failed validation; regenerate the artifact from supported source";
    if (std.mem.eql(u8, message, "InvalidHashKind")) return "invalid artifact (InvalidHashKind): artifact hash section uses an unsupported hash kind; regenerate the artifact";
    if (std.mem.eql(u8, message, "InvalidRequiredSection")) return "invalid artifact (InvalidRequiredSection): required sections or capability bindings are missing or inconsistent; regenerate the artifact";
    if (std.mem.eql(u8, message, "NonZeroReserved")) return "invalid artifact (NonZeroReserved): reserved header bytes are nonzero; regenerate the artifact";
    if (std.mem.eql(u8, message, "StringRefOutOfBounds")) return "invalid artifact (StringRefOutOfBounds): manifest string reference points outside the string table; regenerate the artifact";
    if (std.mem.eql(u8, message, "UnsortedDirectorySection")) return "invalid artifact (UnsortedDirectorySection): section directory is not canonical; regenerate the artifact with the current encoder";
    if (std.mem.eql(u8, message, "UnsupportedEntryParameters")) return "invalid artifact (UnsupportedEntryParameters): entry function requires parameters outside the report profile";
    if (std.mem.eql(u8, message, "UnsupportedVersion")) return "invalid artifact (UnsupportedVersion): ArtifactV1 version is not supported by this checkout";
    if (std.mem.eql(u8, message, "ArtifactHashMismatch")) return "invalid artifact (ArtifactHashMismatch): payload hash does not match the artifact header; regenerate or recopy the artifact";
    if (std.mem.eql(u8, message, "UnsupportedExecutableCodec")) return "invalid artifact (UnsupportedExecutableCodec): program uses a value codec outside the executable profile";
    if (std.mem.eql(u8, message, "UnsupportedExecInstruction")) return "invalid artifact (UnsupportedExecInstruction): program uses an instruction outside the executable profile";
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

fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |byte| switch (byte) {
        '"' => try writer.writeAll("\\\""),
        '\\' => try writer.writeAll("\\\\"),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        0...7 => try writer.print("\\u00{x:0>2}", .{byte}),
        8 => try writer.writeAll("\\b"),
        11, 12 => try writer.print("\\u00{x:0>2}", .{byte}),
        14...31 => try writer.print("\\u00{x:0>2}", .{byte}),
        else => try writer.writeByte(byte),
    };
    try writer.writeByte('"');
}

fn writeJsonVerdict(writer: anytype, verdict: Verdict) !void {
    try writer.writeAll("{\"schema_version\":1,\"status\":");
    try writeJsonString(writer, @tagName(verdict.status));
    try writer.writeAll(",\"code\":");
    try writeJsonString(writer, verdict.code);
    try writer.writeAll(",\"detail\":");
    try writeJsonString(writer, verdict.detail);
    try writer.writeAll("}\n");
}

fn writeFormattedVerdict(writer: anytype, verdict: Verdict, format: OutputFormat) !void {
    switch (format) {
        .text => try writeVerdict(writer, verdict),
        .json => try writeJsonVerdict(writer, verdict),
    }
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
        .unexpected_arg => |arg| {
            var stderr_buffer: [512]u8 = undefined;
            var stderr_writer = std.Io.File.stderr().writerStreaming(init.io, &stderr_buffer);
            const stderr = &stderr_writer.interface;
            try stderr.writeAll("agent-vm-artifact-report: unexpected argument ");
            try writeEscapedDiagnosticValue(stderr, arg);
            try stderr.writeAll("; run --help for supported flags\n");
            try stderr.writeAll(usage_text);
            try stderr.flush();
            std.process.exit(2);
        },
        .unknown_arg => |arg| {
            var stderr_buffer: [512]u8 = undefined;
            var stderr_writer = std.Io.File.stderr().writerStreaming(init.io, &stderr_buffer);
            const stderr = &stderr_writer.interface;
            try stderr.writeAll("agent-vm-artifact-report: unknown argument ");
            try writeEscapedDiagnosticValue(stderr, arg);
            try stderr.writeAll("; run --help for supported flags\n");
            try stderr.writeAll(usage_text);
            try stderr.flush();
            std.process.exit(2);
        },
        .artifact => |request| {
            const read_result = readArtifactForReport(init.io, allocator, request.path) catch |err| {
                if (request.format == .json) {
                    var stdout_buffer: [512]u8 = undefined;
                    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
                    try writeJsonVerdict(&stdout_writer.interface, artifactReadFailureVerdict(err));
                    try stdout_writer.interface.flush();
                    std.process.exit(2);
                }
                var stderr_buffer: [512]u8 = undefined;
                var stderr_writer = std.Io.File.stderr().writerStreaming(init.io, &stderr_buffer);
                const stderr = &stderr_writer.interface;
                try stderr.writeAll("agent-vm-artifact-report: artifact file could not be read: ");
                try writeEscapedDiagnosticValue(stderr, request.path);
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
            try writeFormattedVerdict(&stdout_writer.interface, verdict, request.format);
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
        "invalid artifact (InvalidRequiredSection): required sections or capability bindings are missing or inconsistent; regenerate the artifact",
        stableArtifactDecoderDetail("InvalidRequiredSection"),
    );
}

test "JSON verdict escapes strings and includes stable fields" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    try writeJsonVerdict(&output.writer, .{
        .status = .invalid,
        .code = "invalid_artifact",
        .detail = "bad \"artifact\"\nregenerate",
    });
    const bytes = try output.toOwnedSlice();
    defer std.testing.allocator.free(bytes);

    try std.testing.expectEqualStrings(
        "{\"schema_version\":1,\"status\":\"invalid\",\"code\":\"invalid_artifact\",\"detail\":\"bad \\\"artifact\\\"\\nregenerate\"}\n",
        bytes,
    );
}
