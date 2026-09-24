const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const boundary = b.dependency("boundary", .{ .target = target, .optimize = optimize });
    const imports: []const std.Build.Module.Import = &.{
        .{ .name = "boundary", .module = boundary.module("boundary") },
    };
    const client = b.addExecutable(.{ .name = "public-authoring-client", .root_module = b.createModule(.{ .root_source_file = b.path("main.zig"), .target = target, .optimize = optimize, .imports = imports }) });
    b.step("emit", "Compile the public-package client to BPI3")
        .dependOn(&b.addRunArtifact(client).step);
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = imports,
    }) });
    b.step("test", "Check public-client rejection siblings")
        .dependOn(&b.addRunArtifact(tests).step);
}
