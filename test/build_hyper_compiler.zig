const std = @import("std");
pub fn build(b: *std.Build) void {
    const root = b.option([]const u8, "source", "Exact Boundary source root") orelse @panic("source");
    const data = b.createModule(.{ .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ root, "src/v2/data/root.zig" }) }, .target = b.graph.host, .optimize = .ReleaseSafe });
    const boundary = b.createModule(.{ .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ root, "src/v2/root.zig" }) }, .target = b.graph.host, .optimize = .ReleaseSafe, .imports = &.{.{ .name = "boundary_data", .module = data }} });
    const work = b.createModule(.{ .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ root, "examples/hyper_fold.zig" }) }, .target = b.graph.host, .optimize = .ReleaseSafe, .imports = &.{.{ .name = "boundary", .module = boundary }} });
    const allocation = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("hyper_allocation.zig"), .target = b.graph.host, .optimize = .ReleaseSafe, .imports = &.{ .{ .name = "boundary", .module = boundary }, .{ .name = "workload", .module = work } } }) });
    b.step("allocation", "Sweep actual hyperfunction construction allocations").dependOn(&b.addRunArtifact(allocation).step);
    const profile = b.createModule(.{ .root_source_file = b.path("hyper_compile_bench.zig"), .target = b.graph.host, .optimize = .ReleaseSafe, .imports = &.{ .{ .name = "boundary", .module = boundary }, .{ .name = "workload", .module = work } } });
    const profiled = b.addExecutable(.{ .name = "hyper-compile-bench", .root_module = profile });
    b.step("profile", "Build stage-observed compiler").dependOn(&b.addInstallArtifact(profiled, .{}).step);
    const emitter = b.addExecutable(.{ .name = "hyper-fold", .root_module = work });
    b.step("emitter", "Build the uninstrumented native emitter").dependOn(&b.addInstallArtifact(emitter, .{}).step);
    const adaptive = b.addExecutable(.{ .name = "hyper-adaptive", .root_module = b.createModule(.{ .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ root, "examples/hyper_adaptive.zig" }) }, .target = b.graph.host, .optimize = .ReleaseSafe, .imports = &.{.{ .name = "boundary", .module = boundary }} }) });
    b.step("components", "Build the existing participant emitter").dependOn(&b.addInstallArtifact(adaptive, .{}).step);
    const linker = b.addExecutable(.{ .name = "boundary-link", .root_module = b.createModule(.{ .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ root, "tools/component_link.zig" }) }, .target = b.graph.host, .optimize = .ReleaseSafe, .imports = &.{.{ .name = "boundary_data", .module = data }} }) });
    b.step("linker", "Build the existing source-free linker").dependOn(&b.addInstallArtifact(linker, .{}).step);
}
