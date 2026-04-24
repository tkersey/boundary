// zlinter-disable require_doc_comment - lexical witness helpers are test-only support surfaces.
const common = @import("common.zig");
const lexical_runtime = common.lexical_runtime;
const std = common.std;

fn emitThird(eff: anytype) anyerror!void {
    try eff.state.set(3);
    try eff.writer.tell("yield=3");
}

fn emitSecond(eff: anytype) anyerror!void {
    try eff.state.set(2);
    try eff.writer.tell("yield=2");
    try emitThird(eff);
}

fn emitFirst(eff: anytype) anyerror!void {
    try eff.state.set(1);
    try eff.writer.tell("yield=1");
    try emitSecond(eff);
}

fn generatorBody(eff: anytype) anyerror!i32 {
    try emitFirst(eff);
    const final = try eff.state.get();
    return final;
}

fn runGenerator(writer: anytype) anyerror!void {
    var runtime = lexical_runtime.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    var output_buffer: [256]u8 = undefined;
    var output_fba = std.heap.FixedBufferAllocator.init(&output_buffer);
    const result = try lexical_runtime.with(&runtime, .{
        .writer = lexical_runtime.effect.writer.use([]const u8, output_fba.allocator()),
        .state = lexical_runtime.effect.state.use(@as(i32, 0)),
    }, struct {
        pub fn body(eff: anytype) anyerror!i32 {
            return generatorBody(eff);
        }
    });
    defer output_fba.allocator().free(result.outputs.writer);
    for (result.outputs.writer) |item| try writer.print("{s}\n", .{item});
    try writer.print("done={d}\n", .{result.value});
}

test "lexical witness generator transcripts stay aligned" {
    try common.expectLexicalWitness("generator", runGenerator);
}
