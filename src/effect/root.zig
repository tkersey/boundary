const family = @import("family.zig");
/// Public handler choice-decision helper namespace.
pub const choice = @import("choice.zig");
/// Exception effect family for returning a thrown payload through `boundary.effect handlers`.
pub const exception = @import("exception.zig");
/// Optional effect family for choosing between early return and resumed execution.
pub const optional = @import("optional.zig");
/// Reader effect family for accessing shared environment values.
pub const reader = @import("reader.zig");
/// Resource effect family for bracketed acquire/use/release workflows.
pub const resource = @import("resource.zig");
/// State effect family for reading and updating scoped state.
pub const state = @import("state.zig");
/// Writer effect family for collecting append-only output.
pub const writer = @import("writer.zig");

test {
    const std = @import("std");

    _ = choice;
    _ = exception;
    _ = family;
    _ = optional;
    _ = reader;
    _ = resource;
    _ = state;
    _ = writer;
    try std.testing.expect(!@hasDecl(@This(), "Define"));
    try std.testing.expect(!@hasDecl(@This(), "ops"));
}
