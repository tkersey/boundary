// zlinter-disable require_doc_comment - these fixture witnesses expose public nested bodies only because the lexical API binds comptime-visible structs.
const shift = @import("shift");
const std = @import("std");

fn ExecResult(comptime T: type) type {
    return (shift.RuntimeError || error{ OutOfMemory, BodyOops, ContinueOops, HandlerOops, AfterOops })!T;
}

fn expectFixtureTranscript(comptime fixture_path: []const u8, writer_fn: anytype) anyerror!void {
    var buffer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buffer.deinit();
    try writer_fn(&buffer.writer);
    try std.testing.expectEqualStrings(@embedFile(fixture_path), buffer.written());
}

test "shift.with matches the state fixture transcript through lexical handles" {
    try expectFixtureTranscript("example_proof/fixtures/state_basic.txt", struct {
        fn run(writer: anytype) anyerror!void {
            var runtime = shift.Runtime.init(std.testing.allocator);
            defer runtime.deinit();

            const result = try shift.with(&runtime, .{
                .state = shift.effect.state.use(@as(i32, 5)),
            }, struct {
                pub fn body(eff: anytype) ExecResult(i32) {
                    const before = try eff.state.get();
                    try eff.state.set(before + 1);
                    const after = try eff.state.get();
                    return before + after;
                }
            });

            try writer.print("before=5\nafter=6\nfinal_state={d}\nvalue={d}\n", .{ result.outputs.state, result.value });
        }
    }.run);
}

test "shift.with matches the reader fixture transcript through lexical handles" {
    try expectFixtureTranscript("example_proof/fixtures/reader_basic.txt", struct {
        fn run(writer: anytype) anyerror!void {
            var runtime = shift.Runtime.init(std.testing.allocator);
            defer runtime.deinit();

            const result = try shift.with(&runtime, .{
                .reader = shift.effect.reader.use(@as(i32, 21)),
            }, struct {
                pub fn body(eff: anytype) ExecResult(i32) {
                    const env = try eff.reader.ask();
                    return env + env;
                }
            });

            try writer.print("env=21\nvalue={d}\n", .{result.value});
        }
    }.run);
}

test "shift.with matches the writer fixture transcript through lexical handles" {
    try expectFixtureTranscript("example_proof/fixtures/writer_basic.txt", struct {
        fn run(writer: anytype) anyerror!void {
            var runtime = shift.Runtime.init(std.testing.allocator);
            defer runtime.deinit();

            const result = try shift.with(&runtime, .{
                .writer = shift.effect.writer.use([]const u8, std.testing.allocator),
            }, struct {
                pub fn body(eff: anytype) ExecResult([]const u8) {
                    try eff.writer.tell("a");
                    try eff.writer.tell("b");
                    return "done";
                }
            });
            defer std.testing.allocator.free(result.outputs.writer);

            for (result.outputs.writer) |item| {
                try writer.print("item={s}\n", .{item});
            }
            try writer.print("value={s}\n", .{result.value});
        }
    }.run);
}
