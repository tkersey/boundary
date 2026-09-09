// Copyright (c) 2026 Boundary contributors. MIT license.
const std = @import("std");
const data = @import("boundary_data_v2");

/// Independently owned compiler output; construction storage may be released.
pub const Compiled = struct {
    arena: std.heap.ArenaAllocator,
    program: data.program.Program,

    pub fn deinit(self: *Compiled) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn encode(self: Compiled, allocator: std.mem.Allocator, output: []u8) data.image.Error![]const u8 {
        return data.image.encode(allocator, self.program, output);
    }
};
