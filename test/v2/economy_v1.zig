//! Test-only matched compiler workload for the frozen Boundary 1.8.2 package.
const std = @import("std");
const boundary = @import("boundary");
const options = @import("economy_options");
const ir = boundary.ir;
const integer: ir.ValueType = .{ .scalar = .u64 };
const argument: ir.ValueType = .{ .scalar = .u32 };
const Lookup = boundary.effect.site(0, "example.lookup.v1", u32, u32);
const EffectBody = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = boundary.effect.row(.{Lookup});
    pub const schema_types = .{};
    pub const control_ir: ir.Program = .{
        .label = "one-effect",
        .value_types = &.{ argument, argument },
        .entry = 0,
        .result_type = argument,
        .blocks = &.{
            .{ .id = 0, .parameters = &.{0}, .terminator = .{ .@"suspend" = .{ .kind = .effect, .site_id = 0, .request_values = &.{0}, .continuation = .{ .target = 1, .arguments = &.{.@"resume"} }, .resume_type = argument } } },
            .{ .id = 1, .parameters = &.{1}, .terminator = .{ .return_value = 1 } },
        },
    };
};
const AddBody = struct {
    pub const InitialArgs = u64;
    pub const Result = u64;
    pub const Failure = enum { arithmetic_overflow };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const constants = .{@as(u64, 1)};
    const inputs = blk: {
        var result: [32][2]ir.ValueId = undefined;
        for (&result, 0..) |*item, index| item.* = .{ if (index == 0) 0 else @intCast(index + 1), 1 };
        break :blk result;
    };
    const instructions = blk: {
        var result: [33]ir.Instruction = undefined;
        result[0] = .{ .kind = .constant, .result = 1, .operation = .{ .constant = 0 } };
        for (result[1..], 0..) |*item, index| item.* = .{ .kind = .pure, .result = @intCast(index + 2), .operands = &inputs[index], .operation = .integer_add };
        break :blk result;
    };
    pub const control_ir: ir.Program = .{ .label = "add-32", .value_types = &([_]ir.ValueType{integer} ** 34), .entry = 0, .result_type = integer, .blocks = &.{.{ .id = 0, .parameters = &.{0}, .instructions = &instructions, .terminator = .{ .return_value = 33 } }} };
};
const Program = blk: {
    @setEvalBranchQuota(3_000_000);
    break :blk boundary.program(if (options.kind == 0) "one-effect" else "add-32", if (options.kind == 0) EffectBody else AddBody);
};

pub fn main(init: std.process.Init) !void {
    const Image = Program.image();
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(&Image.bytes);
    try output.interface.flush();
}
