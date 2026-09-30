const std = @import("std");
const data = @import("boundary_data");
const fixture = @import("equality_saturation.zig").interaction;
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const path = args.next() orelse return error.Output;
    if (args.next() != null) return error.Arguments;
    var original = fixture;
    original.constants = &.{ .{ .schema = 1, .bytes = &.{} }, .{ .schema = 0, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } } };
    original.blocks = &.{.{ .function = 0, .instructions = &.{ .{ .destination = 2, .opcode = .constant, .immediate = 1 }, .{ .destination = 3, .opcode = .integer_add, .operands = &.{ 0, 1 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 0 }} }, .{ .destination = 2, .opcode = .integer_mul, .operands = &.{ 2, 3 }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = 0 }} } }, .terminator = .{ .return_value = 2 } }};
    const bytes = try init.gpa.alloc(u8, try data.program_image.encodedLength(original));
    defer init.gpa.free(bytes);
    _ = try data.program_image.encode(init.gpa, original, bytes);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = bytes });
}
