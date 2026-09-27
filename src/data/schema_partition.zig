// Copyright (c) 2026 Boundary contributors. MIT license.
//! Existing linker structural schema partition, shared with closed-program coalescing.
//! Inputs have already passed schema validation; nominal maps remain identities.
const std = @import("std");
const p = @import("program.zig");
const ir = @import("activation.zig");
const relocate = @import("relocation.zig");
const equal = @import("record.zig").equal;
const Kind = relocate.Kind;
const Id = p.Id;
const Error = relocate.Error;

/// Result and scratch belong to the caller's arena. Returns dense schema classes.
pub fn compute(a: std.mem.Allocator, program: ir.Program) Error![]const Id {
    var classes = try a.alloc(Id, program.schemas.len);
    var next = try a.alloc(Id, classes.len);
    @memset(classes, 0);
    var maps = try relocate.identityMaps(a, try relocate.sizes(program));
    while (true) {
        var pass = std.heap.ArenaAllocator.init(a);
        defer pass.deinit();
        maps[@intFromEnum(Kind.schema)] = classes;
        const mapper: relocate.Mapper = .{ .allocator = pass.allocator(), .maps = maps };
        const shapes = try pass.allocator().alloc(p.Schema, classes.len);
        for (shapes, program.schemas, 0..) |*shape, original, i| {
            shape.* = try mapper.schema(original);
            next[i] = i;
            for (shapes[0..i], 0..) |prior, j| if (equal(p.Schema, shape.*, prior)) {
                next[i] = next[j];
                break;
            };
        }
        if (std.mem.eql(Id, classes, next)) break;
        std.mem.swap([]Id, &classes, &next);
    }
    const representatives = try a.alloc(Id, classes.len);
    var count: Id = 0;
    for (classes, 0..) |class, i| if (class == i) {
        representatives[i] = count;
        count += 1;
    };
    for (classes) |*class| class.* = representatives[@intCast(class.*)];
    return classes;
}
