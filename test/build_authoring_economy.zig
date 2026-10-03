const std = @import("std");
pub fn build(b: *std.Build) void {
    // Zig 0.17 can reuse a sibling --build-file configuration in a shared cache.
    // These standalone helpers share a directory; keep compiled-artifact caching
    // but recompute their configuration so the selected file remains authoritative.
    b.graph.poisonCache();
    const root = b.option(std.Build.LazyPath, "source", "Exact Boundary source root") orelse @panic("source");
    const data = b.createModule(.{
        .root_source_file = root.path(b, "src/data/root.zig"),
        .target = b.graph.host,
        .optimize = .safe,
    });
    const boundary = b.createModule(.{
        .root_source_file = root.path(b, "src/root.zig"),
        .target = b.graph.host,
        .optimize = .safe,
        .imports = &.{.{ .name = "boundary_data", .module = data }},
    });
    const reference = b.addExecutable(.{ .name = "twice-reference", .root_module = b.createModule(.{
        .root_source_file = b.path("authoring_twice_reference.zig"),
        .target = b.graph.host,
        .optimize = .safe,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    b.step("reference", "Build the independent frozen twice source")
        .dependOn(&b.addInstallArtifact(reference, .{}).step);
    const workload = b.createModule(.{
        .root_source_file = root.path(b, b.option([]const u8, "workload", "Application source relative to source root") orelse "examples/one_effect.zig"),
        .target = b.graph.host,
        .optimize = .safe,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    });
    const emitter = b.addExecutable(.{ .name = "one-effect", .root_module = workload });
    b.step("emitter", "Build the ordinary emitter").dependOn(&b.addInstallArtifact(emitter, .{}).step);
    const probe = b.addExecutable(.{ .name = "authoring-economy", .root_module = b.createModule(.{
        .root_source_file = b.path("authoring_economy.zig"),
        .target = b.graph.host,
        .optimize = .safe,
        .imports = &.{ .{ .name = "boundary", .module = boundary }, .{ .name = "workload", .module = workload } },
    }) });
    b.step("measure", "Build the author/lower/encode timing probe")
        .dependOn(&b.addInstallArtifact(probe, .{}).step);
}
