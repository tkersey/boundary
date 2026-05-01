// zlinter-disable max_positional_args - synthetic lowering host mirrors the generated packet shape exactly.
const authoring_lowerer = @import("authoring_lowerer");
const effect_ir = @import("effect_ir");
const lowering_api = @import("lowering_api");
const std = @import("std");

/// Lower one synthetic anonymous-body packet through the dedicated synthetic host module.
pub fn maybeLowerSyntheticLexicalBody(
    comptime ValueType: type,
    comptime row: effect_ir.Row,
    comptime outputs: []const effect_ir.OutputSpec,
    comptime synthetic_path: []const u8,
    comptime synthetic_source: [:0]const u8,
    comptime entry_symbol: []const u8,
) ?authoring_lowerer.OpenRowLoweredAuthoring {
    const path_z = std.fmt.comptimePrint("{s}\x00", .{synthetic_path});
    const entry_z = std.fmt.comptimePrint("{s}\x00", .{entry_symbol});
    return lowering_api.maybeLower(
        lowering_api.sourceWithContent(synthetic_path, .{
            .module = @src().module,
            .file = path_z[0..synthetic_path.len :0],
            .line = 1,
            .column = 1,
            .fn_name = entry_z[0..entry_symbol.len :0],
        }, synthetic_source),
        .{
            .label = "ability.with repo-owned lexical body",
            .entry_symbol = entry_symbol,
            .ValueType = ValueType,
            .row = row,
            .outputs = outputs,
        },
    );
}
