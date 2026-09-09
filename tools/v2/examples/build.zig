const std = @import("std");

pub fn build(b: *std.Build) void {
    const dependency = b.dependency("boundary", .{
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    const boundary = dependency.module("boundary");
    const options = b.addOptions();
    const example = b.option(usize, "example", "Example ordinal listed in README") orelse 1;
    const source = b.option(bool, "source", "Emit source terms instead of BPI2") orelse false;
    options.addOption(usize, "example", example);
    options.addOption(bool, "source", source);
    const module = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .imports = &.{.{ .name = "boundary", .module = boundary }},
    });
    module.addOptions("source_options", options);
    const executable = b.addExecutable(.{ .name = "compile-example", .root_module = module });
    b.step("emit", "Compile a checked public example").dependOn(&b.addRunArtifact(executable).step);
}
