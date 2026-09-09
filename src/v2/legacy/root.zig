// Copyright (c) 2026 Boundary contributors. MIT license.
//! Pure admission of immutable historical BPI1 program data. There is no PST1
//! decoder, interpreter, authoring dependency, or native application callback.
const std = @import("std");
pub const image = @import("image.zig");
pub const value = @import("value.zig");
pub const contract = @import("contract.zig");
pub const types = @import("types.zig");
pub const lift = @import("lift.zig").lift;

pub const Decoded = struct {
    arena: std.heap.ArenaAllocator,
    program: image.ValidatedImage,

    pub fn deinit(self: *Decoded) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

/// Own the admitted bytes and their schema index. Temporary validation arrays
/// do not remain in the result and cannot become portable execution state.
pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !Decoded {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const owned = try arena.allocator().dupe(u8, bytes);
    const workspace = try allocator.create(image.ValidationWorkspace);
    defer allocator.destroy(workspace);
    workspace.* = .{};
    var program = try image.validateImage(owned, workspace);
    program.catalogs.schemas.nodes = try arena.allocator().dupe(value.NodeIndex, program.catalogs.schemas.nodes);
    return .{ .arena = arena, .program = program };
}

test {
    _ = image;
    _ = value;
}
