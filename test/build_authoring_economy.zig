const std = @import("std");
pub fn build(b: *std.Build) void {
    const root = b.option([]const u8, "source", "Exact Boundary source root") orelse @panic("source");
    const data = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ root, "src/v2/data/root.zig" }) },
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    const boundary = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ root, "src/v2/root.zig" }) },
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .imports = &.{.{ .name = "boundary_data", .module = data }},
    });
    const reference = b.addExecutable(.{ .name = "twice-reference", .root_module = b.createModule(.{
        .root_source_file = b.path("authoring_twice_reference.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    b.step("reference", "Build the independent frozen twice source")
        .dependOn(&b.addInstallArtifact(reference, .{}).step);
    const workload = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ root, "examples/one_effect.zig" }) },
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    });
    const emitter = b.addExecutable(.{ .name = "one-effect", .root_module = workload });
    b.step("emitter", "Build the ordinary emitter").dependOn(&b.addInstallArtifact(emitter, .{}).step);
    const probe = b.addExecutable(.{ .name = "authoring-economy", .root_module = b.createModule(.{
        .root_source_file = b.path("authoring_economy.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .imports = &.{ .{ .name = "boundary", .module = boundary }, .{ .name = "workload", .module = workload } },
    }) });
    b.step("measure", "Build the author/lower/encode timing probe")
        .dependOn(&b.addInstallArtifact(probe, .{}).step);
}
