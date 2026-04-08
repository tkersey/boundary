const std = @import("std");

/// Return this helper module's own source file string.
pub fn helperSourceFile() []const u8 {
    return @src().file;
}

/// Return the source string captured by a direct zero-argument wrapper.
pub fn directWrapperSourceFile() []const u8 {
    return @src().file;
}

/// Return the source string captured by an inline zero-argument wrapper.
pub inline fn inlineWrapperSourceFile() []const u8 {
    return @src().file;
}

/// Return the source string captured by a namespaced zero-argument trampoline.
pub fn namespacedWrapperSourceFile() []const u8 {
    return namespace.sourceFile();
}

/// Return the caller-owned source string when the caller passes `@src()` explicitly.
pub fn explicitCallerSourceFile(src: std.builtin.SourceLocation) []const u8 {
    return src.file;
}

const namespace = struct {
    fn sourceFile() []const u8 {
        return @src().file;
    }
};
