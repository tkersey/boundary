const build_options = @import("build_options");
const builtin = @import("builtin");
const std = @import("std");

fn compatIo() std.Io {
    return std.testing.io;
}

fn currentEnviron() std.process.Environ {
    return switch (builtin.os.tag) {
        .windows, .freestanding, .other => .{ .block = .global },
        else => environ: {
            const c_environ = std.c.environ;
            var env_count: usize = 0;
            while (c_environ[env_count] != null) : (env_count += 1) {}
            break :environ .{ .block = .{ .slice = c_environ[0..env_count :null] } };
        },
    };
}

fn smokeCaseStart(label: []const u8) std.Io.Timestamp {
    const start_ns = std.Io.Clock.now(.awake, compatIo());
    std.debug.print("[public-root-package-contract] start {s}\n", .{label});
    return start_ns;
}

fn smokeCaseDone(label: []const u8, start_ns: std.Io.Timestamp) void {
    const elapsed_ns = start_ns.durationTo(std.Io.Clock.now(.awake, compatIo())).toNanoseconds();
    const elapsed_ms = @divTrunc(elapsed_ns, std.time.ns_per_ms);
    std.debug.print("[public-root-package-contract] done {s} ({d} ms)\n", .{ label, elapsed_ms });
}

fn writeTmpFile(dir: std.Io.Dir, path: []const u8, contents: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |dir_name| try dir.createDirPath(compatIo(), dir_name);
    var file = try dir.createFile(compatIo(), path, .{ .truncate = true });
    defer file.close(compatIo());
    var buffer: [1024]u8 = undefined;
    var writer = file.writer(compatIo(), &buffer);
    try writer.interface.writeAll(contents);
    try writer.interface.flush();
}

fn runChild(
    cwd_dir: std.Io.Dir,
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    env_map: ?*const std.process.Environ.Map,
) !std.process.RunResult {
    const cwd_path = try cwd_dir.realPathFileAlloc(compatIo(), ".", allocator);
    defer allocator.free(cwd_path);

    var effective_env = if (env_map) |existing| blk: {
        var cloned = std.process.Environ.Map.init(allocator);
        var it = existing.iterator();
        while (it.next()) |entry| {
            try cloned.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        break :blk cloned;
    } else try currentEnviron().createMap(allocator);
    defer effective_env.deinit();

    if (effective_env.get("ZIG_GLOBAL_CACHE_DIR") == null) {
        try effective_env.put("ZIG_GLOBAL_CACHE_DIR", ".zig-global-cache");
    }

    return try std.process.run(allocator, compatIo(), .{
        .argv = argv,
        .cwd = .{ .path = cwd_path },
        .environ_map = &effective_env,
        .stdout_limit = .limited(32 * 1024),
        .stderr_limit = .limited(32 * 1024),
    });
}

fn runChildNoOutput(
    cwd_dir: std.Io.Dir,
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    env_map: ?*const std.process.Environ.Map,
) !std.process.Child.Term {
    const cwd_path = try cwd_dir.realPathFileAlloc(compatIo(), ".", allocator);
    defer allocator.free(cwd_path);

    var effective_env = if (env_map) |existing| blk: {
        var cloned = std.process.Environ.Map.init(allocator);
        var it = existing.iterator();
        while (it.next()) |entry| {
            try cloned.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        break :blk cloned;
    } else try currentEnviron().createMap(allocator);
    defer effective_env.deinit();

    if (effective_env.get("ZIG_GLOBAL_CACHE_DIR") == null) {
        try effective_env.put("ZIG_GLOBAL_CACHE_DIR", ".zig-global-cache");
    }

    var child = try std.process.spawn(compatIo(), .{
        .argv = argv,
        .cwd = .{ .path = cwd_path },
        .environ_map = &effective_env,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    return try child.wait(compatIo());
}

const FingerprintRepair = struct {
    manifest_path: []const u8,
    fingerprint: []const u8,
};

fn extractSuggestedFingerprint(stderr: []const u8) ?FingerprintRepair {
    const marker = "if this is a new or forked package, use this value: ";
    const start = std.mem.find(u8, stderr, marker) orelse return null;
    const fingerprint_tail = stderr[start + marker.len ..];
    const fingerprint_end = std.mem.findScalar(u8, fingerprint_tail, '\n') orelse fingerprint_tail.len;
    const fingerprint = fingerprint_tail[0..fingerprint_end];

    const path_marker = ":1:2: error: invalid fingerprint:";
    const path_end = std.mem.find(u8, stderr, path_marker) orelse return null;
    const line_start = std.mem.findScalarLast(u8, stderr[0..path_end], '\n') orelse 0;
    const path_start = if (line_start == 0) 0 else line_start + 1;
    return .{
        .manifest_path = stderr[path_start..path_end],
        .fingerprint = fingerprint,
    };
}

fn rewriteBuildZonFingerprint(allocator: std.mem.Allocator, manifest_path: []const u8, fingerprint: []const u8) !void {
    const manifest_dir_path = std.Io.Dir.path.dirname(manifest_path) orelse return error.InvalidConsumerManifest;
    const manifest_basename = std.Io.Dir.path.basename(manifest_path);
    var manifest_dir = try std.Io.Dir.openDirAbsolute(compatIo(), manifest_dir_path, .{});
    defer manifest_dir.close(compatIo());

    const manifest = try manifest_dir.readFileAlloc(compatIo(), manifest_basename, allocator, .limited(std.math.maxInt(usize)));
    defer allocator.free(manifest);

    const marker = ".fingerprint = ";
    const start = std.mem.find(u8, manifest, marker) orelse return error.InvalidConsumerManifest;
    const value_start = start + marker.len;
    const after_value = manifest[value_start..];
    const line_end_rel = std.mem.findScalar(u8, after_value, '\n') orelse after_value.len;
    const value_end = value_start + line_end_rel;

    const repaired = try std.fmt.allocPrint(
        allocator,
        "{s}{s}{s}",
        .{ manifest[0..value_start], fingerprint, manifest[value_end..] },
    );
    defer allocator.free(repaired);
    try writeTmpFile(manifest_dir, manifest_basename, repaired);
}

fn runChildWithFingerprintRepair(
    cwd_dir: std.Io.Dir,
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    env_map: ?*const std.process.Environ.Map,
) !std.process.RunResult {
    while (true) {
        const result = try runChild(cwd_dir, allocator, argv, env_map);

        switch (result.term) {
            .exited => |code| if (code != 0) {
                const suggested = extractSuggestedFingerprint(result.stderr) orelse return result;
                try rewriteBuildZonFingerprint(allocator, suggested.manifest_path, suggested.fingerprint);
                allocator.free(result.stdout);
                allocator.free(result.stderr);
                continue;
            },
            else => {},
        }

        return result;
    }
}

fn runChildExpectSuccess(
    cwd_dir: std.Io.Dir,
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    env_map: ?*const std.process.Environ.Map,
) !void {
    while (true) {
        const term = try runChildNoOutput(cwd_dir, allocator, argv, env_map);
        switch (term) {
            .exited => |code| if (code == 0) return,
            else => {},
        }

        const result = try runChild(cwd_dir, allocator, argv, env_map);
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        switch (result.term) {
            .exited => |code| if (code != 0) {
                const suggested = extractSuggestedFingerprint(result.stderr) orelse {
                    std.debug.print("child command failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ argv[0], result.stdout, result.stderr });
                    return error.UnexpectedChildCommandFailure;
                };
                try rewriteBuildZonFingerprint(allocator, suggested.manifest_path, suggested.fingerprint);
                continue;
            },
            else => {},
        }

        std.debug.print("child command unexpectedly failed without an exit code: {s}\n", .{argv[0]});
        return error.UnexpectedChildCommandFailure;
    }
}

fn runChildExpectFailureContains(
    cwd_dir: std.Io.Dir,
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    env_map: ?*const std.process.Environ.Map,
    needle: []const u8,
) !void {
    const result = try runChildWithFingerprintRepair(cwd_dir, allocator, argv, env_map);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) {
            if (std.mem.find(u8, result.stderr, needle) != null or std.mem.find(u8, result.stdout, needle) != null) return;
            std.debug.print("child command failed without expected needle '{s}'\nstdout:\n{s}\nstderr:\n{s}\n", .{ needle, result.stdout, result.stderr });
            return error.UnexpectedChildCommandFailure;
        },
        else => {},
    }

    std.debug.print("child command unexpectedly succeeded: {s}\n", .{argv[0]});
    return error.UnexpectedChildCommandFailure;
}

fn zigBuildArgv() [2][]const u8 {
    return .{ build_options.zig_exe, "build" };
}

fn writeFakeZigOnPath(tmp: *std.testing.TmpDir) ![]const u8 {
    try tmp.dir.createDirPath(compatIo(), "shadow-bin");
    const fake_name = if (builtin.os.tag == .windows) "shadow-bin/zig.bat" else "shadow-bin/zig";
    const fake_contents = if (builtin.os.tag == .windows)
        "@echo off\r\necho FAKE-ZIG-IN-PATH 1>&2\r\nexit /b 97\r\n"
    else
        "#!/bin/sh\nprintf 'FAKE-ZIG-IN-PATH\\n' >&2\nexit 97\n";
    try writeTmpFile(tmp.dir, fake_name, fake_contents);
    if (builtin.os.tag != .windows) {
        var fake_file = try tmp.dir.openFile(compatIo(), fake_name, .{});
        defer fake_file.close(compatIo());
        try fake_file.setPermissions(compatIo(), .fromMode(0o755));
    }
    return "shadow-bin";
}

const published_package_paths = [_][]const u8{
    "README.md",
    "bench",
    "build.zig",
    "build.zig.zon",
    "examples",
    "source_graph_embed.zig",
    "src",
    "test",
    "tools",
};

const mirrored_dep_names = [_][]const u8{
    "zlinter",
};

fn assertPublishedPackagePathsMatchManifest(repo_dir: std.Io.Dir) !void {
    const manifest = try repo_dir.readFileAlloc(compatIo(), "build.zig.zon", std.testing.allocator, .limited(std.math.maxInt(usize)));
    defer std.testing.allocator.free(manifest);

    const paths_start = std.mem.find(u8, manifest, ".paths = .{") orelse return error.InvalidPublishedPackageManifest;
    const block_tail = manifest[paths_start..];
    const paths_end = std.mem.find(u8, block_tail, "    },") orelse return error.InvalidPublishedPackageManifest;
    const paths_block = block_tail[0..paths_end];

    inline for (published_package_paths) |path| {
        const quoted = comptime std.fmt.comptimePrint("\"{s}\"", .{path});
        if (std.mem.find(u8, paths_block, quoted) == null) return error.PublishedPackagePathDrift;
    }

    var line_iter = std.mem.splitScalar(u8, paths_block, '\n');
    var actual_count: usize = 0;
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] != '"') continue;
        actual_count += 1;
    }
    if (actual_count != published_package_paths.len) return error.PublishedPackagePathDrift;
}

fn dependencyBlockRange(manifest: []const u8, dep_name: []const u8) !struct { start: usize, end: usize } {
    var marker_buffer: [128]u8 = undefined;
    const marker = try std.fmt.bufPrint(&marker_buffer, "        .{s} = .{{", .{dep_name});
    const start = std.mem.find(u8, manifest, marker) orelse return error.MissingPublishedPackageDependency;
    const tail = manifest[start..];
    const end_rel = std.mem.find(u8, tail, "        },") orelse return error.InvalidPublishedPackageManifest;
    return .{
        .start = start,
        .end = start + end_rel + "        },".len,
    };
}

fn dependencyHashFromManifest(manifest: []const u8, dep_name: []const u8) ![]const u8 {
    const block = try dependencyBlockRange(manifest, dep_name);
    const dependency_block = manifest[block.start..block.end];
    const hash_marker = ".hash = \"";
    const hash_start = std.mem.find(u8, dependency_block, hash_marker) orelse return error.MissingPublishedPackageDependencyHash;
    const hash_tail = dependency_block[hash_start + hash_marker.len ..];
    const hash_end = std.mem.findScalar(u8, hash_tail, '"') orelse return error.InvalidPublishedPackageManifest;
    return hash_tail[0..hash_end];
}

fn replaceDependencyWithPathAlloc(
    allocator: std.mem.Allocator,
    manifest: []const u8,
    dep_name: []const u8,
    dependency_path: []const u8,
) ![]u8 {
    const block = try dependencyBlockRange(manifest, dep_name);
    const replacement = try std.fmt.allocPrint(
        allocator,
        "        .{s} = .{{ .path = \"{s}\" }},",
        .{ dep_name, dependency_path },
    );
    defer allocator.free(replacement);
    return try std.fmt.allocPrint(
        allocator,
        "{s}{s}{s}",
        .{ manifest[0..block.start], replacement, manifest[block.end..] },
    );
}

fn pathExistsAbsolute(path: []const u8) bool {
    var dir = std.Io.Dir.openDirAbsolute(compatIo(), path, .{}) catch return false;
    defer dir.close(compatIo());
    return true;
}

fn appendCacheRootCandidate(
    allocator: std.mem.Allocator,
    candidates: *std.ArrayList([]const u8),
    cache_root: []const u8,
) !void {
    const package_root = try std.Io.Dir.path.join(allocator, &.{ cache_root, "p" });
    errdefer allocator.free(package_root);
    if (!pathExistsAbsolute(package_root)) return;
    try candidates.append(allocator, package_root);
}

fn findCachedDependencyDirAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    dependency_hash: []const u8,
) ![]u8 {
    var candidates = std.ArrayList([]const u8).empty;
    defer {
        for (candidates.items) |candidate| allocator.free(candidate);
        candidates.deinit(allocator);
    }

    const repo_cache_root = try std.Io.Dir.path.join(allocator, &.{ repo_root, ".zig-global-cache" });
    defer allocator.free(repo_cache_root);
    try appendCacheRootCandidate(allocator, &candidates, repo_cache_root);

    var env_map = try currentEnviron().createMap(allocator);
    defer env_map.deinit();

    if (env_map.get("XDG_CACHE_HOME")) |xdg_cache_home| {
        const zig_cache_root = try std.Io.Dir.path.join(allocator, &.{ xdg_cache_home, "zig" });
        defer allocator.free(zig_cache_root);
        try appendCacheRootCandidate(allocator, &candidates, zig_cache_root);
    } else if (env_map.get("HOME")) |home| {
        const zig_cache_root = try std.Io.Dir.path.join(allocator, &.{ home, ".cache", "zig" });
        defer allocator.free(zig_cache_root);
        try appendCacheRootCandidate(allocator, &candidates, zig_cache_root);
    }

    for (candidates.items) |candidate| {
        const dependency_dir = try std.Io.Dir.path.join(allocator, &.{ candidate, dependency_hash });
        errdefer allocator.free(dependency_dir);
        if (pathExistsAbsolute(dependency_dir)) return dependency_dir;
        allocator.free(dependency_dir);
    }

    return error.MissingPublishedPackageDependencyCache;
}

fn copyRepoFileIntoFixture(
    repo_dir: std.Io.Dir,
    fixture_dir: std.Io.Dir,
    source_path: []const u8,
    dest_path: []const u8,
) !void {
    const contents = try repo_dir.readFileAlloc(compatIo(), source_path, std.testing.allocator, .limited(std.math.maxInt(usize)));
    defer std.testing.allocator.free(contents);
    try writeTmpFile(fixture_dir, dest_path, contents);
}

fn copyRepoDirectoryIntoFixture(
    repo_dir: std.Io.Dir,
    fixture_dir: std.Io.Dir,
    source_dir_path: []const u8,
    dest_dir_path: []const u8,
) !void {
    try fixture_dir.createDirPath(compatIo(), dest_dir_path);

    var source_dir = try repo_dir.openDir(compatIo(), source_dir_path, .{ .iterate = true });
    defer source_dir.close(compatIo());

    var walker = try source_dir.walk(std.testing.allocator);
    defer walker.deinit();

    while (try walker.next(compatIo())) |entry| {
        const fixture_entry_path = try std.Io.Dir.path.join(std.testing.allocator, &.{ dest_dir_path, entry.path });
        defer std.testing.allocator.free(fixture_entry_path);

        switch (entry.kind) {
            .directory => try fixture_dir.createDirPath(compatIo(), fixture_entry_path),
            .file, .sym_link => try copyRepoFileIntoFixture(source_dir, fixture_dir, entry.path, fixture_entry_path),
            .block_device,
            .character_device,
            .named_pipe,
            .unix_domain_socket,
            .whiteout,
            .door,
            .event_port,
            .unknown,
            => return error.UnsupportedPublishedPackageEntry,
        }
    }
}

fn copyAbsoluteDirectoryIntoFixture(
    source_dir_path: []const u8,
    fixture_dir: std.Io.Dir,
    dest_dir_path: []const u8,
) !void {
    try fixture_dir.createDirPath(compatIo(), dest_dir_path);

    var source_dir = try std.Io.Dir.openDirAbsolute(compatIo(), source_dir_path, .{ .iterate = true });
    defer source_dir.close(compatIo());

    var walker = try source_dir.walk(std.testing.allocator);
    defer walker.deinit();

    while (try walker.next(compatIo())) |entry| {
        const fixture_entry_path = try std.Io.Dir.path.join(std.testing.allocator, &.{ dest_dir_path, entry.path });
        defer std.testing.allocator.free(fixture_entry_path);

        switch (entry.kind) {
            .directory => try fixture_dir.createDirPath(compatIo(), fixture_entry_path),
            .file, .sym_link => try copyRepoFileIntoFixture(source_dir, fixture_dir, entry.path, fixture_entry_path),
            .block_device,
            .character_device,
            .named_pipe,
            .unix_domain_socket,
            .whiteout,
            .door,
            .event_port,
            .unknown,
            => return error.UnsupportedPublishedPackageEntry,
        }
    }
}

fn mirrorPublishedPackageDependenciesIntoFixture(tmp: *std.testing.TmpDir, repo_root: []const u8) !void {
    const mirrored_manifest_path = "deps/shift/build.zig.zon";
    const mirrored_manifest = try tmp.dir.readFileAlloc(compatIo(), mirrored_manifest_path, std.testing.allocator, .limited(std.math.maxInt(usize)));
    defer std.testing.allocator.free(mirrored_manifest);

    var rewritten_manifest = try std.testing.allocator.dupe(u8, mirrored_manifest);
    defer std.testing.allocator.free(rewritten_manifest);

    for (mirrored_dep_names) |dep_name| {
        const dep_block = try dependencyBlockRange(rewritten_manifest, dep_name);
        if (std.mem.find(u8, rewritten_manifest[dep_block.start..dep_block.end], ".path = ") != null) {
            continue;
        }
        const dependency_hash = try dependencyHashFromManifest(rewritten_manifest, dep_name);
        const dependency_dir = try findCachedDependencyDirAlloc(std.testing.allocator, repo_root, dependency_hash);
        defer std.testing.allocator.free(dependency_dir);

        const fixture_dependency_path = try std.Io.Dir.path.join(std.testing.allocator, &.{ "deps", dep_name });
        defer std.testing.allocator.free(fixture_dependency_path);
        try copyAbsoluteDirectoryIntoFixture(dependency_dir, tmp.dir, fixture_dependency_path);

        const relative_dependency_path = try std.Io.Dir.path.join(std.testing.allocator, &.{ "..", dep_name });
        defer std.testing.allocator.free(relative_dependency_path);
        const updated_manifest = try replaceDependencyWithPathAlloc(
            std.testing.allocator,
            rewritten_manifest,
            dep_name,
            relative_dependency_path,
        );
        std.testing.allocator.free(rewritten_manifest);
        rewritten_manifest = updated_manifest;
    }

    try writeTmpFile(tmp.dir, mirrored_manifest_path, rewritten_manifest);
}

fn mirrorPublishedPackageIntoFixture(tmp: *std.testing.TmpDir, repo_root: []const u8) !void {
    try tmp.dir.createDirPath(compatIo(), "deps/shift");

    var repo_dir = try std.Io.Dir.openDirAbsolute(compatIo(), repo_root, .{});
    defer repo_dir.close(compatIo());
    try assertPublishedPackagePathsMatchManifest(repo_dir);

    for (published_package_paths) |path| {
        const fixture_path = try std.Io.Dir.path.join(std.testing.allocator, &.{ "deps/shift", path });
        defer std.testing.allocator.free(fixture_path);

        if (repo_dir.openDir(compatIo(), path, .{ .iterate = true })) |dir| {
            var opened_dir = dir;
            opened_dir.close(compatIo());
            try copyRepoDirectoryIntoFixture(repo_dir, tmp.dir, path, fixture_path);
            continue;
        } else |err| switch (err) {
            error.NotDir => try copyRepoFileIntoFixture(repo_dir, tmp.dir, path, fixture_path),
            else => return err,
        }
    }

    try mirrorPublishedPackageDependenciesIntoFixture(tmp, repo_root);
}

fn writeConsumerBuildFiles(tmp: *std.testing.TmpDir, repo_root: []const u8) !void {
    try mirrorPublishedPackageIntoFixture(tmp, repo_root);

    const build_zon = try std.fmt.allocPrint(std.testing.allocator,
        \\.{{
        \\    .name = .consumer_probe,
        \\    .version = "0.0.0",
        \\    .minimum_zig_version = "0.15.2",
        \\    .dependencies = .{{
        \\        .shift = .{{ .path = "deps/shift" }},
        \\    }},
        \\    .paths = .{{
        \\        "build.zig",
        \\        "build.zig.zon",
        \\        "main.zig",
        \\    }},
        \\    .fingerprint = 0x1234567890abcdef,
        \\}}
        \\
    , .{});
    defer std.testing.allocator.free(build_zon);

    try writeTmpFile(tmp.dir, "build.zig.zon", build_zon);
}

fn writeConsumerExecutableBuild(dir: std.Io.Dir, import_name: []const u8) !void {
    return writeConsumerExecutableBuildWithRoot(dir, import_name, "main.zig");
}

fn writeConsumerExecutableBuildWithRoot(
    dir: std.Io.Dir,
    import_name: []const u8,
    root_source_path: []const u8,
) !void {
    const build_zig = try std.fmt.allocPrint(std.testing.allocator,
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {{
        \\    const target = b.standardTargetOptions(.{{}});
        \\    const optimize = b.standardOptimizeOption(.{{}});
        \\    const shift_dep = b.dependency("shift", .{{ .target = target, .optimize = optimize }});
        \\    const exe_mod = b.createModule(.{{
        \\        .root_source_file = b.path("{s}"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    }});
        \\    exe_mod.addImport("{s}", shift_dep.module("{s}"));
        \\    const exe = b.addExecutable(.{{
        \\        .name = "consumer_probe",
        \\        .root_module = exe_mod,
        \\    }});
        \\    b.installArtifact(exe);
        \\}}
        \\
    , .{ root_source_path, import_name, import_name });
    defer std.testing.allocator.free(build_zig);
    try writeTmpFile(dir, "build.zig", build_zig);
}

fn writeConsumerTestBuild(dir: std.Io.Dir, import_name: []const u8) !void {
    const build_zig = try std.fmt.allocPrint(std.testing.allocator,
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {{
        \\    const target = b.standardTargetOptions(.{{}});
        \\    const optimize = b.standardOptimizeOption(.{{}});
        \\    const shift_dep = b.dependency("shift", .{{ .target = target, .optimize = optimize }});
        \\    const test_mod = b.createModule(.{{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    }});
        \\    test_mod.addImport("{s}", shift_dep.module("{s}"));
        \\    const unit_tests = b.addTest(.{{
        \\        .name = "consumer_probe",
        \\        .root_module = test_mod,
        \\    }});
        \\    const run_tests = b.addRunArtifact(unit_tests);
        \\    b.default_step.dependOn(&run_tests.step);
        \\}}
        \\
    , .{ import_name, import_name });
    defer std.testing.allocator.free(build_zig);
    try writeTmpFile(dir, "build.zig", build_zig);
}

const ConsumerSmokeSuite = struct {
    tmp: std.testing.TmpDir,

    fn init(repo_root: []const u8) !ConsumerSmokeSuite {
        var tmp = std.testing.tmpDir(.{});
        try writeConsumerBuildFiles(&tmp, repo_root);
        return .{ .tmp = tmp };
    }

    fn deinit(self: *ConsumerSmokeSuite) void {
        self.tmp.cleanup();
    }

    fn writeFile(self: *ConsumerSmokeSuite, path: []const u8, contents: []const u8) !void {
        try writeTmpFile(self.tmp.dir, path, contents);
    }

    fn expectSuccess(
        self: *ConsumerSmokeSuite,
        label: []const u8,
        argv: []const []const u8,
        env_map: ?*const std.process.Environ.Map,
    ) !void {
        const start_ns = smokeCaseStart(label);
        try runChildExpectSuccess(self.tmp.dir, std.testing.allocator, argv, env_map);
        smokeCaseDone(label, start_ns);
    }

    fn expectFailureContains(
        self: *ConsumerSmokeSuite,
        label: []const u8,
        argv: []const []const u8,
        env_map: ?*const std.process.Environ.Map,
        needle: []const u8,
    ) !void {
        const start_ns = smokeCaseStart(label);
        try runChildExpectFailureContains(self.tmp.dir, std.testing.allocator, argv, env_map, needle);
        smokeCaseDone(label, start_ns);
    }
};

test "downstream consumer smoke suite reuses one mirrored consumer fixture" {
    const repo_root = try std.process.currentPathAlloc(compatIo(), std.testing.allocator);
    defer std.testing.allocator.free(repo_root);

    var suite = try ConsumerSmokeSuite.init(repo_root);
    defer suite.deinit();

    const argv = zigBuildArgv();

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\
        \\pub fn main() void {
        \\    _ = shift.Runtime;
        \\    _ = shift.RuntimeError;
        \\    _ = shift.effect;
        \\    const witness: shift.OwnedSourceWitness = .{};
        \\    _ = witness;
        \\    _ = shift.with;
        \\    _ = shift.withOwnedSource;
        \\}
        \\
    );
    const shadow_path = try writeFakeZigOnPath(&suite.tmp);
    var env_map = try currentEnviron().createMap(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("PATH", shadow_path);
    try suite.expectSuccess("public root imports only shipped APIs", &argv, &env_map);

    try writeConsumerTestBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\test "public root omits retired exports" {
        \\    try std.testing.expect(!@hasDecl(shift, "Program"));
        \\    try std.testing.expect(!@hasDecl(shift, "run"));
        \\    try std.testing.expect(!@hasDecl(shift, "Decl"));
        \\    try std.testing.expect(!@hasDecl(shift, "Op"));
        \\    try std.testing.expect(!@hasDecl(shift, "Decision"));
        \\    try std.testing.expect(!@hasDecl(shift, "compat"));
        \\    try std.testing.expect(!@hasDecl(shift, "artifact"));
        \\    try std.testing.expect(!@hasDecl(shift, "durable"));
        \\    try std.testing.expect(!@hasDecl(shift, "interpreter"));
        \\    try std.testing.expect(!@hasDecl(shift, "withCallerSource"));
        \\    try std.testing.expect(!@hasDecl(shift, "withCallerSourceAndContent"));
        \\}
        \\
    );
    try suite.expectSuccess("public root omits retired exports downstream", &argv, null);

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift_compile");
    try suite.writeFile("main.zig",
        \\const shift_compile = @import("shift_compile");
        \\
        \\pub fn main() void {
        \\    _ = shift_compile.lower;
        \\}
        \\
    );
    try suite.expectFailureContains("shift_compile stays hidden from downstream packages", &argv, null, "shift_compile");

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift_vm");
    try suite.writeFile("main.zig",
        \\const shift_vm = @import("shift_vm");
        \\
        \\pub fn main() void {
        \\    _ = shift_vm.Runtime;
        \\}
        \\
    );
    try suite.expectFailureContains("shift_vm stays hidden from downstream packages", &argv, null, "shift_vm");

    try writeConsumerTestBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\fn witnessMultiPromptBody(_: anytype) anyerror!i32 {
        \\    return 0;
        \\}
        \\
        \\test "repo-owned NamedBody does not use a local fallback in test builds" {
        \\    var runtime = shift.Runtime.init(std.testing.allocator);
        \\    defer runtime.deinit();
        \\    _ = try shift.withAt(@src(), &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, shift.NamedBody(
        \\        "src/witness_sources.zig",
        \\        "witnessMultiPromptBody",
        \\        anyerror!i32,
        \\        witnessMultiPromptBody,
        \\    ));
        \\}
        \\
    );
    try suite.expectFailureContains("repo-owned NamedBody does not fall back to local test bodies", &argv, null, "shift.NamedBody source_path must match the supplied body function provenance");

    try writeConsumerTestBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\test "legacy lexical and state wrappers stay source-compatible" {
        \\    const AnyError = anyerror;
        \\    var runtime = shift.Runtime.init(std.testing.allocator);
        \\    defer runtime.deinit();
        \\
        \\    const with_result = try shift.with(&runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, struct {
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            const before = try eff.state.get();
        \\            try eff.state.set(before + 1);
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\    try std.testing.expectEqual(@as(i32, 1), with_result.value);
        \\    try std.testing.expectEqual(@as(i32, 1), with_result.outputs.state);
        \\
        \\    var state_instance = shift.effect.state.Instance(i32, AnyError).init();
        \\    const handled = try shift.effect.state.handle(i32, &runtime, &state_instance, @as(i32, 0), struct {
        \\        pub fn body(comptime Cap: type, ctx: anytype) AnyError!i32 {
        \\            const before = try shift.effect.state.get(Cap, ctx);
        \\            try shift.effect.state.set(Cap, ctx, before + 2);
        \\            return try shift.effect.state.get(Cap, ctx);
        \\        }
        \\    });
        \\    try std.testing.expectEqual(@as(i32, 2), handled.value);
        \\    try std.testing.expectEqual(@as(i32, 2), handled.state);
        \\
        \\    var state_instance_with_error = shift.effect.state.Instance(i32, AnyError).init();
        \\    const handled_with_error = try shift.effect.state.handleWithErrorSet(i32, AnyError, &runtime, &state_instance_with_error, @as(i32, 0), struct {
        \\        pub fn body(comptime Cap: type, ctx: anytype) AnyError!i32 {
        \\            const before = try shift.effect.state.get(Cap, ctx);
        \\            try shift.effect.state.set(Cap, ctx, before + 3);
        \\            return try shift.effect.state.get(Cap, ctx);
        \\        }
        \\    });
        \\    try std.testing.expectEqual(@as(i32, 3), handled_with_error.value);
        \\    try std.testing.expectEqual(@as(i32, 3), handled_with_error.state);
        \\}
        \\
    );
    try suite.expectSuccess("legacy lexical and state wrappers stay source-compatible", &argv, null);

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const result = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{}, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, struct {
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            const before = try eff.state.get();
        \\            try eff.state.set(before + 1);
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\}
        \\
    );
    try suite.expectSuccess("withOwnedSource anonymous bodies stay usable downstream", &argv, null);

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn body(eff: anytype) anyerror!i32 {
        \\    const before = try eff.state.get();
        \\    try eff.state.set(before + 1);
        \\    return try eff.state.get();
        \\}
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const named = shift.NamedBody(@src().file, "body", anyerror!i32, body);
        \\    const result = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{}, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, named);
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\}
        \\
    );
    try suite.expectSuccess("withOwnedSource keeps repo-owned NamedBody identity", &argv, null);

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn body(eff: anytype) anyerror!i32 {
        \\    const before = try eff.state.get();
        \\    try eff.state.set(before + 1);
        \\    return try eff.state.get();
        \\}
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const result = try shift.with(&runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, shift.NamedBody(@src().file, "body", anyerror!i32, body));
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\    if (result.outputs.state != 1) return error.UnexpectedState;
        \\}
        \\
    );
    try suite.expectSuccess("downstream NamedBody stays usable with shift.with", &argv, null);

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("helpers.zig",
        \\pub fn body(eff: anytype) anyerror!i32 {
        \\    const before = try eff.state.get();
        \\    try eff.state.set(before + 1);
        \\    return try eff.state.get();
        \\}
        \\
    );
    try suite.writeFile("main.zig",
        \\const helpers = @import("helpers.zig");
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const result = try shift.withAt(@src(), &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, shift.NamedBody("helpers.zig", "body", anyerror!i32, helpers.body));
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\    if (result.outputs.state != 1) return error.UnexpectedState;
        \\}
        \\
    );
    try suite.expectSuccess("downstream NamedBody stays usable across helper files with withAt", &argv, null);

    try writeConsumerExecutableBuildWithRoot(suite.tmp.dir, "shift", "src/main.zig");
    try suite.writeFile("src/helpers.zig",
        \\pub fn sourcePath() []const u8 {
        \\    return @src().file;
        \\}
        \\
        \\pub fn body(eff: anytype) anyerror!i32 {
        \\    const before = try eff.state.get();
        \\    try eff.state.set(before + 1);
        \\    return try eff.state.get();
        \\}
        \\
    );
    try suite.writeFile("src/main.zig",
        \\const helpers = @import("helpers.zig");
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const result = try shift.withAt(@src(), &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, shift.NamedBody(helpers.sourcePath(), "body", anyerror!i32, helpers.body));
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\    if (result.outputs.state != 1) return error.UnexpectedState;
        \\}
        \\
    );
    try suite.expectSuccess("downstream NamedBody stays usable for source-rooted helpers with withAt", &argv, null);

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn body(eff: anytype) anyerror!i32 {
        \\    const before = try eff.state.get();
        \\    try eff.state.set(before + 1);
        \\    return try eff.state.get();
        \\}
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const result = try shift.withAt(@src(), &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, shift.NamedBody(@src().file, "body", anyerror!i32, body));
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\    if (result.outputs.state != 1) return error.UnexpectedState;
        \\}
        \\
    );
    try suite.expectSuccess("downstream NamedBody stays usable with withAt", &argv, null);

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn body(eff: anytype) anyerror![]const u8 {
        \\    return try eff.optional.request(struct {
        \\        pub fn apply(value: i32, _: anytype) anyerror![]const u8 {
        \\            if (value != 41) unreachable;
        \\            return "answer=42";
        \\        }
        \\    });
        \\}
        \\
        \\pub fn main() !void {
        \\    const policy = struct {
        \\        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
        \\            return shift.effect.choice.Decision(i32, []const u8).resumeWith(41);
        \\        }
        \\
        \\        pub fn afterResume(answer: []const u8) []const u8 {
        \\            return answer;
        \\        }
        \\    };
        \\
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const result = try shift.withAt(@src(), &runtime, .{
        \\        .optional = shift.effect.optional.use(i32, policy),
        \\    }, shift.NamedBody(@src().file, "body", anyerror![]const u8, body));
        \\    if (!std.mem.eql(u8, result.value, "answer=42")) return error.UnexpectedResult;
        \\}
        \\
    );
    try suite.expectSuccess("downstream NamedBody keeps resumed payload semantics with withAt", &argv, null);

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    const policy = struct {
        \\        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
        \\            return shift.effect.choice.Decision(i32, []const u8).resumeWith(41);
        \\        }
        \\
        \\        pub fn afterResume(answer: []const u8) []const u8 {
        \\            return answer;
        \\        }
        \\    };
        \\
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    _ = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{
        \\        .entry_symbol = "ownedBody",
        \\        .body_source =
        \\        \\pub fn ownedBody(eff: anytype) anyerror![]const u8 {
        \\        \\    return try eff.optional.request(struct {
        \\        \\        pub fn apply(value: i32, _: anytype) anyerror![]const u8 {
        \\        \\            if (value != 41) unreachable;
        \\        \\            return "answer=42";
        \\        \\        }
        \\        \\    }, "extra");
        \\        \\}
        \\        ,
        \\    }, &runtime, .{
        \\        .optional = shift.effect.optional.use(i32, policy),
        \\    }, struct {
        \\        pub fn body(_: anytype) anyerror![]const u8 {
        \\            return "placeholder";
        \\        }
        \\    });
        \\}
        \\
    );
    try suite.expectFailureContains("withOwnedSource rejects explicit continuations with trailing arguments", &argv, null, "shift.withOwnedSource explicit source witnesses must stay within the retained compiled lexical subset");

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\
        \\pub fn body(_: anytype) anyerror!i32 {
        \\    return 1;
        \\}
        \\
        \\pub fn main() void {
        \\    _ = shift.NamedBody(@src().file, "wrongBody", anyerror!i32, &body);
        \\}
        \\
    );
    try suite.expectFailureContains("NamedBody rejects mismatched entry_symbol", &argv, null, "shift.NamedBody entry_symbol must match the supplied body function name");

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("helpers.zig",
        \\pub fn body(_: anytype) anyerror!i32 {
        \\    return 2;
        \\}
        \\
    );
    try suite.writeFile("main.zig",
        \\const helpers = @import("helpers.zig");
        \\const shift = @import("shift");
        \\
        \\pub fn body(_: anytype) anyerror!i32 {
        \\    return 1;
        \\}
        \\
        \\pub fn main() void {
        \\    _ = shift.NamedBody(@src().file, "body", anyerror!i32, &helpers.body);
        \\}
        \\
    );
    try suite.expectFailureContains("NamedBody rejects helper function provenance drift", &argv, null, "shift.NamedBody source_path must match the supplied body function provenance");

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("x/a/helpers.zig",
        \\pub fn body(_: anytype) anyerror!i32 {
        \\    return 2;
        \\}
        \\
    );
    try suite.writeFile("main.zig",
        \\const helpers = @import("x/a/helpers.zig");
        \\const shift = @import("shift");
        \\
        \\pub fn main() void {
        \\    _ = shift.NamedBody("a/helpers.zig", "body", anyerror!i32, &helpers.body);
        \\}
        \\
    );
    try suite.expectFailureContains("NamedBody rejects suffix-only external source_path matches", &argv, null, "shift.NamedBody source_path must match the supplied body function provenance");

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const helpers = @import("x/a/helpers.zig");
        \\const shift = @import("shift");
        \\
        \\pub fn main() void {
        \\    _ = shift.NamedBody("totally/fake/a/helpers.zig", "body", anyerror!i32, &helpers.body);
        \\}
        \\
    );
    try suite.expectFailureContains("NamedBody rejects unrelated external source_path matches", &argv, null, "shift.NamedBody source_path must match the supplied body function provenance");

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("body.zig",
        \\pub fn forged(eff: anytype) anyerror!i32 {
        \\    const before = try eff.state.get();
        \\    try eff.state.set(before + 20);
        \\    return try eff.state.get();
        \\}
        \\
    );
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn body(eff: anytype) anyerror!i32 {
        \\    const before = try eff.state.get();
        \\    try eff.state.set(before + 1);
        \\    return try eff.state.get();
        \\}
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const named = shift.NamedBody(@src().file, "body", anyerror!i32, body);
        \\    const result = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{
        \\        .source_path = "body.zig",
        \\        .entry_symbol = "forged",
        \\    }, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, named);
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\    if (result.outputs.state != 1) return error.UnexpectedState;
        \\}
        \\
    );
    try suite.expectSuccess("explicit witness disagreement cannot override repo-owned NamedBody", &argv, null);

    try writeConsumerTestBuild(suite.tmp.dir, "shift");
    try suite.writeFile("forged.zig",
        \\pub fn body(eff: anytype) anyerror!i32 {
        \\    const before = try eff.state.get();
        \\    try eff.state.set(before + 20);
        \\    return try eff.state.get();
        \\}
        \\
    );
    try suite.writeFile("body.zig",
        \\pub fn body(eff: anytype) anyerror!i32 {
        \\    const before = try eff.state.get();
        \\    try eff.state.set(before + 1);
        \\    return try eff.state.get();
        \\}
        \\
    );
    try suite.writeFile("main.zig",
        \\const body_file = @import("body.zig");
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\test "withOwnedSource keeps downstream NamedBody identity" {
        \\    var runtime = shift.Runtime.init(std.testing.allocator);
        \\    defer runtime.deinit();
        \\    const named = shift.NamedBody("body.zig", "body", anyerror!i32, body_file.body);
        \\    const result = try shift.withOwnedSource(@src(), @embedFile("forged.zig"), .{}, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, named);
        \\    try std.testing.expectEqual(@as(i32, 1), result.value);
        \\    try std.testing.expectEqual(@as(i32, 1), result.outputs.state);
        \\}
        \\
    );
    try suite.expectSuccess("withOwnedSource keeps downstream NamedBody identity", &argv, null);

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("body.zig",
        \\pub fn forged() void {}
        \\
    );
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    _ = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{
        \\        .source_path = "body.zig",
        \\    }, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, struct {
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            const before = try eff.state.get();
        \\            try eff.state.set(before + 1);
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\}
        \\
    );
    try suite.expectFailureContains("withOwnedSource rejects mismatched explicit body-source witnesses", &argv, null, "shift.withOwnedSource anonymous and body-source witnesses require witness.source_path to agree with the caller source");

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    _ = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{}, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, struct {
        \\        pub const source_path = "body.zig";
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            const before = try eff.state.get();
        \\            try eff.state.set(before + 1);
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\}
        \\
    );
    try suite.expectFailureContains("withOwnedSource anonymous bodies reject source_path declarations", &argv, null, "shift.withOwnedSource anonymous bodies must not declare source_path; use witness.source_path or shift.NamedBody(...)");

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    _ = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{}, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, struct {
        \\        pub const entry_symbol = "forged";
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            const before = try eff.state.get();
        \\            try eff.state.set(before + 1);
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\}
        \\
    );
    try suite.expectFailureContains("withOwnedSource anonymous bodies reject entry_symbol declarations", &argv, null, "shift.withOwnedSource anonymous bodies must not declare entry_symbol; use witness.entry_symbol/body_method_name or shift.NamedBody(...)");

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("nested/main.zig",
        \\pub fn body(_: anytype) anyerror!i32 {
        \\    return 2;
        \\}
        \\
    );
    try suite.writeFile("main.zig",
        \\const nested = @import("nested/main.zig");
        \\const shift = @import("shift");
        \\
        \\pub fn body(_: anytype) anyerror!i32 {
        \\    return 1;
        \\}
        \\
        \\pub fn main() void {
        \\    _ = shift.NamedBody("main.zig", "body", anyerror!i32, &nested.body);
        \\}
        \\
    );
    try suite.expectFailureContains("NamedBody keeps nested module provenance distinct", &argv, null, "shift.NamedBody source_path must match the supplied body function provenance");
}
