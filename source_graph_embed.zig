const build_options = @import("authoring_build_options");
const source_graph_comptime = @import("source_graph_comptime");
const std = @import("std");

fn repoRelativePath(comptime source_path: []const u8) []const u8 {
    if (std.fs.path.isAbsolute(source_path)) {
        if (!std.mem.startsWith(u8, source_path, build_options.package_root)) {
            @compileError("public lowering source path must stay under the package root");
        }
        if (source_path.len <= build_options.package_root.len or source_path[build_options.package_root.len] != std.fs.path.sep) {
            @compileError("public lowering source path must point to a file under the package root");
        }
        return source_path[build_options.package_root.len + 1 ..];
    }
    return source_path;
}

/// Embed one repo-relative source file through a repo-root module so examples remain package-visible.
pub fn embeddedSource(comptime source_path: []const u8) [:0]const u8 {
    return @embedFile(repoRelativePath(source_path));
}

/// Analyze one repo-relative source file through the shared comptime source-graph extractor.
pub fn analyzeModuleAt(comptime source_path: []const u8, comptime entry_symbol: []const u8) source_graph_comptime.Error!source_graph_comptime.ModuleGraph {
    return source_graph_comptime.analyzeModule(embeddedSource(source_path), entry_symbol);
}
