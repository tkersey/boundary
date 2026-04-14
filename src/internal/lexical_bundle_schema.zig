// zlinter-disable no_undefined - fixed-size comptime assembly buffers are fully overwritten before observation in this internal schema helper.
const effect_ir = @import("effect_ir");
const effect_schema = @import("../effect_schema.zig");
const std = @import("std");

fn cloneRequirement(comptime requirement: effect_ir.Requirement) effect_ir.Requirement {
    const ops = comptime blk: {
        var buffer: [requirement.ops.len]effect_ir.OpSpec = undefined;
        for (requirement.ops, 0..) |op, index| {
            buffer[index] = op;
        }
        break :blk buffer;
    };
    return .{
        .label = requirement.label,
        .ops = &ops,
    };
}

fn mergeRows(comptime rows: anytype) effect_ir.Row {
    const total = comptime blk: {
        var count: usize = 0;
        for (rows) |row| count += row.requirements.len;
        break :blk count;
    };
    return comptime blk: {
        var buffer: [total]effect_ir.Requirement = undefined;
        var index: usize = 0;
        for (rows) |row| {
            for (row.requirements) |requirement| {
                buffer[index] = cloneRequirement(requirement);
                index += 1;
            }
        }
        break :blk .{ .requirements = &buffer };
    };
}

/// Return the binding-schema tuple for one lexical handler bundle.
pub fn BindingSchemas(comptime HandlersType: type) type {
    const fields = @typeInfo(HandlersType).@"struct".fields;
    var types: [fields.len]type = undefined;
    inline for (fields, 0..) |field, index| {
        const DescriptorType = field.type;
        types[index] = DescriptorType.BindingSchema(field.name);
    }
    return std.meta.Tuple(&types);
}

/// Lower one lexical handler bundle into the shared effect_ir row.
pub fn rowForHandlers(comptime HandlersType: type) effect_ir.Row {
    const fields = @typeInfo(HandlersType).@"struct".fields;
    return comptime blk: {
        var rows: [fields.len]effect_ir.Row = undefined;
        for (fields, 0..) |field, index| {
            const DescriptorType = field.type;
            rows[index] = effect_schema.row(DescriptorType.BindingSchema(field.name));
        }
        break :blk mergeRows(rows);
    };
}

/// Lower one lexical handler bundle into explicit effect_ir outputs.
pub fn outputsForHandlers(comptime HandlersType: type) []const effect_ir.OutputSpec {
    const fields = @typeInfo(HandlersType).@"struct".fields;
    return comptime blk: {
        var count: usize = 0;
        for (fields) |field| {
            const DescriptorType = field.type;
            count += effect_schema.outputs(DescriptorType.BindingSchema(field.name)).len;
        }

        var buffer: [count]effect_ir.OutputSpec = undefined;
        var index: usize = 0;
        for (fields) |field| {
            const DescriptorType = field.type;
            const outputs = effect_schema.outputs(DescriptorType.BindingSchema(field.name));
            for (outputs) |output| {
                buffer[index] = output;
                index += 1;
            }
        }
        break :blk &buffer;
    };
}

test "lexical bundle schema lowers built-in handlers to one merged row and outputs" {
    const state = @import("../effect/state.zig");
    const writer = @import("../effect/writer.zig");

    const Handlers = struct {
        state: state.LexicalDescriptor(i32, error{}),
        writer: writer.LexicalDescriptor([]const u8, error{}),
    };

    const row = rowForHandlers(Handlers);
    const outputs = outputsForHandlers(Handlers);
    try std.testing.expectEqual(@as(usize, 2), row.requirements.len);
    try std.testing.expectEqualStrings("state", row.requirements[0].label);
    try std.testing.expectEqualStrings("writer", row.requirements[1].label);
    try std.testing.expectEqual(@as(usize, 2), outputs.len);
    try std.testing.expectEqualStrings("state", outputs[0].label);
    try std.testing.expectEqualStrings("writer", outputs[1].label);
}
