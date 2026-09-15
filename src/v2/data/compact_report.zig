//! Standalone pure-data byte attribution. This entry point is not imported by the codec.
const std = @import("std");
const p = @import("program.zig");
const image = @import("image.zig");
const compact = @import("compact_image.zig");
const wire = @import("wire.zig");
const record = @import("record.zig");
const packed_record = @import("compact_record.zig");
const sequence = @import("compact_sequence.zig");
const parameters = @import("compact_parameters.zig");
const Row = struct { catalog: []const u8, legacy: usize, compact: usize };

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().reader(init.io, &buffer);
    const bytes = try input.interface.allocRemaining(init.gpa, .unlimited);
    defer init.gpa.free(bytes);
    var decoded = try compact.decode(init.gpa, bytes);
    defer decoded.deinit();
    var plan = try parameters.Plan.init(init.gpa, decoded.program);
    defer plan.deinit();
    var rows: [9]Row = undefined;
    var context: parameters.Writing = .{ .plan = &plan };
    var body_length: usize = 0;
    inline for (std.meta.fields(p.Program), 0..) |field, index| {
        var old: wire.Writer = .{};
        try record.write(field.type, @field(decoded.program, field.name), &old);
        var new: wire.Writer = .{};
        try packed_record.write(field.type, @field(decoded.program, field.name), &new, &context);
        rows[index] = .{ .catalog = field.name, .legacy = old.position, .compact = new.position };
        body_length += new.position;
    }
    var dictionary: wire.Writer = .{};
    try dictionary.natural(plan.backings.items.len);
    var parameter_descriptions: usize = 0;
    for (plan.backings.items) |values| {
        try sequence.write(p.Id, values, &dictionary);
        parameter_descriptions += try sequence.descriptions(p.Id, values);
    }
    var logical_parameters: usize = 0;
    for (decoded.program.blocks, 0..) |block, index| {
        logical_parameters += block.parameters.len;
        parameter_descriptions += if (plan.references[index] != null)
            1
        else
            try sequence.descriptions(p.Id, block.parameters);
    }
    const selected = try compact.encodedLength(init.gpa, decoded.program);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &output_buffer);
    try std.json.Stringify.value(.{
        .input_bytes = bytes.len,
        .identity = std.fmt.bytesToHex(try image.identity(decoded.program), .lower),
        .legacy_bytes = try image.encodedLength(decoded.program),
        .selected_bytes = selected,
        .bpc1_bytes = wire.header_length + dictionary.position + body_length,
        .framing_bytes = wire.header_length,
        .parameter_dictionary_bytes = dictionary.position,
        .parameter_backings = plan.backings.items.len,
        .parameter_reference_direction = if (plan.from_end) "suffix" else "prefix",
        .logical_parameters = logical_parameters,
        .physical_parameter_descriptions = parameter_descriptions,
        .physical_argument_descriptions = try arguments(p.Program, decoded.program),
        .catalogs = rows,
    }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}

fn arguments(comptime T: type, value: T) !usize {
    return switch (@typeInfo(T)) {
        .pointer => |info| blk: {
            if (info.child == p.Argument) break :blk try sequence.descriptions(p.Argument, value);
            if (info.child == u8 or info.child == p.Id or info.child == u32) break :blk 0;
            var count: usize = 0;
            for (value) |element| count += try arguments(info.child, element);
            break :blk count;
        },
        .@"struct" => |info| blk: {
            var count: usize = 0;
            inline for (info.fields) |field| count += try arguments(field.type, @field(value, field.name));
            break :blk count;
        },
        .@"union" => switch (value) {
            inline else => |payload| try arguments(@TypeOf(payload), payload),
        },
        .optional => |info| if (value) |present| try arguments(info.child, present) else 0,
        else => 0,
    };
}
