const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const no_state = struct {};
const search = shift.algebraic.TransformOp("search", []const u8, i32);
const ArtifactSearch = shift.algebraic.Program(i32, NoError, .{search});

/// Write the algebraic artifact-search transcript through the public builder surface.
pub fn run(writer: anytype) anyerror!void {
    const transcript = struct {
        threadlocal var items = [_][]const u8{ "", "", "", "", "", "" };
        threadlocal var len: usize = 0;

        fn note(message: []const u8) void {
            items[len] = message;
            len += 1;
        }
    };

    const search_handler = struct {
        /// Record the search query and return the canonical total.
        pub fn resumeValue(_: no_state, payload: []const u8) i32 {
            if (!std.mem.eql(u8, payload, "artifact-search")) unreachable;
            transcript.note("query=artifact-search");
            return 3;
        }

        /// Preserve the resumed algebraic answer unchanged.
        pub fn afterResume(_: no_state, answer: i32) i32 {
            return answer;
        }
    };

    const configured = ArtifactSearch.handlers(.{
        shift.algebraic.handleTransform(search, no_state{}, search_handler),
    });

    const body = struct {
        /// Trigger the algebraic search operation and emit the canonical artifact transcript fields.
        pub fn program(ctx: *@TypeOf(configured).Context) @TypeOf(ctx.performProgram(search, "artifact-search", struct {
            /// Record the remaining search transcript fields after the algebraic resume.
            pub fn apply(total: i32) i32 {
                if (total != 3) unreachable;
                transcript.note("messages=1");
                transcript.note("tool_calls=0");
                transcript.note("memory_blocks=1");
                transcript.note("opencode_source=jsonl");
                return total;
            }
        })) {
            return ctx.performProgram(search, "artifact-search", struct {
                /// Record the remaining search transcript fields after the algebraic resume.
                pub fn apply(total: i32) i32 {
                    if (total != 3) unreachable;
                    transcript.note("messages=1");
                    transcript.note("tool_calls=0");
                    transcript.note("memory_blocks=1");
                    transcript.note("opencode_source=jsonl");
                    return total;
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    transcript.len = 0;
    const result = try configured.run(&runtime, body);
    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("total={d}\n", .{result});
}

/// Run the algebraic artifact-search example.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
