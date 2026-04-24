// zlinter-disable no_undefined - fixed-size comptime assembly buffers are fully overwritten before observation in this internal schema helper.
// zlinter-disable require_doc_comment - this internal comptime schema helper uses public constants as type-level assembly surfaces.
const effect_ir = @import("effect_ir");
const effect_schema = @import("../effect_schema.zig");
const std = @import("std");

fn RequirementStorage(comptime requirement: effect_ir.Requirement) type {
    return struct {
        pub const ops = blk: {
            var buffer: [requirement.ops.len]effect_ir.OpSpec = undefined;
            for (requirement.ops, 0..) |op, index| {
                buffer[index] = op;
            }
            break :blk buffer;
        };

        pub const value: effect_ir.Requirement = .{
            .label = requirement.label,
            .ops = &ops,
        };
    };
}

fn MergedRowStorage(comptime rows: anytype) type {
    const total = comptime blk: {
        var count: usize = 0;
        for (rows) |row| count += row.requirements.len;
        break :blk count;
    };
    return struct {
        pub const requirements = blk: {
            var buffer: [total]effect_ir.Requirement = undefined;
            var index: usize = 0;
            for (rows) |current_row| {
                for (current_row.requirements) |requirement| {
                    buffer[index] = RequirementStorage(requirement).value;
                    index += 1;
                }
            }
            break :blk buffer;
        };

        pub const row: effect_ir.Row = .{ .requirements = &requirements };
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
    return @Tuple(&types);
}

/// Lower one lexical handler bundle into the shared effect_ir row.
pub fn rowForHandlers(comptime HandlersType: type) effect_ir.Row {
    const fields = @typeInfo(HandlersType).@"struct".fields;
    const rows = comptime blk: {
        var rows: [fields.len]effect_ir.Row = undefined;
        for (fields, 0..) |field, index| {
            const DescriptorType = field.type;
            rows[index] = effect_schema.row(DescriptorType.BindingSchema(field.name));
        }
        break :blk rows;
    };
    return MergedRowStorage(rows).row;
}

/// Lower one lexical handler bundle into explicit effect_ir outputs.
pub fn outputsForHandlers(comptime HandlersType: type) []const effect_ir.OutputSpec {
    const fields = @typeInfo(HandlersType).@"struct".fields;
    const count = comptime blk: {
        var count: usize = 0;
        for (fields) |field| {
            const DescriptorType = field.type;
            count += effect_schema.outputs(DescriptorType.BindingSchema(field.name)).len;
        }
        break :blk count;
    };
    const output_storage = struct {
        pub const values = blk: {
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
            break :blk buffer;
        };
    };
    return &output_storage.values;
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
