const probe = @import("source_ownership_probe_helper.zig");
const shift = @import("shift");
const shift_compile = @import("shift_compile");
const std = @import("std");

fn callerSourceFile(comptime ContextType: type) []const u8 {
    return switch (@typeInfo(@TypeOf(ContextType.caller_source))) {
        .optional => ContextType.caller_source.?.file,
        .null => unreachable,
        else => ContextType.caller_source.file,
    };
}

test "wrapper-local source capture stays callee-owned across realistic zero-argument wrapper forms" {
    const caller_source = @src().file;
    const helper_source = probe.helperSourceFile();

    try std.testing.expectEqualStrings(helper_source, probe.directWrapperSourceFile());
    try std.testing.expectEqualStrings(helper_source, probe.inlineWrapperSourceFile());
    try std.testing.expectEqualStrings(helper_source, probe.namespacedWrapperSourceFile());

    try std.testing.expect(!std.mem.eql(u8, caller_source, probe.directWrapperSourceFile()));
    try std.testing.expect(!std.mem.eql(u8, caller_source, probe.inlineWrapperSourceFile()));
    try std.testing.expect(!std.mem.eql(u8, caller_source, probe.namespacedWrapperSourceFile()));
}

test "only explicit caller participation preserves truthful source ownership across modules" {
    try std.testing.expectEqualStrings(@src().file, probe.explicitCallerSourceFile(@src()));
}

test "public provenance wrappers stay caller-owned only with explicit cross-file participation" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    {
        const result = try shift.withAt(@src(), &runtime, .{
            .state = shift.effect.state.use(@as(i32, 0)),
        }, struct {
            /// Return the caller-owned source observed through the lexical `shift.with` surface.
            pub fn body(eff: anytype) anyerror![]const u8 {
                return callerSourceFile(@TypeOf(eff.state.ctx.?.*));
            }
        });
        try std.testing.expectEqualStrings(@src().file, result.value);
    }

    {
        const NoError = error{};

        var reader_instance = shift.effect.reader.Instance(i32, NoError).init();
        const reader_result = try shift.effect.reader.handleWithErrorSetAt(@src(), []const u8, NoError, &runtime, &reader_instance, @as(i32, 21), struct {
            /// Return the caller-owned source observed through the reader wrapper.
            pub fn body(comptime Cap: type, ctx: anytype) NoError![]const u8 {
                _ = Cap;
                return callerSourceFile(@TypeOf(ctx.*));
            }
        });
        try std.testing.expectEqualStrings(@src().file, reader_result);

        var state_instance = shift.effect.state.Instance(i32, NoError).init();
        const state_result = try shift.effect.state.handleWithErrorSetAt(@src(), []const u8, NoError, &runtime, &state_instance, @as(i32, 0), struct {
            /// Return the caller-owned source observed through the state wrapper.
            pub fn body(comptime Cap: type, ctx: anytype) NoError![]const u8 {
                _ = Cap;
                return callerSourceFile(@TypeOf(ctx.*));
            }
        });
        try std.testing.expectEqualStrings(@src().file, state_result.value);

        const catcher = struct {
            /// Preserve the body answer so the provenance witness remains visible.
            pub fn directReturn(payload: []const u8) []const u8 {
                return payload;
            }
        };
        var exception_instance = shift.effect.exception.Instance([]const u8, NoError).init();
        const exception_result = try shift.effect.exception.handleWithErrorSetAt(@src(), []const u8, NoError, &runtime, &exception_instance, catcher, struct {
            /// Return the caller-owned source observed through the exception wrapper.
            pub fn body(comptime Cap: type, ctx: anytype) NoError![]const u8 {
                _ = Cap;
                return callerSourceFile(@TypeOf(ctx.*));
            }
        });
        try std.testing.expectEqualStrings(@src().file, exception_result);

        const manager = struct {
            /// Return one resource so the resource wrapper can establish its context.
            pub fn acquire() []const u8 {
                return "resource";
            }

            /// Release the probe resource without any side effects.
            pub fn release(_: []const u8) void {
                // No-op release for provenance-only coverage.
            }
        };
        var resource_instance = shift.effect.resource.Instance([]const u8, NoError).init();
        const resource_result = try shift.effect.resource.handleWithErrorSetAt(@src(), []const u8, NoError, &runtime, &resource_instance, manager, struct {
            /// Return the caller-owned source observed through the resource wrapper.
            pub fn body(comptime Cap: type, ctx: anytype) NoError![]const u8 {
                _ = Cap;
                return callerSourceFile(@TypeOf(ctx.*));
            }
        });
        try std.testing.expectEqualStrings(@src().file, resource_result);

        var writer_instance = shift.effect.writer.Instance([]const u8, NoError).init();
        const writer_result = try shift.effect.writer.handleWithErrorSetAt(@src(), .{
            .Item = []const u8,
            .Answer = []const u8,
            .ErrorSet = NoError,
        }, &runtime, &writer_instance, std.testing.allocator, struct {
            /// Return the caller-owned source observed through the writer wrapper.
            pub fn body(comptime Cap: type, ctx: anytype) NoError![]const u8 {
                _ = Cap;
                return callerSourceFile(@TypeOf(ctx.*));
            }
        });
        defer std.testing.allocator.free(writer_result.items);
        try std.testing.expectEqualStrings(@src().file, writer_result.value);

        const Audit = shift.effect.Define(.{
            .state_type = void,
            .ops = .{
                shift.effect.ops.Transform("note", []const u8, void),
            },
        });
        var generated_instance = Audit.Instance.init();
        const generated_result = try Audit.handleWithErrorSetAt(@src(), []const u8, NoError, &runtime, &generated_instance, struct {
            /// Accept the generated-family probe payload without changing state.
            pub fn note(_: *@This(), _: []const u8) void {
                // No-op handler for provenance-only coverage.
            }
        }{}, struct {
            /// Return the caller-owned source observed through the generated-family wrapper.
            pub fn body(comptime Cap: type, ctx: anytype) NoError![]const u8 {
                _ = Cap;
                return callerSourceFile(@TypeOf(ctx.*));
            }
        });
        try std.testing.expectEqualStrings(@src().file, generated_result.value);
    }
}

test "source helper captures explicit repo path plus caller-owned participation" {
    const src = shift_compile.lowering.sourceWithContent("test/source_ownership_probe_test.zig", @src(), @embedFile(@src().file));

    try std.testing.expectEqualStrings("test/source_ownership_probe_test.zig", src.repo_path);
    try std.testing.expectEqualStrings(std.fs.path.basename(@src().file), std.fs.path.basename(src.caller_file));
}

test "source helper stays callable from test modules" {
    const src = shift_compile.lowering.source("test/source_ownership_probe_test.zig", @src());

    try std.testing.expectEqualStrings("test/source_ownership_probe_test.zig", src.repo_path);
    try std.testing.expectEqualStrings(std.fs.path.basename(@src().file), std.fs.path.basename(src.caller_file));
}

test "public root drops compile entrypoints while shift_compile keeps provenance-bearing lowering" {
    try std.testing.expect(!@hasDecl(shift, "lowerAt"));
    try std.testing.expect(!@hasDecl(shift, "lower"));
    try std.testing.expect(!@hasDecl(shift, "lowering"));
    try std.testing.expect(!@hasDecl(shift, "compat"));
    try std.testing.expect(!@hasDecl(shift, "Decl"));
    try std.testing.expect(!@hasDecl(shift, "Op"));
    try std.testing.expect(!@hasDecl(shift, "Decision"));
    try std.testing.expect(!@hasDecl(shift, "Program"));
    try std.testing.expect(!@hasDecl(shift, "run"));
    try std.testing.expect(!@hasDecl(shift, "artifact"));
    try std.testing.expect(!@hasDecl(shift, "durable"));
    try std.testing.expect(!@hasDecl(shift, "interpreter"));
    try std.testing.expect(!@hasDecl(shift, "ir"));
    try std.testing.expect(@hasDecl(shift_compile, "lower"));
    try std.testing.expect(@hasDecl(shift_compile, "lowering"));
    try std.testing.expect(@hasDecl(shift_compile.lowering, "lowerAt"));
}
