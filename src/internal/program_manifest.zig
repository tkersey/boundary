const std = @import("std");

pub const DeclarationMeta = struct {
    name: []const u8,
    kind: []const u8,
    has_binding: bool,
    has_output: bool,
    op_count: usize,
};

pub fn build(
    comptime DeclarationKind: type,
    comptime declarations: anytype,
    comptime hasBinding: fn (type) bool,
    comptime hasOutput: fn (type) bool,
) type {
    const fields = @typeInfo(@TypeOf(declarations)).@"struct".fields;
    comptime var manifest_entry_values = [_]DeclarationMeta{.{
        .name = "",
        .kind = "",
        .has_binding = false,
        .has_output = false,
        .op_count = 0,
    }} ** fields.len;
    comptime var output_names = [_][]const u8{""} ** fields.len;
    comptime var output_count: usize = 0;

    inline for (fields, 0..) |field, index| {
        manifest_entry_values[index] = .{
            .name = field.name,
            .kind = @tagName(@as(DeclarationKind, field.type.kind)),
            .has_binding = hasBinding(field.type),
            .has_output = hasOutput(field.type),
            .op_count = if (@hasDecl(field.type, "generated")) field.type.generated.definition.op_count else 0,
        };
        if (hasOutput(field.type)) {
            output_names[output_count] = field.name;
            output_count += 1;
        }
    }

    const manifest_entries = manifest_entry_values;
    const manifest_outputs = blk: {
        comptime var compact = [_][]const u8{""} ** output_count;
        inline for (0..output_count) |index| compact[index] = output_names[index];
        break :blk compact;
    };

    return struct {
        pub const declaration_count = fields.len;
        pub const entries = manifest_entries;
        pub const outputs = manifest_outputs[0..];
    };
}

pub fn of(comptime ProgramType: type) type {
    return ProgramType.internal_manifest;
}
