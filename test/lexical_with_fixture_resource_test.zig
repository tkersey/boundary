// zlinter-disable require_doc_comment - these fixture witnesses expose public nested resource hooks only because the lexical API binds comptime-visible structs.
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

test "shift.with matches the resource fixture transcript through lexical handles" {
    try expectFixtureTranscript("example_proof/fixtures/resource_basic.txt", struct {
        fn run(writer: anytype) anyerror!void {
            const transcript = struct {
                threadlocal var active_writer: ?@TypeOf(writer) = null;

                fn note(message: []const u8) void {
                    active_writer.?.writeAll(message) catch unreachable;
                }
            };

            const resource_manager = struct {
                threadlocal var next_index: usize = 0;
                const resources = [_][]const u8{ "a", "b" };

                pub fn acquire() []const u8 {
                    const resource = resources[next_index];
                    next_index += 1;
                    transcript.active_writer.?.print("acquire={s}\n", .{resource}) catch unreachable;
                    return resource;
                }

                pub fn release(resource: []const u8) void {
                    transcript.active_writer.?.print("release={s}\n", .{resource}) catch unreachable;
                }
            };

            var runtime = shift.Runtime.init(std.testing.allocator);
            defer runtime.deinit();

            const previous_writer = transcript.active_writer;
            transcript.active_writer = writer;
            defer transcript.active_writer = previous_writer;
            resource_manager.next_index = 0;

            const result = try shift.withAt(@src(), &runtime, .{
                .resource = shift.effect.resource.use([]const u8, resource_manager),
            }, struct {
                pub fn body(eff: anytype) ExecResult([]const u8) {
                    const first = try eff.resource.acquire();
                    transcript.note("use=");
                    transcript.note(first);
                    transcript.note("\n");

                    const second = try eff.resource.acquire();
                    transcript.note("use=");
                    transcript.note(second);
                    transcript.note("\n");

                    return "done";
                }
            });

            try writer.print("final={s}\n", .{result.value});
        }
    }.run);
}
