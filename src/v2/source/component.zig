// Copyright (c) 2026 Boundary contributors. MIT license.
const std = @import("std");
const source = @import("../source.zig");
const lower = @import("activation_lower.zig");
const data = @import("boundary_data_v2");
pub const Interface = struct { imports: []const data.component.Symbol = &.{}, exports: []const data.component.Symbol };
pub const Compiled = struct {
    construction: lower.Construction,
    object: data.component.Object,
    pub fn deinit(self: *Compiled) void {
        self.construction.deinit();
        self.* = undefined;
    }
    pub fn encode(self: *const Compiled, allocator: std.mem.Allocator, output: []u8) ![]const u8 {
        return data.component.encode(allocator, self.object, output);
    }
};
fn less(_: void, a: data.component.Symbol, b: data.component.Symbol) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}
pub fn compile(allocator: std.mem.Allocator, module: source.Module, interface: Interface) !Compiled {
    var temporary = std.heap.ArenaAllocator.init(allocator);
    defer temporary.deinit();
    var functions: std.ArrayList(data.program.Id) = .empty;
    for (interface.imports) |symbol| if (symbol.reference.kind == .function) try functions.append(temporary.allocator(), symbol.reference.id);
    var construction = try lower.lowerComponent(allocator, module, functions.items);
    errdefer construction.deinit();
    const a = construction.arena.allocator();
    const imports = try source.own([]const data.component.Symbol, a, interface.imports);
    const exports = try source.own([]const data.component.Symbol, a, interface.exports);
    std.mem.sort(data.component.Symbol, @constCast(imports), {}, less);
    std.mem.sort(data.component.Symbol, @constCast(exports), {}, less);
    const object: data.component.Object = .{ .program = construction.program, .imports = imports, .exports = exports };
    try data.component.validate(allocator, object);
    return .{ .construction = construction, .object = object };
}
