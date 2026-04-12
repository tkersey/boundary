const builtin = @import("builtin");
const shipped_open_row_corpus = @import("src/shipped_open_row_corpus_registry.zig");
const std = @import("std");
const zlinter = @import("zlinter");

const ShiftConsumerDeps = struct {
    lowered_runtime_mod: ?*std.Build.Module,
    shift_mod: *std.Build.Module,
    shift_compile_mod: ?*std.Build.Module = null,
    shift_vm_mod: ?*std.Build.Module = null,
};

const ShiftPromptFixtureDeps = struct {
    authoring_build_options_mod: *std.Build.Module,
    prompt_support_mod: *std.Build.Module,
    shift_mod: *std.Build.Module,
    shift_compile_mod: ?*std.Build.Module = null,
    shift_vm_mod: ?*std.Build.Module = null,
    with_api_mod: *std.Build.Module,
};

fn absolutizeGraphDirPath(b: *std.Build, maybe_path: ?[]const u8) ?[]const u8 {
    const path = maybe_path orelse return null;
    if (std.fs.path.isAbsolute(path)) return path;
    const cwd = std.fs.cwd().realpathAlloc(b.allocator, ".") catch |err|
        std.process.fatal("failed to resolve build cwd for graph path '{s}': {s}", .{ path, @errorName(err) });
    return std.fs.path.resolve(b.allocator, &.{ cwd, path }) catch |err|
        std.process.fatal("failed to resolve build graph path '{s}': {s}", .{ path, @errorName(err) });
}

fn absolutizeZlinterRuntimePaths(b: *std.Build) void {
    b.graph.global_cache_root.path = absolutizeGraphDirPath(b, b.graph.global_cache_root.path);
    b.graph.zig_lib_directory.path = absolutizeGraphDirPath(b, b.graph.zig_lib_directory.path);
}

fn createShiftConsumerModule(
    b: *std.Build,
    path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    deps: ShiftConsumerDeps,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = lazyPathForSourceFile(b, path),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("shift", deps.shift_mod);
    if (deps.shift_compile_mod) |shift_compile_mod| mod.addImport("shift_compile", shift_compile_mod);
    if (deps.shift_vm_mod) |shift_vm_mod| mod.addImport("shift_vm", shift_vm_mod);
    if (deps.lowered_runtime_mod) |runtime_mod| mod.addImport("private_lowered_runtime", runtime_mod);
    return mod;
}

fn createShiftPromptFixtureModule(
    b: *std.Build,
    path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    deps: ShiftPromptFixtureDeps,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = lazyPathForSourceFile(b, path),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("authoring_build_options", deps.authoring_build_options_mod);
    mod.addImport("shift", deps.shift_mod);
    if (deps.shift_compile_mod) |shift_compile_mod| mod.addImport("shift_compile", shift_compile_mod);
    if (deps.shift_vm_mod) |shift_vm_mod| mod.addImport("shift_vm", shift_vm_mod);
    mod.addImport("prompt_support", deps.prompt_support_mod);
    mod.addImport("with_api", deps.with_api_mod);
    return mod;
}

fn createBridgeExampleModule(
    b: *std.Build,
    path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    import: struct {
        name: []const u8,
        mod: *std.Build.Module,
    },
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = lazyPathForSourceFile(b, path),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport(import.name, import.mod);
    return mod;
}

fn createPlainModule(
    b: *std.Build,
    path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = lazyPathForSourceFile(b, path),
        .target = target,
        .optimize = optimize,
    });
}

fn lazyPathForSourceFile(b: *std.Build, path: []const u8) std.Build.LazyPath {
    if (std.fs.path.isAbsolute(path)) return .{ .cwd_relative = path };
    return b.path(path);
}

fn assertOwnedCompileFailFixtures(b: *std.Build, dir_path: []const u8, fixture_table: anytype) void {
    var test_dir = std.fs.cwd().openDir(b.pathFromRoot("test"), .{}) catch |err| switch (err) {
        // Published package layouts intentionally omit the proof-only test corpus.
        error.FileNotFound => return,
        else => std.process.fatal("unable to open test fixture directory", .{}),
    };
    test_dir.close();

    var owned = std.StringHashMap(void).init(b.allocator);
    defer owned.deinit();

    inline for (fixture_table) |fixture| {
        owned.put(std.fs.path.basename(fixture.path), {}) catch std.process.fatal("unable to record compile-fail fixture", .{});
    }

    var dir = std.fs.cwd().openDir(b.pathFromRoot(dir_path), .{ .iterate = true }) catch
        std.process.fatal("unable to open compile-fail fixture directory", .{});
    defer dir.close();

    var iterator = dir.iterate();
    while (iterator.next() catch std.process.fatal("unable to iterate compile-fail fixture directory", .{})) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;
        if (!owned.contains(entry.name)) {
            std.process.fatal("unowned compile-fail fixture: {s}/{s}", .{ dir_path, entry.name });
        }
    }
}

fn canonicalSourceHash(b: *std.Build, path: []const u8) [32]u8 {
    const bytes = std.fs.cwd().readFileAlloc(b.allocator, b.pathFromRoot(path), 1 << 20) catch |err| switch (err) {
        // Archive/registry package paths intentionally exclude proof-only corpora.
        error.FileNotFound => return std.mem.zeroes([32]u8),
        else => std.process.fatal("unable to read canonical source-lowering source", .{}),
    };
    defer b.allocator.free(bytes);

    const normalized = normalizeSourceForHashAlloc(b.allocator, bytes) catch
        std.process.fatal("unable to normalize canonical source-lowering source", .{});
    defer b.allocator.free(normalized);

    var digest = std.mem.zeroes([32]u8);
    std.crypto.hash.Blake3.hash(normalized, &digest, .{});
    return digest;
}

fn hashBuildIdentityU64(hasher: *std.crypto.hash.Blake3, value: u64) void {
    var buffer: [8]u8 = undefined;
    std.mem.writeInt(u64, &buffer, value, .little);
    hasher.update(&buffer);
}

fn hashBuildIdentityField(
    hasher: *std.crypto.hash.Blake3,
    label: []const u8,
    value: []const u8,
) void {
    hasher.update(label);
    hashBuildIdentityU64(hasher, @as(u64, @intCast(value.len)));
    hasher.update(value);
}

fn pathExistsAtRoot(root_dir: std.fs.Dir, path: []const u8) bool {
    const file = root_dir.openFile(path, .{}) catch return false;
    file.close();
    return true;
}

fn hashBuildIdentityFileAtRoot(
    hasher: *std.crypto.hash.Blake3,
    repo_root: []const u8,
    path: []const u8,
) void {
    var root_dir = std.fs.openDirAbsolute(repo_root, .{}) catch |err|
        std.process.fatal("unable to open build identity root '{s}': {s}", .{ repo_root, @errorName(err) });
    defer root_dir.close();

    var file = root_dir.openFile(path, .{}) catch |err|
        std.process.fatal("unable to open build identity file '{s}': {s}", .{ path, @errorName(err) });
    defer file.close();

    const stat = file.stat() catch |err|
        std.process.fatal("unable to stat build identity file '{s}': {s}", .{ path, @errorName(err) });

    hashBuildIdentityField(hasher, "build-input-path", path);
    hasher.update("build-input-bytes");
    hashBuildIdentityU64(hasher, stat.size);

    var buffer: [4096]u8 = undefined;
    while (true) {
        const read_len = file.read(&buffer) catch |err|
            std.process.fatal("unable to read build identity file '{s}': {s}", .{ path, @errorName(err) });
        if (read_len == 0) break;
        hasher.update(buffer[0..read_len]);
    }
}

fn appendOwnedPathIfMissing(
    allocator: std.mem.Allocator,
    paths: *std.ArrayList([]const u8),
    path_set: *std.StringHashMap(void),
    path: []const u8,
) !void {
    const owned = try allocator.dupe(u8, path);
    errdefer allocator.free(owned);

    const gop = try path_set.getOrPut(owned);
    if (gop.found_existing) return allocator.free(owned);
    try paths.append(allocator, owned);
}

fn sortOwnedPaths(paths: [][]const u8) void {
    var left: usize = 0;
    while (left < paths.len) : (left += 1) {
        var right = left + 1;
        while (right < paths.len) : (right += 1) {
            if (std.mem.order(u8, paths[right], paths[left]) == .lt) {
                const tmp = paths[left];
                paths[left] = paths[right];
                paths[right] = tmp;
            }
        }
    }
}

fn freeOwnedPathList(allocator: std.mem.Allocator, paths: []const []const u8) void {
    for (paths) |path| allocator.free(path);
    allocator.free(paths);
}

fn stringLiteralInner(literal: []const u8) ?[]const u8 {
    if (literal.len < 2) return null;
    if (literal[0] != '"' or literal[literal.len - 1] != '"') return null;
    return literal[1 .. literal.len - 1];
}

fn decodeStringLiteralAlloc(allocator: std.mem.Allocator, literal: []const u8) !?[]u8 {
    const inner = stringLiteralInner(literal) orelse return null;
    if (std.mem.indexOfScalar(u8, inner, '\\') == null) {
        if (std.mem.indexOfAny(u8, inner, "\"\n") != null) return null;
        return try allocator.dupe(u8, inner);
    }

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var index: usize = 0;
    while (index < inner.len) {
        switch (inner[index]) {
            '\\' => {
                const escape_char_index = index + 1;
                const parsed = std.zig.string_literal.parseEscapeSequence(inner, &index);
                const codepoint = switch (parsed) {
                    .success => |value| value,
                    .failure => return null,
                };
                if (escape_char_index >= inner.len) return null;
                if (inner[escape_char_index] == 'u') {
                    var utf8_buffer: [4]u8 = undefined;
                    const utf8_len = std.unicode.utf8Encode(codepoint, &utf8_buffer) catch return null;
                    try out.appendSlice(allocator, utf8_buffer[0..utf8_len]);
                } else {
                    try out.append(allocator, @as(u8, @intCast(codepoint)));
                }
            },
            '"' => return null,
            '\n' => return null,
            else => {
                try out.append(allocator, inner[index]);
            },
        }
        index += 1;
    }

    return try out.toOwnedSlice(allocator);
}

const BuildInputToken = struct {
    tag: std.zig.Token.Tag,
    lexeme: []const u8,
};

const BuildInputTokenWindow = struct {
    items: [8]BuildInputToken = [_]BuildInputToken{.{
        .tag = .invalid,
        .lexeme = "",
    }} ** 8,
    count: usize = 0,

    fn push(self: *@This(), item: BuildInputToken) void {
        if (self.count < self.items.len) {
            self.items[self.count] = item;
            self.count += 1;
            return;
        }
        var index: usize = 1;
        while (index < self.items.len) : (index += 1) {
            self.items[index - 1] = self.items[index];
        }
        self.items[self.items.len - 1] = item;
    }
};

fn tokenSlice(source: [:0]const u8, token: anytype) []const u8 {
    return source[token.loc.start..token.loc.end];
}

fn maybeEmbedFileLiteralPath(window: *const BuildInputTokenWindow) ?[]const u8 {
    if (window.count < 4) return null;
    const tail = window.items[window.count - 4 .. window.count];
    if (!(tail[0].tag == .builtin and
        std.mem.eql(u8, tail[0].lexeme, "@embedFile") and
        tail[1].tag == .l_paren and
        tail[2].tag == .string_literal and
        tail[3].tag == .r_paren))
    {
        return null;
    }
    return tail[2].lexeme;
}

fn maybeEmbedFileIdentifierPath(window: *const BuildInputTokenWindow) ?[]const u8 {
    if (window.count < 4) return null;
    const tail = window.items[window.count - 4 .. window.count];
    if (!(tail[0].tag == .builtin and
        std.mem.eql(u8, tail[0].lexeme, "@embedFile") and
        tail[1].tag == .l_paren and
        tail[2].tag == .identifier and
        tail[3].tag == .r_paren))
    {
        return null;
    }
    return tail[2].lexeme;
}

fn maybeImportLiteralPath(window: *const BuildInputTokenWindow) ?[]const u8 {
    if (window.count < 4) return null;
    const tail = window.items[window.count - 4 .. window.count];
    if (!(tail[0].tag == .builtin and
        std.mem.eql(u8, tail[0].lexeme, "@import") and
        tail[1].tag == .l_paren and
        tail[2].tag == .string_literal and
        tail[3].tag == .r_paren))
    {
        return null;
    }
    return tail[2].lexeme;
}

fn windowMatchesEmbedFileSelf(window: *const BuildInputTokenWindow) bool {
    if (window.count < 8) return false;
    const tail = window.items[window.count - 8 .. window.count];
    return tail[0].tag == .builtin and
        std.mem.eql(u8, tail[0].lexeme, "@embedFile") and
        tail[1].tag == .l_paren and
        tail[2].tag == .builtin and
        std.mem.eql(u8, tail[2].lexeme, "@src") and
        tail[3].tag == .l_paren and
        tail[4].tag == .r_paren and
        tail[5].tag == .period and
        tail[6].tag == .identifier and
        std.mem.eql(u8, tail[6].lexeme, "file") and
        tail[7].tag == .r_paren;
}

fn tryRepoRelativePathFromAbsoluteAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    absolute_path: []const u8,
) !?[]u8 {
    if (!std.mem.startsWith(u8, absolute_path, repo_root)) return null;
    if (absolute_path.len == repo_root.len) return null;
    if (absolute_path[repo_root.len] != std.fs.path.sep) return null;
    return try allocator.dupe(u8, absolute_path[repo_root.len + 1 ..]);
}

const EmbedFileFunctionPattern = struct {
    fn_name: []const u8,
    path_param_indexes: []const usize,

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.fn_name);
        allocator.free(self.path_param_indexes);
        self.* = undefined;
    }
};

const ImportedEmbedFnPattern = struct {
    module_binding: []const u8,
    source_dir: []const u8,
    pattern: EmbedFileFunctionPattern,

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.module_binding);
        allocator.free(self.source_dir);
        self.pattern.deinit(allocator);
        self.* = undefined;
    }
};

const BuildModuleBinding = struct {
    alias: []const u8,
    repo_relative_source_path: []const u8,

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.alias);
        allocator.free(self.repo_relative_source_path);
        self.* = undefined;
    }
};

const BuildInputPathCollector = struct {
    paths: *std.ArrayList([]const u8),
    path_set: *std.StringHashMap(void),
};

const BuildInputSourceScan = struct {
    repo_root: []const u8,
    source_path: []const u8,
    source: [:0]const u8,
    tokens: []const BuildInputToken,
    collector: BuildInputPathCollector,
    top_bindings: *const std.StringHashMap([]const u8),
};

const TopLevelStringDeclaration = struct {
    name: []const u8,
    value_tokens: []const BuildInputToken,
};

fn resolveStringTokensFromBindingMapAlloc(
    allocator: std.mem.Allocator,
    tokens: []const BuildInputToken,
    bindings: *const std.StringHashMap([]const u8),
) !?[]u8 {
    if (tokens.len != 1) return null;
    return switch (tokens[0].tag) {
        .string_literal => try decodeStringLiteralAlloc(allocator, tokens[0].lexeme),
        .identifier => if (bindings.get(tokens[0].lexeme)) |bound|
            try allocator.dupe(u8, bound)
        else
            null,
        else => null,
    };
}

fn collectTopLevelStringDeclarationsAlloc(
    allocator: std.mem.Allocator,
    tokens: []const BuildInputToken,
) ![]const TopLevelStringDeclaration {
    var declarations = std.ArrayList(TopLevelStringDeclaration).empty;
    errdefer declarations.deinit(allocator);

    var index: usize = 0;
    var scope_depth: usize = 0;
    while (index + 1 < tokens.len) {
        switch (tokens[index].tag) {
            .l_brace => {
                scope_depth += 1;
                index += 1;
                continue;
            },
            .r_brace => {
                if (scope_depth > 0) scope_depth -= 1;
                index += 1;
                continue;
            },
            else => {},
        }

        if (scope_depth != 0 or tokens[index].tag != .keyword_const or tokens[index + 1].tag != .identifier) {
            index += 1;
            continue;
        }

        var cursor = index + 2;
        var depth: usize = 0;
        var equal_index: ?usize = null;
        var semicolon_index: ?usize = null;
        while (cursor < tokens.len) : (cursor += 1) {
            switch (tokens[cursor].tag) {
                .l_paren, .l_brace, .l_bracket => depth += 1,
                .r_paren, .r_brace, .r_bracket => {
                    if (depth > 0) depth -= 1;
                },
                .equal => {
                    if (depth == 0 and equal_index == null) equal_index = cursor;
                },
                .semicolon => {
                    if (depth == 0) {
                        semicolon_index = cursor;
                        break;
                    }
                },
                else => {},
            }
        }

        const value_start = equal_index orelse {
            index += 1;
            continue;
        };
        const value_end = semicolon_index orelse {
            index += 1;
            continue;
        };
        try declarations.append(allocator, .{
            .name = tokens[index + 1].lexeme,
            .value_tokens = tokens[value_start + 1 .. value_end],
        });
        index = value_end + 1;
    }

    return declarations.toOwnedSlice(allocator);
}

fn populateTopLevelSimpleStringBindings(
    allocator: std.mem.Allocator,
    tokens: []const BuildInputToken,
    top_bindings: *std.StringHashMap([]const u8),
) !void {
    const declarations = try collectTopLevelStringDeclarationsAlloc(allocator, tokens);
    defer allocator.free(declarations);

    while (true) {
        var made_progress = false;
        for (declarations) |declaration| {
            if (top_bindings.contains(declaration.name)) continue;
            const value = try resolveStringTokensFromBindingMapAlloc(
                allocator,
                declaration.value_tokens,
                top_bindings,
            ) orelse continue;
            errdefer allocator.free(value);
            try top_bindings.put(declaration.name, value);
            made_progress = true;
        }
        if (!made_progress) break;
    }
}

fn lookupVisibleStringBinding(
    scopes: []const std.StringHashMap([]const u8),
    top_bindings: *const std.StringHashMap([]const u8),
    identifier: []const u8,
) ?[]const u8 {
    var index = scopes.len;
    while (index > 0) {
        index -= 1;
        if (scopes[index].get(identifier)) |value| return value;
    }
    return top_bindings.get(identifier);
}

fn resolveStringTokensFromVisibleBindingsAlloc(
    allocator: std.mem.Allocator,
    tokens: []const BuildInputToken,
    scopes: []const std.StringHashMap([]const u8),
    top_bindings: *const std.StringHashMap([]const u8),
) !?[]u8 {
    if (tokens.len != 1) return null;
    return switch (tokens[0].tag) {
        .string_literal => try decodeStringLiteralAlloc(allocator, tokens[0].lexeme),
        .identifier => if (lookupVisibleStringBinding(scopes, top_bindings, tokens[0].lexeme)) |bound|
            try allocator.dupe(u8, bound)
        else
            null,
        else => null,
    };
}

fn setScopeBinding(
    allocator: std.mem.Allocator,
    scope: *std.StringHashMap([]const u8),
    identifier: []const u8,
    value: []const u8,
) !void {
    const gop = try scope.getOrPut(identifier);
    if (gop.found_existing) allocator.free(gop.value_ptr.*);
    gop.value_ptr.* = value;
}

fn resolveVisibleStringBindingAlloc(
    allocator: std.mem.Allocator,
    tokens: []const BuildInputToken,
    use_index: usize,
    identifier: []const u8,
    top_bindings: *const std.StringHashMap([]const u8),
) !?[]u8 {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    errdefer scratch.deinit();
    defer scratch.deinit();
    const scratch_allocator = scratch.allocator();

    var scopes = std.ArrayList(std.StringHashMap([]const u8)).empty;
    errdefer scopes.deinit(scratch_allocator);
    try scopes.append(scratch_allocator, std.StringHashMap([]const u8).init(scratch_allocator));
    defer scopes.deinit(scratch_allocator);

    var index: usize = 0;
    while (index < use_index) {
        switch (tokens[index].tag) {
            .l_brace => {
                try scopes.append(scratch_allocator, std.StringHashMap([]const u8).init(scratch_allocator));
                index += 1;
                continue;
            },
            .r_brace => {
                if (scopes.items.len > 1) {
                    _ = scopes.pop();
                }
                index += 1;
                continue;
            },
            else => {},
        }

        if (scopes.items.len == 1 or
            tokens[index].tag != .keyword_const or
            index + 1 >= use_index or
            tokens[index + 1].tag != .identifier)
        {
            index += 1;
            continue;
        }

        var cursor = index + 2;
        var depth: usize = 0;
        var equal_index: ?usize = null;
        var semicolon_index: ?usize = null;
        while (cursor < use_index) : (cursor += 1) {
            switch (tokens[cursor].tag) {
                .l_paren, .l_brace, .l_bracket => depth += 1,
                .r_paren, .r_brace, .r_bracket => {
                    if (depth > 0) depth -= 1;
                },
                .equal => {
                    if (depth == 0 and equal_index == null) equal_index = cursor;
                },
                .semicolon => {
                    if (depth == 0) {
                        semicolon_index = cursor;
                        break;
                    }
                },
                else => {},
            }
        }

        const value_start = equal_index orelse {
            index += 1;
            continue;
        };
        const value_end = semicolon_index orelse break;

        const value = try resolveStringTokensFromVisibleBindingsAlloc(
            scratch_allocator,
            tokens[value_start + 1 .. value_end],
            scopes.items,
            top_bindings,
        ) orelse {
            index = value_end + 1;
            continue;
        };
        try setScopeBinding(
            scratch_allocator,
            &scopes.items[scopes.items.len - 1],
            tokens[index + 1].lexeme,
            value,
        );
        index = value_end + 1;
    }

    if (lookupVisibleStringBinding(scopes.items, top_bindings, identifier)) |value| {
        return try allocator.dupe(u8, value);
    }
    return null;
}

fn resolveBuildInputStringTokensAtUseAlloc(
    allocator: std.mem.Allocator,
    all_tokens: []const BuildInputToken,
    use_index: usize,
    tokens: []const BuildInputToken,
    top_bindings: *const std.StringHashMap([]const u8),
) !?[]u8 {
    if (tokens.len != 1) return null;
    return switch (tokens[0].tag) {
        .string_literal => try decodeStringLiteralAlloc(allocator, tokens[0].lexeme),
        .identifier => try resolveVisibleStringBindingAlloc(
            allocator,
            all_tokens,
            use_index,
            tokens[0].lexeme,
            top_bindings,
        ),
        else => null,
    };
}

fn freeEmbedFileFunctionPatterns(
    allocator: std.mem.Allocator,
    patterns: []EmbedFileFunctionPattern,
) void {
    for (patterns) |*pattern| pattern.deinit(allocator);
    allocator.free(patterns);
}

fn freeImportedEmbedFileFunctionPatterns(
    allocator: std.mem.Allocator,
    patterns: []ImportedEmbedFnPattern,
) void {
    for (patterns) |*pattern| pattern.deinit(allocator);
    allocator.free(patterns);
}

fn freeBuildModuleBindings(
    allocator: std.mem.Allocator,
    bindings: []BuildModuleBinding,
) void {
    for (bindings) |*binding| binding.deinit(allocator);
    allocator.free(bindings);
}

fn appendUniqueIndex(indexes: *std.ArrayList(usize), allocator: std.mem.Allocator, value: usize) !void {
    for (indexes.items) |existing| {
        if (existing == value) return;
    }
    try indexes.append(allocator, value);
}

fn appendResolvedEmbedPathIfPresent(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    source_dir: []const u8,
    decoded: []const u8,
    collector: BuildInputPathCollector,
) !void {
    const resolved = try std.fs.path.resolve(allocator, &.{ repo_root, source_dir, decoded });
    defer allocator.free(resolved);

    const repo_relative = try tryRepoRelativePathFromAbsoluteAlloc(allocator, repo_root, resolved) orelse return;
    defer allocator.free(repo_relative);

    var root_dir = std.fs.openDirAbsolute(repo_root, .{}) catch |err|
        std.process.fatal("unable to open repo root for embed input scan '{s}': {s}", .{ repo_root, @errorName(err) });
    defer root_dir.close();
    if (!pathExistsAtRoot(root_dir, repo_relative)) return;
    try appendOwnedPathIfMissing(allocator, collector.paths, collector.path_set, repo_relative);
}

fn resolveRepoRelativeImportPathAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    source_dir: []const u8,
    decoded: []const u8,
) !?[]u8 {
    if (!std.mem.endsWith(u8, decoded, ".zig")) return null;

    const resolved = try std.fs.path.resolve(allocator, &.{ repo_root, source_dir, decoded });
    defer allocator.free(resolved);
    return try tryRepoRelativePathFromAbsoluteAlloc(allocator, repo_root, resolved);
}

fn appendResolvedImportPathIfPresent(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    source_dir: []const u8,
    decoded: []const u8,
    collector: BuildInputPathCollector,
) !void {
    const repo_relative = try resolveRepoRelativeImportPathAlloc(allocator, repo_root, source_dir, decoded) orelse return;
    defer allocator.free(repo_relative);
    try appendResolvedEmbedPathIfPresent(allocator, repo_root, ".", repo_relative, collector);
}

fn functionSourceSlice(
    tree: std.zig.Ast,
    source: [:0]const u8,
    member: std.zig.Ast.Node.Index,
    fn_proto: std.zig.Ast.full.FnProto,
) []const u8 {
    const start = tree.tokenStart(fn_proto.firstToken());
    const last = tree.lastToken(member);
    const end = tree.tokenStart(last) + @as(u32, @intCast(tree.tokenSlice(last).len));
    return source[start..end];
}

fn collectSameFileEmbedFunctionPatternsAlloc(
    allocator: std.mem.Allocator,
    source: [:0]const u8,
) ![]EmbedFileFunctionPattern {
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);

    var root_buffer: [2]std.zig.Ast.Node.Index = undefined;
    const root = tree.fullContainerDecl(&root_buffer, .root) orelse return allocator.alloc(EmbedFileFunctionPattern, 0);

    var patterns = std.ArrayList(EmbedFileFunctionPattern).empty;
    errdefer {
        for (patterns.items) |*pattern| {
            pattern.deinit(allocator);
        }
        patterns.deinit(allocator);
    }

    for (root.ast.members) |member| {
        var fn_buffer: [1]std.zig.Ast.Node.Index = undefined;
        const fn_proto = tree.fullFnProto(&fn_buffer, member) orelse continue;
        const fn_name_token = fn_proto.name_token orelse continue;

        var comptime_params = std.ArrayList(struct {
            name: []const u8,
            index: usize,
        }).empty;
        defer {
            for (comptime_params.items) |param| allocator.free(param.name);
            comptime_params.deinit(allocator);
        }

        var iter = fn_proto.iterate(&tree);
        var param_index: usize = 0;
        while (iter.next()) |param| : (param_index += 1) {
            if (param.comptime_noalias == null) continue;
            const name_token = param.name_token orelse continue;
            try comptime_params.append(allocator, .{
                .name = try allocator.dupe(u8, tree.tokenSlice(name_token)),
                .index = param_index,
            });
        }
        if (comptime_params.items.len == 0) continue;

        const fn_source = functionSourceSlice(tree, source, member, fn_proto);
        const fn_source_z = try allocator.dupeZ(u8, fn_source);
        defer allocator.free(fn_source_z);

        var tokenizer = std.zig.Tokenizer.init(fn_source_z);
        var window: BuildInputTokenWindow = .{};
        var matched_indexes = std.ArrayList(usize).empty;
        defer matched_indexes.deinit(allocator);

        while (true) {
            const token = tokenizer.next();
            if (token.tag == .eof) break;
            window.push(.{
                .tag = token.tag,
                .lexeme = tokenSlice(fn_source_z, token),
            });

            const identifier = maybeEmbedFileIdentifierPath(&window) orelse continue;
            for (comptime_params.items) |param| {
                if (!std.mem.eql(u8, identifier, param.name)) continue;
                try appendUniqueIndex(&matched_indexes, allocator, param.index);
            }
        }

        if (matched_indexes.items.len == 0) continue;

        try patterns.append(allocator, .{
            .fn_name = try allocator.dupe(u8, tree.tokenSlice(fn_name_token)),
            .path_param_indexes = try matched_indexes.toOwnedSlice(allocator),
        });
    }

    return try patterns.toOwnedSlice(allocator);
}

fn patternUsesParamIndex(pattern: *const EmbedFileFunctionPattern, index: usize) bool {
    for (pattern.path_param_indexes) |existing| {
        if (existing == index) return true;
    }
    return false;
}

fn importPathFromValueTokensAlloc(
    allocator: std.mem.Allocator,
    value_tokens: []const BuildInputToken,
) !?[]u8 {
    if (value_tokens.len != 4) return null;
    if (value_tokens[0].tag != .builtin or !std.mem.eql(u8, value_tokens[0].lexeme, "@import")) return null;
    if (value_tokens[1].tag != .l_paren or value_tokens[2].tag != .string_literal or value_tokens[3].tag != .r_paren) {
        return null;
    }
    return try decodeStringLiteralAlloc(allocator, value_tokens[2].lexeme);
}

fn moduleRootSourcePathFromExprTokensAlloc(
    allocator: std.mem.Allocator,
    expr_tokens: []const BuildInputToken,
) !?[]u8 {
    if (expr_tokens.len == 1 and expr_tokens[0].tag == .string_literal) {
        return try decodeStringLiteralAlloc(allocator, expr_tokens[0].lexeme);
    }
    if (expr_tokens.len == 6 and
        expr_tokens[0].tag == .identifier and
        expr_tokens[1].tag == .period and
        expr_tokens[2].tag == .identifier and
        std.mem.eql(u8, expr_tokens[2].lexeme, "path") and
        expr_tokens[3].tag == .l_paren and
        expr_tokens[4].tag == .string_literal and
        expr_tokens[5].tag == .r_paren)
    {
        return try decodeStringLiteralAlloc(allocator, expr_tokens[4].lexeme);
    }
    return null;
}

fn moduleRootSourcePathFromValueTokensAlloc(
    allocator: std.mem.Allocator,
    value_tokens: []const BuildInputToken,
) !?[]u8 {
    var index: usize = 0;
    while (index + 2 < value_tokens.len) : (index += 1) {
        if (value_tokens[index].tag != .period or
            value_tokens[index + 1].tag != .identifier or
            !std.mem.eql(u8, value_tokens[index + 1].lexeme, "root_source_file") or
            value_tokens[index + 2].tag != .equal)
        {
            continue;
        }

        const value_start = index + 3;
        var cursor = value_start;
        var depth: usize = 0;
        while (cursor < value_tokens.len) : (cursor += 1) {
            switch (value_tokens[cursor].tag) {
                .l_paren, .l_brace, .l_bracket => depth += 1,
                .r_paren, .r_brace, .r_bracket => {
                    if (depth == 0) break;
                    depth -= 1;
                },
                .comma => if (depth == 0) break,
                else => {},
            }
        }
        return try moduleRootSourcePathFromExprTokensAlloc(allocator, value_tokens[value_start..cursor]);
    }
    return null;
}

fn appendOwnedBuildModuleBinding(
    allocator: std.mem.Allocator,
    bindings: *std.ArrayList(BuildModuleBinding),
    alias: []const u8,
    repo_relative_source_path: []const u8,
) !void {
    for (bindings.items) |existing| {
        if (std.mem.eql(u8, existing.alias, alias)) return;
    }
    try bindings.append(allocator, .{
        .alias = try allocator.dupe(u8, alias),
        .repo_relative_source_path = try allocator.dupe(u8, repo_relative_source_path),
    });
}

fn collectBuildModuleBindingsAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
) ![]BuildModuleBinding {
    var root_dir = std.fs.openDirAbsolute(repo_root, .{}) catch return allocator.alloc(BuildModuleBinding, 0);
    defer root_dir.close();

    const source = root_dir.readFileAlloc(allocator, "build.zig", 4 * 1024 * 1024) catch return allocator.alloc(BuildModuleBinding, 0);
    defer allocator.free(source);
    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);

    var tree = try std.zig.Ast.parse(allocator, source_z, .zig);
    defer tree.deinit(allocator);

    var root_buffer: [2]std.zig.Ast.Node.Index = undefined;
    const root = tree.fullContainerDecl(&root_buffer, .root) orelse return allocator.alloc(BuildModuleBinding, 0);

    var build_fn_source: ?[]const u8 = null;
    for (root.ast.members) |member| {
        var fn_buffer: [1]std.zig.Ast.Node.Index = undefined;
        const fn_proto = tree.fullFnProto(&fn_buffer, member) orelse continue;
        const fn_name_token = fn_proto.name_token orelse continue;
        if (!std.mem.eql(u8, tree.tokenSlice(fn_name_token), "build")) continue;
        build_fn_source = functionSourceSlice(tree, source_z, member, fn_proto);
        break;
    }

    const build_source = build_fn_source orelse return allocator.alloc(BuildModuleBinding, 0);
    const build_source_z = try allocator.dupeZ(u8, build_source);
    defer allocator.free(build_source_z);
    const tokens = try collectBuildInputTokensAlloc(allocator, build_source_z);
    defer allocator.free(tokens);

    var bindings = std.ArrayList(BuildModuleBinding).empty;
    errdefer {
        for (bindings.items) |*binding| binding.deinit(allocator);
        bindings.deinit(allocator);
    }

    var module_vars = std.StringHashMap([]const u8).init(allocator);
    defer {
        var iter = module_vars.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        module_vars.deinit();
    }

    var index: usize = 0;
    var scope_depth: usize = 0;
    while (index < tokens.len) : (index += 1) {
        switch (tokens[index].tag) {
            .l_brace => {
                scope_depth += 1;
                continue;
            },
            .r_brace => {
                if (scope_depth > 0) scope_depth -= 1;
                continue;
            },
            else => {},
        }

        if (scope_depth == 1 and
            index + 1 < tokens.len and
            tokens[index].tag == .keyword_const and
            tokens[index + 1].tag == .identifier)
        {
            var cursor = index + 2;
            var depth: usize = 0;
            var equal_index: ?usize = null;
            var semicolon_index: ?usize = null;
            while (cursor < tokens.len) : (cursor += 1) {
                switch (tokens[cursor].tag) {
                    .l_paren, .l_brace, .l_bracket => depth += 1,
                    .r_paren, .r_brace, .r_bracket => {
                        if (depth > 0) depth -= 1;
                    },
                    .equal => {
                        if (depth == 0 and equal_index == null) equal_index = cursor;
                    },
                    .semicolon => {
                        if (depth == 0) {
                            semicolon_index = cursor;
                            break;
                        }
                    },
                    else => {},
                }
            }

            const value_start = equal_index orelse continue;
            const value_end = semicolon_index orelse continue;
            const value_tokens = tokens[value_start + 1 .. value_end];
            const root_source_path = try moduleRootSourcePathFromValueTokensAlloc(allocator, value_tokens) orelse continue;
            defer allocator.free(root_source_path);
            const repo_relative = try resolveRepoRelativeImportPathAlloc(allocator, repo_root, ".", root_source_path) orelse continue;
            defer allocator.free(repo_relative);

            const module_var = tokens[index + 1].lexeme;
            try module_vars.put(try allocator.dupe(u8, module_var), try allocator.dupe(u8, repo_relative));
            errdefer _ = module_vars.remove(module_var);
            try appendOwnedBuildModuleBinding(allocator, &bindings, module_var, repo_relative);

            if (value_tokens.len >= 6 and
                value_tokens[0].tag == .identifier and
                value_tokens[1].tag == .period and
                value_tokens[2].tag == .identifier and
                std.mem.eql(u8, value_tokens[2].lexeme, "addModule") and
                value_tokens[3].tag == .l_paren and
                value_tokens[4].tag == .string_literal)
            {
                const module_name = try decodeStringLiteralAlloc(allocator, value_tokens[4].lexeme) orelse continue;
                defer allocator.free(module_name);
                try appendOwnedBuildModuleBinding(allocator, &bindings, module_name, repo_relative);
            }
            continue;
        }

        if (scope_depth == 1 and
            index + 6 < tokens.len and
            tokens[index].tag == .identifier and
            tokens[index + 1].tag == .period and
            tokens[index + 2].tag == .identifier and
            std.mem.eql(u8, tokens[index + 2].lexeme, "addImport") and
            tokens[index + 3].tag == .l_paren and
            tokens[index + 4].tag == .string_literal and
            tokens[index + 5].tag == .comma and
            tokens[index + 6].tag == .identifier)
        {
            const import_alias = try decodeStringLiteralAlloc(allocator, tokens[index + 4].lexeme) orelse continue;
            defer allocator.free(import_alias);
            const module_var = tokens[index + 6].lexeme;
            const repo_relative = module_vars.get(module_var) orelse continue;
            try appendOwnedBuildModuleBinding(allocator, &bindings, import_alias, repo_relative);
        }
    }

    return try bindings.toOwnedSlice(allocator);
}

fn resolveBuildModuleImportPathAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    import_alias: []const u8,
) !?[]u8 {
    const bindings = try collectBuildModuleBindingsAlloc(allocator, repo_root);
    defer freeBuildModuleBindings(allocator, bindings);

    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.alias, import_alias)) {
            return try allocator.dupe(u8, binding.repo_relative_source_path);
        }
    }
    return null;
}

fn collectImportedEmbedFileFunctionPatternsAlloc(
    allocator: std.mem.Allocator,
    scan: BuildInputSourceScan,
) ![]ImportedEmbedFnPattern {
    var patterns = std.ArrayList(ImportedEmbedFnPattern).empty;
    errdefer {
        for (patterns.items) |*pattern| pattern.deinit(allocator);
        patterns.deinit(allocator);
    }

    const source_dir = std.fs.path.dirname(scan.source_path) orelse ".";
    var index: usize = 0;
    var scope_depth: usize = 0;
    while (index + 1 < scan.tokens.len) {
        switch (scan.tokens[index].tag) {
            .l_brace => {
                scope_depth += 1;
                index += 1;
                continue;
            },
            .r_brace => {
                if (scope_depth > 0) scope_depth -= 1;
                index += 1;
                continue;
            },
            else => {},
        }

        if (scope_depth != 0 or scan.tokens[index].tag != .keyword_const or scan.tokens[index + 1].tag != .identifier) {
            index += 1;
            continue;
        }

        var cursor = index + 2;
        var depth: usize = 0;
        var equal_index: ?usize = null;
        var semicolon_index: ?usize = null;
        while (cursor < scan.tokens.len) : (cursor += 1) {
            switch (scan.tokens[cursor].tag) {
                .l_paren, .l_brace, .l_bracket => depth += 1,
                .r_paren, .r_brace, .r_bracket => {
                    if (depth > 0) depth -= 1;
                },
                .equal => {
                    if (depth == 0 and equal_index == null) equal_index = cursor;
                },
                .semicolon => {
                    if (depth == 0) {
                        semicolon_index = cursor;
                        break;
                    }
                },
                else => {},
            }
        }

        const value_start = equal_index orelse {
            index += 1;
            continue;
        };
        const value_end = semicolon_index orelse {
            index += 1;
            continue;
        };
        const decoded = try importPathFromValueTokensAlloc(allocator, scan.tokens[value_start + 1 .. value_end]) orelse {
            index = value_end + 1;
            continue;
        };
        defer allocator.free(decoded);

        const repo_relative = (try resolveRepoRelativeImportPathAlloc(allocator, scan.repo_root, source_dir, decoded)) orelse
            (try resolveBuildModuleImportPathAlloc(allocator, scan.repo_root, decoded)) orelse
            {
                index = value_end + 1;
                continue;
            };
        defer allocator.free(repo_relative);
        if (!std.mem.endsWith(u8, repo_relative, ".zig")) {
            index = value_end + 1;
            continue;
        }

        const imported_source_full_path = try std.fs.path.join(allocator, &.{ scan.repo_root, repo_relative });
        defer allocator.free(imported_source_full_path);
        const imported_bytes = std.fs.cwd().readFileAlloc(allocator, imported_source_full_path, 1 << 20) catch |err| switch (err) {
            error.FileNotFound => {
                index = value_end + 1;
                continue;
            },
            else => return err,
        };
        defer allocator.free(imported_bytes);
        const imported_source_z = try allocator.dupeZ(u8, imported_bytes);
        defer allocator.free(imported_source_z);

        const imported_patterns = try collectSameFileEmbedFunctionPatternsAlloc(allocator, imported_source_z);
        defer allocator.free(imported_patterns);
        const imported_source_dir = std.fs.path.dirname(repo_relative) orelse ".";
        for (imported_patterns) |pattern| {
            try patterns.append(allocator, .{
                .module_binding = try allocator.dupe(u8, scan.tokens[index + 1].lexeme),
                .source_dir = try allocator.dupe(u8, imported_source_dir),
                .pattern = pattern,
            });
        }
        index = value_end + 1;
    }

    return try patterns.toOwnedSlice(allocator);
}

fn collectBuildInputTokensAlloc(
    allocator: std.mem.Allocator,
    source: [:0]const u8,
) ![]const BuildInputToken {
    var tokens = std.ArrayList(BuildInputToken).empty;
    errdefer tokens.deinit(allocator);

    var tokenizer = std.zig.Tokenizer.init(source);
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) break;
        try tokens.append(allocator, .{
            .tag = token.tag,
            .lexeme = tokenSlice(source, token),
        });
    }
    return try tokens.toOwnedSlice(allocator);
}

fn collectParameterizedEmbedFileBuildInputsForSource(
    allocator: std.mem.Allocator,
    scan: BuildInputSourceScan,
) !void {
    const Match = struct {
        pattern: *const EmbedFileFunctionPattern,
        call_source_dir: []const u8,
        arg_start: usize,
    };

    const patterns = try collectSameFileEmbedFunctionPatternsAlloc(allocator, scan.source);
    defer freeEmbedFileFunctionPatterns(allocator, patterns);
    const imported_patterns = try collectImportedEmbedFileFunctionPatternsAlloc(allocator, scan);
    defer freeImportedEmbedFileFunctionPatterns(allocator, imported_patterns);
    if (patterns.len == 0 and imported_patterns.len == 0) return;

    const source_dir = std.fs.path.dirname(scan.source_path) orelse ".";
    var index: usize = 0;
    while (index + 1 < scan.tokens.len) : (index += 1) {
        const match = (blk: {
            if (scan.tokens[index].tag == .identifier and scan.tokens[index + 1].tag == .l_paren) {
                if (index > 0 and scan.tokens[index - 1].tag == .keyword_fn) break :blk null;
                for (patterns) |*candidate| {
                    if (std.mem.eql(u8, candidate.fn_name, scan.tokens[index].lexeme)) {
                        break :blk Match{
                            .pattern = candidate,
                            .call_source_dir = source_dir,
                            .arg_start = index + 2,
                        };
                    }
                }
            }
            if (index + 3 < scan.tokens.len and
                scan.tokens[index].tag == .identifier and
                scan.tokens[index + 1].tag == .period and
                scan.tokens[index + 2].tag == .identifier and
                scan.tokens[index + 3].tag == .l_paren)
            {
                for (imported_patterns) |*candidate| {
                    if (!std.mem.eql(u8, candidate.module_binding, scan.tokens[index].lexeme)) continue;
                    if (!std.mem.eql(u8, candidate.pattern.fn_name, scan.tokens[index + 2].lexeme)) continue;
                    break :blk Match{
                        .pattern = &candidate.pattern,
                        .call_source_dir = candidate.source_dir,
                        .arg_start = index + 4,
                    };
                }
            }
            break :blk null;
        }) orelse continue;

        var arg_index: usize = 0;
        var arg_start = match.arg_start;
        var depth: usize = 0;
        var cursor = match.arg_start;
        while (cursor < scan.tokens.len) : (cursor += 1) {
            switch (scan.tokens[cursor].tag) {
                .l_paren, .l_brace, .l_bracket => depth += 1,
                .r_paren => {
                    if (depth == 0) {
                        if (patternUsesParamIndex(match.pattern, arg_index)) {
                            const arg_tokens = scan.tokens[arg_start..cursor];
                            const decoded = try resolveBuildInputStringTokensAtUseAlloc(
                                allocator,
                                scan.tokens,
                                arg_start,
                                arg_tokens,
                                scan.top_bindings,
                            ) orelse null;
                            if (decoded) |owned| {
                                defer allocator.free(owned);
                                try appendResolvedEmbedPathIfPresent(
                                    allocator,
                                    scan.repo_root,
                                    match.call_source_dir,
                                    owned,
                                    scan.collector,
                                );
                            }
                        }
                        index = cursor;
                        break;
                    }
                    depth -= 1;
                },
                .r_brace, .r_bracket => {
                    if (depth > 0) depth -= 1;
                },
                .comma => {
                    if (depth != 0) continue;
                    if (patternUsesParamIndex(match.pattern, arg_index)) {
                        const arg_tokens = scan.tokens[arg_start..cursor];
                        const decoded = try resolveBuildInputStringTokensAtUseAlloc(
                            allocator,
                            scan.tokens,
                            arg_start,
                            arg_tokens,
                            scan.top_bindings,
                        ) orelse null;
                        if (decoded) |owned| {
                            defer allocator.free(owned);
                            try appendResolvedEmbedPathIfPresent(
                                allocator,
                                scan.repo_root,
                                match.call_source_dir,
                                owned,
                                scan.collector,
                            );
                        }
                    }
                    arg_index += 1;
                    arg_start = cursor + 1;
                },
                else => {},
            }
        }
    }
}

fn collectEmbedFileBuildInputsForSource(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    source_path: []const u8,
    paths: *std.ArrayList([]const u8),
    path_set: *std.StringHashMap(void),
) !void {
    const source_full_path = try std.fs.path.join(allocator, &.{ repo_root, source_path });
    defer allocator.free(source_full_path);
    const bytes = try std.fs.cwd().readFileAlloc(allocator, source_full_path, 1 << 20);
    defer allocator.free(bytes);
    const source_z = try allocator.dupeZ(u8, bytes);
    defer allocator.free(source_z);

    const source_dir = std.fs.path.dirname(source_path) orelse ".";
    const collector: BuildInputPathCollector = .{
        .paths = paths,
        .path_set = path_set,
    };
    var scratch = std.heap.ArenaAllocator.init(allocator);
    errdefer scratch.deinit();
    defer scratch.deinit();
    const scratch_allocator = scratch.allocator();
    const tokens = try collectBuildInputTokensAlloc(allocator, source_z);
    defer allocator.free(tokens);
    var top_bindings = std.StringHashMap([]const u8).init(scratch_allocator);
    errdefer top_bindings.deinit();
    defer top_bindings.deinit();
    try populateTopLevelSimpleStringBindings(scratch_allocator, tokens, &top_bindings);
    var window: BuildInputTokenWindow = .{};
    var token_index: usize = 0;
    while (token_index < tokens.len) : (token_index += 1) {
        window.push(tokens[token_index]);

        if (windowMatchesEmbedFileSelf(&window)) {
            try appendOwnedPathIfMissing(allocator, paths, path_set, source_path);
            continue;
        }

        if (maybeImportLiteralPath(&window)) |literal| {
            const decoded = try decodeStringLiteralAlloc(allocator, literal) orelse continue;
            defer allocator.free(decoded);
            try appendResolvedImportPathIfPresent(allocator, repo_root, source_dir, decoded, collector);
            continue;
        }

        if (maybeEmbedFileIdentifierPath(&window)) |identifier| {
            const decoded = try resolveVisibleStringBindingAlloc(
                allocator,
                tokens,
                token_index,
                identifier,
                &top_bindings,
            ) orelse null;
            if (decoded) |owned| {
                defer allocator.free(owned);
                try appendResolvedEmbedPathIfPresent(allocator, repo_root, source_dir, owned, collector);
                continue;
            }
        }

        if (maybeEmbedFileLiteralPath(&window)) |literal| {
            const decoded = try decodeStringLiteralAlloc(allocator, literal) orelse continue;
            defer allocator.free(decoded);
            try appendResolvedEmbedPathIfPresent(allocator, repo_root, source_dir, decoded, collector);
        }
    }

    try collectParameterizedEmbedFileBuildInputsForSource(allocator, .{
        .repo_root = repo_root,
        .source_path = source_path,
        .source = source_z,
        .tokens = tokens,
        .collector = collector,
        .top_bindings = &top_bindings,
    });
}

fn pathIsIgnoredBuildInput(path: []const u8) bool {
    return std.mem.eql(u8, path, ".git") or
        std.mem.startsWith(u8, path, ".git/") or
        std.mem.eql(u8, path, ".zig-cache") or
        std.mem.startsWith(u8, path, ".zig-cache/") or
        std.mem.eql(u8, path, "zig-out") or
        std.mem.startsWith(u8, path, "zig-out/");
}

fn collectFilesystemRepoZigPaths(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    paths: *std.ArrayList([]const u8),
    path_set: *std.StringHashMap(void),
) void {
    var root_dir = std.fs.openDirAbsolute(repo_root, .{ .iterate = true }) catch |err|
        std.process.fatal("unable to open repo root for build input walk '{s}': {s}", .{ repo_root, @errorName(err) });
    defer root_dir.close();

    var walker = root_dir.walk(allocator) catch
        std.process.fatal("unable to walk repo root for build inputs", .{});
    defer walker.deinit();

    while (walker.next() catch
        std.process.fatal("unable to iterate repo build input walk", .{})) |entry|
    {
        if (pathIsIgnoredBuildInput(entry.path)) continue;
        switch (entry.kind) {
            .file, .sym_link => {},
            else => continue,
        }
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;
        appendOwnedPathIfMissing(allocator, paths, path_set, entry.path) catch
            std.process.fatal("unable to record repo Zig build input path", .{});
    }
}

fn collectBuildZigReferencedRepoZigPaths(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    paths: *std.ArrayList([]const u8),
    path_set: *std.StringHashMap(void),
) void {
    var root_dir = std.fs.openDirAbsolute(repo_root, .{}) catch return;
    defer root_dir.close();

    const source = root_dir.readFileAlloc(allocator, "build.zig", 4 * 1024 * 1024) catch return;
    defer allocator.free(source);
    const source_z = allocator.dupeZ(u8, source) catch
        std.process.fatal("unable to duplicate build.zig source for build input scan", .{});
    defer allocator.free(source_z);

    var tree = std.zig.Ast.parse(allocator, source_z, .zig) catch
        std.process.fatal("unable to parse build.zig for build input scan", .{});
    defer tree.deinit(allocator);

    var root_buffer: [2]std.zig.Ast.Node.Index = undefined;
    const root = tree.fullContainerDecl(&root_buffer, .root) orelse return;

    var build_fn_source: ?[]const u8 = null;
    for (root.ast.members) |member| {
        var fn_buffer: [1]std.zig.Ast.Node.Index = undefined;
        const fn_proto = tree.fullFnProto(&fn_buffer, member) orelse continue;
        const fn_name_token = fn_proto.name_token orelse continue;
        if (!std.mem.eql(u8, tree.tokenSlice(fn_name_token), "build")) continue;
        build_fn_source = functionSourceSlice(tree, source_z, member, fn_proto);
        break;
    }

    const build_source = build_fn_source orelse return;
    const build_source_z = allocator.dupeZ(u8, build_source) catch
        std.process.fatal("unable to duplicate build() source for build input scan", .{});
    defer allocator.free(build_source_z);
    const tokens = collectBuildInputTokensAlloc(allocator, build_source_z) catch
        std.process.fatal("unable to tokenize build() source for build input scan", .{});
    defer allocator.free(tokens);

    const collector: BuildInputPathCollector = .{
        .paths = paths,
        .path_set = path_set,
    };
    for (tokens) |token| {
        if (token.tag != .string_literal) continue;
        const decoded = decodeStringLiteralAlloc(allocator, token.lexeme) catch
            std.process.fatal("unable to decode build() path literal for build input scan", .{}) orelse continue;
        defer allocator.free(decoded);
        appendResolvedImportPathIfPresent(allocator, repo_root, ".", decoded, collector) catch
            std.process.fatal("unable to record build() referenced repo Zig path", .{});
    }
}

fn collectTrackedRepoZigPathsAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    paths: *std.ArrayList([]const u8),
    path_set: *std.StringHashMap(void),
) bool {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "-C", repo_root, "ls-files", "--cached", "--", "*.zig" },
        .max_output_bytes = 512 * 1024,
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code != 0) return false,
        else => return false,
    }

    var root_dir = std.fs.openDirAbsolute(repo_root, .{}) catch return false;
    defer root_dir.close();

    var lines = std.mem.tokenizeScalar(u8, result.stdout, '\n');
    while (lines.next()) |line| {
        if (!std.mem.endsWith(u8, line, ".zig")) continue;
        if (!pathExistsAtRoot(root_dir, line)) continue;
        appendOwnedPathIfMissing(allocator, paths, path_set, line) catch
            std.process.fatal("unable to record tracked repo Zig path", .{});
    }
    return true;
}

fn collectRepoZigPathsFromRegistryFile(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    paths: *std.ArrayList([]const u8),
    path_set: *std.StringHashMap(void),
) bool {
    var root_dir = std.fs.openDirAbsolute(repo_root, .{}) catch return false;
    defer root_dir.close();

    const registry = root_dir.readFileAlloc(allocator, "repo_zig_paths.txt", 512 * 1024) catch return false;
    defer allocator.free(registry);

    var lines = std.mem.tokenizeScalar(u8, registry, '\n');
    while (lines.next()) |line| {
        if (!std.mem.endsWith(u8, line, ".zig")) continue;
        if (!pathExistsAtRoot(root_dir, line)) continue;
        appendOwnedPathIfMissing(allocator, paths, path_set, line) catch
            std.process.fatal("unable to record committed repo Zig path", .{});
    }
    return true;
}

fn collectRepoZigPathsAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    paths: *std.ArrayList([]const u8),
    path_set: *std.StringHashMap(void),
) void {
    if (!collectTrackedRepoZigPathsAlloc(allocator, repo_root, paths, path_set)) {
        if (!collectRepoZigPathsFromRegistryFile(allocator, repo_root, paths, path_set)) {
            collectFilesystemRepoZigPaths(allocator, repo_root, paths, path_set);
        }
    }
}

fn artifactBuildInputPathsAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
) []const []const u8 {
    var paths = std.ArrayList([]const u8).empty;
    var path_set = std.StringHashMap(void).init(allocator);
    defer path_set.deinit();

    collectRepoZigPathsAlloc(allocator, repo_root, &paths, &path_set);
    collectBuildZigReferencedRepoZigPaths(allocator, repo_root, &paths, &path_set);

    var index: usize = 0;
    while (index < paths.items.len) : (index += 1) {
        if (!std.mem.endsWith(u8, paths.items[index], ".zig")) continue;
        collectEmbedFileBuildInputsForSource(
            allocator,
            repo_root,
            paths.items[index],
            &paths,
            &path_set,
        ) catch std.process.fatal("unable to collect embedded build inputs from '{s}'", .{paths.items[index]});
    }

    sortOwnedPaths(paths.items);
    return paths.toOwnedSlice(allocator) catch
        std.process.fatal("unable to allocate artifact build input path list", .{});
}

fn hashArtifactBuildInputs(
    hasher: *std.crypto.hash.Blake3,
    allocator: std.mem.Allocator,
    repo_root: []const u8,
) void {
    const input_paths = artifactBuildInputPathsAlloc(allocator, repo_root);
    defer freeOwnedPathList(allocator, input_paths);

    for (input_paths) |path| {
        hashBuildIdentityFileAtRoot(hasher, repo_root, path);
    }

    var root_dir = std.fs.openDirAbsolute(repo_root, .{}) catch |err|
        std.process.fatal("unable to open repo root for build metadata '{s}': {s}", .{ repo_root, @errorName(err) });
    defer root_dir.close();
    if (pathExistsAtRoot(root_dir, "build.zig.zon")) {
        hashBuildIdentityFileAtRoot(hasher, repo_root, "build.zig.zon");
    }
}

fn artifactBuildInputFingerprint(allocator: std.mem.Allocator, repo_root: []const u8) [32]u8 {
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update("shift-artifact-build-input-fingerprint-v1");
    hashArtifactBuildInputs(&hasher, allocator, repo_root);
    var digest = std.mem.zeroes([32]u8);
    hasher.final(&digest);
    return digest;
}

fn hashBuildTargetIdentity(
    hasher: *std.crypto.hash.Blake3,
    b: *std.Build,
    target: std.Build.ResolvedTarget,
) void {
    const query_triple = target.query.zigTriple(b.allocator) catch
        std.process.fatal("unable to serialize build target query triple", .{});
    defer b.allocator.free(query_triple);
    const query_cpu = target.query.serializeCpuAlloc(b.allocator) catch
        std.process.fatal("unable to serialize build target query cpu", .{});
    defer b.allocator.free(query_cpu);
    const result_triple = target.result.zigTriple(b.allocator) catch
        std.process.fatal("unable to serialize resolved build target triple", .{});
    defer b.allocator.free(result_triple);
    const result_cpu = std.zig.serializeCpuAlloc(b.allocator, target.result.cpu) catch
        std.process.fatal("unable to serialize resolved build target cpu", .{});
    defer b.allocator.free(result_cpu);

    hasher.update("query-triple");
    hasher.update(query_triple);
    hasher.update("query-cpu");
    hasher.update(query_cpu);
    hasher.update("query-ofmt");
    if (target.query.ofmt) |ofmt| {
        hasher.update(@tagName(ofmt));
    } else {
        hasher.update("default");
    }
    hasher.update("query-dynamic-linker");
    if (target.query.dynamic_linker.get()) |dynamic_linker| {
        hasher.update(dynamic_linker);
    } else {
        hasher.update("(none)");
    }

    hasher.update("resolved-triple");
    hasher.update(result_triple);
    hasher.update("resolved-cpu");
    hasher.update(result_cpu);
    hasher.update("resolved-ofmt");
    hasher.update(@tagName(target.result.ofmt));
    hasher.update("resolved-dynamic-linker");
    if (target.result.dynamic_linker.get()) |dynamic_linker| {
        hasher.update(dynamic_linker);
    } else {
        hasher.update("(none)");
    }
}

fn defaultArtifactBuildFingerprint(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) [32]u8 {
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update("shift-default-artifact-build-fingerprint-v2");
    hasher.update(builtin.zig_version_string);
    hasher.update(@tagName(optimize));
    hashBuildTargetIdentity(&hasher, b, target);
    hashArtifactBuildInputs(&hasher, b.allocator, b.pathFromRoot("."));

    var digest = std.mem.zeroes([32]u8);
    hasher.final(&digest);
    return digest;
}

fn repoZigPathRegistryAlloc(allocator: std.mem.Allocator, repo_root: []const u8) []const u8 {
    var paths = std.ArrayList([]const u8).empty;
    var path_set = std.StringHashMap(void).init(allocator);
    defer path_set.deinit();

    collectRepoZigPathsAlloc(allocator, repo_root, &paths, &path_set);
    defer {
        for (paths.items) |path| allocator.free(path);
        paths.deinit(allocator);
    }

    sortOwnedPaths(paths.items);

    var registry = std.ArrayList(u8).empty;
    for (paths.items) |path| {
        registry.appendSlice(allocator, path) catch
            std.process.fatal("unable to append repo source path", .{});
        registry.append(allocator, '\n') catch
            std.process.fatal("unable to append repo source separator", .{});
    }
    return registry.toOwnedSlice(allocator) catch
        std.process.fatal("unable to allocate repo source path registry", .{});
}

fn repoZigPathRegistry(b: *std.Build) []const u8 {
    return repoZigPathRegistryAlloc(b.allocator, b.pathFromRoot("."));
}

fn zigLintPathExcluded(path: []const u8) bool {
    if (std.mem.startsWith(u8, path, ".zig-cache/")) return true;
    if (std.mem.startsWith(u8, path, "zig-cache/")) return true;
    if (std.mem.startsWith(u8, path, ".zig-global-cache/")) return true;
    if (std.mem.startsWith(u8, path, "zig-global-cache/")) return true;
    if (std.mem.eql(u8, path, "src/error_witness.zig")) return true;
    if (std.mem.eql(u8, path, "src/op_compat.zig")) return true;
    if (std.mem.eql(u8, path, "src/public_ir.zig")) return true;
    if (std.mem.eql(u8, path, "src/public_lowering.zig")) return true;
    if (std.mem.eql(u8, path, "src/program_api_compat.zig")) return true;
    if (std.mem.eql(u8, path, "src/program_api.zig")) return true;
    if (std.mem.eql(u8, path, "src/root.zig")) return true;
    return false;
}

fn repoZigLintIncludePaths(b: *std.Build) []const std.Build.LazyPath {
    const registry = repoZigPathRegistry(b);
    var includes = std.ArrayList(std.Build.LazyPath).empty;
    var lines = std.mem.tokenizeScalar(u8, registry, '\n');
    while (lines.next()) |line| {
        if (!std.mem.endsWith(u8, line, ".zig")) continue;
        if (zigLintPathExcluded(line)) continue;
        includes.append(b.allocator, b.path(line)) catch
            std.process.fatal("unable to record repo Zig lint path", .{});
    }
    return includes.toOwnedSlice(b.allocator) catch
        std.process.fatal("unable to allocate repo Zig lint path list", .{});
}

const PackageRootAlias = struct {
    path: []const u8,
    available: bool,
};

fn scratchRootPath(b: *std.Build, leaf: []const u8) []const u8 {
    return std.fs.path.join(b.allocator, &.{ "/tmp", leaf }) catch
        std.process.fatal("unable to allocate scratch root path", .{});
}

fn boundaryAliasRoot(b: *std.Build) []const u8 {
    return scratchRootPath(b, ".shift_aliases");
}

fn externalBoundaryFixtureNamespace(allocator: std.mem.Allocator, repo_root: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "shift_repo_{x}",
        .{std.hash.Wyhash.hash(0, repo_root)},
    );
}

fn externalBoundaryFixtureRootPath(allocator: std.mem.Allocator, fixture_root: []const u8, repo_root: []const u8) ![]u8 {
    const fixture_namespace = try externalBoundaryFixtureNamespace(allocator, repo_root);
    defer allocator.free(fixture_namespace);
    return std.fs.path.join(
        allocator,
        &.{ fixture_root, fixture_namespace },
    );
}

fn externalBoundaryFixtureRoot(b: *std.Build) []const u8 {
    const repo_root = b.pathFromRoot(".");
    const fixture_root = scratchRootPath(b, ".shift_external_boundary_fixtures");
    return externalBoundaryFixtureRootPath(b.allocator, fixture_root, repo_root) catch
        std.process.fatal("unable to allocate external boundary fixture root", .{});
}

fn clearAliasPath(alias_path: []const u8, dir_error: []const u8, path_error: []const u8) void {
    std.fs.deleteFileAbsolute(alias_path) catch |err| switch (err) {
        error.FileNotFound => {},
        error.IsDir => std.fs.deleteTreeAbsolute(alias_path) catch
            std.process.fatal("{s}", .{dir_error}),
        else => std.process.fatal("{s}", .{path_error}),
    };
}

fn packageRootAlias(b: *std.Build) PackageRootAlias {
    const repo_root = b.pathFromRoot(".");
    const alias_root = boundaryAliasRoot(b);
    std.fs.makeDirAbsolute(alias_root) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return .{ .path = repo_root, .available = false },
    };
    const alias_leaf = std.fmt.allocPrint(
        b.allocator,
        "shift_repo_alias_{x}",
        .{std.hash.Wyhash.hash(0, repo_root)},
    ) catch std.process.fatal("unable to allocate package-root alias leaf", .{});
    const alias_path = std.fs.path.join(b.allocator, &.{ alias_root, alias_leaf }) catch
        std.process.fatal("unable to allocate package-root alias path", .{});

    var link_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const existing_target = std.fs.readLinkAbsolute(alias_path, &link_buffer) catch |err| switch (err) {
        error.FileNotFound => null,
        else => blk: {
            clearAliasPath(alias_path, "unable to clear package-root alias directory", "unable to clear package-root alias path");
            break :blk null;
        },
    };
    if (existing_target) |target| {
        if (std.mem.eql(u8, target, repo_root)) return .{
            .path = alias_path,
            .available = true,
        };
    }

    clearAliasPath(alias_path, "unable to clear package-root alias directory", "unable to clear package-root alias path");
    std.fs.symLinkAbsolute(repo_root, alias_path, .{}) catch
        return .{ .path = repo_root, .available = false };
    return .{
        .path = alias_path,
        .available = true,
    };
}

fn addWriteTextFileCommand(
    b: *std.Build,
    path: []const u8,
    contents: []const u8,
    name: []const u8,
) *std.Build.Step {
    return &WriteTextFileStep.create(b, path, contents, name).step;
}

fn addAbsoluteSymlinkCommand(
    b: *std.Build,
    target_path: []const u8,
    link_path: []const u8,
    name: []const u8,
) *std.Build.Step {
    return &AbsoluteSymlinkStep.create(b, target_path, link_path, name).step;
}

const WriteTextFileStep = struct {
    step: std.Build.Step,
    path: []const u8,
    contents: []const u8,

    fn create(b: *std.Build, path: []const u8, contents: []const u8, name: []const u8) *WriteTextFileStep {
        const self = b.allocator.create(WriteTextFileStep) catch
            std.process.fatal("unable to allocate write-text build step", .{});
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = name,
                .owner = b,
                .makeFn = make,
            }),
            .path = b.dupePath(path),
            .contents = b.dupe(contents),
        };
        return self;
    }

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) !void {
        const self: *WriteTextFileStep = @fieldParentPtr("step", step);
        if (std.fs.path.dirname(self.path)) |dir_name| {
            try std.fs.cwd().makePath(dir_name);
        }
        var file = if (std.fs.path.isAbsolute(self.path))
            try std.fs.createFileAbsolute(self.path, .{ .truncate = true })
        else
            try std.fs.cwd().createFile(self.path, .{ .truncate = true });
        defer file.close();
        var buffer: [4096]u8 = undefined;
        var writer = file.writer(&buffer);
        try writer.interface.writeAll(self.contents);
        try writer.interface.flush();
    }
};

const AbsoluteSymlinkStep = struct {
    step: std.Build.Step,
    target_path: []const u8,
    link_path: []const u8,

    fn create(b: *std.Build, target_path: []const u8, link_path: []const u8, name: []const u8) *AbsoluteSymlinkStep {
        const self = b.allocator.create(AbsoluteSymlinkStep) catch
            std.process.fatal("unable to allocate absolute-symlink build step", .{});
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = name,
                .owner = b,
                .makeFn = make,
            }),
            .target_path = b.dupePath(target_path),
            .link_path = b.dupePath(link_path),
        };
        return self;
    }

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) !void {
        const self: *AbsoluteSymlinkStep = @fieldParentPtr("step", step);
        if (std.fs.path.dirname(self.link_path)) |dir_name| {
            try std.fs.cwd().makePath(dir_name);
        }
        clearAliasPath(
            self.link_path,
            "unable to clear fixture symlink directory",
            "unable to clear fixture symlink path",
        );
        try std.fs.symLinkAbsolute(self.target_path, self.link_path, .{});
    }
};

fn compileFailEscapeProbeLinkPath(allocator: std.mem.Allocator, fixture_link_path: []const u8) ![]u8 {
    const fixture_dir = std.fs.path.dirname(fixture_link_path) orelse return error.MissingCompileFailFixtureDir;
    return std.fs.path.join(
        allocator,
        &.{ fixture_dir, ".compile_fail_escape_helper_probe_link.zig" },
    );
}

fn compileFailEscapeSymlinkSupported(
    b: *std.Build,
    target_path: []const u8,
    fixture_link_path: []const u8,
) bool {
    const probe_link_path = compileFailEscapeProbeLinkPath(b.allocator, fixture_link_path) catch
        std.process.fatal("unable to allocate compile-fail helper probe link path", .{});
    defer clearAliasPath(
        probe_link_path,
        "unable to clear compile-fail helper probe symlink directory",
        "unable to clear compile-fail helper probe symlink path",
    );
    return ensureOptionalAbsoluteSymlink(
        b.allocator,
        target_path,
        probe_link_path,
        "unable to clear compile-fail helper probe symlink directory",
        "unable to clear compile-fail helper probe symlink path",
    );
}

fn ensureOptionalAbsoluteSymlink(
    allocator: std.mem.Allocator,
    target_path: []const u8,
    link_path: []const u8,
    dir_error: []const u8,
    path_error: []const u8,
) bool {
    var owned_absolute_target: ?[]u8 = null;
    defer if (owned_absolute_target) |path| allocator.free(path);
    const absolute_target = if (std.fs.path.isAbsolute(target_path))
        target_path
    else blk: {
        owned_absolute_target = std.fs.cwd().realpathAlloc(allocator, target_path) catch return false;
        break :blk owned_absolute_target.?;
    };

    var link_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const existing_target = std.fs.readLinkAbsolute(link_path, &link_buffer) catch |err| switch (err) {
        error.FileNotFound => null,
        else => blk: {
            clearAliasPath(link_path, dir_error, path_error);
            break :blk null;
        },
    };
    if (existing_target) |existing| {
        if (std.mem.eql(u8, existing, absolute_target)) return true;
    }

    clearAliasPath(link_path, dir_error, path_error);
    std.fs.symLinkAbsolute(absolute_target, link_path, .{}) catch return false;
    return true;
}

fn zigStringLiteralEscapeAlloc(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var escaped = std.ArrayList(u8).empty;
    defer escaped.deinit(allocator);

    for (value) |byte| switch (byte) {
        '\\' => try escaped.appendSlice(allocator, "\\\\"),
        '"' => try escaped.appendSlice(allocator, "\\\""),
        '\n' => try escaped.appendSlice(allocator, "\\n"),
        '\r' => try escaped.appendSlice(allocator, "\\r"),
        '\t' => try escaped.appendSlice(allocator, "\\t"),
        else => try escaped.append(allocator, byte),
    };

    return try escaped.toOwnedSlice(allocator);
}

fn normalizeSourceForHashAlloc(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var in_string = false;
    var escaped = false;
    var idx: usize = 0;
    while (idx < source.len) : (idx += 1) {
        const byte = source[idx];
        if (in_string) {
            try out.append(allocator, byte);
            if (escaped) {
                escaped = false;
            } else if (byte == '\\') {
                escaped = true;
            } else if (byte == '"') {
                in_string = false;
            }
            continue;
        }

        if (byte == '"') {
            in_string = true;
            try out.append(allocator, byte);
            continue;
        }
        if (byte == '/' and idx + 1 < source.len and source[idx + 1] == '/') {
            idx += 2;
            while (idx < source.len and source[idx] != '\n') : (idx += 1) {}
            continue;
        }
        if (std.ascii.isWhitespace(byte)) continue;
        try out.append(allocator, byte);
    }

    return try out.toOwnedSlice(allocator);
}

test "zigStringLiteralEscapeAlloc escapes path bytes for generated fixture source" {
    const escaped = try zigStringLiteralEscapeAlloc(
        std.testing.allocator,
        "C:\\Users\\\"tk\"\\shift\\downstream_public_lowering_test.zig",
    );
    defer std.testing.allocator.free(escaped);

    try std.testing.expectEqualStrings(
        "C:\\\\Users\\\\\\\"tk\\\"\\\\shift\\\\downstream_public_lowering_test.zig",
        escaped,
    );
}

test "externalBoundaryFixtureRootPath namespaces sibling checkouts" {
    const first = try externalBoundaryFixtureRootPath(
        std.testing.allocator,
        "/tmp/shift-cache",
        "/tmp/shift-parent/shift-a",
    );
    defer std.testing.allocator.free(first);
    const second = try externalBoundaryFixtureRootPath(
        std.testing.allocator,
        "/tmp/shift-cache",
        "/tmp/shift-parent/shift-b",
    );
    defer std.testing.allocator.free(second);

    try std.testing.expect(std.mem.startsWith(
        u8,
        first,
        "/tmp/shift-cache/shift_external_boundary_fixtures/",
    ));
    try std.testing.expect(std.mem.startsWith(
        u8,
        second,
        "/tmp/shift-cache/shift_external_boundary_fixtures/",
    ));
    try std.testing.expect(!std.mem.eql(u8, first, second));
}

test "ensureOptionalAbsoluteSymlink resolves relative targets before linking" {
    const repo_root = try makeExternalTmpDir(std.testing.allocator);
    defer std.testing.allocator.free(repo_root);
    defer runChildExpectSuccess(std.testing.allocator, &.{ "rm", "-rf", repo_root }) catch unreachable;

    var repo_dir = try std.fs.openDirAbsolute(repo_root, .{});
    defer repo_dir.close();
    try writeTmpFile(repo_dir, "target.txt", "ok\n");

    const target_path = try std.fs.path.join(std.testing.allocator, &.{ repo_root, "target.txt" });
    defer std.testing.allocator.free(target_path);
    const canonical_target_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, target_path);
    defer std.testing.allocator.free(canonical_target_path);
    const link_path = try std.fs.path.join(std.testing.allocator, &.{ repo_root, "target.link" });
    defer std.testing.allocator.free(link_path);
    defer clearAliasPath(
        link_path,
        "unable to clear relative target symlink directory",
        "unable to clear relative target symlink path",
    );

    const cwd = try std.process.getCwdAlloc(std.testing.allocator);
    defer std.testing.allocator.free(cwd);
    const relative_target = try std.fs.path.relative(std.testing.allocator, cwd, target_path);
    defer std.testing.allocator.free(relative_target);

    try std.testing.expect(ensureOptionalAbsoluteSymlink(
        relative_target,
        link_path,
        "unable to clear relative target symlink directory",
        "unable to clear relative target symlink path",
    ));

    var link_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const existing_target = try std.fs.readLinkAbsolute(link_path, &link_buffer);
    try std.testing.expectEqualStrings(canonical_target_path, existing_target);
}

test "compileFailEscapeProbeLinkPath stays in the fixture directory" {
    const probe_path = try compileFailEscapeProbeLinkPath(
        std.testing.allocator,
        "/tmp/shift/test/compile_fail_inputs/.compile_fail_escape_helper_link.zig",
    );
    defer std.testing.allocator.free(probe_path);

    try std.testing.expectEqualStrings(
        "/tmp/shift/test/compile_fail_inputs/.compile_fail_escape_helper_probe_link.zig",
        probe_path,
    );
}

fn writeTmpFile(dir: std.fs.Dir, path: []const u8, contents: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir_name| {
        try dir.makePath(dir_name);
    }
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [1024]u8 = undefined;
    var writer = file.writer(&buffer);
    try writer.interface.writeAll(contents);
    try writer.interface.flush();
}

fn runChildExpectSuccess(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .max_output_bytes = 32 * 1024,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code == 0) return,
        else => {},
    }
    std.debug.print("child command failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ argv[0], result.stdout, result.stderr });
    return error.UnexpectedChildCommandFailure;
}

fn makeExternalTmpDir(allocator: std.mem.Allocator) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "mktemp", "-d" },
        .max_output_bytes = 1024,
    });
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code != 0) {
            allocator.free(result.stdout);
            return error.UnexpectedChildCommandFailure;
        },
        else => {
            allocator.free(result.stdout);
            return error.UnexpectedChildCommandFailure;
        },
    }

    const trimmed = std.mem.trimEnd(u8, result.stdout, "\r\n");
    const owned = try allocator.dupe(u8, trimmed);
    allocator.free(result.stdout);
    return owned;
}

test "artifact build fingerprint changes on raw-byte-only Zig edits" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\pub fn main() void {
        \\    const self = @embedFile(@src().file);
        \\    _ = self;
        \\}
        \\
    );
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "probe.zig", "build.zig.zon" });

    const before = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "probe.zig",
        \\// whitespace/comment-only edit must still perturb exact-build identity
        \\pub fn main() void {
        \\    const self = @embedFile(@src().file);
        \\    _ = self;
        \\}
        \\
    );
    const after = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before, &after));
}

test "artifact build fingerprint includes embedded non-Zig inputs and excludes untracked Zig scratch" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\pub fn main() void {
        \\    const schema = @embedFile("schema.json");
        \\    _ = schema;
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "schema.json", "{ \"version\": 1 }\n");
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "probe.zig", "build.zig.zon" });

    const before_asset = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "schema.json", "{ \"version\": 2 }\n");
    const after_asset = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before_asset, &after_asset));

    const before_untracked_zig = after_asset;
    try writeTmpFile(tmp.dir, "helper.zig",
        \\pub fn helper() void {}
        \\
    );
    const after_untracked_zig = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expectEqualSlices(u8, &before_untracked_zig, &after_untracked_zig);
}

test "artifact build fingerprint includes imported untracked Zig inputs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\const helper = @import("helper.zig");
        \\
        \\pub fn main() void {
        \\    helper.touch();
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "helper.zig",
        \\pub fn touch() void {}
        \\
    );
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "probe.zig", "build.zig.zon" });

    const before = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "helper.zig",
        \\pub fn touch() void {
        \\    _ = 1;
        \\}
        \\
    );
    const after = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before, &after));
}

test "artifact build fingerprint includes build.zig-wired untracked Zig modules" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const helper = b.addModule("helper", .{
        \\        .root_source_file = b.path("helper.zig"),
        \\    });
        \\    const probe = b.addModule("probe", .{
        \\        .root_source_file = b.path("probe.zig"),
        \\    });
        \\    probe.addImport("helper", helper);
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\const helper = @import("helper");
        \\
        \\pub fn main() void {
        \\    helper.touch();
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "helper.zig",
        \\pub fn touch() void {}
        \\
    );
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "build.zig", "build.zig.zon", "probe.zig" });

    const before = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "helper.zig",
        \\pub fn touch() void {
        \\    _ = 1;
        \\}
        \\
    );
    const after = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before, &after));
}

test "artifact build fingerprint includes build.zig-wired module-name helper wrapper embed inputs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const helper = b.addModule("helper", .{
        \\        .root_source_file = b.path("helpers/helper.zig"),
        \\    });
        \\    const probe = b.addModule("probe", .{
        \\        .root_source_file = b.path("probe.zig"),
        \\    });
        \\    probe.addImport("helper", helper);
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\const helper = @import("helper");
        \\
        \\pub fn main() void {
        \\    const schema = helper.fixture("schema.json");
        \\    _ = schema;
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "helpers/helper.zig",
        \\pub fn fixture(comptime rel: []const u8) []const u8 {
        \\    return @embedFile(rel);
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "helpers/schema.json", "{ \"version\": 1 }\n");
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "build.zig", "build.zig.zon", "probe.zig" });

    const before = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "helpers/schema.json", "{ \"version\": 2 }\n");
    const after = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before, &after));
}

test "artifact build fingerprint includes same-file comptime parameter embed inputs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\fn fixture(comptime rel: []const u8) []const u8 {
        \\    return @embedFile(rel);
        \\}
        \\
        \\pub fn main() void {
        \\    const schema = fixture("schema.json");
        \\    _ = schema;
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "schema.json", "{ \"version\": 1 }\n");
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "probe.zig", "build.zig.zon" });

    const before = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "schema.json", "{ \"version\": 2 }\n");
    const after = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before, &after));
}

test "artifact build fingerprint includes imported helper wrapper embed inputs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\const helper = @import("helpers/helper.zig");
        \\
        \\pub fn main() void {
        \\    const schema = helper.fixture("schema.json");
        \\    _ = schema;
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "helpers/helper.zig",
        \\pub fn fixture(comptime rel: []const u8) []const u8 {
        \\    return @embedFile(rel);
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "helpers/schema.json", "{ \"version\": 1 }\n");
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "probe.zig", "build.zig.zon" });

    const before = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "helpers/schema.json", "{ \"version\": 2 }\n");
    const after = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before, &after));
}

test "artifact build fingerprint includes identifier-backed embed inputs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\const direct_path = "direct.json";
        \\const wrapped_path = "wrapped.json";
        \\
        \\fn fixture(comptime rel: []const u8) []const u8 {
        \\    return @embedFile(rel);
        \\}
        \\
        \\pub fn main() void {
        \\    const direct = @embedFile(direct_path);
        \\    const wrapped = fixture(wrapped_path);
        \\    _ = direct;
        \\    _ = wrapped;
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "direct.json", "{ \"version\": 1 }\n");
    try writeTmpFile(tmp.dir, "wrapped.json", "{ \"version\": 1 }\n");
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "probe.zig", "build.zig.zon" });

    const before_direct = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "direct.json", "{ \"version\": 2 }\n");
    const after_direct = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before_direct, &after_direct));

    const before_wrapped = after_direct;
    try writeTmpFile(tmp.dir, "wrapped.json", "{ \"version\": 2 }\n");
    const after_wrapped = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before_wrapped, &after_wrapped));
}

test "artifact build fingerprint prefers the nearest visible identifier-backed embed binding" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\const fixture_path = "outer.json";
        \\
        \\fn fixture(comptime rel: []const u8) []const u8 {
        \\    return @embedFile(rel);
        \\}
        \\
        \\pub fn main() void {
        \\    const fixture_path = "inner.json";
        \\    const direct = @embedFile(fixture_path);
        \\    const wrapped = fixture(fixture_path);
        \\    _ = direct;
        \\    _ = wrapped;
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "outer.json", "{ \"version\": 1 }\n");
    try writeTmpFile(tmp.dir, "inner.json", "{ \"version\": 1 }\n");
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "probe.zig", "build.zig.zon" });

    const before_outer = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "outer.json", "{ \"version\": 2 }\n");
    const after_outer = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expectEqualSlices(u8, &before_outer, &after_outer);

    try writeTmpFile(tmp.dir, "inner.json", "{ \"version\": 2 }\n");
    const after_inner = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &after_outer, &after_inner));
}

test "artifact build fingerprint includes top-level forward alias embed inputs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeTmpFile(tmp.dir, "build.zig.zon", ".{ .name = \"fingerprint-probe\", .version = \"0.0.0\" }\n");
    try writeTmpFile(tmp.dir, "probe.zig",
        \\const direct_path = schema_path;
        \\const schema_path = "schema.json";
        \\
        \\pub fn main() void {
        \\    const schema = @embedFile(direct_path);
        \\    _ = schema;
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "schema.json", "{ \"version\": 1 }\n");
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "probe.zig", "build.zig.zon" });

    const before = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try writeTmpFile(tmp.dir, "schema.json", "{ \"version\": 2 }\n");
    const after = artifactBuildInputFingerprint(std.testing.allocator, repo_root);
    try std.testing.expect(!std.mem.eql(u8, &before, &after));
}

test "repo Zig path registry falls back to filesystem when git and committed registry are unavailable" {
    const repo_root = try makeExternalTmpDir(std.testing.allocator);
    defer std.testing.allocator.free(repo_root);
    defer runChildExpectSuccess(std.testing.allocator, &.{ "rm", "-rf", repo_root }) catch unreachable;

    var repo_dir = try std.fs.openDirAbsolute(repo_root, .{});
    defer repo_dir.close();

    try writeTmpFile(repo_dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(_: *std.Build) void {}
        \\
    );
    try writeTmpFile(repo_dir, "src/probe.zig",
        \\pub fn touch() void {}
        \\
    );

    const registry = repoZigPathRegistryAlloc(std.testing.allocator, repo_root);
    defer std.testing.allocator.free(registry);

    try std.testing.expectEqualStrings(
        \\build.zig
        \\src/probe.zig
        \\
    , registry);
}

test "repo Zig path registry ignores deleted tracked files" {
    const repo_root = try makeExternalTmpDir(std.testing.allocator);
    defer std.testing.allocator.free(repo_root);
    defer runChildExpectSuccess(std.testing.allocator, &.{ "rm", "-rf", repo_root }) catch unreachable;

    var repo_dir = try std.fs.openDirAbsolute(repo_root, .{});
    defer repo_dir.close();

    try writeTmpFile(repo_dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(_: *std.Build) void {}
        \\
    );
    try writeTmpFile(repo_dir, "live.zig",
        \\pub fn live() void {}
        \\
    );
    try writeTmpFile(repo_dir, "stale.zig",
        \\pub fn stale() void {}
        \\
    );

    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "init", "-q" });
    try runChildExpectSuccess(std.testing.allocator, &.{ "git", "-C", repo_root, "add", "build.zig", "live.zig", "stale.zig" });
    try repo_dir.deleteFile("stale.zig");

    const registry = repoZigPathRegistryAlloc(std.testing.allocator, repo_root);
    defer std.testing.allocator.free(registry);

    try std.testing.expectEqualStrings(
        \\build.zig
        \\live.zig
        \\
    , registry);
}

/// Configure build, test, lint, example, and benchmark entrypoints for shift.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const bench_optimize: std.builtin.OptimizeMode = .ReleaseFast;

    absolutizeZlinterRuntimePaths(b);

    const shift_mod = b.addModule("shift", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const shift_compile_mod = b.createModule(.{
        .root_source_file = b.path("src/private_modules/shift_compile.zig"),
        .target = target,
        .optimize = optimize,
    });
    const shift_vm_mod = b.createModule(.{
        .root_source_file = b.path("src/private_modules/shift_vm.zig"),
        .target = target,
        .optimize = optimize,
    });
    const shift_shared_mod = b.createModule(.{
        .root_source_file = b.path("src/shift_shared.zig"),
        .target = target,
        .optimize = optimize,
    });
    const shift_compile_api_mod = b.createModule(.{
        .root_source_file = b.path("src/shift_compile_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    const private_bundle_envelope_mod = b.createModule(.{
        .root_source_file = b.path("src/bundle_envelope_v1.zig"),
        .target = target,
        .optimize = optimize,
    });
    const private_host_adapter_v1_mod = b.createModule(.{
        .root_source_file = b.path("src/host_adapter_v1.zig"),
        .target = target,
        .optimize = optimize,
    });
    const private_artifact_vm_core_mod = b.createModule(.{
        .root_source_file = b.path("src/artifact_vm_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const artifact_build_options = b.addOptions();
    artifact_build_options.addOption(
        [32]u8,
        "default_artifact_build_fingerprint",
        defaultArtifactBuildFingerprint(b, target, optimize),
    );
    shift_shared_mod.addOptions("artifact_build_options", artifact_build_options);
    const portable_core_mod = b.createModule(.{
        .root_source_file = b.path("src/portable_core.zig"),
        .target = target,
        .optimize = optimize,
    });
    const error_witness_mod = b.createModule(.{
        .root_source_file = b.path("src/error_witness.zig"),
        .target = target,
        .optimize = optimize,
    });
    const prompt_contract_support_mod = b.createModule(.{
        .root_source_file = b.path("src/prompt_contract.zig"),
        .target = target,
        .optimize = optimize,
    });
    const frontend_support_mod = b.createModule(.{
        .root_source_file = b.path("src/frontend.zig"),
        .target = target,
        .optimize = optimize,
    });
    prompt_contract_support_mod.addImport("portable_core", portable_core_mod);
    frontend_support_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    frontend_support_mod.addImport("portable_core", portable_core_mod);
    shift_mod.addImport("shift_shared", shift_shared_mod);
    shift_mod.addImport("portable_core", portable_core_mod);
    shift_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    shift_mod.addImport("frontend_support", frontend_support_mod);
    shift_mod.addImport("error_witness", error_witness_mod);
    const witnesses_mod = b.createModule(.{
        .root_source_file = b.path("src/witnesses.zig"),
        .target = target,
        .optimize = optimize,
    });
    const formal_core_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/formal_core_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    const parity_scenarios_mod = b.createModule(.{
        .root_source_file = b.path("src/parity_scenarios.zig"),
        .target = target,
        .optimize = optimize,
    });
    parity_scenarios_mod.addImport("formal_core_registry", formal_core_registry_mod);
    shift_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const lowered_machine_mod = b.createModule(.{
        .root_source_file = b.path("src/lowered_machine.zig"),
        .target = target,
        .optimize = optimize,
    });
    lowered_machine_mod.addImport("portable_core", portable_core_mod);
    const effect_ir_mod = b.createModule(.{
        .root_source_file = b.path("src/effect_ir.zig"),
        .target = target,
        .optimize = optimize,
    });
    const helper_body_ir_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/helper_body_ir.zig"),
        .target = target,
        .optimize = optimize,
    });
    const source_graph_engine_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/source_graph_engine.zig"),
        .target = target,
        .optimize = optimize,
    });
    const internal_program_plan_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/program_plan.zig"),
        .target = target,
        .optimize = optimize,
    });
    internal_program_plan_mod.addImport("effect_ir", effect_ir_mod);
    helper_body_ir_mod.addImport("internal_program_plan", internal_program_plan_mod);
    helper_body_ir_mod.addImport("effect_ir", effect_ir_mod);
    const source_graph_comptime_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/source_graph_comptime.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_graph_comptime_mod.addImport("source_graph_engine", source_graph_engine_mod);
    const source_graph_embed_mod = b.createModule(.{
        .root_source_file = b.path("source_graph_embed.zig"),
        .target = target,
        .optimize = optimize,
    });
    const internal_kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/kernel.zig"),
        .target = target,
        .optimize = optimize,
    });
    internal_kernel_mod.addImport("parity_scenarios", parity_scenarios_mod);
    internal_kernel_mod.addImport("internal_program_plan", internal_program_plan_mod);
    const interpreter_mod = b.createModule(.{
        .root_source_file = b.path("src/interpreter.zig"),
        .target = target,
        .optimize = optimize,
    });
    interpreter_mod.addImport("parity_scenarios", parity_scenarios_mod);
    interpreter_mod.addImport("internal_kernel", internal_kernel_mod);
    shift_mod.addImport("effect_ir", effect_ir_mod);
    shift_mod.addImport("internal_kernel", internal_kernel_mod);
    shift_mod.addImport("internal_program_plan", internal_program_plan_mod);
    shift_mod.addImport("interpreter", interpreter_mod);
    shift_mod.addImport("source_graph_engine", source_graph_engine_mod);
    shift_mod.addImport("source_graph_comptime", source_graph_comptime_mod);
    shift_compile_api_mod.addImport("shift_shared", shift_shared_mod);
    shift_compile_mod.addImport("shift_shared", shift_shared_mod);
    shift_compile_mod.addImport("shift_compile_api", shift_compile_api_mod);
    private_bundle_envelope_mod.addImport("shift_shared", shift_shared_mod);
    private_artifact_vm_core_mod.addImport("shift_shared", shift_shared_mod);
    private_artifact_vm_core_mod.addImport("host_adapter_v1", private_host_adapter_v1_mod);
    shift_vm_mod.addImport("shift_shared", shift_shared_mod);
    shift_vm_mod.addImport("bundle_envelope_v1", private_bundle_envelope_mod);
    shift_vm_mod.addImport("host_adapter_v1", private_host_adapter_v1_mod);
    shift_vm_mod.addImport("artifact_vm_runtime", private_artifact_vm_core_mod);
    lowered_machine_mod.addImport("parity_scenarios", parity_scenarios_mod);
    lowered_machine_mod.addImport("internal_kernel", internal_kernel_mod);
    lowered_machine_mod.addImport("interpreter", interpreter_mod);
    const authoring_lowerer_options = b.addOptions();
    const package_root_alias = packageRootAlias(b);
    const lowerer_opts_marker = true;
    authoring_lowerer_options.addOption([]const u8, "package_root", b.pathFromRoot("."));
    authoring_lowerer_options.addOption([]const u8, "package_root_alias", package_root_alias.path);
    authoring_lowerer_options.addOption(bool, "package_root_alias_available", package_root_alias.available);
    authoring_lowerer_options.addOption([]const u8, "repo_zig_paths", repoZigPathRegistry(b));
    authoring_lowerer_options.addOption(bool, "authoring_lowerer_options_marker", lowerer_opts_marker);
    authoring_lowerer_options.addOption([32]u8, "hash_local_mutation_resume", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/local_mutation_resume.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_branch_resume", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/branch_resume.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_loop_resume", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/loop_resume.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_helper_call_resume", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/helper_call_resume.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_nested_prompt_static_redelim", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/nested_prompt_static_redelim.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_typed_error_try", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/typed_error_try.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_defer_resume", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/defer_resume.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_errdefer_error", canonicalSourceHash(b, "test/source_lowering_corpus/fixtures/errdefer_error.zig"));
    inline for (shipped_open_row_corpus.custom_examples) |row| {
        switch (row.kind) {
            .transform_basic => authoring_lowerer_options.addOption([32]u8, "hash_define_basic", canonicalSourceHash(b, row.source_path)),
            .choice_basic => authoring_lowerer_options.addOption([32]u8, "hash_define_choice_basic", canonicalSourceHash(b, row.source_path)),
            .abort_basic => authoring_lowerer_options.addOption([32]u8, "hash_define_abort_basic", canonicalSourceHash(b, row.source_path)),
            .workflow => authoring_lowerer_options.addOption([32]u8, "hash_front_door_workflow", canonicalSourceHash(b, row.source_path)),
            .abortive_validation => authoring_lowerer_options.addOption([32]u8, "hash_algebraic_abortive_validation", canonicalSourceHash(b, row.source_path)),
            .artifact_search => authoring_lowerer_options.addOption([32]u8, "hash_algebraic_artifact_search", canonicalSourceHash(b, row.source_path)),
            .generator => authoring_lowerer_options.addOption([32]u8, "hash_generator", canonicalSourceHash(b, row.source_path)),
        }
    }
    authoring_lowerer_options.addOption([32]u8, "hash_early_exit", canonicalSourceHash(b, "examples/early_exit.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_resume_or_return", canonicalSourceHash(b, "examples/resume_or_return.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_nested_workflow", canonicalSourceHash(b, "examples/nested_workflow.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_state_basic", canonicalSourceHash(b, "examples/state_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_reader_basic", canonicalSourceHash(b, "examples/reader_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_optional_basic", canonicalSourceHash(b, "examples/optional_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_exception_basic", canonicalSourceHash(b, "examples/exception_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_resource_basic", canonicalSourceHash(b, "examples/resource_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_writer_basic", canonicalSourceHash(b, "examples/writer_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_witness_sources", canonicalSourceHash(b, "src/witness_sources.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_witnesses", canonicalSourceHash(b, "src/witnesses.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_algebraic_abortive_validation", canonicalSourceHash(b, "test/direct_style_bridge/open_row_abortive_validation.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_algebraic_artifact_search", canonicalSourceHash(b, "test/direct_style_bridge/open_row_artifact_search.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_atm_resume_transform", canonicalSourceHash(b, "test/direct_style_bridge/atm_resume_transform.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_direct_return", canonicalSourceHash(b, "test/direct_style_bridge/direct_return.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_early_exit", canonicalSourceHash(b, "test/direct_style_bridge/early_exit.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_exception_basic", canonicalSourceHash(b, "test/direct_style_bridge/exception_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_generator", canonicalSourceHash(b, "test/direct_style_bridge/open_row_generator.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_multi_prompt", canonicalSourceHash(b, "test/direct_style_bridge/multi_prompt.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_nested_workflow", canonicalSourceHash(b, "test/direct_style_bridge/nested_workflow.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_optional_basic", canonicalSourceHash(b, "test/direct_style_bridge/optional_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_reader_basic", canonicalSourceHash(b, "test/direct_style_bridge/reader_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_resource_basic", canonicalSourceHash(b, "test/direct_style_bridge/resource_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_resume_or_return", canonicalSourceHash(b, "test/direct_style_bridge/resume_or_return.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_resume_or_return_resume", canonicalSourceHash(b, "test/direct_style_bridge/resume_or_return_resume.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_resume_or_return_return_now", canonicalSourceHash(b, "test/direct_style_bridge/resume_or_return_return_now.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_state_basic", canonicalSourceHash(b, "test/direct_style_bridge/state_basic.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_static_redelim", canonicalSourceHash(b, "test/direct_style_bridge/static_redelim.zig"));
    authoring_lowerer_options.addOption([32]u8, "hash_bridge_fixture_writer_basic", canonicalSourceHash(b, "test/direct_style_bridge/writer_basic.zig"));
    const authoring_build_options_mod = authoring_lowerer_options.createModule();
    source_graph_embed_mod.addImport("authoring_build_options", authoring_build_options_mod);
    source_graph_embed_mod.addImport("source_graph_engine", source_graph_engine_mod);
    source_graph_embed_mod.addImport("source_graph_comptime", source_graph_comptime_mod);
    const authoring_lowerer_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/authoring_lowerer.zig"),
        .target = target,
        .optimize = optimize,
    });
    authoring_lowerer_mod.addImport("authoring_build_options", authoring_build_options_mod);
    authoring_lowerer_mod.addImport("effect_ir", effect_ir_mod);
    authoring_lowerer_mod.addImport("lowered_machine", lowered_machine_mod);
    authoring_lowerer_mod.addImport("parity_scenarios", parity_scenarios_mod);
    authoring_lowerer_mod.addImport("source_graph_engine", source_graph_engine_mod);
    frontend_support_mod.addImport("lowered_machine", lowered_machine_mod);
    shift_mod.addImport("effect_ir", effect_ir_mod);
    shift_mod.addImport("lowered_machine", lowered_machine_mod);
    witnesses_mod.addImport("lowered_machine", lowered_machine_mod);
    witnesses_mod.addImport("frontend_support", frontend_support_mod);
    witnesses_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    const prompt_support_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/prompt_support.zig"),
        .target = target,
        .optimize = optimize,
    });
    prompt_support_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    prompt_support_mod.addImport("frontend_support", frontend_support_mod);
    const with_api_mod = b.createModule(.{
        .root_source_file = b.path("src/with_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    with_api_mod.addImport("portable_core", portable_core_mod);
    with_api_mod.addImport("frontend_support", frontend_support_mod);
    with_api_mod.addImport("lowered_machine", lowered_machine_mod);
    with_api_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    const program_frontend_mod = b.createModule(.{
        .root_source_file = b.path("src/program_frontend.zig"),
        .target = target,
        .optimize = optimize,
    });
    program_frontend_mod.addImport("effect_ir", effect_ir_mod);
    program_frontend_mod.addImport("helper_body_ir", helper_body_ir_mod);
    program_frontend_mod.addImport("parity_scenarios", parity_scenarios_mod);
    internal_program_plan_mod.addImport("program_frontend", program_frontend_mod);
    internal_program_plan_mod.addImport("helper_body_ir", helper_body_ir_mod);
    shift_mod.addImport("program_frontend", program_frontend_mod);
    shift_mod.addImport("authoring_build_options", authoring_build_options_mod);
    shift_mod.addImport("source_graph_embed", source_graph_embed_mod);
    authoring_lowerer_mod.addImport("program_frontend", program_frontend_mod);
    shift_mod.addImport("authoring_lowerer", authoring_lowerer_mod);
    const lexical_runtime_internal_mod = b.createModule(.{
        .root_source_file = b.path("src/lexical_runtime_internal.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_runtime_internal_mod.addImport("portable_core", portable_core_mod);
    lexical_runtime_internal_mod.addImport("frontend_support", frontend_support_mod);
    lexical_runtime_internal_mod.addImport("lowered_machine", lowered_machine_mod);
    lexical_runtime_internal_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    const witness_sources_mod = b.createModule(.{
        .root_source_file = b.path("src/witness_sources.zig"),
        .target = target,
        .optimize = optimize,
    });
    witness_sources_mod.addImport("lowered_machine", lowered_machine_mod);
    witness_sources_mod.addImport("shift", shift_shared_mod);
    witness_sources_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    witness_sources_mod.addImport("frontend_support", frontend_support_mod);
    witnesses_mod.addImport("witness_sources", witness_sources_mod);
    const bridge_manifest_mod = b.createModule(.{
        .root_source_file = b.path("src/direct_style_bridge_manifest.zig"),
        .target = target,
        .optimize = optimize,
    });
    bridge_manifest_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const program_bridge_mod = b.createModule(.{
        .root_source_file = b.path("src/program_bridge.zig"),
        .target = target,
        .optimize = optimize,
    });
    program_bridge_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    program_bridge_mod.addImport("parity_scenarios", parity_scenarios_mod);
    program_bridge_mod.addImport("program_frontend", program_frontend_mod);
    program_bridge_mod.addImport("authoring_lowerer", authoring_lowerer_mod);
    const private_lowered_runtime_mod = b.createModule(.{
        .root_source_file = b.path("src/private_lowered_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    private_lowered_runtime_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    private_lowered_runtime_mod.addImport("lowered_machine", lowered_machine_mod);
    private_lowered_runtime_mod.addImport("parity_scenarios", parity_scenarios_mod);
    private_lowered_runtime_mod.addImport("program_bridge", program_bridge_mod);
    const source_lowering_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/source_lowering_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_registry_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const shipped_open_row_corpus_mod = b.createModule(.{
        .root_source_file = b.path("src/shipped_open_row_corpus_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    const source_lowering_mod = b.createModule(.{
        .root_source_file = b.path("src/source_lowering.zig"),
        .target = target,
        .optimize = optimize,
    });
    const source_lowering_options = b.addOptions();
    source_lowering_options.addOption([]const u8, "package_root", b.pathFromRoot("."));
    source_lowering_mod.addOptions("build_options", source_lowering_options);
    source_lowering_mod.addImport("effect_ir", effect_ir_mod);
    source_lowering_mod.addImport("program_frontend", program_frontend_mod);
    source_lowering_mod.addImport("source_lowering_registry", source_lowering_registry_mod);
    source_lowering_mod.addImport("parity_scenarios", parity_scenarios_mod);
    source_lowering_mod.addImport("lowered_machine", lowered_machine_mod);
    source_lowering_mod.addImport("error_witness", error_witness_mod);
    source_lowering_mod.addImport("authoring_lowerer", authoring_lowerer_mod);
    source_lowering_mod.addImport("shipped_open_row_corpus_registry", shipped_open_row_corpus_mod);
    shift_mod.addImport("source_lowering", source_lowering_mod);
    shift_shared_mod.addImport("portable_core", portable_core_mod);
    shift_shared_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    shift_shared_mod.addImport("frontend_support", frontend_support_mod);
    shift_shared_mod.addImport("error_witness", error_witness_mod);
    shift_shared_mod.addImport("parity_scenarios", parity_scenarios_mod);
    shift_shared_mod.addImport("effect_ir", effect_ir_mod);
    shift_shared_mod.addImport("internal_kernel", internal_kernel_mod);
    shift_shared_mod.addImport("internal_program_plan", internal_program_plan_mod);
    shift_shared_mod.addImport("interpreter", interpreter_mod);
    shift_shared_mod.addImport("source_graph_engine", source_graph_engine_mod);
    shift_shared_mod.addImport("source_graph_comptime", source_graph_comptime_mod);
    shift_shared_mod.addImport("lowered_machine", lowered_machine_mod);
    shift_shared_mod.addImport("program_frontend", program_frontend_mod);
    shift_shared_mod.addImport("authoring_build_options", authoring_build_options_mod);
    shift_shared_mod.addImport("source_graph_embed", source_graph_embed_mod);
    shift_shared_mod.addImport("authoring_lowerer", authoring_lowerer_mod);
    shift_shared_mod.addImport("source_lowering", source_lowering_mod);
    const src_lower_cov_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/source_lowering_coverage_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    src_lower_cov_registry_mod.addImport("formal_core_registry", formal_core_registry_mod);
    src_lower_cov_registry_mod.addImport("shipped_open_row_corpus_registry", shipped_open_row_corpus_mod);
    witnesses_mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);
    const reference_eval_mod = b.createModule(.{
        .root_source_file = b.path("src/reference_eval.zig"),
        .target = target,
        .optimize = optimize,
    });
    reference_eval_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const reference_machine_mod = b.createModule(.{
        .root_source_file = b.path("src/reference_machine.zig"),
        .target = target,
        .optimize = optimize,
    });
    reference_machine_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const parity_kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/parity_kernel.zig"),
        .target = target,
        .optimize = optimize,
    });
    parity_kernel_mod.addImport("internal_kernel", internal_kernel_mod);
    parity_kernel_mod.addImport("interpreter", interpreter_mod);
    parity_kernel_mod.addImport("lowered_machine", lowered_machine_mod);
    parity_kernel_mod.addImport("parity_scenarios", parity_scenarios_mod);
    reference_machine_mod.addImport("parity_kernel", parity_kernel_mod);

    const check_step = b.step("check", "Compile the shift module and examples.");
    b.default_step.dependOn(check_step);

    const lib_check = b.addObject(.{
        .name = "shift",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lib_check.root_module.addImport("shift_shared", shift_shared_mod);
    lib_check.root_module.addImport("effect_ir", effect_ir_mod);
    lib_check.root_module.addImport("interpreter", interpreter_mod);
    lib_check.root_module.addImport("lowered_machine", lowered_machine_mod);
    lib_check.root_module.addImport("portable_core", portable_core_mod);
    lib_check.root_module.addImport("parity_scenarios", parity_scenarios_mod);
    lib_check.root_module.addImport("internal_kernel", internal_kernel_mod);
    lib_check.root_module.addImport("internal_program_plan", internal_program_plan_mod);
    lib_check.root_module.addImport("authoring_lowerer", authoring_lowerer_mod);
    lib_check.root_module.addImport("authoring_build_options", authoring_build_options_mod);
    lib_check.root_module.addImport("program_frontend", program_frontend_mod);
    lib_check.root_module.addImport("source_graph_engine", source_graph_engine_mod);
    lib_check.root_module.addImport("source_graph_comptime", source_graph_comptime_mod);
    lib_check.root_module.addImport("source_graph_embed", source_graph_embed_mod);
    lib_check.root_module.addImport("source_lowering", source_lowering_mod);
    lib_check.root_module.addImport("error_witness", error_witness_mod);
    check_step.dependOn(&lib_check.step);

    const root_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    root_tests.root_module.addImport("shift_shared", shift_shared_mod);
    root_tests.root_module.addImport("effect_ir", effect_ir_mod);
    root_tests.root_module.addImport("interpreter", interpreter_mod);
    root_tests.root_module.addImport("lowered_machine", lowered_machine_mod);
    root_tests.root_module.addImport("portable_core", portable_core_mod);
    root_tests.root_module.addImport("parity_scenarios", parity_scenarios_mod);
    root_tests.root_module.addImport("internal_kernel", internal_kernel_mod);
    root_tests.root_module.addImport("internal_program_plan", internal_program_plan_mod);
    root_tests.root_module.addImport("authoring_lowerer", authoring_lowerer_mod);
    root_tests.root_module.addImport("authoring_build_options", authoring_build_options_mod);
    root_tests.root_module.addImport("program_frontend", program_frontend_mod);
    root_tests.root_module.addImport("source_graph_engine", source_graph_engine_mod);
    root_tests.root_module.addImport("source_graph_comptime", source_graph_comptime_mod);
    root_tests.root_module.addImport("source_graph_embed", source_graph_embed_mod);
    root_tests.root_module.addImport("source_lowering", source_lowering_mod);
    root_tests.root_module.addImport("error_witness", error_witness_mod);
    root_tests.root_module.addImport("prompt_contract_support", prompt_contract_support_mod);
    root_tests.root_module.addImport("frontend_support", frontend_support_mod);
    const run_root_tests = b.addRunArtifact(root_tests);
    const test_step = b.step("test", "Run the default shift proof surface.");
    test_step.dependOn(&run_root_tests.step);

    const frontend_internal_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/frontend.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    frontend_internal_tests.root_module.addImport("lowered_machine", lowered_machine_mod);
    frontend_internal_tests.root_module.addImport("portable_core", portable_core_mod);
    frontend_internal_tests.root_module.addImport("prompt_contract_support", prompt_contract_support_mod);
    const run_frontend_internal_tests = b.addRunArtifact(frontend_internal_tests);
    const frontend_internal_step = b.step("frontend-internal-check", "Run frontend contextual replay regression tests.");
    frontend_internal_step.dependOn(&run_frontend_internal_tests.step);
    test_step.dependOn(&run_frontend_internal_tests.step);

    const internal_program_plan_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/program_plan_review_regression_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    internal_program_plan_tests.root_module.addImport("internal_program_plan", internal_program_plan_mod);
    internal_program_plan_tests.root_module.addImport("effect_ir", effect_ir_mod);
    const run_plan_review_tests = b.addRunArtifact(internal_program_plan_tests);
    const internal_program_plan_step = b.step("program-plan-check", "Run internal runtime program-plan regression tests.");
    internal_program_plan_step.dependOn(&run_plan_review_tests.step);
    test_step.dependOn(&run_plan_review_tests.step);

    const witness_mod = b.createModule(.{
        .root_source_file = b.path("test/witness_corpus_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    witness_mod.addImport("shift", shift_shared_mod);
    witness_mod.addImport("reference_eval", reference_eval_mod);
    witness_mod.addImport("reference_machine", reference_machine_mod);
    witness_mod.addImport("witnesses", witnesses_mod);
    witness_mod.addImport("formal_core_registry", formal_core_registry_mod);
    witness_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const witness_tests = b.addTest(.{
        .root_module = witness_mod,
    });
    const run_witness_tests = b.addRunArtifact(witness_tests);
    test_step.dependOn(&run_witness_tests.step);

    const runtime_contract_mod = b.createModule(.{
        .root_source_file = b.path("test/runtime_contract_suite.zig"),
        .target = target,
        .optimize = optimize,
    });
    runtime_contract_mod.addImport("shift", shift_shared_mod);
    runtime_contract_mod.addImport("prompt_support", prompt_support_mod);
    runtime_contract_mod.addImport("runtime_contract_registry", b.createModule(.{
        .root_source_file = b.path("src/runtime_contract_registry.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const survey_runtime_mod = b.createModule(.{
        .root_source_file = b.path("test/one_shot_survey/protocol_resume_transform_executes.zig"),
        .target = target,
        .optimize = optimize,
    });
    runtime_contract_mod.addImport("survey_resume_transform_executes", survey_runtime_mod);
    const runtime_contract_tests = b.addTest(.{
        .root_module = runtime_contract_mod,
    });
    const run_runtime_contract_tests = b.addRunArtifact(runtime_contract_tests);
    const runtime_contract_step = b.step("runtime-contract-suite", "Run executable lowered-runtime contract cases for the remaining runtime obligations.");
    runtime_contract_step.dependOn(&run_runtime_contract_tests.step);
    test_step.dependOn(&run_runtime_contract_tests.step);
    const compat_runtime_contract_step = b.step("compat-runtime-contract-check", "Check that legacy Runtime misuse semantics still hold through the compat shell.");
    compat_runtime_contract_step.dependOn(&run_runtime_contract_tests.step);

    const prompt_token_contract_mod = b.createModule(.{
        .root_source_file = b.path("test/prompt_token_contract_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    prompt_token_contract_mod.addImport("portable_core", portable_core_mod);
    prompt_token_contract_mod.addImport("prompt_support", prompt_support_mod);
    const prompt_token_tests = b.addTest(.{
        .root_module = prompt_token_contract_mod,
    });
    const run_prompt_token_tests = b.addRunArtifact(prompt_token_tests);
    const prompt_token_contract_step = b.step("prompt-token-contract-check", "Check explicit prompt-token construction and source-backed token allocation.");
    prompt_token_contract_step.dependOn(&run_prompt_token_tests.step);
    test_step.dependOn(&run_prompt_token_tests.step);
    const durable_session_mod = b.createModule(.{
        .root_source_file = b.path("test/durable_session_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    durable_session_mod.addImport("shift_vm", shift_vm_mod);
    const durable_session_tests = b.addTest(.{
        .root_module = durable_session_mod,
    });
    const run_durable_session_tests = b.addRunArtifact(durable_session_tests);
    const durable_session_resume_step = b.step("durable-session-resume-check", "Check append-only durable session replay over the interpreter core.");
    durable_session_resume_step.dependOn(&run_durable_session_tests.step);
    test_step.dependOn(durable_session_resume_step);

    const backend_parity_mod = b.createModule(.{
        .root_source_file = b.path("test/backend_parity_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const kernel_parity_witness_mod = b.createModule(.{
        .root_source_file = b.path("test/kernel_parity_witness_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const backend_parity_manifest_mod = b.createModule(.{
        .root_source_file = b.path("test/backend_parity_manifest.zig"),
        .target = target,
        .optimize = optimize,
    });
    backend_parity_manifest_mod.addImport("formal_core_registry", formal_core_registry_mod);
    backend_parity_manifest_mod.addImport("parity_scenarios", parity_scenarios_mod);
    backend_parity_mod.addImport("shift", shift_shared_mod);
    backend_parity_mod.addImport("backend_parity_manifest", backend_parity_manifest_mod);
    backend_parity_mod.addImport("parity_kernel", parity_kernel_mod);
    backend_parity_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const parity_machine_mod = b.createModule(.{
        .root_source_file = b.path("src/parity_machine.zig"),
        .target = target,
        .optimize = optimize,
    });
    parity_machine_mod.addImport("parity_kernel", parity_kernel_mod);
    parity_machine_mod.addImport("parity_scenarios", parity_scenarios_mod);
    backend_parity_mod.addImport("parity_machine", parity_machine_mod);
    backend_parity_mod.addImport("witnesses_src", witnesses_mod);
    backend_parity_mod.addImport("example_open_row_abort_basic", createShiftConsumerModule(b, "examples/open_row_abort_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_open_row_abortive_validation", createShiftConsumerModule(b, "examples/open_row_abortive_validation.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_open_row_artifact_search", createShiftConsumerModule(b, "examples/open_row_artifact_search.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_open_row_choice_basic", createShiftConsumerModule(b, "examples/open_row_choice_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_early_exit", createShiftConsumerModule(b, "examples/early_exit.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_exception_basic", createShiftConsumerModule(b, "examples/exception_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_open_row_generator", createShiftConsumerModule(b, "examples/open_row_generator.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_open_row_transform_basic", createShiftConsumerModule(b, "examples/open_row_transform_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_open_row_workflow", createShiftConsumerModule(b, "examples/open_row_workflow.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_nested_workflow", createShiftConsumerModule(b, "examples/nested_workflow.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_optional_basic", createShiftConsumerModule(b, "examples/optional_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_reader_basic", createShiftConsumerModule(b, "examples/reader_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_resource_basic", createShiftConsumerModule(b, "examples/resource_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_resume_or_return", createShiftConsumerModule(b, "examples/resume_or_return.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_state_basic", createShiftConsumerModule(b, "examples/state_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("example_writer_basic", createShiftConsumerModule(b, "examples/writer_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    backend_parity_mod.addImport("survey_resume_transform_executes", createShiftConsumerModule(b, "test/one_shot_survey/protocol_resume_transform_executes.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    const backend_parity_tests = b.addTest(.{
        .root_module = backend_parity_mod,
    });
    const run_backend_parity_tests = b.addRunArtifact(backend_parity_tests);
    kernel_parity_witness_mod.addImport("backend_parity_manifest", backend_parity_manifest_mod);
    kernel_parity_witness_mod.addImport("parity_kernel", parity_kernel_mod);
    kernel_parity_witness_mod.addImport("parity_machine", parity_machine_mod);
    kernel_parity_witness_mod.addImport("witnesses_src", witnesses_mod);
    const kernel_parity_witness_tests = b.addTest(.{
        .root_module = kernel_parity_witness_mod,
    });
    const run_parity_witness_tests = b.addRunArtifact(kernel_parity_witness_tests);
    const backend_parity_step = b.step("kernel-parity-check", "Check the hidden lowered proof engine beneath the root execution kernel.");
    backend_parity_step.dependOn(&run_backend_parity_tests.step);
    backend_parity_step.dependOn(&run_parity_witness_tests.step);

    const proof_fixture_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_proof_fixtures.zig"),
        .target = target,
        .optimize = optimize,
    });
    proof_fixture_mod.addImport("parity_scenarios", parity_scenarios_mod);
    const proof_fixture_exe = b.addExecutable(.{
        .name = "shift-proof-fixture-render",
        .root_module = proof_fixture_mod,
    });
    const proof_fixture_check_cmd = b.addRunArtifact(proof_fixture_exe);
    proof_fixture_check_cmd.addArg("check");
    const proof_fixture_check_step = b.step("proof-fixtures-check", "Check generated proof fixtures against the canonical scenario registry.");
    proof_fixture_check_step.dependOn(&proof_fixture_check_cmd.step);
    const proof_fixture_write_cmd = b.addRunArtifact(proof_fixture_exe);
    proof_fixture_write_cmd.addArg("write");
    const proof_fixture_write_step = b.step("proof-fixtures-write", "Refresh generated proof fixtures from the canonical scenario registry.");
    proof_fixture_write_step.dependOn(&proof_fixture_write_cmd.step);

    const authoring_lower_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_authoring_lowerings.zig"),
        .target = target,
        .optimize = optimize,
    });
    authoring_lower_mod.addImport("program_frontend", program_frontend_mod);
    const authoring_lower_exe = b.addExecutable(.{
        .name = "shift-authoring-lowering-render",
        .root_module = authoring_lower_mod,
    });
    const authoring_lower_check_cmd = b.addRunArtifact(authoring_lower_exe);
    authoring_lower_check_cmd.addArg("check");
    const authoring_lower_check_step = b.step("authoring-lowering-check", "Check lowered structured-program snapshots.");
    authoring_lower_check_step.dependOn(&authoring_lower_check_cmd.step);
    const authoring_lower_write_cmd = b.addRunArtifact(authoring_lower_exe);
    authoring_lower_write_cmd.addArg("write");
    const authoring_lower_write_step = b.step("authoring-lowering-write", "Refresh lowered structured-program snapshots.");
    authoring_lower_write_step.dependOn(&authoring_lower_write_cmd.step);

    const formal_core_render_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_formal_core.zig"),
        .target = target,
        .optimize = optimize,
    });
    formal_core_render_mod.addImport("formal_core_registry", formal_core_registry_mod);
    formal_core_render_mod.addImport("witnesses", witnesses_mod);
    const formal_core_render_exe = b.addExecutable(.{
        .name = "shift-formal-core-render",
        .root_module = formal_core_render_mod,
    });
    const formal_core_cmd = b.addRunArtifact(formal_core_render_exe);
    formal_core_cmd.addArg("check");
    const formal_core_step = b.step("formal-core", "Check the implementation-derived formal core against the root-kernel contract.");
    formal_core_step.dependOn(&formal_core_cmd.step);
    test_step.dependOn(&formal_core_cmd.step);

    const formal_core_write_cmd = b.addRunArtifact(formal_core_render_exe);
    formal_core_write_cmd.addArg("write");
    const formal_core_write_step = b.step("formal-core-write", "Refresh the generated formal core artifact.");
    formal_core_write_step.dependOn(&formal_core_write_cmd.step);

    const readme_contract_cmd = b.addSystemCommand(&.{ "sh", "test/readme_contract/run.sh" });
    const readme_contract_step = b.step("readme-contract", "Check README kernel-contract anchors and tombstone coverage.");
    readme_contract_step.dependOn(&readme_contract_cmd.step);
    test_step.dependOn(&readme_contract_cmd.step);

    const construction_boundary_cmd = b.addSystemCommand(&.{ "sh", "test/effect_construction_boundary/run.sh" });
    const construction_boundary_step = b.step("effect-construction-boundary", "Check that effect families route through the generalized substrate.");
    construction_boundary_step.dependOn(&construction_boundary_cmd.step);
    test_step.dependOn(&construction_boundary_cmd.step);

    const shared_engine_boundary_cmd = b.addSystemCommand(&.{ "sh", "test/shared_algebraic_engine_boundary/run.sh" });
    const shared_engine_boundary_step = b.step("shared-declaration-engine-boundary", "Check that surviving declaration surfaces share one internal declaration engine.");
    shared_engine_boundary_step.dependOn(&shared_engine_boundary_cmd.step);
    test_step.dependOn(&shared_engine_boundary_cmd.step);

    const size_check_mod = b.createModule(.{
        .root_source_file = b.path("test/size_check.zig"),
        .target = target,
        .optimize = optimize,
    });
    size_check_mod.addImport("shift", shift_mod);
    size_check_mod.addImport("shift_shared", shift_shared_mod);
    size_check_mod.addImport("prompt_support", prompt_support_mod);
    const size_tests = b.addTest(.{
        .root_module = size_check_mod,
    });
    const run_size_tests = b.addRunArtifact(size_tests);
    const size_step = b.step("size-check", "Run size and layout invariants.");
    test_step.dependOn(&run_size_tests.step);
    size_step.dependOn(&run_size_tests.step);

    const single_front_package_step = b.step("single-front-package-contract", "Check that downstream consumers can import only the shipped shift front.");
    size_step.dependOn(single_front_package_step);
    test_step.dependOn(single_front_package_step);
    const single_front_contract_root = std.fs.path.join(
        b.allocator,
        &.{ externalBoundaryFixtureRoot(b), "single_front_package_contract" },
    ) catch std.process.fatal("unable to allocate single-front contract fixture root", .{});
    const single_front_zon_template =
        ".{{\n    .name = .single_front_consumer,\n    .version = \"0.0.0\",\n    .dependencies = .{{\n        .shift = .{{ .path = \"shift_dep\" }},\n    }},\n    .minimum_zig_version = \"0.15.2\",\n    .paths = .{{\n        \"build.zig\",\n        \"build.zig.zon\",\n        \"probe.zig\",\n    }},\n    .fingerprint = 0x{x},\n}}\n";
    const single_front_fixture_template =
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {{
        \\    const target = b.standardTargetOptions(.{{}});
        \\    const optimize = b.standardOptimizeOption(.{{}});
        \\    const dep = b.dependency("shift", .{{
        \\        .target = target,
        \\        .optimize = optimize,
        \\    }});
        \\    const consumer_mod = b.createModule(.{{
        \\        .root_source_file = b.path("probe.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    }});
        \\    consumer_mod.addImport("{s}", dep.module("{s}"));
        \\    const consumer = b.addObject(.{{
        \\        .name = "consumer",
        \\        .root_module = consumer_mod,
        \\    }});
        \\    b.default_step.dependOn(&consumer.step);
        \\}}
    ;
    const single_front_success_root = std.fs.path.join(
        b.allocator,
        &.{ single_front_contract_root, "success" },
    ) catch std.process.fatal("unable to allocate single-front success fixture root", .{});
    const single_front_success_build = std.fs.path.join(
        b.allocator,
        &.{ single_front_success_root, "build.zig" },
    ) catch std.process.fatal("unable to allocate single-front success build path", .{});
    const single_front_success_zon = std.fs.path.join(
        b.allocator,
        &.{ single_front_success_root, "build.zig.zon" },
    ) catch std.process.fatal("unable to allocate single-front success zon path", .{});
    const single_front_success_probe = std.fs.path.join(
        b.allocator,
        &.{ single_front_success_root, "probe.zig" },
    ) catch std.process.fatal("unable to allocate single-front success probe path", .{});
    const single_front_success_build_src = std.fmt.allocPrint(
        b.allocator,
        single_front_fixture_template,
        .{ "shift", "shift" },
    ) catch std.process.fatal("unable to allocate single-front success build source", .{});
    const single_front_success_zon_src = std.fmt.allocPrint(
        b.allocator,
        single_front_zon_template,
        .{@as(u64, 0xf26c26a7555f9af0)},
    ) catch std.process.fatal("unable to allocate single-front success zon", .{});
    const write_single_front_build = addWriteTextFileCommand(
        b,
        single_front_success_build,
        single_front_success_build_src,
        "write-single-front-success-build-zig",
    );
    const write_single_front_success_zon = addWriteTextFileCommand(
        b,
        single_front_success_zon,
        single_front_success_zon_src,
        "write-single-front-success-build-zig-zon",
    );
    const write_single_front_probe = addWriteTextFileCommand(
        b,
        single_front_success_probe,
        \\const shift = @import("shift");
        \\
        \\comptime {
        \\    _ = shift.Runtime;
        \\    _ = shift.RuntimeError;
        \\    _ = shift.effect;
        \\    _ = shift.with;
        \\}
        \\
        \\pub export fn touch() void {}
    ,
        "write-single-front-success-probe",
    );
    const single_front_hidden_fixtures = [_]struct {
        fingerprint: u64,
        module_name: []const u8,
        step_name: []const u8,
        root_name: []const u8,
    }{
        .{
            .fingerprint = 0xf26c26a7b2e6c8be,
            .module_name = "shift_compile",
            .step_name = "check-single-front-hidden-shift-compile",
            .root_name = "hidden_shift_compile",
        },
        .{
            .fingerprint = 0xf26c26a7bd911cd6,
            .module_name = "shift_vm",
            .step_name = "check-single-front-hidden-shift-vm",
            .root_name = "hidden_shift_vm",
        },
    };
    const single_front_success_cmd = b.addSystemCommand(&.{
        "sh",
        "-eu",
        "-c",
        \\dir="$1"
        \\repo_root="$2"
        \\dep_dir="$dir/shift_dep"
        \\rm -rf "$dep_dir"
        \\mkdir -p "$dep_dir"
        \\for path in README.md build.zig build.zig.zon repo_zig_paths.txt source_graph_embed.zig src; do
        \\  ln -s "$repo_root/$path" "$dep_dir/$path"
        \\done
        \\cache_root="$dir/.zig-contract-cache"
        \\rm -rf "$cache_root"
        \\local="$cache_root/local"
        \\global="$cache_root/global"
        \\mkdir -p "$local" "$global"
        \\log="$dir/build.log"
        \\cd "$dir"
        \\zig build --cache-dir "$local" --global-cache-dir "$global" >"$log" 2>&1 || {
        \\  cat "$log" >&2
        \\  exit 1
        \\}
        ,
        "sh",
        single_front_success_root,
        b.pathFromRoot("."),
    });
    single_front_success_cmd.setName("single-front dependency consumer success");
    single_front_success_cmd.step.dependOn(write_single_front_build);
    single_front_success_cmd.step.dependOn(write_single_front_success_zon);
    single_front_success_cmd.step.dependOn(write_single_front_probe);
    single_front_package_step.dependOn(&single_front_success_cmd.step);
    inline for (single_front_hidden_fixtures) |fixture| {
        const fixture_root = std.fs.path.join(
            b.allocator,
            &.{ single_front_contract_root, fixture.root_name },
        ) catch std.process.fatal("unable to allocate single-front hidden fixture root", .{});
        const fixture_build = std.fs.path.join(
            b.allocator,
            &.{ fixture_root, "build.zig" },
        ) catch std.process.fatal("unable to allocate single-front hidden build path", .{});
        const fixture_zon = std.fs.path.join(
            b.allocator,
            &.{ fixture_root, "build.zig.zon" },
        ) catch std.process.fatal("unable to allocate single-front hidden zon path", .{});
        const fixture_probe = std.fs.path.join(
            b.allocator,
            &.{ fixture_root, "probe.zig" },
        ) catch std.process.fatal("unable to allocate single-front hidden probe path", .{});
        const fixture_build_src = std.fmt.allocPrint(
            b.allocator,
            single_front_fixture_template,
            .{ fixture.module_name, fixture.module_name },
        ) catch std.process.fatal("unable to allocate single-front hidden build source", .{});
        const fixture_zon_src = std.fmt.allocPrint(
            b.allocator,
            single_front_zon_template,
            .{fixture.fingerprint},
        ) catch std.process.fatal("unable to allocate single-front hidden zon", .{});
        const write_fixture_build = addWriteTextFileCommand(
            b,
            fixture_build,
            fixture_build_src,
            fixture.step_name ++ "-build-zig",
        );
        const write_fixture_zon = addWriteTextFileCommand(
            b,
            fixture_zon,
            fixture_zon_src,
            fixture.step_name ++ "-build-zig-zon",
        );
        const probe_src = std.fmt.allocPrint(
            b.allocator,
            "const hidden = @import(\"{s}\");\n\ncomptime {{\n    _ = hidden;\n}}\n\npub export fn touch() void {{}}\n",
            .{fixture.module_name},
        ) catch std.process.fatal("unable to allocate single-front hidden probe source", .{});
        const write_fixture_probe = addWriteTextFileCommand(
            b,
            fixture_probe,
            probe_src,
            fixture.step_name ++ "-probe-zig",
        );
        const fixture_cmd = b.addSystemCommand(&.{
            "sh",
            "-eu",
            "-c",
            \\dir="$1"
            \\repo_root="$2"
            \\module_name="$3"
            \\dep_dir="$dir/shift_dep"
            \\rm -rf "$dep_dir"
            \\mkdir -p "$dep_dir"
            \\for path in README.md build.zig build.zig.zon repo_zig_paths.txt source_graph_embed.zig src; do
            \\  ln -s "$repo_root/$path" "$dep_dir/$path"
            \\done
            \\cache_root="$dir/.zig-contract-cache"
            \\rm -rf "$cache_root"
            \\local="$cache_root/local"
            \\global="$cache_root/global"
            \\mkdir -p "$local" "$global"
            \\log="$dir/build.log"
            \\cd "$dir"
            \\if zig build --cache-dir "$local" --global-cache-dir "$global" >"$log" 2>&1; then
            \\  echo "expected dependency consumer requesting $module_name to fail" >&2
            \\  cat "$log" >&2
            \\  exit 1
            \\fi
            \\grep -q "unable to find module '$module_name'" "$log" || {
            \\  cat "$log" >&2
            \\  exit 1
            \\}
            ,
            "sh",
            fixture_root,
            b.pathFromRoot("."),
            fixture.module_name,
        });
        fixture_cmd.setName(fixture.step_name);
        fixture_cmd.step.dependOn(write_fixture_build);
        fixture_cmd.step.dependOn(write_fixture_zon);
        fixture_cmd.step.dependOn(write_fixture_probe);
        single_front_package_step.dependOn(&fixture_cmd.step);
    }

    const agent_vm_spec_contract_cmd = b.addSystemCommand(&.{ "sh", "test/agent_vm_spec_contract/run.sh" });
    const agent_vm_spec_contract_step = b.step("agent-vm-spec-contract", "Check ArtifactV1 and HostAdapterV1 specification anchors.");
    agent_vm_spec_contract_step.dependOn(&agent_vm_spec_contract_cmd.step);
    test_step.dependOn(agent_vm_spec_contract_step);

    const artifact_v1_api_mod = b.createModule(.{
        .root_source_file = b.path("test/artifact_v1_api_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    artifact_v1_api_mod.addImport("shift_compile", shift_compile_mod);
    artifact_v1_api_mod.addImport("shift_vm", shift_vm_mod);
    artifact_v1_api_mod.addImport("example_open_row_state_writer", createShiftConsumerModule(
        b,
        "examples/open_row_state_writer.zig",
        target,
        optimize,
        .{
            .shift_mod = shift_mod,
            .shift_compile_mod = shift_compile_mod,
            .shift_vm_mod = shift_vm_mod,
            .lowered_runtime_mod = private_lowered_runtime_mod,
        },
    ));
    const artifact_v1_api_tests = b.addTest(.{
        .root_module = artifact_v1_api_mod,
    });
    const run_artifact_v1_api_tests = b.addRunArtifact(artifact_v1_api_tests);
    const artifact_v1_api_step = b.step("artifact-v1-api-check", "Check ArtifactV1 encode/decode/disasm and shift_compile artifact emission.");
    artifact_v1_api_step.dependOn(&run_artifact_v1_api_tests.step);
    test_step.dependOn(artifact_v1_api_step);

    const artifact_vm_runtime_mod = b.createModule(.{
        .root_source_file = b.path("test/artifact_vm_runtime_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const host_adapter_runtime_mod = b.createModule(.{
        .root_source_file = b.path("src/host_adapter_v1_conformance.zig"),
        .target = target,
        .optimize = optimize,
    });
    host_adapter_runtime_mod.addImport("shift_vm", shift_vm_mod);
    artifact_vm_runtime_mod.addImport("shift", shift_mod);
    artifact_vm_runtime_mod.addImport("host_adapter_v1_conformance", host_adapter_runtime_mod);
    artifact_vm_runtime_mod.addImport("internal_program_plan", internal_program_plan_mod);
    artifact_vm_runtime_mod.addImport("shift_compile", shift_compile_mod);
    artifact_vm_runtime_mod.addImport("shift_vm", shift_vm_mod);
    artifact_vm_runtime_mod.addImport("example_open_row_state_writer", createShiftConsumerModule(
        b,
        "examples/open_row_state_writer.zig",
        target,
        optimize,
        .{
            .shift_mod = shift_mod,
            .shift_compile_mod = shift_compile_mod,
            .shift_vm_mod = shift_vm_mod,
            .lowered_runtime_mod = private_lowered_runtime_mod,
        },
    ));
    const artifact_vm_runtime_tests = b.addTest(.{
        .root_module = artifact_vm_runtime_mod,
    });
    const run_artifact_vm_runtime_tests = b.addRunArtifact(artifact_vm_runtime_tests);
    const artifact_vm_runtime_step = b.step("artifact-vm-runtime-check", "Check synchronous ArtifactV1 execution over HostAdapterV1.");
    artifact_vm_runtime_step.dependOn(&run_artifact_vm_runtime_tests.step);
    test_step.dependOn(artifact_vm_runtime_step);

    const bundle_envelope_mod = b.createModule(.{
        .root_source_file = b.path("test/bundle_envelope_v1_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    bundle_envelope_mod.addImport("shift_compile", shift_compile_mod);
    bundle_envelope_mod.addImport("shift_vm", shift_vm_mod);
    bundle_envelope_mod.addImport("example_open_row_state_writer", createShiftConsumerModule(
        b,
        "examples/open_row_state_writer.zig",
        target,
        optimize,
        .{
            .shift_mod = shift_mod,
            .shift_compile_mod = shift_compile_mod,
            .shift_vm_mod = shift_vm_mod,
            .lowered_runtime_mod = private_lowered_runtime_mod,
        },
    ));
    const bundle_envelope_tests = b.addTest(.{
        .root_module = bundle_envelope_mod,
    });
    const run_bundle_envelope_tests = b.addRunArtifact(bundle_envelope_tests);
    const bundle_envelope_step = b.step("bundle-envelope-v1-check", "Check BundleEnvelopeV1 export/import and exact-build rejection.");
    bundle_envelope_step.dependOn(&run_bundle_envelope_tests.step);
    test_step.dependOn(bundle_envelope_step);

    const host_adapter_impl_mod = b.createModule(.{
        .root_source_file = b.path("src/host_adapter_v1_conformance.zig"),
        .target = target,
        .optimize = optimize,
    });
    host_adapter_impl_mod.addImport("shift_vm", shift_vm_mod);
    const host_adapter_conformance_mod = b.createModule(.{
        .root_source_file = b.path("test/host_adapter_v1_conformance_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    host_adapter_conformance_mod.addImport("shift_vm", shift_vm_mod);
    host_adapter_conformance_mod.addImport("host_adapter_v1_conformance", host_adapter_impl_mod);
    const host_adapter_conformance_tests = b.addTest(.{
        .root_module = host_adapter_conformance_mod,
    });
    const run_host_adapter_tests = b.addRunArtifact(host_adapter_conformance_tests);
    const host_adapter_conformance_step = b.step("host-adapter-conformance-check", "Check HostAdapterV1 request/result conformance helpers.");
    const host_adapter_v1_step = b.step("host-adapter-v1-conformance-check", "Compatibility alias for HostAdapterV1 request/result conformance helpers.");
    host_adapter_conformance_step.dependOn(&run_host_adapter_tests.step);
    host_adapter_v1_step.dependOn(&run_host_adapter_tests.step);
    test_step.dependOn(host_adapter_conformance_step);

    const artifact_dump_mod = b.createModule(.{
        .root_source_file = b.path("tools/artifact_v1_dump.zig"),
        .target = target,
        .optimize = optimize,
    });
    artifact_dump_mod.addImport("shift_vm", shift_vm_mod);
    const artifact_dump_exe = b.addExecutable(.{
        .name = "shift-artifact-v1-dump",
        .root_module = artifact_dump_mod,
    });
    const artifact_dump_install = b.addInstallArtifact(artifact_dump_exe, .{});
    const artifact_dump_step = b.step("artifact-v1-dump", "Build the ArtifactV1 dump tool.");
    artifact_dump_step.dependOn(&artifact_dump_exe.step);
    artifact_dump_step.dependOn(&artifact_dump_install.step);

    const artifact_vm_runner_mod = b.createModule(.{
        .root_source_file = b.path("tools/artifact_vm_state_writer_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    artifact_vm_runner_mod.addImport("shift_compile", shift_compile_mod);
    artifact_vm_runner_mod.addImport("shift_vm", shift_vm_mod);
    artifact_vm_runner_mod.addImport("example_open_row_state_writer", createShiftConsumerModule(
        b,
        "examples/open_row_state_writer.zig",
        target,
        optimize,
        .{
            .shift_mod = shift_mod,
            .shift_compile_mod = shift_compile_mod,
            .shift_vm_mod = shift_vm_mod,
            .lowered_runtime_mod = private_lowered_runtime_mod,
        },
    ));
    const artifact_vm_runner_exe = b.addExecutable(.{
        .name = "shift-artifact-vm-runner",
        .root_module = artifact_vm_runner_mod,
    });
    const artifact_vm_runner_step = b.step("artifact-vm-runner", "Build the native ArtifactV1 parity runner.");
    artifact_vm_runner_step.dependOn(&artifact_vm_runner_exe.step);

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
    });
    const shift_shared_wasm_mod = b.createModule(.{
        .root_source_file = b.path("src/shift_shared.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    const shift_compile_api_wasm_mod = b.createModule(.{
        .root_source_file = b.path("src/shift_compile_api.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    const private_bundle_env_wasm_mod = b.createModule(.{
        .root_source_file = b.path("src/bundle_envelope_v1.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    const private_host_adapter_wasm_mod = b.createModule(.{
        .root_source_file = b.path("src/host_adapter_v1.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    const private_artifact_vm_wasm_mod = b.createModule(.{
        .root_source_file = b.path("src/artifact_vm_runtime.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    const artifact_build_options_wasm = b.addOptions();
    artifact_build_options_wasm.addOption(
        [32]u8,
        "default_artifact_build_fingerprint",
        defaultArtifactBuildFingerprint(b, wasm_target, optimize),
    );
    shift_shared_wasm_mod.addOptions("artifact_build_options", artifact_build_options_wasm);
    shift_shared_wasm_mod.addImport("portable_core", portable_core_mod);
    shift_shared_wasm_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    shift_shared_wasm_mod.addImport("frontend_support", frontend_support_mod);
    shift_shared_wasm_mod.addImport("error_witness", error_witness_mod);
    shift_shared_wasm_mod.addImport("parity_scenarios", parity_scenarios_mod);
    shift_shared_wasm_mod.addImport("effect_ir", effect_ir_mod);
    shift_shared_wasm_mod.addImport("internal_kernel", internal_kernel_mod);
    shift_shared_wasm_mod.addImport("internal_program_plan", internal_program_plan_mod);
    shift_shared_wasm_mod.addImport("interpreter", interpreter_mod);
    shift_shared_wasm_mod.addImport("source_graph_engine", source_graph_engine_mod);
    shift_shared_wasm_mod.addImport("source_graph_comptime", source_graph_comptime_mod);
    shift_shared_wasm_mod.addImport("lowered_machine", lowered_machine_mod);
    shift_shared_wasm_mod.addImport("program_frontend", program_frontend_mod);
    shift_shared_wasm_mod.addImport("authoring_build_options", authoring_build_options_mod);
    shift_shared_wasm_mod.addImport("source_graph_embed", source_graph_embed_mod);
    shift_shared_wasm_mod.addImport("authoring_lowerer", authoring_lowerer_mod);
    shift_shared_wasm_mod.addImport("source_lowering", source_lowering_mod);
    const shift_wasm_mod = b.addModule("shift_wasm_artifact_runner", .{
        .root_source_file = b.path("src/root.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    shift_wasm_mod.addImport("shift_shared", shift_shared_wasm_mod);
    const shift_compile_wasm_mod = b.addModule("shift_compile_wasm_artifact_runner", .{
        .root_source_file = b.path("src/private_modules/shift_compile.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    shift_compile_wasm_mod.addImport("shift_shared", shift_shared_wasm_mod);
    shift_compile_api_wasm_mod.addImport("shift_shared", shift_shared_wasm_mod);
    shift_compile_wasm_mod.addImport("shift_compile_api", shift_compile_api_wasm_mod);
    const shift_vm_wasm_mod = b.addModule("shift_vm_wasm_artifact_runner", .{
        .root_source_file = b.path("src/private_modules/shift_vm.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    shift_vm_wasm_mod.addImport("shift_shared", shift_shared_wasm_mod);
    private_bundle_env_wasm_mod.addImport("shift_shared", shift_shared_wasm_mod);
    private_artifact_vm_wasm_mod.addImport("shift_shared", shift_shared_wasm_mod);
    private_artifact_vm_wasm_mod.addImport("host_adapter_v1", private_host_adapter_wasm_mod);
    shift_vm_wasm_mod.addImport("bundle_envelope_v1", private_bundle_env_wasm_mod);
    shift_vm_wasm_mod.addImport("host_adapter_v1", private_host_adapter_wasm_mod);
    shift_vm_wasm_mod.addImport("artifact_vm_runtime", private_artifact_vm_wasm_mod);
    const artifact_vm_wasm_runner_mod = b.createModule(.{
        .root_source_file = b.path("tools/artifact_vm_state_writer_runner.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    artifact_vm_wasm_runner_mod.addImport("shift_compile", shift_compile_wasm_mod);
    artifact_vm_wasm_runner_mod.addImport("shift_vm", shift_vm_wasm_mod);
    artifact_vm_wasm_runner_mod.addImport("example_open_row_state_writer", createShiftConsumerModule(
        b,
        "examples/open_row_state_writer.zig",
        wasm_target,
        optimize,
        .{
            .shift_mod = shift_wasm_mod,
            .shift_compile_mod = shift_compile_wasm_mod,
            .shift_vm_mod = shift_vm_wasm_mod,
            .lowered_runtime_mod = null,
        },
    ));
    const artifact_vm_wasm_runner_exe = b.addExecutable(.{
        .name = "shift-artifact-vm-runner-wasm",
        .root_module = artifact_vm_wasm_runner_mod,
    });
    const artifact_vm_wasm_step = b.step("artifact-vm-wasm-parity-check", "Run native and WASM ArtifactV1 state-writer parity through wasmtime.");
    const wasm_parity_cmd = b.addSystemCommand(&.{ "sh", "test/artifact_vm_wasm_parity/run.sh" });
    wasm_parity_cmd.addArtifactArg(artifact_vm_runner_exe);
    wasm_parity_cmd.addArtifactArg(artifact_vm_wasm_runner_exe);
    artifact_vm_wasm_step.dependOn(&wasm_parity_cmd.step);

    const structured_program_mod = b.createModule(.{
        .root_source_file = b.path("test/structured_program_suite.zig"),
        .target = target,
        .optimize = optimize,
    });
    structured_program_mod.addImport("shift", shift_shared_mod);
    structured_program_mod.addImport("program_frontend", program_frontend_mod);
    structured_program_mod.addImport("parity_kernel", parity_kernel_mod);
    structured_program_mod.addImport("parity_scenarios", parity_scenarios_mod);
    structured_program_mod.addImport("example_early_exit", createShiftConsumerModule(b, "examples/early_exit.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    structured_program_mod.addImport("example_exception_basic", createShiftConsumerModule(b, "examples/exception_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    structured_program_mod.addImport("example_nested_workflow", createShiftConsumerModule(b, "examples/nested_workflow.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    structured_program_mod.addImport("example_optional_basic", createShiftConsumerModule(b, "examples/optional_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    structured_program_mod.addImport("example_reader_basic", createShiftConsumerModule(b, "examples/reader_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    structured_program_mod.addImport("example_resume_or_return", createShiftConsumerModule(b, "examples/resume_or_return.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    structured_program_mod.addImport("example_state_basic", createShiftConsumerModule(b, "examples/state_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    const structured_program_tests = b.addTest(.{
        .root_module = structured_program_mod,
    });
    const run_structured_program_tests = b.addRunArtifact(structured_program_tests);
    const structured_program_step = b.step("structured-program-suite", "Run internal structured-program lowering and execution checks.");
    structured_program_step.dependOn(&authoring_lower_check_cmd.step);
    structured_program_step.dependOn(&run_structured_program_tests.step);

    const boundary_mod = b.createModule(.{
        .root_source_file = b.path("test/program_frontend_boundary_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    boundary_mod.addImport("effect_ir", effect_ir_mod);
    boundary_mod.addImport("program_frontend", program_frontend_mod);
    survey_runtime_mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);
    const runtime_route_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime_route_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    const runtime_stack_baseline_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime_stack_baseline.zig"),
        .target = target,
        .optimize = optimize,
    });
    runtime_stack_baseline_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    runtime_stack_baseline_mod.addImport("example_open_row_abortive_validation", createShiftConsumerModule(b, "examples/open_row_abortive_validation.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_open_row_artifact_search", createShiftConsumerModule(b, "examples/open_row_artifact_search.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_open_row_generator", createShiftConsumerModule(b, "examples/open_row_generator.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("witnesses_src", witnesses_mod);
    runtime_stack_baseline_mod.addImport("example_early_exit", createShiftConsumerModule(b, "examples/early_exit.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_exception_basic", createShiftConsumerModule(b, "examples/exception_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_nested_workflow", createShiftConsumerModule(b, "examples/nested_workflow.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_optional_basic", createShiftConsumerModule(b, "examples/optional_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_reader_basic", createShiftConsumerModule(b, "examples/reader_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_resource_basic", createShiftConsumerModule(b, "examples/resource_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_resume_or_return", createShiftConsumerModule(b, "examples/resume_or_return.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_state_basic", createShiftConsumerModule(b, "examples/state_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    runtime_stack_baseline_mod.addImport("example_writer_basic", createShiftConsumerModule(b, "examples/writer_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    const bridge_mod = b.createModule(.{
        .root_source_file = b.path("test/direct_style_bridge_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    bridge_mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);
    bridge_mod.addImport("program_bridge", program_bridge_mod);
    bridge_mod.addImport("direct_style_bridge_open_row_abortive_validation", createBridgeExampleModule(b, "test/direct_style_bridge/open_row_abortive_validation.zig", target, optimize, .{ .name = "example_open_row_abortive_validation", .mod = createShiftConsumerModule(b, "examples/open_row_abortive_validation.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_open_row_artifact_search", createBridgeExampleModule(b, "test/direct_style_bridge/open_row_artifact_search.zig", target, optimize, .{ .name = "example_open_row_artifact_search", .mod = createShiftConsumerModule(b, "examples/open_row_artifact_search.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_early_exit", createBridgeExampleModule(b, "test/direct_style_bridge/early_exit.zig", target, optimize, .{ .name = "example_early_exit", .mod = createShiftConsumerModule(b, "examples/early_exit.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_open_row_generator", createBridgeExampleModule(b, "test/direct_style_bridge/open_row_generator.zig", target, optimize, .{ .name = "example_open_row_generator", .mod = createShiftConsumerModule(b, "examples/open_row_generator.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_nested_workflow", createBridgeExampleModule(b, "test/direct_style_bridge/nested_workflow.zig", target, optimize, .{ .name = "example_nested_workflow", .mod = createShiftConsumerModule(b, "examples/nested_workflow.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_resource_basic", createBridgeExampleModule(b, "test/direct_style_bridge/resource_basic.zig", target, optimize, .{ .name = "example_resource_basic", .mod = createShiftConsumerModule(b, "examples/resource_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_resume_or_return", createBridgeExampleModule(b, "test/direct_style_bridge/resume_or_return.zig", target, optimize, .{ .name = "example_resume_or_return", .mod = createShiftConsumerModule(b, "examples/resume_or_return.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_state_basic", createBridgeExampleModule(b, "test/direct_style_bridge/state_basic.zig", target, optimize, .{ .name = "example_state_basic", .mod = createShiftConsumerModule(b, "examples/state_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_reader_basic", createBridgeExampleModule(b, "test/direct_style_bridge/reader_basic.zig", target, optimize, .{ .name = "example_reader_basic", .mod = createShiftConsumerModule(b, "examples/reader_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_optional_basic", createBridgeExampleModule(b, "test/direct_style_bridge/optional_basic.zig", target, optimize, .{ .name = "example_optional_basic", .mod = createShiftConsumerModule(b, "examples/optional_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_exception_basic", createBridgeExampleModule(b, "test/direct_style_bridge/exception_basic.zig", target, optimize, .{ .name = "example_exception_basic", .mod = createShiftConsumerModule(b, "examples/exception_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_writer_basic", createBridgeExampleModule(b, "test/direct_style_bridge/writer_basic.zig", target, optimize, .{ .name = "example_writer_basic", .mod = createShiftConsumerModule(b, "examples/writer_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    const bridge_boundary_mod = b.createModule(.{
        .root_source_file = b.path("test/direct_style_bridge_boundary_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    bridge_boundary_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    bridge_boundary_mod.addImport("direct_style_bridge_early_exit", createBridgeExampleModule(b, "test/direct_style_bridge/early_exit.zig", target, optimize, .{ .name = "example_early_exit", .mod = createShiftConsumerModule(b, "examples/early_exit.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }) }));
    bridge_boundary_mod.addImport("program_bridge", program_bridge_mod);
    bridge_boundary_mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);
    const boundary_tests = b.addTest(.{
        .root_module = boundary_mod,
    });
    const bridge_tests = b.addTest(.{
        .root_module = bridge_mod,
    });
    const bridge_boundary_tests = b.addTest(.{
        .root_module = bridge_boundary_mod,
    });
    const run_boundary_tests = b.addRunArtifact(boundary_tests);
    const run_bridge_tests = b.addRunArtifact(bridge_tests);
    run_bridge_tests.setName("hidden direct-style bridge parity runner");
    const run_bridge_boundary_tests = b.addRunArtifact(bridge_boundary_tests);
    const boundary_step = b.step("direct-style-boundary", "Run explicit boundary checks for unsupported raw direct-style lowering.");
    boundary_step.dependOn(&run_bridge_tests.step);
    boundary_step.dependOn(&run_boundary_tests.step);
    boundary_step.dependOn(&run_bridge_boundary_tests.step);

    const source_lowering_corpus_mod = b.createModule(.{
        .root_source_file = b.path("test/source_lowering_corpus_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_corpus_mod.addImport("source_lowering_registry", source_lowering_registry_mod);
    source_lowering_corpus_mod.addImport("source_lowering", source_lowering_mod);
    source_lowering_corpus_mod.addImport("lowered_machine", lowered_machine_mod);
    source_lowering_corpus_mod.addImport("parity_scenarios", parity_scenarios_mod);
    source_lowering_corpus_mod.addImport("source_fixture_branch_resume", createPlainModule(b, "test/source_lowering_corpus/fixtures/branch_resume.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_defer_resume", createPlainModule(b, "test/source_lowering_corpus/fixtures/defer_resume.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_errdefer_error", createPlainModule(b, "test/source_lowering_corpus/fixtures/errdefer_error.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_helper_call_resume", createPlainModule(b, "test/source_lowering_corpus/fixtures/helper_call_resume.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_local_mutation_resume", createPlainModule(b, "test/source_lowering_corpus/fixtures/local_mutation_resume.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_loop_resume", createPlainModule(b, "test/source_lowering_corpus/fixtures/loop_resume.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_nested_prompt_static_redelim", createPlainModule(b, "test/source_lowering_corpus/fixtures/nested_prompt_static_redelim.zig", target, optimize));
    source_lowering_corpus_mod.addImport("source_fixture_typed_error_try", createPlainModule(b, "test/source_lowering_corpus/fixtures/typed_error_try.zig", target, optimize));
    const src_lower_corpus_tests = b.addTest(.{
        .root_module = source_lowering_corpus_mod,
    });
    const run_src_lower_corpus_tests = b.addRunArtifact(src_lower_corpus_tests);

    const source_lowering_boundary_mod = b.createModule(.{
        .root_source_file = b.path("test/source_lowering_boundary_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_boundary_mod.addImport("source_lowering_registry", source_lowering_registry_mod);
    source_lowering_boundary_mod.addImport("source_lowering", source_lowering_mod);
    source_lowering_boundary_mod.addImport("shift", shift_shared_mod);
    const src_lower_boundary_tests = b.addTest(.{
        .root_module = source_lowering_boundary_mod,
    });
    const run_src_lower_boundary_tests = b.addRunArtifact(src_lower_boundary_tests);

    const source_lowering_promoted_mod = b.createModule(.{
        .root_source_file = b.path("test/source_lowering_promoted_cohort_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_promoted_mod.addImport("source_lowering", source_lowering_mod);
    source_lowering_promoted_mod.addImport("parity_scenarios", parity_scenarios_mod);
    source_lowering_promoted_mod.addImport("promoted_example_early_exit", createShiftConsumerModule(b, "examples/early_exit.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_open_row_abort_basic", createShiftConsumerModule(b, "examples/open_row_abort_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_open_row_abortive_validation", createShiftConsumerModule(b, "examples/open_row_abortive_validation.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_open_row_artifact_search", createShiftConsumerModule(b, "examples/open_row_artifact_search.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_open_row_choice_basic", createShiftConsumerModule(b, "examples/open_row_choice_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_open_row_generator", createShiftConsumerModule(b, "examples/open_row_generator.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_open_row_transform_basic", createShiftConsumerModule(b, "examples/open_row_transform_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_open_row_workflow", createShiftConsumerModule(b, "examples/open_row_workflow.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_resume_or_return", createShiftConsumerModule(b, "examples/resume_or_return.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_nested_workflow", createShiftConsumerModule(b, "examples/nested_workflow.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_state_basic", createShiftConsumerModule(b, "examples/state_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_reader_basic", createShiftConsumerModule(b, "examples/reader_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_optional_basic", createShiftConsumerModule(b, "examples/optional_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_exception_basic", createShiftConsumerModule(b, "examples/exception_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_resource_basic", createShiftConsumerModule(b, "examples/resource_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    source_lowering_promoted_mod.addImport("promoted_example_writer_basic", createShiftConsumerModule(b, "examples/writer_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    const src_lower_promoted_tests = b.addTest(.{
        .root_module = source_lowering_promoted_mod,
    });
    const run_src_lower_promoted_tests = b.addRunArtifact(src_lower_promoted_tests);

    const source_lowering_completion_mod = b.createModule(.{
        .root_source_file = b.path("test/source_lowering_completion_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_completion_mod.addImport("source_lowering", source_lowering_mod);
    source_lowering_completion_mod.addImport("parity_scenarios", parity_scenarios_mod);
    source_lowering_completion_mod.addImport("example_resource_basic", createShiftConsumerModule(b, "examples/resource_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    source_lowering_completion_mod.addImport("example_writer_basic", createShiftConsumerModule(b, "examples/writer_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = null }));
    const src_lower_completion_tests = b.addTest(.{
        .root_module = source_lowering_completion_mod,
    });
    const run_src_lower_completion_tests = b.addRunArtifact(src_lower_completion_tests);

    const open_row_lowering_mod = b.createModule(.{
        .root_source_file = b.path("test/open_row_lowering_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    open_row_lowering_mod.addImport("authoring_build_options", authoring_build_options_mod);
    open_row_lowering_mod.addImport("effect_ir", effect_ir_mod);
    open_row_lowering_mod.addImport("source_lowering", source_lowering_mod);
    open_row_lowering_mod.addImport("program_frontend", program_frontend_mod);
    open_row_lowering_mod.addImport("shift_compile", shift_compile_mod);
    open_row_lowering_mod.addImport("shift_vm", shift_vm_mod);
    open_row_lowering_mod.addImport("example_open_row_escaped_string_helper_body", createShiftConsumerModule(b, "examples/open_row_escaped_string_helper_body.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_linear_helper_body", createShiftConsumerModule(b, "examples/open_row_linear_helper_body.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_branching_helper_body", createShiftConsumerModule(b, "examples/open_row_branching_helper_body.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_cross_file_writer", createShiftConsumerModule(b, "examples/open_row_cross_file_writer.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_helper_bool_flow", createShiftConsumerModule(b, "examples/open_row_helper_bool_flow.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_helper_value_flow", createShiftConsumerModule(b, "examples/open_row_helper_value_flow.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_helper_value_flow_cross", createShiftConsumerModule(b, "examples/open_row_helper_value_flow_cross.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_state_writer", createShiftConsumerModule(b, "examples/open_row_state_writer.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_recursive_writer", createShiftConsumerModule(b, "examples/open_row_recursive_writer.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    open_row_lowering_mod.addImport("example_open_row_recursive_cross_writer", createShiftConsumerModule(b, "examples/open_row_recursive_cross_writer.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    const open_row_lowering_tests = b.addTest(.{
        .root_module = open_row_lowering_mod,
    });
    const run_open_row_lowering_tests = b.addRunArtifact(open_row_lowering_tests);
    const compile_fail_escape_helper_src =
        \\pub fn helper(eff: anytype) !void {
        \\    try eff.writer.tell("escaped");
        \\}
    ;
    const cf_escape_helper_target = std.fs.path.join(
        b.allocator,
        &.{ externalBoundaryFixtureRoot(b), "compile_fail_escape_helper_target.zig" },
    ) catch std.process.fatal("unable to allocate compile-fail helper target fixture path", .{});
    const cf_escape_helper_link = b.pathFromRoot("test/compile_fail_inputs/.compile_fail_escape_helper_link.zig");
    const compile_fail_escape_symlink_ok = compileFailEscapeSymlinkSupported(
        b,
        cf_escape_helper_target,
        cf_escape_helper_link,
    );
    const write_cf_escape_helper = addWriteTextFileCommand(
        b,
        cf_escape_helper_target,
        compile_fail_escape_helper_src,
        "write-compile-fail-escape-helper-fixture",
    );
    const prep_cf_escape_symlink = addAbsoluteSymlinkCommand(
        b,
        cf_escape_helper_target,
        cf_escape_helper_link,
        "write-compile-fail-escape-helper-symlink",
    );
    prep_cf_escape_symlink.dependOn(write_cf_escape_helper);

    const source_ownership_probe_mod = b.createModule(.{
        .root_source_file = b.path("test/source_ownership_probe_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_ownership_probe_mod.addImport("shift", shift_mod);
    source_ownership_probe_mod.addImport("shift_compile", shift_compile_mod);
    const source_ownership_probe_tests = b.addTest(.{
        .root_module = source_ownership_probe_mod,
    });
    const run_src_ownership_probe_tests = b.addRunArtifact(source_ownership_probe_tests);

    const src_lower_witness_mod = b.createModule(.{
        .root_source_file = b.path("test/source_lowering_witness_completion_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    src_lower_witness_mod.addImport("source_lowering", source_lowering_mod);
    src_lower_witness_mod.addImport("parity_scenarios", parity_scenarios_mod);
    src_lower_witness_mod.addImport("witness_sources", witness_sources_mod);
    const src_lower_witness_tests = b.addTest(.{
        .root_module = src_lower_witness_mod,
    });
    const run_src_lower_witness_tests = b.addRunArtifact(src_lower_witness_tests);

    const src_lower_reject_mod = b.createModule(.{
        .root_source_file = b.path("test/source_lowering_rejection_corpus_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    src_lower_reject_mod.addImport("source_lowering", source_lowering_mod);
    const src_lower_reject_tests = b.addTest(.{
        .root_module = src_lower_reject_mod,
    });
    const run_src_lower_reject_tests = b.addRunArtifact(src_lower_reject_tests);

    const source_lowering_contract_cmd = b.addSystemCommand(&.{ "sh", "test/source_lowering_contract/run.sh" });

    const source_lowering_matrix_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_source_lowering_matrix.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_matrix_mod.addImport("source_lowering_registry", source_lowering_registry_mod);
    const source_lowering_matrix_exe = b.addExecutable(.{
        .name = "shift-source-lowering-matrix",
        .root_module = source_lowering_matrix_mod,
    });
    const src_lower_matrix_check = b.addRunArtifact(source_lowering_matrix_exe);
    src_lower_matrix_check.addArg("check");
    const src_lower_matrix_chk_step = b.step("source-lowering-matrix-check", "Check the source-lowering matrix artifact.");
    src_lower_matrix_chk_step.dependOn(&src_lower_matrix_check.step);
    const src_lower_matrix_write = b.addRunArtifact(source_lowering_matrix_exe);
    src_lower_matrix_write.addArg("write");
    const src_lower_matrix_wr_step = b.step("source-lowering-matrix-write", "Refresh the source-lowering matrix artifact.");
    src_lower_matrix_wr_step.dependOn(&src_lower_matrix_write.step);

    const source_lowering_tool_mod = b.createModule(.{
        .root_source_file = b.path("tools/shift_source_lower.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_tool_mod.addImport("source_lowering", source_lowering_mod);
    source_lowering_tool_mod.addImport("lowered_machine", lowered_machine_mod);
    source_lowering_tool_mod.addImport("error_witness", error_witness_mod);
    const source_lowering_tool_exe = b.addExecutable(.{
        .name = "shift-source-lower",
        .root_module = source_lowering_tool_mod,
    });
    const source_lowering_tool_install = b.addInstallArtifact(source_lowering_tool_exe, .{});
    const source_lowering_tool_step = b.step("source-lower", "Build the internal source-lowering tool.");
    source_lowering_tool_step.dependOn(&source_lowering_tool_exe.step);
    source_lowering_tool_step.dependOn(&source_lowering_tool_install.step);
    const src_lower_tool_contract = b.addSystemCommand(&.{ "sh", "test/source_lowering_tool_contract/run.sh" });
    src_lower_tool_contract.step.dependOn(&source_lowering_tool_install.step);
    const src_lower_tool_contract_step = b.step("source-lowering-tool-contract", "Check internal source-lowering tool rejected and accepted emission contracts.");
    src_lower_tool_contract_step.dependOn(&src_lower_tool_contract.step);
    const src_lower_err_wit_cmd = b.addSystemCommand(&.{ "sh", "test/source_lowering_error_witness/run.sh" });
    src_lower_err_wit_cmd.step.dependOn(&source_lowering_tool_install.step);
    const src_lower_err_wit_step = b.step("source-lowering-error-witness-check", "Check that the source-lowering tool emits the checked public witness surface.");
    src_lower_err_wit_step.dependOn(&src_lower_err_wit_cmd.step);
    const public_error_api_ban_cmd = b.addSystemCommand(&.{ "sh", "test/public_error_api_ban/run.sh" });
    const public_error_api_ban_step = b.step("public-error-api-ban", "Fail closed if retired public root spellings reappear.");
    public_error_api_ban_step.dependOn(&public_error_api_ban_cmd.step);
    const public_root_snapshot_mod = b.createModule(.{
        .root_source_file = b.path("tools/check_public_root_contract_snapshot.zig"),
        .target = target,
        .optimize = optimize,
    });
    const public_root_snapshot_exe = b.addExecutable(.{
        .name = "shift-public-root-contract-snapshot",
        .root_module = public_root_snapshot_mod,
    });
    const public_root_snapshot_cmd = b.addRunArtifact(public_root_snapshot_exe);
    const public_root_snapshot_step = b.step("public-root-contract-snapshot-check", "Check the lexical-root public contract snapshot.");
    public_root_snapshot_step.dependOn(&public_root_snapshot_cmd.step);
    const interpreter_portability_mod = b.createModule(.{
        .root_source_file = b.path("tools/check_interpreter_portability.zig"),
        .target = target,
        .optimize = optimize,
    });
    const interpreter_portability_exe = b.addExecutable(.{
        .name = "shift-interpreter-portability-check",
        .root_module = interpreter_portability_mod,
    });
    const interpreter_portability_cmd = b.addRunArtifact(interpreter_portability_exe);
    const interpreter_portability_step = b.step("interpreter-portability-check", "Fail closed if the interpreter core takes on TLS or thread-affinity assumptions.");
    interpreter_portability_step.dependOn(&interpreter_portability_cmd.step);
    test_step.dependOn(interpreter_portability_step);
    const portable_core_mod_check = b.createModule(.{
        .root_source_file = b.path("tools/check_portable_core.zig"),
        .target = target,
        .optimize = optimize,
    });
    const portable_core_exe = b.addExecutable(.{
        .name = "shift-portable-core-check",
        .root_module = portable_core_mod_check,
    });
    const portable_core_cmd = b.addRunArtifact(portable_core_exe);
    const portable_core_step = b.step("portable-core-check", "Fail closed if the portable core takes on TLS or thread-affinity assumptions.");
    portable_core_step.dependOn(&portable_core_cmd.step);
    const retired_lane_inventory_mod = b.createModule(.{
        .root_source_file = b.path("tools/check_retired_lane_inventory.zig"),
        .target = target,
        .optimize = optimize,
    });
    const retired_lane_inventory_exe = b.addExecutable(.{
        .name = "shift-retired-lane-inventory",
        .root_module = retired_lane_inventory_mod,
    });
    const retired_lane_inventory_cmd = b.addRunArtifact(retired_lane_inventory_exe);
    const retired_lane_inventory_step = b.step("retired-lane-inventory-check", "Check that retired lane vocabulary stays out of proof-facing files.");
    retired_lane_inventory_step.dependOn(&retired_lane_inventory_cmd.step);
    const error_witness_equivalence_cmd = b.addSystemCommand(&.{ "sh", "test/error_witness_equivalence/run.sh" });
    error_witness_equivalence_cmd.step.dependOn(&source_lowering_tool_install.step);
    const error_witness_equivalence_step = b.step("error-witness-equivalence-check", "Check that canonical source-lowering witnesses expose an equivalent public runtime/setup witness surface across example cases.");
    error_witness_equivalence_step.dependOn(&error_witness_equivalence_cmd.step);

    test_step.dependOn(src_lower_err_wit_step);
    test_step.dependOn(public_error_api_ban_step);
    test_step.dependOn(public_root_snapshot_step);
    test_step.dependOn(portable_core_step);
    test_step.dependOn(retired_lane_inventory_step);
    test_step.dependOn(error_witness_equivalence_step);

    const source_lowering_coverage_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_source_lowering_coverage_matrix.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_lowering_coverage_mod.addImport("source_lowering_coverage_registry", src_lower_cov_registry_mod);
    const source_lowering_coverage_exe = b.addExecutable(.{
        .name = "shift-source-lowering-coverage-matrix",
        .root_module = source_lowering_coverage_mod,
    });
    const src_lower_cov_check = b.addRunArtifact(source_lowering_coverage_exe);
    src_lower_cov_check.addArg("check");
    const src_lower_cov_chk_step = b.step("source-lowering-coverage-check", "Check the source-lowering coverage matrix artifact.");
    src_lower_cov_chk_step.dependOn(&src_lower_cov_check.step);
    const src_lower_cov_write = b.addRunArtifact(source_lowering_coverage_exe);
    src_lower_cov_write.addArg("write");
    const src_lower_cov_wr_step = b.step("source-lowering-coverage-matrix-write", "Refresh the source-lowering coverage matrix artifact.");
    src_lower_cov_wr_step.dependOn(&src_lower_cov_write.step);

    const lowering_equivalence_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_lowering_equivalence_report.zig"),
        .target = target,
        .optimize = optimize,
    });
    lowering_equivalence_mod.addImport("source_lowering", source_lowering_mod);
    lowering_equivalence_mod.addImport("source_lowering_coverage_registry", src_lower_cov_registry_mod);
    lowering_equivalence_mod.addImport("source_lowering_registry", source_lowering_registry_mod);
    lowering_equivalence_mod.addImport("parity_scenarios", parity_scenarios_mod);
    lowering_equivalence_mod.addImport("lowered_machine", lowered_machine_mod);
    lowering_equivalence_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    lowering_equivalence_mod.addImport("program_bridge", program_bridge_mod);
    lowering_equivalence_mod.addImport("shipped_open_row_corpus_registry", shipped_open_row_corpus_mod);
    const lowering_equivalence_exe = b.addExecutable(.{
        .name = "shift-lowering-equivalence-report",
        .root_module = lowering_equivalence_mod,
    });
    const lower_eq_check = b.addRunArtifact(lowering_equivalence_exe);
    lower_eq_check.addArg("check");
    const lower_eq_chk_step = b.step("lowering-equivalence-report-check", "Check the legacy-named lowering admission report artifact.");
    lower_eq_chk_step.dependOn(&lower_eq_check.step);
    const lower_eq_write = b.addRunArtifact(lowering_equivalence_exe);
    lower_eq_write.addArg("write");
    const lower_eq_wr_step = b.step("lowering-equivalence-report-write", "Refresh the legacy-named lowering admission report artifact.");
    lower_eq_wr_step.dependOn(&lower_eq_write.step);

    const lowering_rejection_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_lowering_rejection_report.zig"),
        .target = target,
        .optimize = optimize,
    });
    lowering_rejection_mod.addImport("source_lowering", source_lowering_mod);
    const lowering_rejection_exe = b.addExecutable(.{
        .name = "shift-lowering-rejection-report",
        .root_module = lowering_rejection_mod,
    });
    const lower_reject_check = b.addRunArtifact(lowering_rejection_exe);
    lower_reject_check.addArg("check");
    const lower_reject_chk_step = b.step("lowering-rejection-report-check", "Check the lowering rejection report artifact.");
    lower_reject_chk_step.dependOn(&lower_reject_check.step);
    const lower_reject_write = b.addRunArtifact(lowering_rejection_exe);
    lower_reject_write.addArg("write");
    const lower_reject_wr_step = b.step("lowering-rejection-report-write", "Refresh the lowering rejection report artifact.");
    lower_reject_wr_step.dependOn(&lower_reject_write.step);

    const witness_admission_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/witness_admission_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    witness_admission_registry_mod.addImport("formal_core_registry", formal_core_registry_mod);
    bridge_manifest_mod.addImport("witness_admission_registry", witness_admission_registry_mod);
    bridge_boundary_mod.addImport("witness_admission_registry", witness_admission_registry_mod);
    const witness_admission_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_witness_admission_matrix.zig"),
        .target = target,
        .optimize = optimize,
    });
    witness_admission_mod.addImport("witness_admission_registry", witness_admission_registry_mod);
    const witness_admission_exe = b.addExecutable(.{
        .name = "shift-witness-admission-matrix",
        .root_module = witness_admission_mod,
    });
    const witness_admission_check_cmd = b.addRunArtifact(witness_admission_exe);
    witness_admission_check_cmd.addArg("check");
    const witness_admission_check_step = b.step("witness-admission-matrix-check", "Check the witness admission matrix.");
    witness_admission_check_step.dependOn(&witness_admission_check_cmd.step);
    const witness_admission_write_cmd = b.addRunArtifact(witness_admission_exe);
    witness_admission_write_cmd.addArg("write");
    const witness_admission_write_step = b.step("witness-admission-matrix-write", "Refresh the witness admission matrix.");
    witness_admission_write_step.dependOn(&witness_admission_write_cmd.step);

    const source_lowering_gauntlet_step = b.step("kernel-source-lowering-check", "Check the internal source-lowering proof surface beneath the root execution kernel.");
    source_lowering_gauntlet_step.dependOn(&run_src_lower_corpus_tests.step);
    source_lowering_gauntlet_step.dependOn(&run_src_lower_boundary_tests.step);
    source_lowering_gauntlet_step.dependOn(&run_src_lower_promoted_tests.step);
    source_lowering_gauntlet_step.dependOn(&run_src_lower_completion_tests.step);
    source_lowering_gauntlet_step.dependOn(&run_open_row_lowering_tests.step);
    source_lowering_gauntlet_step.dependOn(&run_src_ownership_probe_tests.step);
    source_lowering_gauntlet_step.dependOn(&run_src_lower_witness_tests.step);
    source_lowering_gauntlet_step.dependOn(&run_src_lower_reject_tests.step);
    source_lowering_gauntlet_step.dependOn(&source_lowering_contract_cmd.step);
    source_lowering_gauntlet_step.dependOn(&src_lower_matrix_check.step);
    source_lowering_gauntlet_step.dependOn(&src_lower_tool_contract.step);
    source_lowering_gauntlet_step.dependOn(lower_eq_chk_step);
    source_lowering_gauntlet_step.dependOn(lower_reject_chk_step);
    test_step.dependOn(source_lowering_gauntlet_step);

    const scorecard_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_surface_truth_scorecard.zig"),
        .target = target,
        .optimize = optimize,
    });
    scorecard_mod.addImport("program_frontend", program_frontend_mod);
    scorecard_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    scorecard_mod.addImport("source_lowering_registry", source_lowering_registry_mod);
    scorecard_mod.addImport("source_lowering_coverage_registry", src_lower_cov_registry_mod);
    const scorecard_exe = b.addExecutable(.{
        .name = "shift-surface-truth-scorecard",
        .root_module = scorecard_mod,
    });
    const scorecard_check_cmd = b.addRunArtifact(scorecard_exe);
    scorecard_check_cmd.addArg("check");
    const scorecard_check_step = b.step("surface-truth-scorecard-check", "Check the machine-readable surface-truth scorecard.");
    scorecard_check_step.dependOn(&scorecard_check_cmd.step);
    const scorecard_write_cmd = b.addRunArtifact(scorecard_exe);
    scorecard_write_cmd.addArg("write");
    const scorecard_write_step = b.step("surface-truth-scorecard-write", "Refresh the machine-readable surface-truth scorecard.");
    scorecard_write_step.dependOn(&scorecard_write_cmd.step);

    const route_matrix_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_runtime_route_matrix.zig"),
        .target = target,
        .optimize = optimize,
    });
    route_matrix_mod.addImport("runtime_route_registry", runtime_route_registry_mod);
    const route_matrix_exe = b.addExecutable(.{
        .name = "shift-runtime-route-matrix",
        .root_module = route_matrix_mod,
    });
    const route_matrix_check_cmd = b.addRunArtifact(route_matrix_exe);
    route_matrix_check_cmd.addArg("check");
    const route_matrix_check_step = b.step("runtime-route-matrix-check", "Check the runtime route matrix artifact.");
    route_matrix_check_step.dependOn(&route_matrix_check_cmd.step);
    const route_matrix_write_cmd = b.addRunArtifact(route_matrix_exe);
    route_matrix_write_cmd.addArg("write");
    const route_matrix_write_step = b.step("runtime-route-matrix-write", "Refresh the runtime route matrix artifact.");
    route_matrix_write_step.dependOn(&route_matrix_write_cmd.step);

    const obligation_matrix_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime_obligation_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    const obligation_matrix_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_runtime_obligation_matrix.zig"),
        .target = target,
        .optimize = optimize,
    });
    obligation_matrix_mod.addImport("runtime_obligation_registry", obligation_matrix_registry_mod);
    const obligation_matrix_exe = b.addExecutable(.{
        .name = "shift-runtime-obligation-matrix",
        .root_module = obligation_matrix_mod,
    });
    const obligation_matrix_check_cmd = b.addRunArtifact(obligation_matrix_exe);
    obligation_matrix_check_cmd.addArg("check");
    const obligation_matrix_check_step = b.step("runtime-obligation-matrix-check", "Check the runtime obligation matrix artifact.");
    obligation_matrix_check_step.dependOn(&obligation_matrix_check_cmd.step);
    const obligation_matrix_write_cmd = b.addRunArtifact(obligation_matrix_exe);
    obligation_matrix_write_cmd.addArg("write");
    const obligation_matrix_write_step = b.step("runtime-obligation-matrix-write", "Refresh the runtime obligation matrix artifact.");
    obligation_matrix_write_step.dependOn(&obligation_matrix_write_cmd.step);

    const error_surface_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime_error_surface_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    error_surface_registry_mod.addImport("error_witness", error_witness_mod);
    const error_surface_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_runtime_error_surface_matrix.zig"),
        .target = target,
        .optimize = optimize,
    });
    error_surface_mod.addImport("runtime_error_surface_registry", error_surface_registry_mod);
    const error_surface_exe = b.addExecutable(.{
        .name = "shift-runtime-error-surface-matrix",
        .root_module = error_surface_mod,
    });
    const error_surface_check_cmd = b.addRunArtifact(error_surface_exe);
    error_surface_check_cmd.addArg("check");
    const error_surface_check_step = b.step("runtime-error-surface-matrix-check", "Check the public runtime error surface matrix.");
    error_surface_check_step.dependOn(&error_surface_check_cmd.step);
    const error_surface_write_cmd = b.addRunArtifact(error_surface_exe);
    error_surface_write_cmd.addArg("write");
    const error_surface_write_step = b.step("runtime-error-surface-matrix-write", "Refresh the public runtime error surface matrix.");
    error_surface_write_step.dependOn(&error_surface_write_cmd.step);

    const lexical_witness_runners_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_witness_support.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_witness_runners_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
    const structured_witness_runner_mod = b.createModule(.{
        .root_source_file = b.path("test/structured_witness_runner_suite.zig"),
        .target = target,
        .optimize = optimize,
    });
    structured_witness_runner_mod.addImport("lexical_witness_runners", lexical_witness_runners_mod);
    structured_witness_runner_mod.addImport("parity_kernel", parity_kernel_mod);
    structured_witness_runner_mod.addImport("program_frontend", program_frontend_mod);
    const structured_witness_tests = b.addTest(.{
        .root_module = structured_witness_runner_mod,
    });
    const run_structured_witness_tests = b.addRunArtifact(structured_witness_tests);
    structured_program_step.dependOn(&run_structured_witness_tests.step);
    test_step.dependOn(&run_structured_witness_tests.step);

    const bridge_witness_runner_mod = b.createModule(.{
        .root_source_file = b.path("test/direct_style_bridge_witness_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    bridge_witness_runner_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    bridge_witness_runner_mod.addImport("lexical_witness_runners", lexical_witness_runners_mod);
    bridge_witness_runner_mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);
    const bridge_witness_tests = b.addTest(.{
        .root_module = bridge_witness_runner_mod,
    });
    const run_bridge_witness_tests = b.addRunArtifact(bridge_witness_tests);
    test_step.dependOn(&run_bridge_witness_tests.step);

    const lexical_witness_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_witness_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_witness_mod.addImport("shift", shift_shared_mod);
    lexical_witness_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
    lexical_witness_mod.addImport("parity_scenarios", parity_scenarios_mod);
    lexical_witness_mod.addImport("lexical_witness_runners", lexical_witness_runners_mod);
    const lexical_witness_tests = b.addTest(.{
        .root_module = lexical_witness_mod,
    });
    const run_lexical_witness_tests = b.addRunArtifact(lexical_witness_tests);
    const lexical_witness_step = b.step("lexical-witness-suite", "Run the lexical witness proof surface.");
    lexical_witness_step.dependOn(&run_lexical_witness_tests.step);
    test_step.dependOn(&run_lexical_witness_tests.step);

    const lexical_with_mod = b.createModule(.{
        .root_source_file = b.path("test/lexical_with_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexical_with_mod.addImport("lexical_runtime_internal", lexical_runtime_internal_mod);
    const lexical_with_tests = b.addTest(.{
        .root_module = lexical_with_mod,
    });
    const run_lexical_with_tests = b.addRunArtifact(lexical_with_tests);
    const lexical_with_step = b.step("lexical-with-suite", "Run the lexical descriptor/runtime helper proof surface.");
    lexical_with_step.dependOn(&run_lexical_with_tests.step);
    test_step.dependOn(&run_lexical_with_tests.step);
    const cleanup_contract_step = b.step("cleanup-contract-check", "Check cleanup-stack and resource cleanup contracts through the existing lexical/resource proof surface.");
    cleanup_contract_step.dependOn(&run_lexical_with_tests.step);

    const shipped_frontier_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/shipped_surface_frontier_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    const shipped_frontier_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_shipped_surface_frontier_matrix.zig"),
        .target = target,
        .optimize = optimize,
    });
    shipped_frontier_mod.addImport("shipped_surface_frontier_registry", shipped_frontier_registry_mod);
    const shipped_frontier_exe = b.addExecutable(.{
        .name = "shift-shipped-surface-frontier-matrix",
        .root_module = shipped_frontier_mod,
    });
    const shipped_frontier_check_cmd = b.addRunArtifact(shipped_frontier_exe);
    shipped_frontier_check_cmd.addArg("check");
    const shipped_frontier_check_step = b.step("shipped-surface-frontier-matrix-check", "Check the shipped-surface frontier matrix.");
    shipped_frontier_check_step.dependOn(&shipped_frontier_check_cmd.step);
    const shipped_frontier_write_cmd = b.addRunArtifact(shipped_frontier_exe);
    shipped_frontier_write_cmd.addArg("write");
    const shipped_frontier_write_step = b.step("shipped-surface-frontier-matrix-write", "Refresh the shipped-surface frontier matrix.");
    shipped_frontier_write_step.dependOn(&shipped_frontier_write_cmd.step);

    const no_raw_repo_refs_cmd = b.addSystemCommand(&.{ "sh", "test/no_raw_repo_refs/run.sh" });
    const no_raw_repo_refs_step = b.step("no-raw-repo-refs-check", "Fail closed when repo-facing raw runtime references remain.");
    no_raw_repo_refs_step.dependOn(&no_raw_repo_refs_cmd.step);

    const frontend_feature_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/frontend_feature_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    const frontend_feature_mod = b.createModule(.{
        .root_source_file = b.path("tools/render_frontend_feature_matrix.zig"),
        .target = target,
        .optimize = optimize,
    });
    frontend_feature_mod.addImport("frontend_feature_registry", frontend_feature_registry_mod);
    const frontend_feature_exe = b.addExecutable(.{
        .name = "shift-frontend-feature-matrix",
        .root_module = frontend_feature_mod,
    });
    const frontend_feature_check_cmd = b.addRunArtifact(frontend_feature_exe);
    frontend_feature_check_cmd.addArg("check");
    const frontend_feature_check_step = b.step("frontend-feature-matrix-check", "Check the canonical frontend feature matrix.");
    frontend_feature_check_step.dependOn(&frontend_feature_check_cmd.step);
    const frontend_feature_write_cmd = b.addRunArtifact(frontend_feature_exe);
    frontend_feature_write_cmd.addArg("write");
    const frontend_feature_write_step = b.step("frontend-feature-matrix-write", "Refresh the canonical frontend feature matrix.");
    frontend_feature_write_step.dependOn(&frontend_feature_write_cmd.step);

    const shipped_backend_cmd = b.addSystemCommand(&.{ "sh", "test/shipped_backend_contract/run.sh" });
    shipped_backend_cmd.setName("hidden shipped backend contract runner");
    const shipped_backend_step = b.step("shipped-backend-contract", "Check the shipped backend contract guard.");
    shipped_backend_step.dependOn(&shipped_backend_cmd.step);
    test_step.dependOn(shipped_backend_step);

    test_step.dependOn(&authoring_lower_check_cmd.step);
    test_step.dependOn(&run_bridge_tests.step);
    test_step.dependOn(&run_boundary_tests.step);
    test_step.dependOn(&run_bridge_boundary_tests.step);
    test_step.dependOn(&run_structured_program_tests.step);

    const compile_fail_step = b.step("compile-fail", "Verify compile-fail misuse fixtures.");
    const one_shot_success_fixtures = [_]struct {
        name: []const u8,
        path: []const u8,
    }{
        .{ .name = "one-shot-protocol-resume-transform", .path = "test/one_shot_survey/protocol_resume_transform_compiles.zig" },
        .{ .name = "one-shot-protocol-erroring-resume-transform", .path = "test/one_shot_survey/protocol_erroring_resume_transform_compiles.zig" },
        .{ .name = "one-shot-protocol-direct-return", .path = "test/one_shot_survey/protocol_direct_return_compiles.zig" },
        .{ .name = "one-shot-protocol-erroring-direct-return", .path = "test/one_shot_survey/protocol_erroring_direct_return_compiles.zig" },
        .{ .name = "one-shot-protocol-resume-or-return", .path = "test/one_shot_survey/protocol_resume_or_return_compiles.zig" },
        .{ .name = "one-shot-protocol-erroring-resume-or-return", .path = "test/one_shot_survey/protocol_erroring_resume_or_return_compiles.zig" },
    };
    inline for (one_shot_success_fixtures) |fixture| {
        const fixture_mod = createShiftPromptFixtureModule(b, fixture.path, target, optimize, .{
            .authoring_build_options_mod = authoring_build_options_mod,
            .shift_mod = shift_mod,
            .shift_compile_mod = shift_compile_mod,
            .shift_vm_mod = shift_vm_mod,
            .prompt_support_mod = prompt_support_mod,
            .with_api_mod = with_api_mod,
        });
        const fixture_check = b.addObject(.{
            .name = fixture.name,
            .root_module = fixture_mod,
        });
        const fixture_check_step = b.step(fixture.name, "Compile one plain-Zig one-shot survey success fixture.");
        fixture_check_step.dependOn(&fixture_check.step);
    }
    const one_shot_runtime_mod = b.createModule(.{
        .root_source_file = b.path("test/one_shot_survey/runtime_success_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    one_shot_runtime_mod.addImport("survey_resume_transform_executes", survey_runtime_mod);
    const one_shot_runtime_tests = b.addTest(.{
        .root_module = one_shot_runtime_mod,
    });
    const run_one_shot_runtime_tests = b.addRunArtifact(one_shot_runtime_tests);
    const one_shot_survey_step = b.step("one-shot-survey", "Run the current plain-Zig one-shot survey contract.");
    inline for (one_shot_success_fixtures) |fixture| {
        const fixture_mod = createShiftPromptFixtureModule(b, fixture.path, target, optimize, .{
            .authoring_build_options_mod = authoring_build_options_mod,
            .shift_mod = shift_mod,
            .shift_compile_mod = shift_compile_mod,
            .shift_vm_mod = shift_vm_mod,
            .prompt_support_mod = prompt_support_mod,
            .with_api_mod = with_api_mod,
        });
        const fixture_check = b.addObject(.{
            .name = fixture.name ++ "-aggregate",
            .root_module = fixture_mod,
        });
        one_shot_survey_step.dependOn(&fixture_check.step);
        test_step.dependOn(&fixture_check.step);
    }
    one_shot_survey_step.dependOn(&run_one_shot_runtime_tests.step);
    test_step.dependOn(&run_one_shot_runtime_tests.step);

    const compile_fail_owned_fixtures = [_]struct {
        name: []const u8,
        path: []const u8,
        expected: []const u8,
    }{
        .{ .name = "cf-retired-program", .path = "test/compile_fail/retired_program_fails.zig", .expected = "has no member named 'Transform'" },
        .{ .name = "cf-retired-decl", .path = "test/compile_fail/retired_decl_fails.zig", .expected = "has no member named 'Choice'" },
        .{ .name = "cf-retired-op", .path = "test/compile_fail/retired_op_fails.zig", .expected = "has no member named 'Abort'" },
        .{ .name = "cf-retired-ops", .path = "test/compile_fail/retired_ops_fails.zig", .expected = "has no member named 'Row'" },
        .{ .name = "cf-retired-runwith", .path = "test/compile_fail/retired_runwith_fails.zig", .expected = "has no member named 'mergeRows'" },
        .{ .name = "cf-retired-rowspec", .path = "test/compile_fail/retired_rowspec_fails.zig", .expected = "has no member named 'effects'" },
        .{ .name = "cf-retired-mergerowspecs", .path = "test/compile_fail/retired_mergerowspecs_fails.zig", .expected = "has no member named 'handlers'" },
        .{ .name = "cf-resume-value-mismatch", .path = "test/compile_fail/resume_value_mismatch.zig", .expected = ".resumeValue must have type fn () Resume or fn () ResetError(ErrorSet)!Resume" },
        .{ .name = "cf-source-ownership-mismatch", .path = "test/compile_fail/source_ownership_mismatch_fails.zig", .expected = "public lowering source ownership requires caller_file to end with repo_path" },
        .{ .name = "cf-source-ownership-content-mirror", .path = "test/compile_fail/source_ownership_content_mirror_fails.zig", .expected = "public lowering source ownership requires caller_file to end with repo_path" },
        .{ .name = "cf-source-ownership-absolute-content-mirror", .path = "test/compile_fail/source_ownership_absolute_content_mirror_fails.zig", .expected = "public lowering source ownership requires caller_file to end with repo_path" },
        .{ .name = "cf-absolute-owned-helper-import-absolute-path", .path = "test/compile_fail/absolute_owned_helper_import_absolute_path_fails.zig", .expected = "public lowering imported source helper requires a non-escaping relative .zig import path" },
        .{ .name = "cf-absolute-owned-helper-import-windows-absolute-path", .path = "test/compile_fail/absolute_owned_helper_import_windows_absolute_path_fails.zig", .expected = "public lowering imported source helper requires a non-escaping relative .zig import path" },
        .{ .name = "cf-absolute-owned-helper-import-escape", .path = "test/compile_fail/absolute_owned_helper_import_escape_fails.zig", .expected = "public lowering imported source helper requires a non-escaping relative .zig import path" },
        .{ .name = "cf-source-ownership-relative-no-content", .path = "test/compile_fail/source_ownership_relative_no_content_witness_fails.zig", .expected = "public lowering source ownership requires caller_file to end with repo_path" },
        .{ .name = "cf-source-ownership-relative-hash-only", .path = "test/compile_fail/source_ownership_relative_hash_only_witness_fails.zig", .expected = "public lowering source ownership requires caller_file to end with repo_path" },
        .{ .name = "cf-source-ownership-relative-content", .path = "test/compile_fail/source_ownership_relative_content_witness_fails.zig", .expected = "public lowering source ownership requires caller_file to end with repo_path" },
        .{ .name = "cf-source-ownership-basename-witness", .path = "test/compile_fail/source_ownership_basename_witness_fails.zig", .expected = "public lowering source ownership requires caller_file to end with repo_path" },
        .{ .name = "cf-source-ownership-owned-root-suffix-spoof", .path = "test/compile_fail/source_ownership_owned_root_suffix_spoof_fails.zig", .expected = "public lowering source ownership requires caller_file to end with repo_path" },
        .{ .name = "cf-source-with-content-parse-error", .path = "test/compile_fail/source_with_content_parse_error_fails.zig", .expected = "public lowering rejected source text that does not parse as Zig" },
        .{ .name = "cf-source-with-content-missing-imported-helper", .path = "test/compile_fail/source_with_content_missing_imported_helper_fails.zig", .expected = "public lowering could not resolve one imported helper module or helper symbol" },
        .{ .name = "cf-source-ref-missing-imported-helper", .path = "test/compile_fail/source_ref_missing_imported_helper_fails.zig", .expected = "public lowering could not resolve one imported helper module or helper symbol" },
        .{ .name = "cf-source-with-content-owned-helper-override", .path = "test/compile_fail/source_with_content_owned_helper_override_fails.zig", .expected = "public lowering source ownership requires caller_file to end with repo_path" },
        .{ .name = "cf-source-with-content-absolute-owned-repo-helper-override", .path = "test/compile_fail/source_with_content_absolute_owned_repo_helper_override_fails.zig", .expected = "public lowering could not resolve one imported helper module or helper symbol" },
        .{ .name = "cf-public-ir-entry-value-run", .path = "test/compile_fail/public_ir_entry_value_run_fails.zig", .expected = "public lowered-program execution is available only when the entry function has no value parameters" },
        .{ .name = "cf-public-ir-value-dst", .path = "test/compile_fail/public_ir_value_dst_fails.zig", .expected = "runtime plan generator produced an instruction with an out-of-range function-local reference" },
        .{ .name = "cf-public-ir-terminator-precondition", .path = "test/compile_fail/public_ir_terminator_precondition_fails.zig", .expected = "runtime plan generator produced a block terminator without its required producer instruction" },
        .{ .name = "cf-public-ir-blockless-entry", .path = "test/compile_fail/public_ir_blockless_entry_fails.zig", .expected = "runtime plan generator produced an invalid function entry block" },
        .{ .name = "cf-public-ir-invalid-call-helper-target", .path = "test/compile_fail/public_ir_invalid_call_helper_target_fails.zig", .expected = "runtime plan generator produced an out-of-range helper target" },
        .{ .name = "cf-public-ir-foreign-row-call-op", .path = "test/compile_fail/public_ir_foreign_row_call_op_fails.zig", .expected = "runtime plan generator produced an out-of-range or foreign-row op target" },
        .{ .name = "cf-string-list-codec", .path = "test/compile_fail/string_list_codec_fails.zig", .expected = "public lowering runtime plan rejected string_list values across executable boundaries" },
        .{ .name = "cf-entry-value-param-lower-at", .path = "test/compile_fail/entry_value_param_lower_at_fails.zig", .expected = "public lowering rejected entry functions with value parameters because run(runtime, handlers) cannot supply entry arguments" },
        .{ .name = "cf-unsupported-helper-body", .path = "test/compile_fail/unsupported_helper_body_fails.zig", .expected = "public lowering cannot synthesize unsupported helper or entry bodies; test/compile_fail_inputs/unsupported_helper_body_source.zig:helper must stay within the retained lowered-body subset" },
        .{ .name = "cf-helper-import-escape-lower-at", .path = "test/compile_fail/helper_import_escape_lower_at_fails.zig", .expected = "public lowering source path must resolve to an owned repo file" },
        .{ .name = "cf-helper-import-escape-ir-program-at", .path = "test/compile_fail/helper_import_escape_ir_program_at_fails.zig", .expected = "public lowering source path must resolve to an owned repo file" },
        .{ .name = "cf-entry-path-escape-lower-at", .path = "test/compile_fail/entry_path_escape_lower_at_fails.zig", .expected = "public lowering source path must stay under the package root" },
        .{ .name = "cf-entry-path-escape-ir-program-at", .path = "test/compile_fail/entry_path_escape_ir_program_at_fails.zig", .expected = "public lowering source path must stay under the package root" },
        .{ .name = "cf-collect-closed-outputs-const-mutating-finish", .path = "test/compile_fail/collect_closed_outputs_const_mutating_finish_fails.zig", .expected = "cast discards const qualifier" },
        .{ .name = "cf-one-shot-missing-after-resume", .path = "test/one_shot_survey/missing_after_resume_fails.zig", .expected = "must declare afterResume" },
        .{ .name = "cf-one-shot-missing-resume-or-return", .path = "test/one_shot_survey/missing_resume_or_return_fails.zig", .expected = "must declare resumeOrReturn" },
        .{ .name = "cf-one-shot-wrong-after-resume", .path = "test/one_shot_survey/wrong_after_resume_type_fails.zig", .expected = ".afterResume must have type fn (InAnswer) OutAnswer or fn (InAnswer) ResetError(ErrorSet)!OutAnswer" },
        .{ .name = "cf-one-shot-wrong-ror-type", .path = "test/one_shot_survey/wrong_resume_or_return_type_fails.zig", .expected = ".resumeOrReturn must have type fn () ResumeOrReturn or fn () ResetError(ErrorSet)!ResumeOrReturn" },
        .{ .name = "cf-one-shot-wrong-ror-after", .path = "test/one_shot_survey/wrong_resume_or_return_after_resume_fails.zig", .expected = ".afterResume must have type fn (InAnswer) OutAnswer or fn (InAnswer) ResetError(ErrorSet)!OutAnswer" },
        .{ .name = "cf-one-shot-direct-return-mode-mismatch", .path = "test/one_shot_survey/direct_return_mode_mismatch_fails.zig", .expected = "must declare directReturn" },
        .{ .name = "cf-one-shot-legacy-alias", .path = "test/one_shot_survey/legacy_continuation_alias_recheck_fails.zig", .expected = "has no member named 'Continuation'" },
        .{ .name = "cf-one-shot-legacy-store", .path = "test/one_shot_survey/legacy_continuation_store_recheck_fails.zig", .expected = "has no member named 'Continuation'" },
    };
    assertOwnedCompileFailFixtures(b, "test/compile_fail", compile_fail_owned_fixtures);

    const compile_fail_fixtures = [_]struct {
        name: []const u8,
        path: []const u8,
        expected: []const u8,
    }{
        .{ .name = "cf-retired-program", .path = "test/compile_fail/retired_program_fails.zig", .expected = "has no member named 'Transform'" },
        .{ .name = "cf-retired-decl", .path = "test/compile_fail/retired_decl_fails.zig", .expected = "has no member named 'Choice'" },
        .{ .name = "cf-retired-op", .path = "test/compile_fail/retired_op_fails.zig", .expected = "has no member named 'Abort'" },
        .{ .name = "cf-retired-ops", .path = "test/compile_fail/retired_ops_fails.zig", .expected = "has no member named 'Row'" },
        .{ .name = "cf-retired-runwith", .path = "test/compile_fail/retired_runwith_fails.zig", .expected = "has no member named 'mergeRows'" },
        .{ .name = "cf-retired-rowspec", .path = "test/compile_fail/retired_rowspec_fails.zig", .expected = "has no member named 'effects'" },
        .{ .name = "cf-retired-mergerowspecs", .path = "test/compile_fail/retired_mergerowspecs_fails.zig", .expected = "has no member named 'handlers'" },
        .{ .name = "cf-resume-value-mismatch", .path = "test/compile_fail/resume_value_mismatch.zig", .expected = ".resumeValue must have type fn () Resume or fn () ResetError(ErrorSet)!Resume" },
        .{ .name = "cf-source-ownership-mismatch", .path = "test/compile_fail/source_ownership_mismatch_fails.zig", .expected = "public lowering source ownership requires caller_file to end with repo_path" },
        .{ .name = "cf-source-ownership-content-mirror", .path = "test/compile_fail/source_ownership_content_mirror_fails.zig", .expected = "public lowering source ownership requires caller_file to end with repo_path" },
        .{ .name = "cf-source-ownership-absolute-content-mirror", .path = "test/compile_fail/source_ownership_absolute_content_mirror_fails.zig", .expected = "public lowering source ownership requires caller_file to end with repo_path" },
        .{ .name = "cf-absolute-owned-helper-import-absolute-path", .path = "test/compile_fail/absolute_owned_helper_import_absolute_path_fails.zig", .expected = "public lowering imported source helper requires a non-escaping relative .zig import path" },
        .{ .name = "cf-absolute-owned-helper-import-windows-absolute-path", .path = "test/compile_fail/absolute_owned_helper_import_windows_absolute_path_fails.zig", .expected = "public lowering imported source helper requires a non-escaping relative .zig import path" },
        .{ .name = "cf-absolute-owned-helper-import-escape", .path = "test/compile_fail/absolute_owned_helper_import_escape_fails.zig", .expected = "public lowering imported source helper requires a non-escaping relative .zig import path" },
        .{ .name = "cf-source-ownership-relative-no-content", .path = "test/compile_fail/source_ownership_relative_no_content_witness_fails.zig", .expected = "public lowering source ownership requires caller_file to end with repo_path" },
        .{ .name = "cf-source-ownership-relative-hash-only", .path = "test/compile_fail/source_ownership_relative_hash_only_witness_fails.zig", .expected = "public lowering source ownership requires caller_file to end with repo_path" },
        .{ .name = "cf-source-ownership-relative-content", .path = "test/compile_fail/source_ownership_relative_content_witness_fails.zig", .expected = "public lowering source ownership requires caller_file to end with repo_path" },
        .{ .name = "cf-source-ownership-basename-witness", .path = "test/compile_fail/source_ownership_basename_witness_fails.zig", .expected = "public lowering source ownership requires caller_file to end with repo_path" },
        .{ .name = "cf-source-ownership-owned-root-suffix-spoof", .path = "test/compile_fail/source_ownership_owned_root_suffix_spoof_fails.zig", .expected = "public lowering source ownership requires caller_file to end with repo_path" },
        .{ .name = "cf-source-with-content-parse-error", .path = "test/compile_fail/source_with_content_parse_error_fails.zig", .expected = "public lowering rejected source text that does not parse as Zig" },
        .{ .name = "cf-source-with-content-missing-imported-helper", .path = "test/compile_fail/source_with_content_missing_imported_helper_fails.zig", .expected = "public lowering could not resolve one imported helper module or helper symbol" },
        .{ .name = "cf-source-ref-missing-imported-helper", .path = "test/compile_fail/source_ref_missing_imported_helper_fails.zig", .expected = "public lowering could not resolve one imported helper module or helper symbol" },
        .{ .name = "cf-source-with-content-owned-helper-override", .path = "test/compile_fail/source_with_content_owned_helper_override_fails.zig", .expected = "public lowering source ownership requires caller_file to end with repo_path" },
        .{ .name = "cf-source-with-content-absolute-owned-repo-helper-override", .path = "test/compile_fail/source_with_content_absolute_owned_repo_helper_override_fails.zig", .expected = "public lowering could not resolve one imported helper module or helper symbol" },
        .{ .name = "cf-public-ir-entry-value-run", .path = "test/compile_fail/public_ir_entry_value_run_fails.zig", .expected = "public lowered-program execution is available only when the entry function has no value parameters" },
        .{ .name = "cf-public-ir-value-dst", .path = "test/compile_fail/public_ir_value_dst_fails.zig", .expected = "runtime plan generator produced an instruction with an out-of-range function-local reference" },
        .{ .name = "cf-public-ir-terminator-precondition", .path = "test/compile_fail/public_ir_terminator_precondition_fails.zig", .expected = "runtime plan generator produced a block terminator without its required producer instruction" },
        .{ .name = "cf-public-ir-blockless-entry", .path = "test/compile_fail/public_ir_blockless_entry_fails.zig", .expected = "runtime plan generator produced an invalid function entry block" },
        .{ .name = "cf-public-ir-invalid-call-helper-target", .path = "test/compile_fail/public_ir_invalid_call_helper_target_fails.zig", .expected = "runtime plan generator produced an out-of-range helper target" },
        .{ .name = "cf-public-ir-foreign-row-call-op", .path = "test/compile_fail/public_ir_foreign_row_call_op_fails.zig", .expected = "runtime plan generator produced an out-of-range or foreign-row op target" },
        .{ .name = "cf-string-list-codec", .path = "test/compile_fail/string_list_codec_fails.zig", .expected = "public lowering runtime plan rejected string_list values across executable boundaries" },
        .{ .name = "cf-entry-value-param-lower-at", .path = "test/compile_fail/entry_value_param_lower_at_fails.zig", .expected = "public lowering rejected entry functions with value parameters because run(runtime, handlers) cannot supply entry arguments" },
        .{ .name = "cf-unsupported-helper-body", .path = "test/compile_fail/unsupported_helper_body_fails.zig", .expected = "public lowering cannot synthesize unsupported helper or entry bodies; test/compile_fail_inputs/unsupported_helper_body_source.zig:helper must stay within the retained lowered-body subset" },
        .{ .name = "cf-entry-path-escape-lower-at", .path = "test/compile_fail/entry_path_escape_lower_at_fails.zig", .expected = "public lowering source path must stay under the package root" },
        .{ .name = "cf-entry-path-escape-ir-program-at", .path = "test/compile_fail/entry_path_escape_ir_program_at_fails.zig", .expected = "public lowering source path must stay under the package root" },
        .{ .name = "cf-collect-closed-outputs-const-mutating-finish", .path = "test/compile_fail/collect_closed_outputs_const_mutating_finish_fails.zig", .expected = "cast discards const qualifier" },
        .{ .name = "cf-one-shot-missing-after-resume", .path = "test/one_shot_survey/missing_after_resume_fails.zig", .expected = "must declare afterResume" },
        .{ .name = "cf-one-shot-missing-resume-or-return", .path = "test/one_shot_survey/missing_resume_or_return_fails.zig", .expected = "must declare resumeOrReturn" },
        .{ .name = "cf-one-shot-wrong-after-resume", .path = "test/one_shot_survey/wrong_after_resume_type_fails.zig", .expected = ".afterResume must have type fn (InAnswer) OutAnswer or fn (InAnswer) ResetError(ErrorSet)!OutAnswer" },
        .{ .name = "cf-one-shot-wrong-ror-type", .path = "test/one_shot_survey/wrong_resume_or_return_type_fails.zig", .expected = ".resumeOrReturn must have type fn () ResumeOrReturn or fn () ResetError(ErrorSet)!ResumeOrReturn" },
        .{ .name = "cf-one-shot-wrong-ror-after", .path = "test/one_shot_survey/wrong_resume_or_return_after_resume_fails.zig", .expected = ".afterResume must have type fn (InAnswer) OutAnswer or fn (InAnswer) ResetError(ErrorSet)!OutAnswer" },
        .{ .name = "cf-one-shot-direct-return-mode-mismatch", .path = "test/one_shot_survey/direct_return_mode_mismatch_fails.zig", .expected = "must declare directReturn" },
        .{ .name = "cf-one-shot-legacy-alias", .path = "test/one_shot_survey/legacy_continuation_alias_recheck_fails.zig", .expected = "has no member named 'Continuation'" },
        .{ .name = "cf-one-shot-legacy-store", .path = "test/one_shot_survey/legacy_continuation_store_recheck_fails.zig", .expected = "has no member named 'Continuation'" },
    };
    inline for (compile_fail_fixtures) |fixture| {
        const fixture_mod = createShiftPromptFixtureModule(b, fixture.path, target, optimize, .{
            .authoring_build_options_mod = authoring_build_options_mod,
            .shift_mod = shift_mod,
            .shift_compile_mod = shift_compile_mod,
            .shift_vm_mod = shift_vm_mod,
            .prompt_support_mod = prompt_support_mod,
            .with_api_mod = with_api_mod,
        });
        const fixture_check = b.addObject(.{
            .name = fixture.name,
            .root_module = fixture_mod,
        });
        fixture_check.expect_errors = .{ .contains = fixture.expected };
        compile_fail_step.dependOn(&fixture_check.step);
        test_step.dependOn(&fixture_check.step);
    }
    // Hosts without symlink support still need ordinary build/test lanes to stay usable.
    if (compile_fail_escape_symlink_ok) {
        const compile_fail_escape_fixtures = [_]struct {
            name: []const u8,
            path: []const u8,
            expected: []const u8,
        }{
            .{ .name = "cf-helper-import-escape-lower-at", .path = "test/compile_fail/helper_import_escape_lower_at_fails.zig", .expected = "public lowering source path must resolve to an owned repo file" },
            .{ .name = "cf-helper-import-escape-ir-program-at", .path = "test/compile_fail/helper_import_escape_ir_program_at_fails.zig", .expected = "public lowering source path must resolve to an owned repo file" },
        };
        inline for (compile_fail_escape_fixtures) |fixture| {
            const fixture_mod = createShiftPromptFixtureModule(b, fixture.path, target, optimize, .{
                .authoring_build_options_mod = authoring_build_options_mod,
                .shift_mod = shift_mod,
                .shift_compile_mod = shift_compile_mod,
                .shift_vm_mod = shift_vm_mod,
                .prompt_support_mod = prompt_support_mod,
                .with_api_mod = with_api_mod,
            });
            const fixture_check = b.addObject(.{
                .name = fixture.name,
                .root_module = fixture_mod,
            });
            fixture_check.step.dependOn(prep_cf_escape_symlink);
            fixture_check.expect_errors = .{ .contains = fixture.expected };
            compile_fail_step.dependOn(&fixture_check.step);
            test_step.dependOn(&fixture_check.step);
        }
    }

    const example_proof_mod = b.createModule(.{
        .root_source_file = b.path("test/example_proof_suite.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_proof_mod.addImport("example_open_row_abort_basic", createShiftConsumerModule(b, "examples/open_row_abort_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    example_proof_mod.addImport("example_open_row_abortive_validation", createShiftConsumerModule(b, "examples/open_row_abortive_validation.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    example_proof_mod.addImport("example_open_row_artifact_search", createShiftConsumerModule(b, "examples/open_row_artifact_search.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    example_proof_mod.addImport("example_open_row_choice_basic", createShiftConsumerModule(b, "examples/open_row_choice_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    example_proof_mod.addImport("example_open_row_generator", createShiftConsumerModule(b, "examples/open_row_generator.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    example_proof_mod.addImport("example_open_row_state_writer", createShiftConsumerModule(b, "examples/open_row_state_writer.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    example_proof_mod.addImport("example_open_row_transform_basic", createShiftConsumerModule(b, "examples/open_row_transform_basic.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    example_proof_mod.addImport("example_open_row_workflow", createShiftConsumerModule(b, "examples/open_row_workflow.zig", target, optimize, .{ .shift_mod = shift_mod, .shift_compile_mod = shift_compile_mod, .shift_vm_mod = shift_vm_mod, .lowered_runtime_mod = private_lowered_runtime_mod }));
    const example_proof_tests = b.addTest(.{
        .root_module = example_proof_mod,
    });
    const run_example_proof_tests = b.addRunArtifact(example_proof_tests);
    const example_proof_step = b.step("example-proof", "Run exact-output proof for the shipped checked example corpus.");
    example_proof_step.dependOn(&proof_fixture_check_cmd.step);
    example_proof_step.dependOn(&run_example_proof_tests.step);
    test_step.dependOn(&proof_fixture_check_cmd.step);
    test_step.dependOn(&run_example_proof_tests.step);

    const examples = [_]struct {
        name: []const u8,
        src: []const u8,
        step_name: []const u8,
        step_desc: []const u8,
    }{
        .{
            .name = "durable_session_demo",
            .src = "examples/durable_session_demo.zig",
            .step_name = "durable-session-demo",
            .step_desc = "Run the append-only durable session demo.",
        },
        .{
            .name = "early_exit",
            .src = "examples/early_exit.zig",
            .step_name = "run-early-exit",
            .step_desc = "Run the direct-return example.",
        },
        .{
            .name = "exception_basic",
            .src = "examples/exception_basic.zig",
            .step_name = "run-exception-basic",
            .step_desc = "Run the direct-return exception effect example.",
        },
        .{
            .name = "nested_workflow",
            .src = "examples/nested_workflow.zig",
            .step_name = "run-nested-workflow",
            .step_desc = "Run the nested workflow example.",
        },
        .{
            .name = "optional_basic",
            .src = "examples/optional_basic.zig",
            .step_name = "run-optional-basic",
            .step_desc = "Run the optional-resumption effect example.",
        },
        .{
            .name = "resume_or_return",
            .src = "examples/resume_or_return.zig",
            .step_name = "run-resume-or-return",
            .step_desc = "Run the optional-resumption example.",
        },
        .{
            .name = "open_row_state_writer",
            .src = "examples/open_row_state_writer.zig",
            .step_name = "run-open-row-state-writer",
            .step_desc = "Run the checked state-plus-writer example (legacy proof label).",
        },
        .{
            .name = "reader_basic",
            .src = "examples/reader_basic.zig",
            .step_name = "run-reader-basic",
            .step_desc = "Run the additive reader-effect example.",
        },
        .{
            .name = "resource_basic",
            .src = "examples/resource_basic.zig",
            .step_name = "run-resource-basic",
            .step_desc = "Run the bracketed resource effect example.",
        },
        .{
            .name = "writer_basic",
            .src = "examples/writer_basic.zig",
            .step_name = "run-writer-basic",
            .step_desc = "Run the append-only writer effect example.",
        },
        .{
            .name = "state_basic",
            .src = "examples/state_basic.zig",
            .step_name = "run-state-basic",
            .step_desc = "Run the additive state-effect example.",
        },
    };

    inline for (examples) |example| {
        const mod = b.createModule(.{
            .root_source_file = b.path(example.src),
            .target = target,
            .optimize = optimize,
        });
        mod.addImport("shift", shift_mod);
        mod.addImport("shift_compile", shift_compile_mod);
        mod.addImport("shift_vm", shift_vm_mod);
        mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);

        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = mod,
        });
        b.installArtifact(exe);
        check_step.dependOn(&exe.step);

        const run = b.addRunArtifact(exe);
        const run_step = b.step(example.step_name, example.step_desc);
        run_step.dependOn(&run.step);
    }

    inline for (shipped_open_row_corpus.custom_examples) |example| {
        const mod = b.createModule(.{
            .root_source_file = b.path(example.source_path),
            .target = target,
            .optimize = optimize,
        });
        mod.addImport("shift", shift_mod);
        mod.addImport("shift_compile", shift_compile_mod);
        mod.addImport("shift_vm", shift_vm_mod);
        mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);

        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = mod,
        });
        b.installArtifact(exe);
        check_step.dependOn(&exe.step);

        const run = b.addRunArtifact(exe);
        const run_step = b.step(example.run_step_name, example.run_step_desc);
        run_step.dependOn(&run.step);
    }

    const shift_bench_mod = b.createModule(.{
        .root_source_file = b.path("src/bench_support.zig"),
        .target = target,
        .optimize = bench_optimize,
    });
    shift_bench_mod.addImport("portable_core", portable_core_mod);
    shift_bench_mod.addImport("prompt_contract_support", prompt_contract_support_mod);
    shift_bench_mod.addImport("frontend_support", frontend_support_mod);
    shift_bench_mod.addImport("error_witness", error_witness_mod);
    shift_bench_mod.addImport("parity_scenarios", parity_scenarios_mod);
    shift_bench_mod.addImport("effect_ir", effect_ir_mod);
    shift_bench_mod.addImport("internal_kernel", internal_kernel_mod);
    shift_bench_mod.addImport("internal_program_plan", internal_program_plan_mod);
    shift_bench_mod.addImport("interpreter", interpreter_mod);
    shift_bench_mod.addImport("source_graph_engine", source_graph_engine_mod);
    shift_bench_mod.addImport("source_graph_comptime", source_graph_comptime_mod);
    shift_bench_mod.addImport("lowered_machine", lowered_machine_mod);
    shift_bench_mod.addImport("program_frontend", program_frontend_mod);
    shift_bench_mod.addImport("authoring_build_options", authoring_build_options_mod);
    shift_bench_mod.addImport("source_graph_embed", source_graph_embed_mod);
    shift_bench_mod.addImport("authoring_lowerer", authoring_lowerer_mod);
    shift_bench_mod.addImport("source_lowering", source_lowering_mod);
    const bench_specs = [_]struct {
        name: []const u8,
        src: []const u8,
        step_name: []const u8,
        step_desc: []const u8,
    }{
        .{
            .name = "shift-direct-no-capture-bench",
            .src = "bench/no_capture_bench.zig",
            .step_name = "bench",
            .step_desc = "Run the direct-style no-capture benchmark.",
        },
        .{
            .name = "shift-direct-first-suspend-bench",
            .src = "bench/direct_first_suspend_bench.zig",
            .step_name = "bench-first-suspend",
            .step_desc = "Run the direct-style first-suspend benchmark.",
        },
        .{
            .name = "shift-state-effect-bench",
            .src = "bench/state_effect_bench.zig",
            .step_name = "bench-state-effect",
            .step_desc = "Compare the additive state effect against the raw prompt baseline.",
        },
        .{
            .name = "shift-effect-family-matrix-bench",
            .src = "bench/effect_family_matrix_bench.zig",
            .step_name = "bench-family-matrix",
            .step_desc = "Compare every shipped declaration family against its chosen comparator lane.",
        },
        .{
            .name = "shift-algebraic-builder-decompose-bench",
            .src = "bench/algebraic_builder_decompose_bench.zig",
            .step_name = "bench-family-builder-decompose",
            .step_desc = "Decompose family-builder shell and full-path costs.",
        },
        .{
            .name = "shift-writer-effect-decompose-bench",
            .src = "bench/writer_effect_decompose_bench.zig",
            .step_name = "bench-writer-decompose",
            .step_desc = "Decompose writer-effect storage and finalization costs.",
        },
        .{
            .name = "shift-resource-effect-decompose-bench",
            .src = "bench/resource_effect_decompose_bench.zig",
            .step_name = "bench-resource-decompose",
            .step_desc = "Decompose resource-effect acquire and cleanup costs.",
        },
        .{
            .name = "shift-abortive-effect-decompose-bench",
            .src = "bench/abortive_effect_decompose_bench.zig",
            .step_name = "bench-abortive-decompose",
            .step_desc = "Decompose heavier abortive optional and exception costs.",
        },
    };

    inline for (bench_specs) |bench_spec| {
        const bench_mod = b.createModule(.{
            .root_source_file = b.path(bench_spec.src),
            .target = target,
            .optimize = bench_optimize,
        });
        bench_mod.addImport("shift", shift_bench_mod);
        bench_mod.addImport("lowered_machine", lowered_machine_mod);
        const bench_exe = b.addExecutable(.{
            .name = bench_spec.name,
            .root_module = bench_mod,
        });
        const bench_run = b.addRunArtifact(bench_exe);
        const bench_step = b.step(bench_spec.step_name, bench_spec.step_desc);
        bench_step.dependOn(&bench_run.step);
    }

    const runtime_backend_bench_mod = b.createModule(.{
        .root_source_file = b.path("bench/runtime_backend_matrix_bench.zig"),
        .target = target,
        .optimize = bench_optimize,
    });
    runtime_backend_bench_mod.addImport("direct_style_bridge_manifest", bridge_manifest_mod);
    runtime_backend_bench_mod.addImport("private_lowered_runtime", private_lowered_runtime_mod);
    runtime_backend_bench_mod.addImport("runtime_stack_baseline", runtime_stack_baseline_mod);
    const runtime_backend_bench_exe = b.addExecutable(.{
        .name = "shift-runtime-backend-matrix-bench",
        .root_module = runtime_backend_bench_mod,
    });
    const runtime_backend_bench_run = b.addRunArtifact(runtime_backend_bench_exe);
    const runtime_backend_bench_step = b.step("bench-runtime-backends", "Compare the current stack runtime against the lowered runtime over the supported bridge corpus.");
    runtime_backend_bench_step.dependOn(&runtime_backend_bench_run.step);

    const zprof_hotspots_step = b.step("zprof-hotspots", "Profile writer/resource allocator hotspots with zprof.");
    if (b.lazyDependency("zprof", .{
        .target = target,
        .optimize = bench_optimize,
    })) |zprof_dep| {
        const zprof_hotspots_mod = b.createModule(.{
            .root_source_file = b.path("bench/zprof_hotspots.zig"),
            .target = target,
            .optimize = bench_optimize,
        });
        zprof_hotspots_mod.addImport("shift", shift_bench_mod);
        zprof_hotspots_mod.addImport("zprof", zprof_dep.module("zprof"));
        const zprof_hotspots_exe = b.addExecutable(.{
            .name = "shift-zprof-hotspots",
            .root_module = zprof_hotspots_mod,
        });
        const zprof_hotspots_run = b.addRunArtifact(zprof_hotspots_exe);
        zprof_hotspots_step.dependOn(&zprof_hotspots_run.step);
    }

    const bench_artifact_write_cmd = b.addSystemCommand(&.{ "sh", "bench/state_effect_artifact.sh", "write" });
    const bench_artifact_write_step = b.step("bench-state-effect-write", "Refresh the checked state-effect benchmark artifact.");
    bench_artifact_write_step.dependOn(&bench_artifact_write_cmd.step);

    const bench_artifact_check_cmd = b.addSystemCommand(&.{ "sh", "bench/state_effect_artifact.sh", "check" });
    const bench_artifact_check_step = b.step("bench-state-effect-check", "Check the state-effect benchmark artifact against the current clean tree.");
    bench_artifact_check_step.dependOn(&bench_artifact_check_cmd.step);

    const bench_matrix_write_cmd = b.addSystemCommand(&.{ "sh", "bench/effect_family_matrix_artifact.sh", "write" });
    const bench_matrix_write_step = b.step("bench-family-matrix-write", "Refresh the checked family-matrix benchmark artifact.");
    bench_matrix_write_step.dependOn(&bench_matrix_write_cmd.step);

    const bench_matrix_check_cmd = b.addSystemCommand(&.{ "sh", "bench/effect_family_matrix_artifact.sh", "check" });
    const bench_matrix_check_step = b.step("bench-family-matrix-check", "Check the family-matrix benchmark artifact against the current clean tree.");
    bench_matrix_check_step.dependOn(&bench_matrix_check_cmd.step);

    const bench_matrix_stability_cmd = b.addSystemCommand(&.{ "sh", "bench/effect_matrix_stability.sh" });
    const bench_matrix_stability_step = b.step("bench-family-matrix-stability", "Run repeated clean-tree family-matrix stability characterization.");
    bench_matrix_stability_step.dependOn(&bench_matrix_stability_cmd.step);

    const runtime_backend_write_cmd = b.addSystemCommand(&.{ "sh", "bench/runtime_backend_matrix_artifact.sh", "write" });
    const runtime_backend_write_step = b.step("bench-runtime-backends-write", "Refresh the checked runtime backend comparison artifact.");
    runtime_backend_write_step.dependOn(&runtime_backend_write_cmd.step);

    const runtime_backend_check_cmd = b.addSystemCommand(&.{ "sh", "bench/runtime_backend_matrix_artifact.sh", "check" });
    const runtime_backend_check_step = b.step("bench-runtime-backends-check", "Check the runtime backend comparison artifact against the current clean tree.");
    runtime_backend_check_step.dependOn(&runtime_backend_check_cmd.step);

    const runtime_backend_stability_cmd = b.addSystemCommand(&.{ "sh", "bench/runtime_backend_stability.sh" });
    const runtime_backend_stability_step = b.step("bench-runtime-backends-stability", "Run repeated clean-tree lowered-vs-stack backend stability characterization.");
    runtime_backend_stability_step.dependOn(&runtime_backend_stability_cmd.step);

    const lint_step = b.step("lint", "Lint source code.");
    lint_step.dependOn(step: {
        const saved_verbose = b.verbose;
        b.verbose = true;
        defer b.verbose = saved_verbose;
        var builder = zlinter.builder(b, .{});
        builder.addPaths(.{
            // Feed zlinter the explicit repo path registry so lint stays fail-closed
            // without relying on recursive cwd walking or exclude-index construction.
            .include = repoZigLintIncludePaths(b),
            .exclude = &.{},
        });
        inline for (@typeInfo(zlinter.BuiltinLintRule).@"enum".fields) |field| {
            const rule: zlinter.BuiltinLintRule = @enumFromInt(field.value);
            builder.addRule(.{ .builtin = rule }, .{});
        }
        break :step builder.build();
    });
}
