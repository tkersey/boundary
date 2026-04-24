// zlinter-disable require_doc_comment - lexical witness helpers are test-only support surfaces.
const common = @import("common.zig");
const lexical_runtime = common.lexical_runtime;
const std = common.std;

fn directReturnBody(eff: anytype) anyerror![]const u8 {
    try eff.exception.throw("result=early");
}

fn runDirectReturn(writer: anytype) anyerror!void {
    const transcript = struct {
        threadlocal var handler_line: []const u8 = "";
    };
    const catch_policy = struct {
        pub fn directReturn(payload: []const u8) []const u8 {
            transcript.handler_line = "handler-direct-return";
            return payload;
        }
    };

    var runtime = lexical_runtime.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.handler_line = "";
    const result = try lexical_runtime.with(&runtime, .{
        .exception = lexical_runtime.effect.exception.use([]const u8, catch_policy),
    }, struct {
        pub fn body(eff: anytype) anyerror![]const u8 {
            return directReturnBody(eff);
        }
    });
    try writer.print("{s}\n", .{transcript.handler_line});
    try writer.print("final={s}\n", .{result.value});
}

test "lexical witness direct_return transcripts stay aligned" {
    try common.expectLexicalWitness("direct_return", runDirectReturn);
}
