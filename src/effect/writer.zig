const algebraic = @import("algebraic.zig");
const family = @import("family.zig");
const shift = @import("../root.zig");
const std = @import("std");

fn WriterState(comptime ItemType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        first_item: ?ItemType = null,
        items: std.ArrayList(ItemType) = .empty,

        fn init(allocator: std.mem.Allocator) @This() {
            return .{ .allocator = allocator };
        }

        fn deinit(self: *@This()) void {
            self.items.deinit(self.allocator);
        }

        fn append(self: *@This(), item: ItemType) !void {
            if (self.first_item == null and self.items.items.len == 0) {
                self.first_item = item;
                return;
            }
            if (self.items.items.len == 0) {
                try self.items.ensureTotalCapacity(self.allocator, 2);
                self.items.appendAssumeCapacity(self.first_item.?);
                self.first_item = null;
            }
            try self.items.append(self.allocator, item);
        }

        fn intoOwnedSlice(self: *@This()) ![]ItemType {
            if (self.items.items.len != 0) {
                return try self.items.toOwnedSlice(self.allocator);
            }

            if (self.first_item) |item| {
                const slice = try self.allocator.alloc(ItemType, 1);
                slice[0] = item;
                self.first_item = null;
                return slice;
            }

            return try self.allocator.alloc(ItemType, 0);
        }
    };
}

/// Prompt-backed effect instance for an append-only writer family.
pub fn Instance(comptime ItemType: type, comptime ErrorSetType: type) type {
    return family.Instance(WriterState(ItemType), ErrorSetType);
}

/// Final writer log plus body answer returned from a handled writer program.
pub fn HandleResult(comptime ItemType: type, comptime ValueType: type) type {
    return struct {
        items: []ItemType,
        value: ValueType,
    };
}

/// Append one item to the current writer log.
pub inline fn tell(
    comptime Cap: type,
    ctx: anytype,
    item: anytype,
) shift.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!void {
    const WriterStateType = family.ContextStateType(@TypeOf(ctx));
    _ = try algebraic.mutateTransformState(Cap, ctx, item, struct {
        /// Resume the caller with no value after a writer append.
        pub const Result = void;

        /// Append one item into the active writer state.
        pub fn apply(state: *WriterStateType, value: @TypeOf(item)) shift.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!void {
            try state.append(value);
        }
    });
}

/// Run a writer effect body and return the accumulated log plus the body answer.
pub fn handle(
    comptime ItemType: type,
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    allocator: std.mem.Allocator,
    comptime Body: type,
) shift.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!HandleResult(ItemType, AnswerType) {
    const StateType = WriterState(ItemType);
    var result = try family.handle(AnswerType, runtime, instance, StateType.init(allocator), Body);
    errdefer result.state.deinit();
    const items = try result.state.intoOwnedSlice();
    return .{
        .items = items,
        .value = result.value,
    };
}

test "writer instance shell stays prompt-sized" {
    const NoError = error{};
    const WriterInstance = Instance([]const u8, NoError);
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(WriterInstance));
}

test "writer handle accumulates items in order" {
    const NoError = error{};
    const WriterInstance = Instance([]const u8, NoError);
    const demo = struct {
        /// Append two items and then return normally.
        pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)![]const u8 {
            try tell(Cap, ctx, "a");
            try tell(Cap, ctx, "b");
            return "done";
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    var instance = WriterInstance.init();
    const result = try handle([]const u8, []const u8, &runtime, &instance, std.testing.allocator, demo);
    defer std.testing.allocator.free(result.items);
    try std.testing.expectEqual(@as(usize, 2), result.items.len);
    try std.testing.expectEqualStrings("a", result.items[0]);
    try std.testing.expectEqualStrings("b", result.items[1]);
    try std.testing.expectEqualStrings("done", result.value);
}

test "nested same-shaped writer handles get distinct capability types" {
    const NoError = error{};
    const WriterInstance = Instance([]const u8, NoError);
    const demo = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var inner_ptr: ?*const WriterInstance = null;

        /// Open an inner writer handle and prove its capability differs from the outer one.
        pub fn outer(comptime OuterCap: type, _: anytype) shift.ResetError(NoError)![]const u8 {
            const result = try handle([]const u8, []const u8, runtime_ptr.?, inner_ptr.?, std.testing.allocator, struct {
                /// Reject capability-type collapse inside the nested writer handle.
                pub fn body(comptime InnerCap: type, _: anytype) shift.ResetError(NoError)![]const u8 {
                    comptime if (OuterCap == InnerCap) {
                        @compileError("nested writer handles must receive distinct capability types");
                    };
                    return "done";
                }
            });
            defer std.testing.allocator.free(result.items);
            return result.value;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    var outer_instance = WriterInstance.init();
    var inner_instance = WriterInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    const result = try handle([]const u8, []const u8, &runtime, &outer_instance, std.testing.allocator, struct {
        /// Enter the outer writer handle and hand its capability inward.
        pub fn body(comptime OuterCap: type, ctx: anytype) shift.ResetError(NoError)![]const u8 {
            return try demo.outer(OuterCap, ctx);
        }
    });
    defer std.testing.allocator.free(result.items);
    try std.testing.expectEqualStrings("done", result.value);
}
