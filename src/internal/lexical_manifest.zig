// zlinter-disable require_doc_comment - this internal manifest helper exposes comptime bridge constants for the compiled lexical seam.
const lexical_bundle_schema = @import("lexical_bundle_schema.zig");
const lexical_compile_input = @import("lexical_compile_input.zig");
const lexical_executable_bundle = @import("lexical_executable_bundle.zig");
const std = @import("std");

/// Canonical manifest for one lexical handler bundle on the compiled-path boundary.
pub fn Manifest(comptime HandlersType: type) type {
    return struct {
        pub const BindingSchemas = lexical_bundle_schema.BindingSchemas(HandlersType);
        pub const ExecutableBundle = lexical_executable_bundle.BundleType(HandlersType);

        pub fn row() @TypeOf(lexical_bundle_schema.rowForHandlers(HandlersType)) {
            return lexical_bundle_schema.rowForHandlers(HandlersType);
        }

        pub fn outputs() @TypeOf(lexical_bundle_schema.outputsForHandlers(HandlersType)) {
            return lexical_bundle_schema.outputsForHandlers(HandlersType);
        }

        pub fn compileInput() lexical_compile_input.CompileInput(HandlersType) {
            return .{
                .row = row(),
                .outputs = outputs(),
            };
        }

        pub fn fromLexicalState(lexical_state: anytype) ExecutableBundle {
            return lexical_executable_bundle.fromLexicalState(lexical_state);
        }

        pub fn deinitBundle(bundle_ptr: anytype) anyerror!void {
            return try lexical_executable_bundle.deinit(bundle_ptr);
        }
    };
}

test "lexical manifest unifies compile input and executable bundle for built-in handlers" {
    const lowered_machine = @import("lowered_machine");
    const state = @import("../effect/state.zig");
    const writer = @import("../effect/writer.zig");

    const Handlers = struct {
        state: state.LexicalDescriptor(i32, error{}),
        writer: writer.LexicalDescriptor([]const u8, error{}),
    };
    const manifest_shape = Manifest(Handlers);

    try std.testing.expectEqual(@as(usize, 2), manifest_shape.row().requirements.len);
    try std.testing.expectEqual(@as(usize, 2), manifest_shape.outputs().len);

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var handlers: Handlers = .{
        .state = state.use(@as(i32, 4)),
        .writer = writer.use([]const u8, std.testing.allocator),
    };
    const lexical_state = struct {
        runtime: *lowered_machine.Runtime,
        handlers_ptr: *Handlers,
    }{
        .runtime = &runtime,
        .handlers_ptr = &handlers,
    };

    var bundle = manifest_shape.fromLexicalState(lexical_state);
    try std.testing.expectEqual(@as(i32, 4), bundle.state.get());
    try bundle.writer.tell("queued");
    const finished = try bundle.writer.finish();
    defer std.testing.allocator.free(finished);
    try std.testing.expectEqual(@as(usize, 1), finished.len);
    try std.testing.expectEqualStrings("queued", finished[0]);
}

test "lexical manifest compile input derives from with_api lexical state pointers" {
    const state = @import("../effect/state.zig");
    const with_api = @import("../with_api.zig");

    const Handlers = struct {
        state: state.LexicalDescriptor(i32, error{}),
    };
    const lexical_effect_state = struct {};
    const LexicalStatePtr = *with_api.LexicalState(Handlers, lexical_effect_state);
    const input = lexical_compile_input.fromLexicalStatePointer(LexicalStatePtr);

    try std.testing.expectEqual(@as(usize, 1), input.row.requirements.len);
    try std.testing.expectEqual(@as(usize, 1), input.outputs.len);
    try std.testing.expectEqualStrings("state", input.row.requirements[0].label);
}
