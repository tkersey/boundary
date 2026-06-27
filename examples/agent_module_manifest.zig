// zlinter-disable declaration_naming require_doc_comment no_hidden_allocations no_inferred_error_unions
const boundary = @import("boundary");
const fixture = @import("world_surface_ports.zig");
const std = @import("std");

const Agent = boundary.Agent;
const Target = fixture.Target;
const Tools = Agent.ClosedToolSet(&.{"approval_request"});
const tool_ids = [_]Agent.ToolId{Tools.id(0)};

const config = Agent.Config{
    .max_iterations = 3,
    .max_model_calls = 3,
    .max_tool_calls = 2,
    .max_observation_bytes = 512,
    .max_action_bytes = 256,
    .max_tool_result_bytes = 512,
    .max_trace_entries = 6,
};

fn profile() Agent.Profile {
    return Agent.Profile.fromConfig(config, &tool_ids, &.{Target.WorldSurface.surface_fingerprint}, "agent-module-manifest");
}

fn boundaryValueRefFingerprint(ref: anytype) u64 {
    var hasher = std.hash.Wyhash.init(0x4147454e545f5256);
    hasher.update(ref.codec);
    if (ref.schema_index) |index| {
        var buffer: [@sizeOf(u16)]u8 = undefined;
        std.mem.writeInt(u16, &buffer, index, .little);
        hasher.update(&buffer);
    } else {
        const sentinel = [_]u8{ 0xff, 0xff };
        hasher.update(&sentinel);
    }
    return hasher.final();
}

fn moduleArtifact(bytes: []const u8, loaded: anytype) Agent.ModuleArtifact {
    return Agent.ModuleArtifact.init(.{
        .role = .toolbox,
        .profile = profile(),
        .module_fingerprint = loaded.moduleFingerprint(),
        .manifest_fingerprint = loaded.manifest().manifest_fingerprint,
        .world_surface_fingerprint = loaded.worldSurfaceFingerprint(),
        .import_count = loaded.imports().len,
        .export_result_fingerprint = boundaryValueRefFingerprint(loaded.exportMain().result_ref),
        .bytes = bytes,
    });
}

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    const bytes = try Target.Module.fullImage(allocator);
    defer allocator.free(bytes);
    var loaded = try Target.Module.decode(allocator, bytes);
    defer loaded.deinit();

    const artifact = moduleArtifact(bytes, loaded);
    try artifact.validate(profile(), .toolbox);

    try writer.print("agent_profile_fingerprint={x}\n", .{artifact.profile_fingerprint});
    try writer.print("agent_module_role={s}\n", .{@tagName(artifact.role)});
    try writer.print("module_fingerprint={x}\n", .{artifact.module_fingerprint});
    try writer.print("module_byte_fingerprint={x}\n", .{artifact.byte_fingerprint});
    try writer.print("module_byte_len={d}\n", .{artifact.byte_len});
    try writer.print("module_import_count={d}\n", .{artifact.import_count});
}

test "Agent module manifest binds real full module bytes to profile provenance" {
    const allocator = std.testing.allocator;
    const bytes = try Target.Module.fullImage(allocator);
    defer allocator.free(bytes);
    var loaded = try Target.Module.decode(allocator, bytes);
    defer loaded.deinit();

    const artifact = moduleArtifact(bytes, loaded);
    try artifact.validate(profile(), .toolbox);
    try std.testing.expectEqual(Agent.fingerprintBytes(bytes), artifact.byte_fingerprint);
    try std.testing.expect(artifact.import_count > 0);
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
