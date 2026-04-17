const example_open_row_cross_file_writer = @import("example_open_row_cross_file_writer");
const example_open_row_recursive_cross_writer = @import("example_open_row_recursive_cross_writer");
const example_open_row_state_writer = @import("example_open_row_state_writer");
const shift = @import("shift_compile");
const shift_vm = @import("shift_vm");
const std = @import("std");

const LoweredStateHandler = struct {
    value: i32,

    pub fn get(self: *@This()) anyerror!i32 {
        return self.value;
    }

    pub fn set(self: *@This(), value: i32) anyerror!void {
        self.value = value;
    }

    pub fn finish(self: *@This()) i32 {
        return self.value;
    }
};

const LoweredWriterHandler = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList([]const u8) = .empty,

    pub fn tell(self: *@This(), value: []const u8) anyerror!void {
        try self.items.append(self.allocator, value);
    }

    pub fn finish(self: *@This()) anyerror![][]const u8 {
        return try self.items.toOwnedSlice(self.allocator);
    }

    pub fn deinit(self: *@This()) void {
        self.items.deinit(self.allocator);
    }
};

const LoweredStateWriterHandlers = struct {
    state: LoweredStateHandler,
    writer: LoweredWriterHandler,
};

test "open-row smoke lowers same-module program through the public path" {
    const lowered = try example_open_row_state_writer.loweredProgram();

    try std.testing.expectEqualStrings("example.open_row_state_writer", lowered.label);
    try std.testing.expectEqualStrings("runBody", lowered.program.functions[lowered.program.entry_index].symbol.symbol_name);
    try std.testing.expectEqual(@as(usize, 2), lowered.normalization.requirement_count);
    try std.testing.expectEqual(@as(usize, 3), lowered.normalization.op_count);
}

test "open-row smoke executes same-file lowered runner" {
    var runtime = shift_vm.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var handlers: LoweredStateWriterHandlers = .{
        .state = .{ .value = 5 },
        .writer = .{ .allocator = std.testing.allocator },
    };
    defer handlers.writer.deinit();

    const result = try example_open_row_state_writer.CompiledProgram.run(&runtime, &handlers);
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(i32, 6), result.outputs.state);
    try std.testing.expectEqualStrings("done", result.value);
}

test "open-row smoke executes cross-file lowered runner" {
    var runtime = shift_vm.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var handlers: LoweredStateWriterHandlers = .{
        .state = .{ .value = 5 },
        .writer = .{ .allocator = std.testing.allocator },
    };
    defer handlers.writer.deinit();

    const result = try example_open_row_cross_file_writer.CompiledProgram.run(&runtime, &handlers);
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(i32, 7), result.outputs.state);
    try std.testing.expectEqualStrings("done", result.value);
}

test "open-row smoke executes recursive imported-helper lowered runner" {
    var runtime = shift_vm.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var handlers: LoweredStateWriterHandlers = .{
        .state = .{ .value = 2 },
        .writer = .{ .allocator = std.testing.allocator },
    };
    defer handlers.writer.deinit();

    const result = try shift.lowering.run(&runtime, example_open_row_recursive_cross_writer.CompiledProgram, &handlers);
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(i32, 0), result.outputs.state);
    try std.testing.expectEqualStrings("done", result.value);
}
