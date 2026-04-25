const build_options = @import("build_options");
const builtin = @import("builtin");
const std = @import("std");

fn writeTmpFile(dir: std.Io.Dir, sub_path: []const u8, contents: []const u8) !void {
    try dir.writeFile(std.testing.io, .{
        .sub_path = sub_path,
        .data = contents,
        .flags = .{ .truncate = true },
    });
}

fn runChildAtPathExpectSuccess(
    cwd_path: []const u8,
    argv: []const []const u8,
    environ_map: ?*const std.process.Environ.Map,
) !void {
    var child = try std.process.spawn(std.testing.io, .{
        .argv = argv,
        .cwd = .{ .path = cwd_path },
        .environ_map = environ_map,
        .stdin = .ignore,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const term = try child.wait(std.testing.io);

    switch (term) {
        .exited => |code| if (code == 0) return,
        else => {},
    }
    std.debug.print("child command failed: {s}\n", .{argv[0]});
    return error.UnexpectedChildCommandFailure;
}

fn writeFakeZigOnPath(tmp_dir: std.Io.Dir) !void {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    try writeTmpFile(tmp_dir, "zig", "#!/bin/sh\nexit 1\n");
    var fake_zig = try tmp_dir.openFile(std.testing.io, "zig", .{});
    defer fake_zig.close(std.testing.io);
    try fake_zig.setPermissions(std.testing.io, .fromMode(0o755));
}

test "ability_agent_vm package module is exported to downstream dependency consumers" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const consumer_root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(consumer_root);

    const build_zig = try std.fmt.allocPrint(std.testing.allocator,
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {{
        \\    const target = b.standardTargetOptions(.{{}});
        \\    const optimize = b.standardOptimizeOption(.{{}});
        \\    const dep = b.dependency("ability", .{{ .target = target, .optimize = optimize }});
        \\
        \\    const root = b.createModule(.{{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    }});
        \\    root.addImport("ability_agent_vm", dep.module("ability_agent_vm"));
        \\
        \\    const exe = b.addExecutable(.{{
        \\        .name = "ability-agent-vm-consumer",
        \\        .root_module = root,
        \\    }});
        \\    b.default_step.dependOn(&exe.step);
        \\}}
        \\
    , .{});
    defer std.testing.allocator.free(build_zig);
    try writeTmpFile(tmp.dir, "build.zig", build_zig);

    const build_zon = try std.fmt.allocPrint(std.testing.allocator,
        \\.{{
        \\    .name = .ability_agent_vm_consumer,
        \\    .version = "0.0.0",
        \\    .minimum_zig_version = "0.16.0",
        \\    .dependencies = .{{
        \\        .ability = .{{ .path = "../../.." }},
        \\    }},
        \\    .paths = .{{ "build.zig", "build.zig.zon", "main.zig" }},
        \\    .fingerprint = 0x59e8b7e9f2dd2bb8,
        \\}}
        \\
    , .{});
    defer std.testing.allocator.free(build_zon);
    try writeTmpFile(tmp.dir, "build.zig.zon", build_zon);

    try writeTmpFile(tmp.dir, "main.zig",
        \\const ability_agent_vm = @import("ability_agent_vm");
        \\
        \\pub fn main() void {
        \\    _ = ability_agent_vm.host.Adapter;
        \\    _ = ability_agent_vm.runtime.runArtifact;
        \\}
        \\
    );

    var env_map = std.process.Environ.Map.init(std.testing.allocator);
    defer env_map.deinit();
    try writeFakeZigOnPath(tmp.dir);
    try env_map.put("PATH", consumer_root);

    try runChildAtPathExpectSuccess(
        consumer_root,
        &.{
            build_options.zig_exe,
            "build",
            "--summary",
            "none",
            "--cache-dir",
            ".zig-cache",
            "--global-cache-dir",
            "zig-global-cache",
        },
        &env_map,
    );
}
