// zlinter-disable declaration_naming - local test-only witness names stay capitalized to mirror the derived types under test.
// zlinter-disable import_ordering - helper imports stay grouped by local compile-input layering.
const lexical_bundle_schema = @import("lexical_bundle_schema.zig");
const std = @import("std");

/// Return the compile-input packet type for one lexical handler bundle.
pub fn CompileInput(comptime HandlersType: type) type {
    return struct {
        row: @TypeOf(lexical_bundle_schema.rowForHandlers(HandlersType)),
        outputs: @TypeOf(lexical_bundle_schema.outputsForHandlers(HandlersType)),
    };
}

/// Derive one shared row/output packet from a concrete lexical-state pointer type.
pub fn fromLexicalStatePointer(comptime LexicalStatePtrType: type) CompileInput(std.meta.Child(@FieldType(@typeInfo(LexicalStatePtrType).pointer.child, "handlers_ptr"))) {
    const pointer = @typeInfo(LexicalStatePtrType);
    if (pointer != .pointer) @compileError("expected lexical state pointer type");
    const LexicalStateType = pointer.pointer.child;
    if (!@hasField(LexicalStateType, "handlers_ptr")) @compileError("lexical state must expose handlers_ptr");

    const HandlersPtrType = @FieldType(LexicalStateType, "handlers_ptr");
    const HandlersType = std.meta.Child(HandlersPtrType);
    return .{
        .row = lexical_bundle_schema.rowForHandlers(HandlersType),
        .outputs = lexical_bundle_schema.outputsForHandlers(HandlersType),
    };
}

test "lexical compile input derives row and outputs from lexical state pointer" {
    const with_api = @import("../with_api.zig");
    const state = @import("../effect/state.zig");
    const writer = @import("../effect/writer.zig");

    const Handlers = struct {
        state: state.LexicalDescriptor(i32, error{}),
        writer: writer.LexicalDescriptor([]const u8, error{}),
    };
    const Eff = struct {};
    const StatePtr = *with_api.LexicalState(Handlers, Eff);
    const input = fromLexicalStatePointer(StatePtr);
    try std.testing.expectEqual(@as(usize, 2), input.row.requirements.len);
    try std.testing.expectEqual(@as(usize, 2), input.outputs.len);
}
