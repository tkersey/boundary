// zlinter-disable require_doc_comment - these fixture witnesses expose public nested handlers and bodies only because the lexical API binds comptime-visible structs.
const shift = @import("lexical_runtime_internal");
const std = @import("std");

fn ExecResult(comptime T: type) type {
    return (shift.RuntimeError || error{ OutOfMemory, BodyOops, ContinueOops, HandlerOops, AfterOops })!T;
}

fn expectFixtureTranscript(comptime fixture_path: []const u8, writer_fn: anytype) anyerror!void {
    var buffer: std.io.Writer.Allocating = .init(std.testing.allocator);
    defer buffer.deinit();
    try writer_fn(&buffer.writer);
    try std.testing.expectEqualStrings(@embedFile(fixture_path), buffer.written());
}

test "shift.with matches the exception fixture transcript through lexical handles" {
    try expectFixtureTranscript("example_proof/fixtures/exception_basic.txt", struct {
        fn run(writer: anytype) anyerror!void {
            const transcript = struct {
                threadlocal var active_writer: ?@TypeOf(writer) = null;

                fn note(message: []const u8) void {
                    active_writer.?.writeAll(message) catch unreachable;
                }
            };

            const catch_policy = struct {
                pub fn directReturn(payload: []const u8) []const u8 {
                    transcript.active_writer.?.print("catch={s}\n", .{payload}) catch unreachable;
                    return payload;
                }
            };

            var runtime = shift.Runtime.init(std.testing.allocator);
            defer runtime.deinit();

            const previous_writer = transcript.active_writer;
            transcript.active_writer = writer;
            defer transcript.active_writer = previous_writer;

            try writer.writeAll("branch=pass\n");
            const ok = try shift.withAt(@src(), &runtime, .{
                .exception = shift.effect.exception.use([]const u8, catch_policy),
            }, struct {
                pub fn body(_: anytype) ExecResult([]const u8) {
                    return "result=ok";
                }
            });
            try writer.writeAll("body-pass\n");
            try writer.print("final={s}\n", .{ok.value});

            try writer.writeAll("branch=throw\n");
            try writer.writeAll("body-before-throw\n");
            const thrown = try shift.withAt(@src(), &runtime, .{
                .exception = shift.effect.exception.use([]const u8, catch_policy),
            }, struct {
                pub fn body(eff: anytype) ExecResult([]const u8) {
                    try eff.exception.throw("result=boom");
                }
            });
            try writer.print("final={s}\n", .{thrown.value});
        }
    }.run);
}
