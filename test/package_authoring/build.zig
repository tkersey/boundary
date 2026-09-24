const std = @import("std");
pub fn build(b: *std.Build) void {
    const dependency = b.dependency("boundary", .{ .optimize = .ReleaseSafe });
    const boundary = dependency.module("boundary");
    const pure = b.dependency("boundary", .{ .@"data-only" = true });
    const pure_test = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("data.zig"),
        .target = b.graph.host,
        .imports = &.{.{ .name = "boundary_data", .module = pure.module("boundary_data") }},
    }) });
    b.step("data", "Check isolated data-only dependency").dependOn(&b.addRunArtifact(pure_test).step);
    const client = b.addExecutable(.{ .name = "client", .root_module = b.createModule(.{
        .root_source_file = b.path("client.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    b.step("emit", "Emit public-package client").dependOn(&b.addRunArtifact(client).step);
    const rejection = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("rejection.zig"),
        .target = b.graph.host,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    }) });
    b.step("reject", "Check rejected public-package neighbor").dependOn(&b.addRunArtifact(rejection).step);
    if (b.option(bool, "category", "Build the deliberate category error") orelse false) {
        const wrong = b.addExecutable(.{ .name = "category", .root_module = b.createModule(.{
            .root_source_file = b.path("category.zig"),
            .target = b.graph.host,
            .imports = &.{.{ .name = "boundary", .module = boundary }},
        }) });
        b.getInstallStep().dependOn(&b.addInstallArtifact(wrong, .{}).step);
    }
}
