const ability_agent_vm = @import("ability_agent_vm");
const std = @import("std");

const usage_text =
    "usage: agent-vm-artifact-report --artifact <path>\n" ++
    "\n" ++
    "Runs one ArtifactV1 payload under the fixed no-host conformance profile.\n";

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
};

/// Parse the report tool's fixed `--artifact <path>` CLI contract.
pub fn parseArgs(args: []const []const u8) ParseArgsResult {
    if (args.len == 2 and (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h"))) return .help;
    if (args.len != 3) return .{ .invalid = "missing required --artifact <path>" };
    if (!std.mem.eql(u8, args[1], "--artifact")) return .{ .invalid = "expected --artifact <path>" };
    if (std.mem.startsWith(u8, args[2], "--")) return .{ .invalid = "missing required --artifact <path>" };
    return .{ .artifact_path = args[2] };
}

fn noHostAdapter() ability_agent_vm.host.Adapter {
    return .{
        .ctx = null,
        .dispatchFn = struct {
            fn dispatch(
                _: ?*anyopaque,
                _: std.mem.Allocator,
                _: ability_agent_vm.host.Request,
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
        .detail = "artifact exceeded the fixed conformance profile",
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
            .detail = @errorName(err),
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
            .detail = "artifact exceeded the fixed conformance profile",
        };
    }
    return .{
        .status = .incompatible,
        .code = "runtime_failure",
        .detail = "artifact failed under the fixed conformance profile",
    };
}

fn classifyRejected(failure: ability_agent_vm.host.Failure) Verdict {
    if (std.mem.eql(u8, failure.code, "invalid_artifact")) {
        return .{
            .status = .invalid,
            .code = "invalid_artifact",
            .detail = "artifact rejected by ArtifactV1 decoder",
        };
    }
    return .{
        .status = .incompatible,
        .code = "runtime_rejected",
        .detail = "artifact was rejected under the fixed conformance profile",
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
        .invalid => |message| {
            std.debug.print("agent-vm-artifact-report: {s}\n{s}", .{ message, usage_text });
            std.process.exit(2);
        },
        .artifact_path => |path| {
            const read_result = readArtifactForReport(init.io, allocator, path) catch |err| {
                std.debug.print("agent-vm-artifact-report: unable to read artifact: {s}\n", .{@errorName(err)});
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
