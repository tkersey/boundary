const std = @import("std");
pub fn build(b: *std.Build) void {
    // Zig 0.17 can reuse a sibling --build-file configuration in a shared cache.
    // These standalone helpers share a directory; keep compiled-artifact caching
    // but recompute their configuration so the selected file remains authoritative.
    b.graph.poisonCache();
    const root = b.option(std.Build.LazyPath, "source", "Exact Boundary source root") orelse @panic("source");
    const data = b.createModule(.{ .root_source_file = root.path(b, "src/data/root.zig"), .target = b.graph.host, .optimize = .safe });
    const boundary = b.createModule(.{ .root_source_file = root.path(b, "src/root.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{.{ .name = "boundary_data", .module = data }} });
    const work = b.createModule(.{ .root_source_file = root.path(b, "examples/hyper_fold.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{.{ .name = "boundary", .module = boundary }} });
    const allocation = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("hyper_allocation.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{ .{ .name = "boundary", .module = boundary }, .{ .name = "workload", .module = work } } }) });
    b.step("allocation", "Sweep actual hyperfunction construction allocations").dependOn(&b.addRunArtifact(allocation).step);
    const profile = b.createModule(.{ .root_source_file = b.path("hyper_compile_bench.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{ .{ .name = "boundary", .module = boundary }, .{ .name = "workload", .module = work } } });
    const profiled = b.addExecutable(.{ .name = "hyper-compile-bench", .root_module = profile });
    b.step("profile", "Build stage-observed compiler").dependOn(&b.addInstallArtifact(profiled, .{}).step);
    const emitter = b.addExecutable(.{ .name = "hyper-fold", .root_module = work });
    b.step("emitter", "Build the uninstrumented native emitter").dependOn(&b.addInstallArtifact(emitter, .{}).step);
    const adaptive = b.addExecutable(.{ .name = "hyper-adaptive", .root_module = b.createModule(.{ .root_source_file = root.path(b, "examples/hyper_adaptive.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{.{ .name = "boundary", .module = boundary }} }) });
    b.step("components", "Build the existing participant emitter").dependOn(&b.addInstallArtifact(adaptive, .{}).step);
    const linker = b.addExecutable(.{ .name = "boundary-link", .root_module = b.createModule(.{ .root_source_file = root.path(b, "tools/component_link.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{.{ .name = "boundary_data", .module = data }} }) });
    b.step("linker", "Build the existing source-free linker").dependOn(&b.addInstallArtifact(linker, .{}).step);
}
