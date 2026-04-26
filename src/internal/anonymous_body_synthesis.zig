// zlinter-disable declaration_naming - anonymous-body provenance helpers intentionally mirror compiler-produced names during restoration work.
// zlinter-disable no_empty_block - tiny witness bodies in local tests intentionally stay minimal while the seam is under construction.
// zlinter-disable no_unused - nearby restoration helpers stay together while the with_api cutover is still in progress.
// zlinter-disable no_deprecated - restoration code intentionally keeps historical std.mem search helpers until the seam stabilizes.
// zlinter-disable require_doc_comment - this is an internal provenance/synthesis helper, not a user-facing API surface.
// zlinter-disable require_labeled_continue - tokenizer loops remain close to the historical implementation during restoration.
// zlinter-disable require_exhaustive_enum_switch - tokenizer tag switches intentionally handle only delimiter/brace tokens; all other tags are data-bearing fallthrough.
// zlinter-disable max_positional_args - synthetic source helpers preserve the explicit packet shape while the seam stabilizes.
// zlinter-disable import_ordering - sibling source_graph imports intentionally stay grouped beside lowering helpers during restoration work.
const build_options = @import("authoring_build_options");
const lexical_manifest = @import("lexical_manifest.zig");
const lowering_api = @import("lowering_api");
const source_lowering = @import("source_lowering");
const source_graph_embed = @import("source_graph_embed");
const source_graph_engine = @import("source_graph_engine");
const std = @import("std");

/// Call-site families supported by anonymous-body source synthesis.
pub const CompilationKind = enum {
    none,
    owned_source,
    plain_with,
};

const Bounds = struct {
    start: usize,
    end: usize,
};

const AnonymousBodyIdentity = struct {
    module_path: []const u8,
    enclosing_function: []const u8,
    struct_suffix: []const u8,
};

fn registryContainsLine(comptime registry: []const u8, comptime candidate: []const u8) bool {
    comptime {
        @setEvalBranchQuota(2_000_000);
    }
    var start: usize = 0;
    while (start < registry.len) {
        var end = start;
        while (end < registry.len and registry[end] != '\n') : (end += 1) {}
        const line = registry[start..end];
        if (line.len != 0 and std.mem.eql(u8, line, candidate)) return true;
        start = end + 1;
    }
    return false;
}

fn sourceModulePath(comptime source_path_value: []const u8) []const u8 {
    const without_ext = if (std.mem.endsWith(u8, source_path_value, ".zig"))
        source_path_value[0 .. source_path_value.len - ".zig".len]
    else
        source_path_value;
    const normalized = if (std.mem.startsWith(u8, without_ext, "./") or std.mem.startsWith(u8, without_ext, ".\\"))
        without_ext[2..]
    else
        without_ext;

    const dotted = comptime blk: {
        var buffer: [normalized.len]u8 = undefined;
        for (normalized, 0..) |char, idx| {
            buffer[idx] = switch (char) {
                '/', '\\' => '.',
                else => char,
            };
        }
        break :blk buffer;
    };
    return dotted[0..];
}

fn sourceBaseModuleName(comptime source_path_value: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = source_path_value.len;
    for (source_path_value, 0..) |char, index| {
        if (char == '/' or char == '\\') start = index + 1;
    }
    if (std.mem.endsWith(u8, source_path_value[start..end], ".zig")) {
        end -= ".zig".len;
    }
    return source_path_value[start..end];
}

fn isTestModulePath(comptime module_path: []const u8) bool {
    return std.mem.endsWith(u8, module_path, ".test");
}

fn canonicalLookupModulePath(comptime module_path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, module_path, ".test")) {
        return module_path[0 .. module_path.len - ".test".len];
    }
    return module_path;
}

fn candidateAllowsBaseModuleAlias(comptime candidate: []const u8) bool {
    if (std.mem.indexOfScalar(u8, candidate, '/')) |first_slash| {
        const rest = candidate[first_slash + 1 ..];
        return std.mem.indexOfScalar(u8, rest, '/') == null;
    }
    return true;
}

fn modulePathMatchesCandidate(
    comptime module_path: []const u8,
    comptime candidate: []const u8,
) bool {
    if (std.mem.eql(u8, module_path, candidate)) return true;
    if (std.mem.indexOfScalar(u8, candidate, '.')) |_| {
        if (std.mem.endsWith(u8, module_path, "." ++ candidate)) return true;
    }
    return false;
}

pub fn bodyIdentity(comptime Body: type) ?AnonymousBodyIdentity {
    comptime {
        @setEvalBranchQuota(20_000);
    }
    const name = @typeName(Body);
    const struct_marker_index = std.mem.indexOf(u8, name, "__struct_") orelse return null;
    const before_struct = name[0..struct_marker_index];
    if (std.mem.indexOf(u8, before_struct, ".test.")) |test_index| {
        const module_end = test_index + ".test".len;
        return .{
            .module_path = before_struct[0..module_end],
            .enclosing_function = before_struct[module_end + 1 ..],
            .struct_suffix = name[struct_marker_index..],
        };
    }
    const function_dot_index = std.mem.lastIndexOfScalar(u8, before_struct, '.') orelse return null;
    return .{
        .module_path = before_struct[0..function_dot_index],
        .enclosing_function = before_struct[function_dot_index + 1 ..],
        .struct_suffix = name[struct_marker_index..],
    };
}

pub fn canonicalEnclosingFunctionName(comptime function_name: []const u8) []const u8 {
    const anon_index = std.mem.indexOf(u8, function_name, "__anon_") orelse return function_name;
    return function_name[0..anon_index];
}

pub fn resolvedRepoPath(comptime Body: type) ?[]const u8 {
    const identity = bodyIdentity(Body) orelse return null;
    const lookup_module = canonicalLookupModulePath(identity.module_path);
    comptime {
        @setEvalBranchQuota(10_000_000);
    }
    var best_score: u8 = 0;
    var match_count: usize = 0;
    var matched_path: ?[]const u8 = null;
    var start: usize = 0;
    while (start < build_options.repo_zig_paths.len) {
        var end = start;
        while (end < build_options.repo_zig_paths.len and build_options.repo_zig_paths[end] != '\n') : (end += 1) {}
        const candidate = build_options.repo_zig_paths[start..end];
        start = end + 1;
        if (candidate.len == 0) continue;
        const canonical_module = sourceModulePath(candidate);
        const base_module = sourceBaseModuleName(candidate);
        const example_alias: ?[]const u8 = if (std.mem.startsWith(u8, candidate, "examples/") and candidateAllowsBaseModuleAlias(candidate))
            std.fmt.comptimePrint("example_{s}", .{base_module})
        else
            null;
        const test_alias: ?[]const u8 = if (std.mem.startsWith(u8, candidate, "test/"))
            base_module
        else
            null;
        const score: u8 = if (modulePathMatchesCandidate(lookup_module, canonical_module))
            4
        else if (example_alias != null and modulePathMatchesCandidate(lookup_module, example_alias.?))
            3
        else if (test_alias != null and modulePathMatchesCandidate(lookup_module, test_alias.?))
            2
        else if (candidateAllowsBaseModuleAlias(candidate) and modulePathMatchesCandidate(lookup_module, base_module))
            1
        else
            continue;

        if (score > best_score) {
            best_score = score;
            match_count = 1;
            matched_path = candidate;
            continue;
        }
        if (score == best_score) {
            match_count += 1;
        }
    }
    if (match_count != 1) return null;
    return matched_path;
}

fn candidateScoreForLookupModule(
    comptime lookup_module: []const u8,
    comptime candidate: []const u8,
) ?u8 {
    const canonical_module = sourceModulePath(candidate);
    const base_module = sourceBaseModuleName(candidate);
    const example_alias: ?[]const u8 = if (std.mem.startsWith(u8, candidate, "examples/") and candidateAllowsBaseModuleAlias(candidate))
        std.fmt.comptimePrint("example_{s}", .{base_module})
    else
        null;
    const test_alias: ?[]const u8 = if (std.mem.startsWith(u8, candidate, "test/"))
        base_module
    else
        null;
    return if (modulePathMatchesCandidate(lookup_module, canonical_module))
        4
    else if (example_alias != null and modulePathMatchesCandidate(lookup_module, example_alias.?))
        3
    else if (test_alias != null and modulePathMatchesCandidate(lookup_module, test_alias.?))
        2
    else if (candidateAllowsBaseModuleAlias(candidate) and modulePathMatchesCandidate(lookup_module, base_module))
        1
    else
        null;
}

fn candidateBoundsForIdentity(
    comptime source_path: []const u8,
    comptime identity: AnonymousBodyIdentity,
    comptime kind: CompilationKind,
) ?[]const Bounds {
    const caller_source = source_graph_embed.embeddedSource(source_path);
    if (isTestModulePath(identity.module_path)) {
        const test_block = testBlockBounds(caller_source, identity.enclosing_function) orelse return null;
        return bodyExpressionBoundsInRangeCandidates(
            caller_source,
            test_block.start,
            test_block.end,
            kind,
        );
    }
    const graph = source_graph_engine.analyzeComptime(caller_source, .{}) catch return null;
    const function_name = canonicalEnclosingFunctionName(identity.enclosing_function);
    const function_node = for (graph.functions) |function| {
        if (std.mem.eql(u8, function.name, function_name)) break function;
    } else return null;
    return bodyExpressionBoundsInRangeCandidates(
        caller_source,
        function_node.body_start_offset,
        function_node.body_end_offset,
        kind,
    );
}

fn candidateBoundsForIdentityInSource(
    comptime caller_source: [:0]const u8,
    comptime identity: AnonymousBodyIdentity,
    comptime kind: CompilationKind,
) ?[]const Bounds {
    if (isTestModulePath(identity.module_path)) {
        const test_block = testBlockBounds(caller_source, identity.enclosing_function) orelse return null;
        return bodyExpressionBoundsInRangeCandidates(
            caller_source,
            test_block.start,
            test_block.end,
            kind,
        );
    }
    const graph = source_graph_engine.analyzeComptime(caller_source, .{}) catch return null;
    const function_name = canonicalEnclosingFunctionName(identity.enclosing_function);
    const function_node = for (graph.functions) |function| {
        if (std.mem.eql(u8, function.name, function_name)) break function;
    } else return null;
    return bodyExpressionBoundsInRangeCandidates(
        caller_source,
        function_node.body_start_offset,
        function_node.body_end_offset,
        kind,
    );
}

fn fallbackResolvedRepoPathForIdentity(
    comptime identity: AnonymousBodyIdentity,
    comptime kind: CompilationKind,
) ?[]const u8 {
    const lookup_module = canonicalLookupModulePath(identity.module_path);
    var best_score: u8 = 0;
    var match_count: usize = 0;
    var matched_path: ?[]const u8 = null;
    var start: usize = 0;
    while (start < build_options.repo_zig_paths.len) {
        var end = start;
        while (end < build_options.repo_zig_paths.len and build_options.repo_zig_paths[end] != '\n') : (end += 1) {}
        const candidate = build_options.repo_zig_paths[start..end];
        start = end + 1;
        if (candidate.len == 0) continue;
        const score = candidateScoreForLookupModule(lookup_module, candidate) orelse continue;
        const bounds = candidateBoundsForIdentity(candidate, identity, kind) orelse continue;
        if (bounds.len == 0) continue;
        if (score > best_score) {
            best_score = score;
            match_count = 1;
            matched_path = candidate;
            continue;
        }
        if (score == best_score) {
            match_count += 1;
        }
    }
    if (match_count != 1) return null;
    return matched_path;
}

pub fn repoOwnedCandidateCount(comptime Body: type) usize {
    const identity = bodyIdentity(Body) orelse return 0;
    const lookup_module = canonicalLookupModulePath(identity.module_path);
    comptime {
        @setEvalBranchQuota(10_000_000);
    }
    var match_count: usize = 0;
    var start: usize = 0;
    while (start < build_options.repo_zig_paths.len) {
        var end = start;
        while (end < build_options.repo_zig_paths.len and build_options.repo_zig_paths[end] != '\n') : (end += 1) {}
        const candidate = build_options.repo_zig_paths[start..end];
        start = end + 1;
        if (candidate.len == 0) continue;
        if (candidateScoreForLookupModule(lookup_module, candidate) != null) match_count += 1;
    }
    return match_count;
}

pub fn hasRepoOwnedCandidate(comptime Body: type) bool {
    return repoOwnedCandidateCount(Body) != 0;
}

fn callName(comptime kind: CompilationKind) ?[]const u8 {
    return switch (kind) {
        .none => null,
        .owned_source => "withOwnedSource",
        .plain_with => "with",
    };
}

fn bodyArgIndex(comptime kind: CompilationKind) ?usize {
    return switch (kind) {
        .none => null,
        .owned_source => 5,
        .plain_with => 2,
    };
}

fn offsetForLineColumn(
    comptime source: []const u8,
    comptime target_line: u32,
    comptime target_column: u32,
) ?usize {
    var line: u32 = 1;
    var column: u32 = 1;
    for (source, 0..) |byte, index| {
        if (line == target_line and column == target_column) return index;
        if (byte == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    if (line == target_line and column == target_column) return source.len;
    return null;
}

fn isIgnorableToken(tag: std.zig.Token.Tag) bool {
    return switch (tag) {
        .doc_comment,
        .container_doc_comment,
        => true,
        else => false,
    };
}

fn updateBraceDepthForTopLevelScan(depth: *usize, token: std.zig.Token) bool {
    switch (token.tag) {
        .l_brace => depth.* += 1,
        .r_brace => {
            if (depth.* == 0) return false;
            depth.* -= 1;
        },
        else => {},
    }
    return true;
}

fn bodyMethodName(comptime Body: type) ?[]const u8 {
    if (@hasDecl(Body, "run")) return "run";
    if (@hasDecl(Body, "body")) return "body";
    return null;
}

fn bodyMethodNameInSource(comptime Body: type, comptime expr_source: []const u8) ?[]const u8 {
    if (@hasDecl(Body, "run") and std.mem.indexOf(u8, expr_source, "fn run(") != null) return "run";
    if (@hasDecl(Body, "body") and std.mem.indexOf(u8, expr_source, "fn body(") != null) return "body";
    return bodyMethodName(Body);
}

fn sourceMethodName(comptime expr_source: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, expr_source, "fn run(") != null) return "run";
    if (std.mem.indexOf(u8, expr_source, "fn body(") != null) return "body";
    return null;
}

fn BodyMethodFnType(comptime Body: type, comptime method_name: []const u8) type {
    const FnRef = @TypeOf(@field(Body, method_name));
    return switch (@typeInfo(FnRef)) {
        .pointer => |pointer| if (@typeInfo(pointer.child) == .@"fn") pointer.child else @compileError("ability.with body method must be callable"),
        .@"fn" => FnRef,
        else => @compileError("ability.with body method must be callable"),
    };
}

fn canonicalPayloadTypeSyntax(comptime T: type) ?[]const u8 {
    return switch (T) {
        void => "void",
        bool => "bool",
        i32 => "i32",
        usize => "usize",
        []const u8 => "[]const u8",
        else => null,
    };
}

pub fn canonicalReturnTypeSyntax(comptime ReturnType: type) ?[]const u8 {
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| blk: {
            const payload = canonicalPayloadTypeSyntax(err_union.payload) orelse break :blk null;
            break :blk std.fmt.comptimePrint("anyerror!{s}", .{payload});
        },
        else => canonicalPayloadTypeSyntax(ReturnType),
    };
}

fn entryName(caller: std.builtin.SourceLocation) [:0]const u8 {
    const name = std.fmt.comptimePrint(
        "__ability_with_entry_l{d}_c{d}\x00",
        .{ caller.line, caller.column },
    );
    return name[0 .. name.len - 1 :0];
}

pub fn callerEntryName(caller: std.builtin.SourceLocation) [:0]const u8 {
    return entryName(caller);
}

fn bodyExpressionBounds(
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source: []const u8,
    comptime kind: CompilationKind,
) ?Bounds {
    comptime {
        @setEvalBranchQuota(2_000_000);
    }
    const target_call = comptime callName(kind) orelse return null;
    const target_arg = comptime bodyArgIndex(kind).?;
    const target_offset = comptime offsetForLineColumn(caller_source, caller.line, caller.column) orelse return null;
    const call_offset = std.mem.lastIndexOf(u8, caller_source[0..target_offset], target_call) orelse return null;
    const sentinel = std.fmt.comptimePrint("{s}\x00", .{caller_source});
    var tokenizer = std.zig.Tokenizer.init(sentinel[0..caller_source.len :0]);
    var seen_name = false;

    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) return null;
        if (isIgnorableToken(token.tag)) continue;
        if (token.loc.start < call_offset) continue;

        if (!seen_name) {
            if (token.tag == .identifier and std.mem.eql(u8, sentinel[token.loc.start..token.loc.end], target_call)) {
                seen_name = true;
            }
            continue;
        }
        if (token.tag != .l_paren) continue;

        var paren_depth: usize = 1;
        var brace_depth: usize = 0;
        var bracket_depth: usize = 0;
        var arg_index: usize = 0;
        var arg_start: ?usize = null;

        while (true) {
            const arg_token = tokenizer.next();
            if (arg_token.tag == .eof) return null;
            if (isIgnorableToken(arg_token.tag)) continue;
            if (arg_start == null) arg_start = arg_token.loc.start;

            const is_delimiter = (arg_token.tag == .comma or arg_token.tag == .r_paren) and
                paren_depth == 1 and
                brace_depth == 0 and
                bracket_depth == 0;
            if (is_delimiter) {
                if (arg_index == target_arg) {
                    return .{ .start = arg_start.?, .end = arg_token.loc.start };
                }
                arg_index += 1;
                arg_start = null;
                if (arg_token.tag == .r_paren) return null;
                continue;
            }

            switch (arg_token.tag) {
                .l_paren => paren_depth += 1,
                .r_paren => {
                    if (paren_depth == 0) return null;
                    paren_depth -= 1;
                },
                .l_brace => brace_depth += 1,
                .r_brace => {
                    if (brace_depth == 0) return null;
                    brace_depth -= 1;
                },
                .l_bracket => bracket_depth += 1,
                .r_bracket => {
                    if (bracket_depth == 0) return null;
                    bracket_depth -= 1;
                },
                else => {},
            }
        }
    }
}

fn namedStructExpressionBounds(
    comptime source: []const u8,
    comptime body_symbol: []const u8,
) ?Bounds {
    comptime {
        @setEvalBranchQuota(2_000_000);
    }
    const sentinel = std.fmt.comptimePrint("{s}\x00", .{source});
    var tokenizer = std.zig.Tokenizer.init(sentinel[0..source.len :0]);
    var matches = [_]Bounds{.{ .start = 0, .end = 0 }} ** 8;
    var match_count: usize = 0;
    var brace_depth: usize = 0;

    while (true) {
        const first = tokenizer.next();
        if (first.tag == .eof) break;
        if (isIgnorableToken(first.tag)) continue;
        if (brace_depth != 0) {
            if (!updateBraceDepthForTopLevelScan(&brace_depth, first)) return null;
            continue;
        }

        if (first.tag == .l_brace or first.tag == .r_brace) {
            if (!updateBraceDepthForTopLevelScan(&brace_depth, first)) return null;
            continue;
        }

        var name = first;
        if (first.tag == .keyword_pub) {
            const const_token = tokenizer.next();
            if (!updateBraceDepthForTopLevelScan(&brace_depth, const_token)) return null;
            if (const_token.tag != .keyword_const) continue;
            name = tokenizer.next();
            if (!updateBraceDepthForTopLevelScan(&brace_depth, name)) return null;
        } else if (first.tag != .keyword_const) {
            continue;
        } else {
            name = tokenizer.next();
            if (!updateBraceDepthForTopLevelScan(&brace_depth, name)) return null;
        }

        if (name.tag != .identifier) continue;
        if (!std.mem.eql(u8, sentinel[name.loc.start..name.loc.end], body_symbol)) continue;

        var eq = tokenizer.next();
        if (!updateBraceDepthForTopLevelScan(&brace_depth, eq)) return null;
        if (eq.tag == .colon) {
            const type_token = tokenizer.next();
            if (!updateBraceDepthForTopLevelScan(&brace_depth, type_token)) return null;
            if (type_token.tag != .identifier) continue;
            if (!std.mem.eql(u8, sentinel[type_token.loc.start..type_token.loc.end], "type")) continue;
            eq = tokenizer.next();
            if (!updateBraceDepthForTopLevelScan(&brace_depth, eq)) return null;
        }
        if (eq.tag != .equal) continue;
        const struct_token = tokenizer.next();
        if (!updateBraceDepthForTopLevelScan(&brace_depth, struct_token)) return null;
        if (struct_token.tag != .keyword_struct) continue;
        const open = tokenizer.next();
        if (!updateBraceDepthForTopLevelScan(&brace_depth, open)) return null;
        if (open.tag != .l_brace) continue;

        const close = findMatchingDelimiter(source, open.loc.start, '{', '}') orelse return null;
        if (match_count >= matches.len) return null;
        matches[match_count] = .{ .start = struct_token.loc.start, .end = close + 1 };
        match_count += 1;
    }

    if (match_count != 1) return null;
    return matches[0];
}

fn identityLiteralToken(comptime source_identity: []const u8) []const u8 {
    if (source_identity.len == 0) return "";
    for (source_identity) |char| {
        switch (char) {
            'A'...'Z', 'a'...'z', '0'...'9', '_', '.', '/', '-', ':' => {},
            else => return "",
        }
    }
    return std.fmt.comptimePrint("\"{s}\"", .{source_identity});
}

fn structExpressionHasSourceIdentity(
    comptime expr_source: []const u8,
    comptime source_identity: []const u8,
) bool {
    const expected_literal = comptime identityLiteralToken(source_identity);
    if (expected_literal.len == 0) return false;
    const sentinel = std.fmt.comptimePrint("{s}\x00", .{expr_source});
    var tokenizer = std.zig.Tokenizer.init(sentinel[0..expr_source.len :0]);
    var brace_depth: usize = 0;

    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) return false;
        switch (token.tag) {
            .l_brace => {
                brace_depth += 1;
                continue;
            },
            .r_brace => {
                if (brace_depth == 0) return false;
                brace_depth -= 1;
                continue;
            },
            else => {},
        }
        if (brace_depth != 1 or token.tag != .keyword_pub) continue;

        var const_token = tokenizer.next();
        while (isIgnorableToken(const_token.tag)) const_token = tokenizer.next();
        if (const_token.tag != .keyword_const) continue;
        var name = tokenizer.next();
        while (isIgnorableToken(name.tag)) name = tokenizer.next();
        if (name.tag != .identifier) continue;
        if (!std.mem.eql(u8, sentinel[name.loc.start..name.loc.end], "source_identity")) continue;

        var eq = tokenizer.next();
        while (isIgnorableToken(eq.tag)) eq = tokenizer.next();
        if (eq.tag != .equal) continue;
        var literal = tokenizer.next();
        while (isIgnorableToken(literal.tag)) literal = tokenizer.next();
        if (literal.tag != .string_literal) continue;
        if (std.mem.eql(u8, sentinel[literal.loc.start..literal.loc.end], expected_literal)) return true;
    }
}

pub fn namedStructSourceIdentityMatches(
    comptime source: []const u8,
    comptime body_symbol: []const u8,
    comptime source_identity: []const u8,
) bool {
    const bounds = comptime namedStructExpressionBounds(source, body_symbol) orelse return false;
    return comptime structExpressionHasSourceIdentity(source[bounds.start..bounds.end], source_identity);
}

pub fn uniqueBodyExpressionBoundsInRange(
    comptime source: [:0]const u8,
    comptime range_start: usize,
    comptime range_end: usize,
    comptime kind: CompilationKind,
) ?Bounds {
    const candidates = bodyExpressionBoundsInRangeCandidates(source, range_start, range_end, kind) orelse return null;
    if (candidates.len != 1) return null;
    return candidates[0];
}

fn bodyExpressionBoundsInRangeCandidates(
    comptime source: [:0]const u8,
    comptime range_start: usize,
    comptime range_end: usize,
    comptime kind: CompilationKind,
) ?[]const Bounds {
    comptime {
        @setEvalBranchQuota(2_000_000);
    }
    const target_call = comptime callName(kind) orelse return null;
    const target_arg = comptime bodyArgIndex(kind).?;
    var tokenizer = std.zig.Tokenizer.init(source);
    var matches = [_]Bounds{.{ .start = 0, .end = 0 }} ** 16;
    var match_count: usize = 0;

    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof or token.loc.start >= range_end) break;
        if (isIgnorableToken(token.tag)) continue;
        if (token.loc.start < range_start) continue;
        if (token.tag != .identifier) continue;
        if (!std.mem.eql(u8, source[token.loc.start..token.loc.end], target_call)) continue;

        const open = tokenizer.next();
        if (open.tag != .l_paren) continue;

        var paren_depth: usize = 1;
        var brace_depth: usize = 0;
        var bracket_depth: usize = 0;
        var arg_index: usize = 0;
        var arg_start: ?usize = null;

        while (true) {
            const arg_token = tokenizer.next();
            if (arg_token.tag == .eof or arg_token.loc.start >= range_end) return null;
            if (isIgnorableToken(arg_token.tag)) continue;
            if (arg_start == null) arg_start = arg_token.loc.start;

            const is_delimiter = (arg_token.tag == .comma or arg_token.tag == .r_paren) and
                paren_depth == 1 and
                brace_depth == 0 and
                bracket_depth == 0;
            if (is_delimiter) {
                if (arg_index == target_arg) {
                    const current: Bounds = .{ .start = arg_start.?, .end = arg_token.loc.start };
                    if (match_count >= matches.len) return null;
                    matches[match_count] = current;
                    match_count += 1;
                }
                arg_index += 1;
                arg_start = null;
                if (arg_token.tag == .r_paren) break;
                continue;
            }

            switch (arg_token.tag) {
                .l_paren => paren_depth += 1,
                .r_paren => {
                    if (paren_depth == 0) return null;
                    paren_depth -= 1;
                },
                .l_brace => brace_depth += 1,
                .r_brace => {
                    if (brace_depth == 0) return null;
                    brace_depth -= 1;
                },
                .l_bracket => bracket_depth += 1,
                .r_bracket => {
                    if (bracket_depth == 0) return null;
                    bracket_depth -= 1;
                },
                else => {},
            }
        }
    }

    const exact = matches;
    return exact[0..match_count];
}

pub fn testBlockBounds(
    comptime source: [:0]const u8,
    comptime test_name: []const u8,
) ?struct { start: usize, end: usize } {
    const marker = std.fmt.comptimePrint("test \"{s}\"", .{test_name});
    const marker_index = std.mem.indexOf(u8, source, marker) orelse return null;
    const brace_index = std.mem.indexOfScalarPos(u8, source, marker_index + marker.len, '{') orelse return null;
    const brace_end = findMatchingDelimiter(source, brace_index, '{', '}') orelse return null;
    return .{
        .start = brace_index,
        .end = brace_end + 1,
    };
}

fn findMatchingDelimiter(
    comptime source: []const u8,
    comptime open_index: usize,
    comptime open_char: u8,
    comptime close_char: u8,
) ?usize {
    var depth: usize = 0;
    for (source[open_index..], open_index..) |char, index| {
        if (char == open_char) {
            depth += 1;
            continue;
        }
        if (char == close_char) {
            if (depth == 0) return null;
            depth -= 1;
            if (depth == 0) return index;
        }
    }
    return null;
}

fn functionBodyUsesIdentifier(comptime source: []const u8, comptime identifier: []const u8) bool {
    const sentinel = std.fmt.comptimePrint("{s}\x00", .{source});
    var tokenizer = std.zig.Tokenizer.init(sentinel[0..source.len :0]);
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) return false;
        if (token.tag != .identifier) continue;
        if (std.mem.eql(u8, sentinel[token.loc.start..token.loc.end], identifier)) return true;
    }
}

fn stripSelfDiscardStatement(comptime body_source: []const u8, comptime identifier: []const u8) []const u8 {
    const discard_pattern = std.fmt.comptimePrint("_ = {s};", .{identifier});
    const inner = body_source[1 .. body_source.len - 1];
    const inner_pattern_index = std.mem.indexOf(u8, inner, discard_pattern) orelse return body_source;

    const after = inner[inner_pattern_index + discard_pattern.len ..];
    const after_trimmed = trimAsciiWhitespace(after);

    if (functionBodyUsesIdentifier(after_trimmed, identifier)) return body_source;
    return std.fmt.comptimePrint(
        "{{\n{s}\n}}",
        .{after_trimmed},
    );
}

fn hasSelfDiscardStatement(comptime body_source: []const u8, comptime identifier: []const u8) bool {
    const discard_pattern = std.fmt.comptimePrint("_ = {s};", .{identifier});
    return std.mem.indexOf(u8, body_source, discard_pattern) != null;
}

pub fn entryBodyHasBareFunctionCall(
    comptime source: []const u8,
    comptime entry_symbol: []const u8,
) bool {
    const marker = std.fmt.comptimePrint("fn {s}(", .{entry_symbol});
    const fn_index = std.mem.indexOf(u8, source, marker) orelse return true;
    const params_start = fn_index + marker.len - 1;
    const params_end = findMatchingDelimiter(source, params_start, '(', ')') orelse return true;
    const params_source = source[params_start .. params_end + 1];
    const body_start = std.mem.indexOfScalarPos(u8, source, params_end, '{') orelse return true;
    const body_end = findMatchingDelimiter(source, body_start, '{', '}') orelse return true;
    const body_source = source[body_start..body_end];
    const sentinel = std.fmt.comptimePrint("{s}\x00", .{body_source});
    var tokenizer = std.zig.Tokenizer.init(sentinel[0..body_source.len :0]);
    var previous_tag: std.zig.Token.Tag = .invalid;
    var previous_previous_tag: std.zig.Token.Tag = .invalid;
    var token_window = EntryBodyTokenWindow{};
    var aliases = [_]EntryBodyAlias{.{
        .name = "",
        .kind = .effect_root,
    }} ** 32;
    var alias_count: usize = 0;

    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) return false;
        if (isIgnorableToken(token.tag)) continue;
        token_window.push(.{
            .tag = token.tag,
            .lexeme = body_source[token.loc.start..token.loc.end],
        });
        if (token.tag == .l_paren and
            previous_tag == .identifier and
            previous_previous_tag != .keyword_fn)
        {
            if (previous_previous_tag != .period) return true;
            if (!qualifiedCallRootIsSupportedEffectAccess(params_source, aliases[0..alias_count], &token_window)) return true;
        }
        if (token.tag == .semicolon) {
            if (maybeEntryBodyAliasFromDeclaration(params_source, aliases[0..alias_count], &token_window)) |alias| {
                if (!upsertEntryBodyAlias(aliases[0..], &alias_count, alias.name, alias.kind)) return true;
            }
        }
        previous_previous_tag = previous_tag;
        previous_tag = token.tag;
    }
}

const EntryBodyAliasKind = union(enum) {
    effect_root,
    requirement: []const u8,
};

const EntryBodyAlias = struct {
    name: []const u8,
    kind: EntryBodyAliasKind,
};

const EntryBodyToken = struct {
    tag: std.zig.Token.Tag,
    lexeme: []const u8,
};

const EntryBodyTokenWindow = struct {
    items: [32]EntryBodyToken = [_]EntryBodyToken{.{
        .tag = .invalid,
        .lexeme = "",
    }} ** 32,
    count: usize = 0,

    fn push(self: *@This(), item: EntryBodyToken) void {
        if (self.count < self.items.len) {
            self.items[self.count] = item;
            self.count += 1;
            return;
        }
        for (self.items[0 .. self.items.len - 1], 0..) |_, index| {
            self.items[index] = self.items[index + 1];
        }
        self.items[self.items.len - 1] = item;
    }
};

fn qualifiedCallRoot(window: *const EntryBodyTokenWindow) ?[]const u8 {
    if (window.count < 4) return null;
    if (window.items[window.count - 1].tag != .l_paren or
        window.items[window.count - 2].tag != .identifier or
        window.items[window.count - 3].tag != .period) return null;

    var root_index = window.count - 2;
    var consumed_qualified_segment = false;
    while (root_index >= 2 and
        window.items[root_index - 1].tag == .period and
        window.items[root_index - 2].tag == .identifier)
    {
        root_index -= 2;
        consumed_qualified_segment = true;
    }
    if (!consumed_qualified_segment) return null;
    return window.items[root_index].lexeme;
}

fn qualifiedCallRootIsSupportedEffectAccess(
    comptime params_source: []const u8,
    comptime aliases: []const EntryBodyAlias,
    window: *const EntryBodyTokenWindow,
) bool {
    const root = qualifiedCallRoot(window) orelse return false;
    return entryBodyAliasKind(params_source, aliases, root) != null;
}

fn entryBodyAliasKind(
    comptime params_source: []const u8,
    comptime aliases: []const EntryBodyAlias,
    comptime name: []const u8,
) ?EntryBodyAliasKind {
    if (entryParamsContainAnytypeParamNamed(params_source, name)) return .effect_root;
    for (aliases) |alias| {
        if (std.mem.eql(u8, alias.name, name)) return alias.kind;
    }
    return null;
}

fn upsertEntryBodyAlias(
    aliases: []EntryBodyAlias,
    alias_count: *usize,
    comptime name: []const u8,
    comptime kind: EntryBodyAliasKind,
) bool {
    for (aliases[0..alias_count.*]) |*alias| {
        if (!std.mem.eql(u8, alias.name, name)) continue;
        alias.kind = kind;
        return true;
    }
    if (alias_count.* >= aliases.len) return false;
    aliases[alias_count.*] = .{
        .name = name,
        .kind = kind,
    };
    alias_count.* += 1;
    return true;
}

fn maybeEntryBodyAliasFromDeclaration(
    comptime params_source: []const u8,
    comptime aliases: []const EntryBodyAlias,
    window: *const EntryBodyTokenWindow,
) ?struct {
    name: []const u8,
    kind: EntryBodyAliasKind,
} {
    if (window.count >= 5) {
        const tail = window.items[window.count - 5 .. window.count];
        if ((tail[0].tag == .keyword_const or tail[0].tag == .keyword_var) and
            tail[1].tag == .identifier and
            tail[2].tag == .equal and
            tail[3].tag == .identifier and
            tail[4].tag == .semicolon)
        {
            const source_kind = entryBodyAliasKind(params_source, aliases, tail[3].lexeme) orelse return null;
            return .{
                .name = tail[1].lexeme,
                .kind = source_kind,
            };
        }
    }

    if (window.count >= 7) {
        const tail = window.items[window.count - 7 .. window.count];
        if ((tail[0].tag == .keyword_const or tail[0].tag == .keyword_var) and
            tail[1].tag == .identifier and
            tail[2].tag == .equal and
            tail[3].tag == .identifier and
            tail[4].tag == .period and
            tail[5].tag == .identifier and
            tail[6].tag == .semicolon)
        {
            const source_kind = entryBodyAliasKind(params_source, aliases, tail[3].lexeme) orelse return null;
            return switch (source_kind) {
                .effect_root => .{
                    .name = tail[1].lexeme,
                    .kind = .{ .requirement = tail[5].lexeme },
                },
                .requirement => null,
            };
        }
    }

    return null;
}

fn entryParamsContainAnytypeParamNamed(comptime params_source: []const u8, root: []const u8) bool {
    if (params_source.len < 2 or params_source[0] != '(' or params_source[params_source.len - 1] != ')') return false;
    const inner = params_source[1 .. params_source.len - 1];
    var start: usize = 0;
    var paren_depth: usize = 0;
    var brace_depth: usize = 0;
    var bracket_depth: usize = 0;
    var index: usize = 0;
    while (index <= inner.len) : (index += 1) {
        if (index == inner.len or
            (inner[index] == ',' and paren_depth == 0 and brace_depth == 0 and bracket_depth == 0))
        {
            if (paramSegmentIsAnytypeParamNamed(inner[start..index], root)) return true;
            start = index + 1;
            continue;
        }
        switch (inner[index]) {
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth > 0) paren_depth -= 1;
            },
            '{' => brace_depth += 1,
            '}' => {
                if (brace_depth > 0) brace_depth -= 1;
            },
            '[' => bracket_depth += 1,
            ']' => {
                if (bracket_depth > 0) bracket_depth -= 1;
            },
            else => {},
        }
    }
    return false;
}

fn paramSegmentIsAnytypeParamNamed(comptime segment: []const u8, root: []const u8) bool {
    const trimmed = trimAsciiWhitespace(segment);
    const colon_index = std.mem.indexOfScalar(u8, trimmed, ':') orelse return false;
    var name = trimAsciiWhitespace(trimmed[0..colon_index]);
    if (std.mem.startsWith(u8, name, "comptime ")) {
        name = trimAsciiWhitespace(name["comptime ".len..]);
    }
    if (!std.mem.eql(u8, name, root)) return false;
    if (!source_graph_engine.isEffectParamName(name)) return false;
    return std.mem.eql(u8, trimAsciiWhitespace(trimmed[colon_index + 1 ..]), "anytype");
}

fn trimAsciiWhitespace(comptime source: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = source.len;
    while (start < end and std.ascii.isWhitespace(source[start])) : (start += 1) {}
    while (end > start and std.ascii.isWhitespace(source[end - 1])) : (end -= 1) {}
    return source[start..end];
}

pub fn normalizedSyntheticCallerSource(comptime caller_source: []const u8) []const u8 {
    const public_ability_import = "const ability = @import(\"ability\");";
    const synthetic_ability_import = "const ability = @import(\"synthetic_ability\");";
    const import_index = std.mem.indexOf(u8, caller_source, public_ability_import) orelse return caller_source;
    return std.fmt.comptimePrint(
        "{s}{s}{s}",
        .{
            caller_source[0..import_index],
            synthetic_ability_import,
            caller_source[import_index + public_ability_import.len ..],
        },
    );
}

fn syntheticStubBodyExpr(comptime expr_source: []const u8) []const u8 {
    const method_name = sourceMethodName(expr_source) orelse "body";
    return std.fmt.comptimePrint(
        "struct {{ pub fn {s}(_: anytype) void {{}} }}",
        .{method_name},
    );
}

fn sanitizedCallerSourceForBounds(comptime caller_source: []const u8, comptime bounds: Bounds) []const u8 {
    return std.fmt.comptimePrint(
        "{s}{s}{s}",
        .{
            caller_source[0..bounds.start],
            syntheticStubBodyExpr(caller_source[bounds.start..bounds.end]),
            caller_source[bounds.end..],
        },
    );
}

fn callerOwnedSyntheticCallerSource(
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source: []const u8,
) []const u8 {
    const target_offset = comptime offsetForLineColumn(caller_source, caller.line, caller.column) orelse return caller_source;
    const sentinel = std.fmt.comptimePrint("{s}\x00", .{caller_source});
    const maybe_decl_start = if (source_graph_engine.analyzeComptime(sentinel[0..caller_source.len :0], .{})) |graph| blk: {
        const function = functionContainingOffset(graph.functions, target_offset) orelse break :blk null;
        break :blk functionDeclStart(caller_source, function);
    } else |_| blk: {
        const search = caller_source[0..target_offset];
        const fn_index = std.mem.lastIndexOf(u8, search, "fn ") orelse break :blk null;
        var start = fn_index;
        while (start > 0 and std.ascii.isWhitespace(caller_source[start - 1])) : (start -= 1) {}
        if (start >= 3 and std.mem.eql(u8, caller_source[start - 3 .. start], "pub")) break :blk start - 3;
        break :blk fn_index;
    };
    const decl_start = maybe_decl_start orelse return caller_source;
    return caller_source[0..decl_start];
}

fn functionContainingOffset(
    comptime functions: []const source_graph_engine.FunctionNode,
    comptime offset: usize,
) ?source_graph_engine.FunctionNode {
    inline for (functions) |function| {
        if (function.body_start_offset == 0 and function.body_end_offset == 0) continue;
        if (offset >= function.body_start_offset and offset <= function.body_end_offset) return function;
    }
    return null;
}

fn functionDeclStart(
    comptime source: []const u8,
    comptime function: source_graph_engine.FunctionNode,
) ?usize {
    const plain = std.fmt.comptimePrint("fn {s}(", .{function.name});
    const public = std.fmt.comptimePrint("pub fn {s}(", .{function.name});
    const search = source[0..function.body_start_offset];
    if (std.mem.lastIndexOf(u8, search, public)) |index| return index;
    if (std.mem.lastIndexOf(u8, search, plain)) |index| return index;
    return null;
}

fn repoOwnedSyntheticCallerSource(
    comptime caller_source: []const u8,
    comptime bounds: Bounds,
    comptime identity: AnonymousBodyIdentity,
) []const u8 {
    if (isTestModulePath(identity.module_path)) {
        const sentinel = std.fmt.comptimePrint("{s}\x00", .{caller_source});
        const test_block = testBlockBounds(sentinel[0..caller_source.len :0], identity.enclosing_function) orelse
            return sanitizedCallerSourceForBounds(caller_source, bounds);
        return caller_source[0..test_block.start];
    }
    const sentinel = std.fmt.comptimePrint("{s}\x00", .{caller_source});
    const graph = source_graph_engine.analyzeComptime(sentinel[0..caller_source.len :0], .{}) catch
        return sanitizedCallerSourceForBounds(caller_source, bounds);
    const function = functionContainingOffset(graph.functions, bounds.start) orelse
        return sanitizedCallerSourceForBounds(caller_source, bounds);
    const decl_start = functionDeclStart(caller_source, function) orelse
        return sanitizedCallerSourceForBounds(caller_source, bounds);
    return caller_source[0..decl_start];
}

fn firstParamName(comptime params_source: []const u8) ?[]const u8 {
    if (params_source.len < 2 or params_source[0] != '(' or params_source[params_source.len - 1] != ')') return null;
    const inner = trimAsciiWhitespace(params_source[1 .. params_source.len - 1]);
    if (inner.len == 0) return null;
    const colon_index = std.mem.indexOfScalar(u8, inner, ':') orelse return null;
    return trimAsciiWhitespace(inner[0..colon_index]);
}

fn elideLeadingParam(comptime params_source: []const u8) ?[]const u8 {
    if (params_source.len < 2 or params_source[0] != '(' or params_source[params_source.len - 1] != ')') return null;
    const inner = params_source[1 .. params_source.len - 1];
    var paren_depth: usize = 0;
    var brace_depth: usize = 0;
    var bracket_depth: usize = 0;
    for (inner, 0..) |char, index| {
        switch (char) {
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth > 0) paren_depth -= 1;
            },
            '{' => brace_depth += 1,
            '}' => {
                if (brace_depth > 0) brace_depth -= 1;
            },
            '[' => bracket_depth += 1,
            ']' => {
                if (bracket_depth > 0) bracket_depth -= 1;
            },
            ',' => {
                if (paren_depth == 0 and brace_depth == 0 and bracket_depth == 0) {
                    const tail = trimAsciiWhitespace(inner[index + 1 ..]);
                    return std.fmt.comptimePrint("({s})", .{tail});
                }
            },
            else => {},
        }
    }
    return null;
}

fn declarationStartForFunction(comptime source: []const u8, comptime fn_index: usize) usize {
    var prefix_end = fn_index;
    while (prefix_end > 0 and std.ascii.isWhitespace(source[prefix_end - 1])) : (prefix_end -= 1) {}
    if (prefix_end >= 3 and std.mem.eql(u8, source[prefix_end - 3 .. prefix_end], "pub")) {
        return prefix_end - 3;
    }
    return fn_index;
}

fn supportingDeclsAroundMethod(
    comptime expr_source: []const u8,
    comptime method_start: usize,
    comptime method_end: usize,
) []const u8 {
    if (!std.mem.startsWith(u8, trimAsciiWhitespace(expr_source), "struct")) return "";
    const open_brace = std.mem.indexOfScalar(u8, expr_source, '{') orelse return "";
    const close_brace = findMatchingDelimiter(expr_source, open_brace, '{', '}') orelse return "";
    if (close_brace <= open_brace + 1) return "";
    const decl_start = declarationStartForFunction(expr_source, method_start);

    const before = trimAsciiWhitespace(expr_source[open_brace + 1 .. decl_start]);
    const after = trimAsciiWhitespace(expr_source[method_end + 1 .. close_brace]);
    if (before.len == 0) return after;
    if (after.len == 0) return before;
    return std.fmt.comptimePrint("{s}\n{s}", .{ before, after });
}

pub fn extractedEntrySource(
    comptime Body: type,
    comptime expr_source: []const u8,
    comptime generated_entry_name: []const u8,
    comptime override_return_syntax: ?[]const u8,
) ?[]const u8 {
    const method_name = bodyMethodNameInSource(Body, expr_source) orelse return null;
    const marker = std.fmt.comptimePrint("fn {s}(", .{method_name});
    const fn_index = std.mem.indexOf(u8, expr_source, marker) orelse return null;
    const params_start = fn_index + marker.len - 1;
    const params_end = findMatchingDelimiter(expr_source, params_start, '(', ')') orelse return null;
    const body_start = std.mem.indexOfScalarPos(u8, expr_source, params_end, '{') orelse return null;
    const body_end = findMatchingDelimiter(expr_source, body_start, '{', '}') orelse return null;
    const supporting_decls = supportingDeclsAroundMethod(expr_source, fn_index, body_end);
    const params_suffix = expr_source[params_start .. params_end + 1];
    const return_suffix = expr_source[params_end + 1 .. body_start];
    const chosen_return_suffix = if (override_return_syntax) |syntax|
        std.fmt.comptimePrint(" {s} ", .{syntax})
    else blk: {
        const method_fn_type = BodyMethodFnType(Body, method_name);
        break :blk switch (@typeInfo(method_fn_type)) {
            .@"fn" => |fn_info| inner: {
                const return_type = fn_info.return_type orelse break :inner return_suffix;
                if (canonicalReturnTypeSyntax(return_type)) |canonical| {
                    break :inner std.fmt.comptimePrint(" {s} ", .{canonical});
                }
                break :inner return_suffix;
            },
            else => unreachable,
        };
    };
    const body_suffix = expr_source[body_start .. body_end + 1];
    var rewritten_params: []const u8 = params_suffix;

    if (std.mem.eql(u8, method_name, "run") and elideLeadingParam(params_suffix) != null) {
        const name = firstParamName(params_suffix) orelse return null;
        const stripped_body = stripSelfDiscardStatement(body_suffix, name);
        rewritten_params = elideLeadingParam(params_suffix).?;
        if (hasSelfDiscardStatement(body_suffix, name)) {
            const entry = std.fmt.comptimePrint(
                "pub fn {s}{s}{s}{s}",
                .{ generated_entry_name, rewritten_params, chosen_return_suffix, stripped_body },
            );
            if (supporting_decls.len != 0) return std.fmt.comptimePrint("{s}\n{s}", .{ supporting_decls, entry });
            return entry;
        }
        if (functionBodyUsesIdentifier(stripped_body, name)) return null;
        const entry = std.fmt.comptimePrint(
            "pub fn {s}{s}{s}{s}",
            .{ generated_entry_name, rewritten_params, chosen_return_suffix, stripped_body },
        );
        if (supporting_decls.len != 0) return std.fmt.comptimePrint("{s}\n{s}", .{ supporting_decls, entry });
        return entry;
    }

    const entry = std.fmt.comptimePrint(
        "pub fn {s}{s}{s}{s}",
        .{ generated_entry_name, rewritten_params, chosen_return_suffix, body_suffix },
    );
    if (supporting_decls.len != 0) return std.fmt.comptimePrint("{s}\n{s}", .{ supporting_decls, entry });
    return entry;
}

fn extractedEntrySourceFromSource(
    comptime expr_source: []const u8,
    comptime generated_entry_name: []const u8,
    comptime override_return_syntax: ?[]const u8,
) ?[]const u8 {
    const method_name = sourceMethodName(expr_source) orelse return null;
    const marker = std.fmt.comptimePrint("fn {s}(", .{method_name});
    const fn_index = std.mem.indexOf(u8, expr_source, marker) orelse return null;
    const params_start = fn_index + marker.len - 1;
    const params_end = findMatchingDelimiter(expr_source, params_start, '(', ')') orelse return null;
    const body_start = std.mem.indexOfScalarPos(u8, expr_source, params_end, '{') orelse return null;
    const body_end = findMatchingDelimiter(expr_source, body_start, '{', '}') orelse return null;
    const supporting_decls = supportingDeclsAroundMethod(expr_source, fn_index, body_end);
    const params_suffix = expr_source[params_start .. params_end + 1];
    const body_suffix = expr_source[body_start .. body_end + 1];
    const chosen_return_suffix = if (override_return_syntax) |syntax|
        std.fmt.comptimePrint(" {s} ", .{syntax})
    else
        expr_source[params_end + 1 .. body_start];
    var rewritten_params: []const u8 = params_suffix;

    if (std.mem.eql(u8, method_name, "run") and elideLeadingParam(params_suffix) != null) {
        const name = firstParamName(params_suffix) orelse return null;
        const stripped_body = stripSelfDiscardStatement(body_suffix, name);
        rewritten_params = elideLeadingParam(params_suffix).?;
        if (hasSelfDiscardStatement(body_suffix, name)) {
            const entry = std.fmt.comptimePrint(
                "pub fn {s}{s}{s}{s}",
                .{ generated_entry_name, rewritten_params, chosen_return_suffix, stripped_body },
            );
            if (supporting_decls.len != 0) return std.fmt.comptimePrint("{s}\n{s}", .{ supporting_decls, entry });
            return entry;
        }
        if (functionBodyUsesIdentifier(stripped_body, name)) return null;
        const entry = std.fmt.comptimePrint(
            "pub fn {s}{s}{s}{s}",
            .{ generated_entry_name, rewritten_params, chosen_return_suffix, stripped_body },
        );
        if (supporting_decls.len != 0) return std.fmt.comptimePrint("{s}\n{s}", .{ supporting_decls, entry });
        return entry;
    }

    const entry = std.fmt.comptimePrint(
        "pub fn {s}{s}{s}{s}",
        .{ generated_entry_name, rewritten_params, chosen_return_suffix, body_suffix },
    );
    if (supporting_decls.len != 0) return std.fmt.comptimePrint("{s}\n{s}", .{ supporting_decls, entry });
    return entry;
}

pub fn syntheticSourceForExpr(
    comptime Body: type,
    comptime expr_source: []const u8,
    comptime caller_source: []const u8,
    comptime generated_entry_name: []const u8,
    comptime override_return_syntax: ?[]const u8,
) ?[:0]const u8 {
    const stable_expr_source = std.fmt.comptimePrint("{s}", .{expr_source});
    const normalized_caller_source = comptime normalizedSyntheticCallerSource(caller_source);
    const maybe_extracted_entry = comptime extractedEntrySource(Body, stable_expr_source, generated_entry_name, override_return_syntax);
    const maybe_fallback_entry = extractedEntrySourceFromSource(stable_expr_source, generated_entry_name, override_return_syntax);
    const extracted_entry = if (maybe_extracted_entry) |entry|
        entry
    else
        maybe_fallback_entry orelse return null;
    return std.fmt.comptimePrint(
        "{s}\n{s}\n",
        .{ normalized_caller_source, extracted_entry },
    );
}

fn syntheticSourceForBounds(
    comptime Body: type,
    comptime bounds: Bounds,
    comptime caller_source: []const u8,
    comptime synthetic_caller_source: []const u8,
    comptime generated_entry_name: []const u8,
    comptime override_return_syntax: ?[]const u8,
) ?[:0]const u8 {
    return syntheticSourceForExpr(
        Body,
        caller_source[bounds.start..bounds.end],
        synthetic_caller_source,
        generated_entry_name,
        override_return_syntax,
    );
}

pub fn syntheticSourceWithEntry(
    comptime caller: std.builtin.SourceLocation,
    comptime Body: type,
    comptime caller_source: []const u8,
    comptime kind: CompilationKind,
    comptime generated_entry_name: []const u8,
    comptime override_return_syntax: ?[]const u8,
) ?[:0]const u8 {
    const bounds = comptime bodyExpressionBounds(caller, caller_source, kind) orelse return null;
    const synthetic_caller_source = sanitizedCallerSourceForBounds(caller_source, bounds);
    return syntheticSourceForBounds(
        Body,
        bounds,
        caller_source,
        synthetic_caller_source,
        generated_entry_name,
        override_return_syntax,
    );
}

pub fn syntheticSourceForNamedTypeWithEntry(
    comptime Body: type,
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source: []const u8,
    comptime body_symbol: []const u8,
    comptime generated_entry_name: []const u8,
    comptime override_return_syntax: ?[]const u8,
) ?[:0]const u8 {
    const bounds = comptime namedStructExpressionBounds(caller_source, body_symbol) orelse return null;
    return syntheticSourceForBounds(
        Body,
        bounds,
        caller_source,
        callerOwnedSyntheticCallerSource(caller, caller_source),
        generated_entry_name,
        override_return_syntax,
    );
}

/// Synthetic source packet for one unique repo-owned anonymous body candidate.
pub const RepoOwnedAnonymousSource = struct {
    source_path: []const u8,
    entry_symbol: [:0]const u8,
    source: [:0]const u8,
};

pub fn maybeLowerSyntheticLexicalBody(
    comptime HandlersType: type,
    comptime ValueType: type,
    comptime synthetic_path: []const u8,
    comptime synthetic_source: [:0]const u8,
    comptime entry_symbol: []const u8,
) ?source_lowering.OpenRowGeneratedProgram {
    return @import("synthetic_lowering_host").maybeLowerSyntheticLexicalBody(
        ValueType,
        lexical_manifest.Manifest(HandlersType).row(),
        lexical_manifest.Manifest(HandlersType).outputs(),
        synthetic_path,
        synthetic_source,
        entry_symbol,
    );
}

fn genericMaybeLowerSynthetic(
    comptime HandlersType: type,
    comptime ValueType: type,
    comptime synthetic_path: []const u8,
    comptime synthetic_source: [:0]const u8,
    comptime entry_symbol: []const u8,
) ?source_lowering.OpenRowGeneratedProgram {
    const row = comptime lexical_manifest.Manifest(HandlersType).row();
    const outputs = comptime lexical_manifest.Manifest(HandlersType).outputs();
    return lowering_api.maybeLower(
        lowering_api.sourceWithContent(synthetic_path, .{
            .module = "generic_probe",
            .file = synthetic_path ++ "\x00",
            .line = 1,
            .column = 1,
            .fn_name = entry_symbol ++ "\x00",
        }, synthetic_source),
        .{
            .label = "ability.with repo-owned lexical body",
            .entry_symbol = entry_symbol,
            .ValueType = ValueType,
            .row = row,
            .outputs = outputs,
        },
    );
}

fn entryNameFromIdentity(comptime identity: AnonymousBodyIdentity) [:0]const u8 {
    const suffix = identity.struct_suffix["__struct_".len..];
    const sanitized_suffix = comptime blk: {
        var buffer: [suffix.len]u8 = undefined;
        for (suffix, 0..) |char, index| {
            buffer[index] = if (std.ascii.isAlphanumeric(char) or char == '_') char else '_';
        }
        break :blk buffer;
    };
    const name = std.fmt.comptimePrint("__ability_with_entry_{s}\x00", .{sanitized_suffix[0..]});
    return name[0 .. name.len - 1 :0];
}

/// Return one repo-owned anonymous body as synthetic source only when the enclosing function contains a unique matching candidate.
pub fn uniqueRepoOwnedAnonymousSourceWithReturnSyntax(
    comptime Body: type,
    comptime kind: CompilationKind,
    comptime override_return_syntax: ?[]const u8,
) ?RepoOwnedAnonymousSource {
    const identity = bodyIdentity(Body) orelse return null;
    const initial_source_path = resolvedRepoPath(Body) orelse return null;
    const source_path = if (candidateBoundsForIdentity(initial_source_path, identity, kind)) |bounds|
        if (bounds.len != 0) initial_source_path else fallbackResolvedRepoPathForIdentity(identity, kind) orelse return null
    else
        fallbackResolvedRepoPathForIdentity(identity, kind) orelse return null;
    const caller_source = source_graph_embed.embeddedSource(source_path);
    const candidate_bounds = candidateBoundsForIdentity(source_path, identity, kind) orelse return null;
    const entry_symbol = entryNameFromIdentity(identity);
    if (candidate_bounds.len == 0) return null;
    const selected_bounds = if (candidate_bounds.len == 1)
        candidate_bounds[0]
    else blk: {
        const first_source = comptime syntheticSourceForBounds(
            Body,
            candidate_bounds[0],
            caller_source,
            repoOwnedSyntheticCallerSource(caller_source, candidate_bounds[0], identity),
            entry_symbol,
            override_return_syntax,
        ) orelse return null;
        inline for (candidate_bounds[1..]) |candidate| {
            const candidate_source = comptime syntheticSourceForBounds(
                Body,
                candidate,
                caller_source,
                repoOwnedSyntheticCallerSource(caller_source, candidate, identity),
                entry_symbol,
                override_return_syntax,
            ) orelse return null;
            if (!std.mem.eql(u8, first_source, candidate_source)) return null;
        }
        break :blk candidate_bounds[0];
    };
    return .{
        .source_path = source_path,
        .entry_symbol = entry_symbol,
        .source = comptime syntheticSourceForBounds(
            Body,
            selected_bounds,
            caller_source,
            repoOwnedSyntheticCallerSource(caller_source, selected_bounds, identity),
            entry_symbol,
            override_return_syntax,
        ) orelse return null,
    };
}

/// Return one source-backed anonymous body from caller-owned bytes only when the
/// source contains a unique matching `ability.with(..., Body)` candidate.
pub fn uniqueSourceBackedAnonymousSourceWithReturnSyntax(
    comptime Body: type,
    comptime caller_source: []const u8,
    comptime kind: CompilationKind,
    comptime override_return_syntax: ?[]const u8,
) ?RepoOwnedAnonymousSource {
    const identity = bodyIdentity(Body) orelse return null;
    const source = std.fmt.comptimePrint("{s}\x00", .{caller_source});
    const candidate_bounds = candidateBoundsForIdentityInSource(source[0..caller_source.len :0], identity, kind) orelse return null;
    const entry_symbol = entryNameFromIdentity(identity);
    if (candidate_bounds.len == 0) return null;
    const selected_bounds = if (candidate_bounds.len == 1)
        candidate_bounds[0]
    else blk: {
        const first_source = comptime syntheticSourceForBounds(
            Body,
            candidate_bounds[0],
            caller_source,
            repoOwnedSyntheticCallerSource(caller_source, candidate_bounds[0], identity),
            entry_symbol,
            override_return_syntax,
        ) orelse return null;
        inline for (candidate_bounds[1..]) |candidate| {
            const candidate_source = comptime syntheticSourceForBounds(
                Body,
                candidate,
                caller_source,
                repoOwnedSyntheticCallerSource(caller_source, candidate, identity),
                entry_symbol,
                override_return_syntax,
            ) orelse return null;
            if (!std.mem.eql(u8, first_source, candidate_source)) return null;
        }
        break :blk candidate_bounds[0];
    };
    return .{
        .source_path = "source-backed-body.zig",
        .entry_symbol = entry_symbol,
        .source = comptime syntheticSourceForBounds(
            Body,
            selected_bounds,
            caller_source,
            repoOwnedSyntheticCallerSource(caller_source, selected_bounds, identity),
            entry_symbol,
            override_return_syntax,
        ) orelse return null,
    };
}

pub fn uniqueRepoOwnedAnonymousSource(comptime Body: type, comptime kind: CompilationKind) ?RepoOwnedAnonymousSource {
    return uniqueRepoOwnedAnonymousSourceWithReturnSyntax(Body, kind, null);
}

test "bodyExpressionBounds finds the anonymous withOwnedSource body argument" {
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = "/tmp/probe.zig",
        .line = 5,
        .column = 34,
        .fn_name = "probe",
    };
    const source =
        \\const ability = @import("ability");
        \\
        \\pub fn probe() !void {
        \\    _ = try ability.withOwnedSource(@src(), @embedFile(@src().file), .{}, undefined, .{}, struct {
        \\        pub fn body(eff: anytype) anyerror!void { _ = eff; }
        \\    });
        \\}
    ;
    const bounds = comptime bodyExpressionBounds(caller, source, .owned_source).?;
    try std.testing.expect(std.mem.eql(u8, source[bounds.start..bounds.end], "struct {\n        pub fn body(eff: anytype) anyerror!void { _ = eff; }\n    }"));
}

test "named source identity matches only the selected top-level declaration" {
    const source =
        \\const Wrapper = struct {
        \\    const Body = struct {
        \\        pub const source_identity = "nested.Body";
        \\    };
        \\};
        \\
        \\const Body = struct {
        \\    pub const source_identity = "main.Body";
        \\    pub fn body(eff: anytype) anyerror!i32 {
        \\        return try eff.state.get();
        \\    }
        \\};
    ;

    try std.testing.expect(comptime namedStructSourceIdentityMatches(source, "Body", "main.Body"));
    try std.testing.expect(!comptime namedStructSourceIdentityMatches(source, "Body", "nested.Body"));

    const private_source =
        \\const Body = struct {
        \\    const source_identity = "main.Body";
        \\};
    ;
    try std.testing.expect(!comptime namedStructSourceIdentityMatches(private_source, "Body", "main.Body"));
}

test "syntheticSourceWithEntry appends one renamed entry function" {
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = "/tmp/probe.zig",
        .line = 5,
        .column = 34,
        .fn_name = "probe",
    };
    const source =
        \\const ability = @import("ability");
        \\
        \\pub fn probe() !void {
        \\    _ = try ability.withOwnedSource(@src(), @embedFile(@src().file), .{}, undefined, .{}, struct {
        \\        pub fn body(eff: anytype) anyerror!void { _ = eff; }
        \\    });
        \\}
    ;
    const Body = struct {
        fn body(_: anytype) anyerror!void {}
    };
    const synthetic = comptime syntheticSourceWithEntry(caller, Body, source, .owned_source, "__ability_with_entry_l5_c34", null).?;
    try std.testing.expect(std.mem.containsAtLeast(u8, synthetic, 1, "pub fn __ability_with_entry_l5_c34"));
}

test "syntheticSourceForExpr hoists supporting declarations around anonymous body methods" {
    const caller_source =
        \\const ability = @import("ability");
        \\
        \\pub fn demo() !void {
        \\    _ = try ability.with(undefined, .{}, struct {
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            _ = eff;
        \\            return Support.answer();
        \\        }
        \\
        \\        const Support = struct {
        \\            pub fn answer() i32 {
        \\                return 42;
        \\            }
        \\        };
        \\    });
        \\}
    ;
    const expr_source =
        \\struct {
        \\    pub fn body(eff: anytype) anyerror!i32 {
        \\        _ = eff;
        \\        return Support.answer();
        \\    }
        \\
        \\    const Support = struct {
        \\        pub fn answer() i32 {
        \\            return 42;
        \\        }
        \\    };
        \\}
    ;
    const Body = struct {
        pub fn body(_: anytype) anyerror!i32 {
            return 42;
        }
    };
    const synthetic = comptime syntheticSourceForExpr(
        Body,
        expr_source,
        caller_source,
        "__ability_with_entry_demo",
        "anyerror!i32",
    ).?;
    try std.testing.expect(std.mem.containsAtLeast(u8, synthetic, 1, "const Support = struct"));
    try std.testing.expect(std.mem.containsAtLeast(u8, synthetic, 1, "pub fn __ability_with_entry_demo"));
    try std.testing.expect(std.mem.containsAtLeast(u8, synthetic, 1, "return Support.answer();"));
}

test "bodyIdentity parses anonymous inline body provenance from type names" {
    const Body = struct {
        fn body(_: anytype) anyerror!void {}
    };
    const identity = bodyIdentity(Body).?;
    try std.testing.expectEqualStrings("anonymous_body_synthesis", identity.module_path);
    try std.testing.expectEqualStrings("test \"bodyIdentity parses anonymous inline body provenance from type names\"", identity.enclosing_function);
    try std.testing.expect(std.mem.startsWith(u8, identity.struct_suffix, "__struct_"));
}

test "resolvedRepoPath maps anonymous inline body module paths back to one repo file" {
    const Body = struct {
        fn body(_: anytype) anyerror!void {}
    };
    const path = resolvedRepoPath(Body).?;
    try std.testing.expectEqualStrings("src/internal/anonymous_body_synthesis.zig", path);
}

test "resolvedRepoPath accepts nested test module base aliases when they remain unique" {
    const nested_source =
        \\const ability = @import("ability");
        \\
        \\test "nested lexical witness generator" {
        \\    _ = try ability.with(undefined, .{}, struct {
        \\        pub fn body(eff: anytype) anyerror!void {
        \\            _ = eff;
        \\        }
        \\    });
        \\}
    ;
    const bounds = testBlockBounds(nested_source, "nested lexical witness generator").?;
    const body_bounds = uniqueBodyExpressionBoundsInRange(
        nested_source,
        bounds.start,
        bounds.end,
        .plain_with,
    ).?;
    try std.testing.expectEqualStrings("pub fn body(eff: anytype) anyerror!void {\n            _ = eff;\n        }", trimAsciiWhitespace(nested_source[body_bounds.start..body_bounds.end]));
    try std.testing.expectEqualStrings("generator_test", sourceBaseModuleName("test/lexical_witness/generator_test.zig"));
    try std.testing.expect(modulePathMatchesCandidate("generator_test", "generator_test"));
}

test "uniqueBodyExpressionBoundsInRange fails closed when one function contains two plain with bodies" {
    const source =
        \\const ability = @import("ability");
        \\
        \\pub fn run() !void {
        \\    _ = try ability.with(undefined, .{}, struct {
        \\        pub fn body(eff: anytype) anyerror!void { _ = eff; }
        \\    });
        \\    _ = try ability.with(undefined, .{}, struct {
        \\        pub fn body(eff: anytype) anyerror!void { _ = eff; }
        \\    });
        \\}
    ;
    const graph = source_graph_engine.analyzeComptime(source, .{}) catch unreachable;
    const function_node = graph.functions[0];
    try std.testing.expect(uniqueBodyExpressionBoundsInRange(
        source,
        function_node.body_start_offset,
        function_node.body_end_offset,
        .plain_with,
    ) == null);
}

test "repo-owned plain with examples classify unique vs ambiguous bodies" {
    const state_source = source_graph_embed.embeddedSource("examples/state_basic.zig");
    const state_graph = source_graph_engine.analyzeComptime(state_source, .{}) catch unreachable;
    const state_function = blk: {
        for (state_graph.functions) |function| {
            if (std.mem.eql(u8, function.name, "run")) break :blk function;
        }
        unreachable;
    };
    try std.testing.expect(uniqueBodyExpressionBoundsInRange(
        state_source,
        state_function.body_start_offset,
        state_function.body_end_offset,
        .plain_with,
    ) != null);

    const exception_source = source_graph_embed.embeddedSource("examples/exception_basic.zig");
    const exception_graph = source_graph_engine.analyzeComptime(exception_source, .{}) catch unreachable;
    const exception_function = blk: {
        for (exception_graph.functions) |function| {
            if (std.mem.eql(u8, function.name, "run")) break :blk function;
        }
        unreachable;
    };
    try std.testing.expect(uniqueBodyExpressionBoundsInRange(
        exception_source,
        exception_function.body_start_offset,
        exception_function.body_end_offset,
        .plain_with,
    ) == null);
}

test "state_basic synthesized anonymous body lowers through lowering_api" {
    const state = @import("../effect/state.zig");
    const source_path = "examples/state_basic.zig";
    const body_type = struct {
        pub fn body(eff: anytype) anyerror!i32 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            return try eff.state.get();
        }
    };
    const synthetic = comptime uniqueRepoOwnedAnonymousSource(body_type, .plain_with).?;
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = source_path,
        .line = 1,
        .column = 1,
        .fn_name = "run",
    };
    const Handlers = struct {
        state: state.LexicalDescriptor(i32, error{}),
    };
    const lowered = lowering_api.maybeLower(
        lowering_api.sourceWithContent(source_path, caller, synthetic.source),
        .{
            .label = "anonymous_body_synthesis.state_basic",
            .entry_symbol = synthetic.entry_symbol,
            .ValueType = i32,
            .row = lexical_manifest.Manifest(Handlers).row(),
            .outputs = lexical_manifest.Manifest(Handlers).outputs(),
        },
    );
    try std.testing.expect(lowered != null);
}

test "synthetic plain with helper-call body stays lowerable" {
    const state = @import("../effect/state.zig");
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = "/tmp/helper_probe.zig",
        .line = 8,
        .column = 34,
        .fn_name = "run",
    };
    const source =
        \\fn helper(eff: anytype) anyerror!i32 {
        \\    return try eff.state.get();
        \\}
        \\
        \\pub fn run() !void {
        \\    _ = try ability.with(undefined, .{
        \\        .state = undefined,
        \\    }, struct {
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            return helper(eff);
        \\        }
        \\    });
        \\}
    ;
    const Body = struct {
        pub fn body(eff: anytype) anyerror!i32 {
            return helper(eff);
        }
        fn helper(_: anytype) anyerror!i32 {
            unreachable;
        }
    };
    const synthetic = comptime syntheticSourceWithEntry(caller, Body, source, .plain_with, "__ability_with_entry_l8_c34", null).?;
    const Handlers = struct {
        state: state.LexicalDescriptor(i32, error{}),
    };
    const lowered = lowering_api.maybeLower(
        lowering_api.sourceWithContent("/tmp/helper_probe.zig", caller, synthetic),
        .{
            .label = "anonymous_body_synthesis.helper_probe",
            .entry_symbol = "__ability_with_entry_l8_c34",
            .ValueType = i32,
            .row = lexical_manifest.Manifest(Handlers).row(),
            .outputs = lexical_manifest.Manifest(Handlers).outputs(),
        },
    );
    try std.testing.expect(lowered != null);
}

test "caller-owned entry scan admits effect-qualified calls" {
    const source =
        \\pub fn __ability_with_entry_l1_c1(eff: anytype) anyerror!i32 {
        \\    return try eff.state.get();
        \\}
    ;
    try std.testing.expect(!entryBodyHasBareFunctionCall(source, "__ability_with_entry_l1_c1"));

    const ctx_source =
        \\pub fn __ability_with_entry_l1_c1(ctx: anytype) anyerror!i32 {
        \\    return try ctx.state.get();
        \\}
    ;
    try std.testing.expect(!entryBodyHasBareFunctionCall(ctx_source, "__ability_with_entry_l1_c1"));
}

test "caller-owned entry scan admits requirement-alias effect calls" {
    const requirement_alias_source =
        \\pub fn __ability_with_entry_l1_c1(eff: anytype) anyerror!i32 {
        \\    const state = eff.state;
        \\    return try state.get();
        \\}
    ;
    try std.testing.expect(!entryBodyHasBareFunctionCall(requirement_alias_source, "__ability_with_entry_l1_c1"));
}

test "caller-owned entry scan rejects qualified helper calls" {
    const this_source =
        \\pub fn __ability_with_entry_l1_c1(eff: anytype) anyerror!i32 {
        \\    return try eff.state.get() + @This().helper();
        \\}
    ;
    try std.testing.expect(entryBodyHasBareFunctionCall(this_source, "__ability_with_entry_l1_c1"));

    const namespace_source =
        \\pub fn __ability_with_entry_l1_c1(eff: anytype) anyerror!i32 {
        \\    return try eff.state.get() + Helpers.foo();
        \\}
    ;
    try std.testing.expect(entryBodyHasBareFunctionCall(namespace_source, "__ability_with_entry_l1_c1"));

    const arbitrary_anytype_source =
        \\pub fn __ability_with_entry_l1_c1(helper_ns: anytype) anyerror!i32 {
        \\    return helper_ns.foo();
        \\}
    ;
    try std.testing.expect(entryBodyHasBareFunctionCall(arbitrary_anytype_source, "__ability_with_entry_l1_c1"));
}

test "synthetic plain with run(self, eff) lowers when self is unused" {
    const state = @import("../effect/state.zig");
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = "/tmp/self_probe.zig",
        .line = 5,
        .column = 34,
        .fn_name = "run",
    };
    const source =
        \\pub fn run() !void {
        \\    _ = try ability.with(undefined, .{
        \\        .state = undefined,
        \\    }, struct {
        \\        pub fn run(self: @This(), eff: anytype) anyerror!i32 {
        \\            _ = self;
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\}
    ;
    const Body = struct {
        pub fn run(self: @This(), eff: anytype) anyerror!i32 {
            _ = self;
            return try eff.state.get();
        }
    };
    const synthetic = comptime syntheticSourceWithEntry(caller, Body, source, .plain_with, "__ability_with_entry_l5_c34", null).?;
    const Handlers = struct {
        state: state.LexicalDescriptor(i32, error{}),
    };
    const lowered = lowering_api.maybeLower(
        lowering_api.sourceWithContent("/tmp/self_probe.zig", caller, synthetic),
        .{
            .label = "anonymous_body_synthesis.self_probe",
            .entry_symbol = "__ability_with_entry_l5_c34",
            .ValueType = i32,
            .row = lexical_manifest.Manifest(Handlers).row(),
            .outputs = lexical_manifest.Manifest(Handlers).outputs(),
        },
    );
    try std.testing.expect(lowered != null);
}

test "actual lexical_with_test run(self, eff) source lowers through synthetic entry" {
    const ability = @import("ability");
    const source = source_graph_embed.embeddedSource("test/lexical_with_test.zig");
    const bounds = comptime blk: {
        const test_block = testBlockBounds(source, "ability.with accepts body run(self, eff)").?;
        break :blk uniqueBodyExpressionBoundsInRange(source, test_block.start, test_block.end, .plain_with).?;
    };
    const Body = struct {
        pub fn run(self: @This(), eff: anytype) anyerror!i32 {
            _ = self;
            return try eff.state.get();
        }
    };
    const entry_symbol = "__ability_with_entry_36363";
    const synthetic_path = "/tmp/ability_with/__ability_with_entry_36363.zig";
    const synthetic = comptime syntheticSourceForExpr(
        Body,
        source[bounds.start..bounds.end],
        source,
        entry_symbol,
        null,
    ).?;
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = synthetic_path,
        .line = 1,
        .column = 1,
        .fn_name = entry_symbol,
    };
    const Handlers = @TypeOf(.{
        .state = ability.effect.state.use(@as(i32, 11)),
    });
    const lowered = lowering_api.maybeLower(
        lowering_api.sourceWithContent(synthetic_path, caller, synthetic),
        .{
            .label = "ability.with repo-owned lexical body",
            .entry_symbol = entry_symbol,
            .ValueType = i32,
            .row = lexical_manifest.Manifest(Handlers).row(),
            .outputs = lexical_manifest.Manifest(Handlers).outputs(),
        },
    );
    try std.testing.expect(lowered != null);
    try std.testing.expect(maybeLowerSyntheticLexicalBody(
        Handlers,
        i32,
        synthetic_path,
        synthetic,
        entry_symbol,
    ) != null);
    _ = lowering_api.lower(
        lowering_api.sourceWithContent(synthetic_path, caller, synthetic),
        .{
            .label = "ability.with repo-owned lexical body",
            .entry_symbol = entry_symbol,
            .ValueType = i32,
            .row = lexical_manifest.Manifest(Handlers).row(),
            .outputs = lexical_manifest.Manifest(Handlers).outputs(),
        },
    );
    try std.testing.expect(genericMaybeLowerSynthetic(
        Handlers,
        i32,
        synthetic_path,
        synthetic,
        entry_symbol,
    ) != null);
}

test "actual lexical_with_test run(eff) synthetic hash probe" {
    const source = source_graph_embed.embeddedSource("test/lexical_with_test.zig");
    const test_block = comptime testBlockBounds(source, "ability.with accepts body run(eff)").?;
    const bounds = comptime uniqueBodyExpressionBoundsInRange(
        source,
        test_block.start,
        test_block.end,
        .plain_with,
    ).?;
    const Body = struct {
        pub fn run(eff: anytype) anyerror!i32 {
            return try eff.state.get();
        }
    };
    _ = comptime syntheticSourceForExpr(
        Body,
        source[bounds.start..bounds.end],
        source,
        "__ability_with_entry_probe",
        null,
    ).?;
}

test "actual writer_basic helper body lowers through synthetic entry" {
    const ability = @import("ability");
    const source = source_graph_embed.embeddedSource("examples/writer_basic.zig");
    const graph = source_graph_engine.analyzeComptime(source, .{}) catch unreachable;
    const function_node = blk: {
        for (graph.functions) |function| {
            if (std.mem.eql(u8, function.name, "runWithAllocator")) break :blk function;
        }
        unreachable;
    };
    const bounds = uniqueBodyExpressionBoundsInRange(
        source,
        function_node.body_start_offset,
        function_node.body_end_offset,
        .plain_with,
    ).?;
    const Body = struct {
        pub fn body(eff: anytype) anyerror![]const u8 {
            return writerBody(eff);
        }

        fn writerBody(_: anytype) anyerror![]const u8 {
            unreachable;
        }
    };
    const entry_symbol = "__ability_with_entry_36746";
    const synthetic_path = "/tmp/ability_with/__ability_with_entry_36746.zig";
    const synthetic = comptime syntheticSourceForExpr(
        Body,
        source[bounds.start..bounds.end],
        source,
        entry_symbol,
        "anyerror![]const u8",
    ).?;
    try std.testing.expectEqual(@as(u64, 4967362839013197614), std.hash.Wyhash.hash(0, synthetic));
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = synthetic_path,
        .line = 1,
        .column = 1,
        .fn_name = entry_symbol,
    };
    const Handlers = @TypeOf(.{
        .writer = ability.effect.writer.use([]const u8, std.testing.allocator),
    });
    const lowered = lowering_api.maybeLower(
        lowering_api.sourceWithContent(synthetic_path, caller, synthetic),
        .{
            .label = "ability.with repo-owned lexical body",
            .entry_symbol = entry_symbol,
            .ValueType = []const u8,
            .row = lexical_manifest.Manifest(Handlers).row(),
            .outputs = lexical_manifest.Manifest(Handlers).outputs(),
        },
    );
    try std.testing.expect(lowered != null);
    try std.testing.expect(maybeLowerSyntheticLexicalBody(
        Handlers,
        []const u8,
        synthetic_path,
        synthetic,
        entry_symbol,
    ) != null);
    try std.testing.expect(genericMaybeLowerSynthetic(
        Handlers,
        []const u8,
        synthetic_path,
        synthetic,
        entry_symbol,
    ) != null);
}

test "actual resource_basic helper body lowers through synthetic entry" {
    const ability = @import("ability");
    const source = source_graph_embed.embeddedSource("examples/resource_basic.zig");
    const graph = source_graph_engine.analyzeComptime(source, .{}) catch unreachable;
    const function_node = blk: {
        for (graph.functions) |function| {
            if (std.mem.eql(u8, function.name, "run")) break :blk function;
        }
        unreachable;
    };
    const bounds = uniqueBodyExpressionBoundsInRange(
        source,
        function_node.body_start_offset,
        function_node.body_end_offset,
        .plain_with,
    ).?;
    const Body = struct {
        pub fn body(eff: anytype) anyerror![]const u8 {
            return resourceBody(eff);
        }

        fn resourceBody(_: anytype) anyerror![]const u8 {
            unreachable;
        }
    };
    const entry_symbol = "__ability_with_entry_30142";
    const synthetic_path = "/tmp/ability_with/__ability_with_entry_30142.zig";
    const synthetic = comptime syntheticSourceForExpr(
        Body,
        source[bounds.start..bounds.end],
        source,
        entry_symbol,
        "anyerror![]const u8",
    ).?;
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = synthetic_path,
        .line = 1,
        .column = 1,
        .fn_name = entry_symbol,
    };
    const resource_manager = struct {
        pub fn acquire() []const u8 {
            unreachable;
        }
        pub fn release(_: []const u8) void {}
    };
    const Handlers = @TypeOf(.{
        .resource = ability.effect.resource.use([]const u8, resource_manager),
    });
    const lowered = lowering_api.maybeLower(
        lowering_api.sourceWithContent(synthetic_path, caller, synthetic),
        .{
            .label = "ability.with repo-owned lexical body",
            .entry_symbol = entry_symbol,
            .ValueType = []const u8,
            .row = lexical_manifest.Manifest(Handlers).row(),
            .outputs = lexical_manifest.Manifest(Handlers).outputs(),
        },
    );
    try std.testing.expect(lowered != null);
    try std.testing.expect(maybeLowerSyntheticLexicalBody(
        Handlers,
        []const u8,
        synthetic_path,
        synthetic,
        entry_symbol,
    ) != null);
}

test "caller-owned writer_basic body lowers through syntheticSourceWithEntry" {
    const ability = @import("ability");
    const source = source_graph_embed.embeddedSource("examples/writer_basic.zig");
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = "examples/writer_basic.zig",
        .line = 14,
        .column = 34,
        .fn_name = "runWithAllocator",
    };
    const Body = struct {
        pub fn body(eff: anytype) anyerror![]const u8 {
            return writerBody(eff);
        }

        fn writerBody(_: anytype) anyerror![]const u8 {
            unreachable;
        }
    };
    const entry_symbol = callerEntryName(caller);
    const synthetic = comptime syntheticSourceWithEntry(caller, Body, source, .plain_with, entry_symbol, null).?;
    const synthetic_path = std.fmt.comptimePrint("/tmp/ability_with/{s}.zig", .{entry_symbol});
    const path_z = std.fmt.comptimePrint("{s}\x00", .{synthetic_path});
    const entry_z = std.fmt.comptimePrint("{s}\x00", .{entry_symbol});
    const caller_owned = std.builtin.SourceLocation{
        .module = @src().module,
        .file = path_z[0..synthetic_path.len :0],
        .line = 1,
        .column = 1,
        .fn_name = entry_z[0..entry_symbol.len :0],
    };
    const Handlers = @TypeOf(.{
        .writer = ability.effect.writer.use([]const u8, std.testing.allocator),
    });
    try std.testing.expect(lowering_api.maybeLower(
        lowering_api.sourceWithContent(synthetic_path, caller_owned, synthetic),
        .{
            .label = "ability.with repo-owned lexical body",
            .entry_symbol = entry_symbol,
            .ValueType = []const u8,
            .row = lexical_manifest.Manifest(Handlers).row(),
            .outputs = lexical_manifest.Manifest(Handlers).outputs(),
        },
    ) != null);
}

test "caller-owned resource_basic body lowers through syntheticSourceWithEntry" {
    const ability = @import("ability");
    const source = source_graph_embed.embeddedSource("examples/resource_basic.zig");
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = "examples/resource_basic.zig",
        .line = 49,
        .column = 34,
        .fn_name = "run",
    };
    const Body = struct {
        pub fn body(eff: anytype) anyerror![]const u8 {
            return resourceBody(eff);
        }

        fn resourceBody(_: anytype) anyerror![]const u8 {
            unreachable;
        }
    };
    const entry_symbol = callerEntryName(caller);
    const synthetic = comptime syntheticSourceWithEntry(caller, Body, source, .plain_with, entry_symbol, null).?;
    const synthetic_path = std.fmt.comptimePrint("/tmp/ability_with/{s}.zig", .{entry_symbol});
    const path_z = std.fmt.comptimePrint("{s}\x00", .{synthetic_path});
    const entry_z = std.fmt.comptimePrint("{s}\x00", .{entry_symbol});
    const caller_owned = std.builtin.SourceLocation{
        .module = @src().module,
        .file = path_z[0..synthetic_path.len :0],
        .line = 1,
        .column = 1,
        .fn_name = entry_z[0..entry_symbol.len :0],
    };
    const resource_manager = struct {
        pub fn acquire() []const u8 {
            unreachable;
        }
        pub fn release(_: []const u8) void {}
    };
    const Handlers = @TypeOf(.{
        .resource = ability.effect.resource.use([]const u8, resource_manager),
    });
    try std.testing.expect(lowering_api.maybeLower(
        lowering_api.sourceWithContent(synthetic_path, caller_owned, synthetic),
        .{
            .label = "ability.with repo-owned lexical body",
            .entry_symbol = entry_symbol,
            .ValueType = []const u8,
            .row = lexical_manifest.Manifest(Handlers).row(),
            .outputs = lexical_manifest.Manifest(Handlers).outputs(),
        },
    ) != null);
}

test "caller-owned state_basic body lowers through syntheticSourceWithEntry" {
    const ability = @import("ability");
    const source = source_graph_embed.embeddedSource("examples/state_basic.zig");
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = "examples/state_basic.zig",
        .line = 16,
        .column = 34,
        .fn_name = "run",
    };
    const Body = struct {
        pub fn body(eff: anytype) @TypeOf(stateBody(eff)) {
            return stateBody(eff);
        }

        fn stateBody(_: anytype) anyerror!i32 {
            unreachable;
        }
    };
    const entry_symbol = callerEntryName(caller);
    const synthetic = comptime syntheticSourceWithEntry(caller, Body, source, .plain_with, entry_symbol, "anyerror!i32").?;
    const synthetic_path = std.fmt.comptimePrint("/tmp/ability_with/{s}.zig", .{entry_symbol});
    const path_z = std.fmt.comptimePrint("{s}\x00", .{synthetic_path});
    const entry_z = std.fmt.comptimePrint("{s}\x00", .{entry_symbol});
    const caller_owned = std.builtin.SourceLocation{
        .module = @src().module,
        .file = path_z[0..synthetic_path.len :0],
        .line = 1,
        .column = 1,
        .fn_name = entry_z[0..entry_symbol.len :0],
    };
    const Handlers = @TypeOf(.{
        .state = ability.effect.state.use(@as(i32, 5)),
    });
    try std.testing.expect(lowering_api.maybeLower(
        lowering_api.sourceWithContent(synthetic_path, caller_owned, synthetic),
        .{
            .label = "ability.with repo-owned lexical body",
            .entry_symbol = entry_symbol,
            .ValueType = i32,
            .row = lexical_manifest.Manifest(Handlers).row(),
            .outputs = lexical_manifest.Manifest(Handlers).outputs(),
        },
    ) != null);
}

test "actual state_basic helper body lowers through synthetic entry" {
    const ability = @import("ability");
    const source = source_graph_embed.embeddedSource("examples/state_basic.zig");
    const graph = source_graph_engine.analyzeComptime(source, .{}) catch unreachable;
    const function_node = blk: {
        for (graph.functions) |function| {
            if (std.mem.eql(u8, function.name, "run")) break :blk function;
        }
        unreachable;
    };
    const bounds = uniqueBodyExpressionBoundsInRange(
        source,
        function_node.body_start_offset,
        function_node.body_end_offset,
        .plain_with,
    ).?;
    const Body = struct {
        pub fn body(eff: anytype) @TypeOf(stateBody(eff)) {
            return stateBody(eff);
        }

        fn stateBody(_: anytype) anyerror!i32 {
            unreachable;
        }
    };
    const entry_symbol = "__ability_with_entry_30101";
    const synthetic_path = "/tmp/ability_with/__ability_with_entry_30101.zig";
    const synthetic = comptime syntheticSourceForExpr(
        Body,
        source[bounds.start..bounds.end],
        source,
        entry_symbol,
        "anyerror!i32",
    ).?;
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = synthetic_path,
        .line = 1,
        .column = 1,
        .fn_name = entry_symbol,
    };
    const Handlers = @TypeOf(.{
        .state = ability.effect.state.use(@as(i32, 5)),
    });
    const lowered = lowering_api.maybeLower(
        lowering_api.sourceWithContent(synthetic_path, caller, synthetic),
        .{
            .label = "ability.with repo-owned lexical body",
            .entry_symbol = entry_symbol,
            .ValueType = i32,
            .row = lexical_manifest.Manifest(Handlers).row(),
            .outputs = lexical_manifest.Manifest(Handlers).outputs(),
        },
    );
    try std.testing.expect(lowered != null);
    try std.testing.expect(maybeLowerSyntheticLexicalBody(
        Handlers,
        i32,
        synthetic_path,
        synthetic,
        entry_symbol,
    ) != null);
}

test "actual open_row_generator helper body lowers through synthetic entry" {
    const ability = @import("ability");
    const source = source_graph_embed.embeddedSource("examples/open_row_generator.zig");
    const graph = source_graph_engine.analyzeComptime(source, .{}) catch unreachable;
    const function_node = blk: {
        for (graph.functions) |function| {
            if (std.mem.eql(u8, function.name, "runWithAllocator")) break :blk function;
        }
        unreachable;
    };
    const bounds = uniqueBodyExpressionBoundsInRange(
        source,
        function_node.body_start_offset,
        function_node.body_end_offset,
        .plain_with,
    ).?;
    const Body = struct {
        pub fn body(eff: anytype) anyerror!i32 {
            return generatorBody(eff);
        }

        fn generatorBody(_: anytype) anyerror!i32 {
            unreachable;
        }
    };
    const entry_symbol = "__ability_with_entry_30125";
    const synthetic_path = "/tmp/ability_with/__ability_with_entry_30125.zig";
    const synthetic = comptime syntheticSourceForExpr(
        Body,
        source[bounds.start..bounds.end],
        source,
        entry_symbol,
        null,
    ).?;
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = synthetic_path,
        .line = 1,
        .column = 1,
        .fn_name = entry_symbol,
    };
    const Handlers = @TypeOf(.{
        .state = ability.effect.state.use(@as(i32, 0)),
        .writer = ability.effect.writer.use([]const u8, std.testing.allocator),
    });
    const lowered = lowering_api.maybeLower(
        lowering_api.sourceWithContent(synthetic_path, caller, synthetic),
        .{
            .label = "ability.with repo-owned lexical body",
            .entry_symbol = entry_symbol,
            .ValueType = i32,
            .row = lexical_manifest.Manifest(Handlers).row(),
            .outputs = lexical_manifest.Manifest(Handlers).outputs(),
        },
    );
    try std.testing.expect(lowered != null);
    try std.testing.expect(maybeLowerSyntheticLexicalBody(
        Handlers,
        i32,
        synthetic_path,
        synthetic,
        entry_symbol,
    ) != null);
}

test "actual open_row_workflow helper body lowers through synthetic entry" {
    const ability = @import("ability");
    const source = source_graph_embed.embeddedSource("examples/open_row_workflow.zig");
    const graph = source_graph_engine.analyzeComptime(source, .{}) catch unreachable;
    const function_node = blk: {
        for (graph.functions) |function| {
            if (std.mem.eql(u8, function.name, "runWithAllocator")) break :blk function;
        }
        unreachable;
    };
    const bounds = uniqueBodyExpressionBoundsInRange(
        source,
        function_node.body_start_offset,
        function_node.body_end_offset,
        .plain_with,
    ).?;
    const Search = ability.effect.Define(.{
        .state_type = struct {},
        .ops = .{
            ability.effect.ops.Transform("search", []const u8, i32),
        },
    });
    const Approval = ability.effect.Define(.{
        .state_type = void,
        .ops = .{
            ability.effect.ops.Choice("publish", void, []const u8),
        },
    });
    const search_handler = struct {
        pub fn search(_: *@This(), _: []const u8) i32 {
            unreachable;
        }
        pub fn afterSearch(_: *@This(), answer: []const u8) []const u8 {
            return answer;
        }
    };
    const approval_handler = struct {
        pub fn publish(_: *@This()) ability.effect.choice.Decision([]const u8, []const u8) {
            unreachable;
        }
        pub fn afterPublish(_: *@This(), answer: []const u8) []const u8 {
            return answer;
        }
    };
    const Body = struct {
        pub fn body(eff: anytype) anyerror![]const u8 {
            return workflowBody(eff);
        }

        fn workflowBody(_: anytype) anyerror![]const u8 {
            unreachable;
        }
    };
    const entry_symbol = "__ability_with_entry_30467";
    const synthetic_path = "/tmp/ability_with/__ability_with_entry_30467.zig";
    const synthetic = comptime syntheticSourceForExpr(
        Body,
        source[bounds.start..bounds.end],
        source,
        entry_symbol,
        null,
    ).?;
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = synthetic_path,
        .line = 1,
        .column = 1,
        .fn_name = entry_symbol,
    };
    const Handlers = @TypeOf(.{
        .state = ability.effect.state.use(@as(i32, 0)),
        .writer = ability.effect.writer.use([]const u8, std.testing.allocator),
        .search = Search.use(.{ .handler = search_handler{} }),
        .approval = Approval.use(.{ .handler = approval_handler{} }),
    });
    const lowered = lowering_api.maybeLower(
        lowering_api.sourceWithContent(synthetic_path, caller, synthetic),
        .{
            .label = "ability.with repo-owned lexical body",
            .entry_symbol = entry_symbol,
            .ValueType = []const u8,
            .row = lexical_manifest.Manifest(Handlers).row(),
            .outputs = lexical_manifest.Manifest(Handlers).outputs(),
        },
    );
    try std.testing.expect(lowered != null);
    try std.testing.expect(maybeLowerSyntheticLexicalBody(
        Handlers,
        []const u8,
        synthetic_path,
        synthetic,
        entry_symbol,
    ) != null);
}
