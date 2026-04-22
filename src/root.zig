const shared = @import("shift_shared");

/// Public lexical effect namespace.
pub const effect = shared.effect;
/// Canonical runtime handle for lexical execution.
pub const Runtime = shared.Runtime;
/// Public runtime misuse and semantic-contract errors surfaced by `shift`.
pub const RuntimeError = shared.RuntimeError;
/// Canonical named lexical body helper for compiled `shift.withAt(@src(), ...)`.
pub const NamedBody = shared.NamedBody;
/// Explicit caller-owned source witness for `shift.withOwnedSource(...)`.
pub const OwnedSourceWitness = shared.OwnedSourceWitness;
/// Run the public lexical handler entrypoint.
pub const with = shared.with;
/// Run the public lexical handler entrypoint with explicit caller provenance.
pub const withAt = shared.withAt;
/// Run the public lexical handler entrypoint through an explicit caller-owned source witness.
pub const withOwnedSource = shared.withOwnedSource;

test {
    _ = Runtime;
    _ = RuntimeError;
    _ = effect;
    _ = NamedBody;
    _ = OwnedSourceWitness;
    _ = with;
    _ = withAt;
    _ = withOwnedSource;
}

test "retained public_ir/public_lowering imports stay source-compatible" {
    const public_ir = @import("public_ir");
    const public_lowering = @import("public_lowering");
    const std = @import("std");

    try std.testing.expect(public_ir.Program == shared.ir.Program);
    try std.testing.expect(public_lowering.ProgramPlan == shared.lowering.ProgramPlan);
    try std.testing.expect(@hasDecl(public_ir, "compile"));
    try std.testing.expect(@hasDecl(public_lowering, "lowerAt"));
}

test "retained compat program entrypoints keep source-compatible runner arity" {
    const demo_program = shared.compat.Program(.{
        .state = shared.compat.Decl.state(i32),
    }, struct {
        pub fn body(eff: anytype) anyerror!i32 {
            return try eff.state.get();
        }
    });

    var runtime = Runtime.init(@import("std").testing.allocator);
    defer runtime.deinit();

    const compat_result = try shared.compat.run(&runtime, demo_program, .{ .state = 7 });
    try @import("std").testing.expectEqual(@as(i32, 7), compat_result.outputs.state);
    try @import("std").testing.expectEqual(@as(i32, 7), compat_result.value);

    const run_result = try demo_program.run(&runtime, .{ .state = 9 });
    try @import("std").testing.expectEqual(@as(i32, 9), run_result.outputs.state);
    try @import("std").testing.expectEqual(@as(i32, 9), run_result.value);

    const free_result = try shared.run(&runtime, demo_program, .{ .state = 11 });
    try @import("std").testing.expectEqual(@as(i32, 11), free_result.outputs.state);
    try @import("std").testing.expectEqual(@as(i32, 11), free_result.value);

    const run_at_result = try demo_program.runAt(@src(), &runtime, .{ .state = 11 });
    try @import("std").testing.expectEqual(@as(i32, 11), run_at_result.outputs.state);
    try @import("std").testing.expectEqual(@as(i32, 11), run_at_result.value);
}

test "retained explicit-caller program entrypoints preserve caller provenance across the root surface" {
    const caller_program = shared.Program(.{
        .state = shared.Decl.state(i32),
    }, struct {
        pub fn body(eff: anytype) anyerror![]const u8 {
            const CallerContext = @TypeOf(eff.state.ctx.?.*);
            const caller_source = CallerContext.caller_source;
            return switch (@typeInfo(@TypeOf(caller_source))) {
                .optional => caller_source.?.file,
                .null => unreachable,
                else => caller_source.file,
            };
        }
    });

    var runtime = Runtime.init(@import("std").testing.allocator);
    defer runtime.deinit();

    const compat_result = try shared.compat.runAt(@src(), &runtime, caller_program, .{ .state = 0 });
    try @import("std").testing.expectEqualStrings(@src().file, compat_result.value);

    const run_result = try caller_program.runAt(@src(), &runtime, .{ .state = 0 });
    try @import("std").testing.expectEqualStrings(@src().file, run_result.value);
}
