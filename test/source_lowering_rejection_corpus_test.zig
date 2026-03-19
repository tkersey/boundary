const source_lowering = @import("source_lowering");
const std = @import("std");

const dead_code_source =
    \\pub fn run(writer: anytype) anyerror!void {
    \\    try writer.writeAll("branch=before\n");
    \\    return;
    \\    var answer: i32 = 0;
    \\    const take_branch = true;
    \\    if (take_branch) {
    \\        try writer.writeAll("branch=taken\n");
    \\        const resumed: i32 = 41;
    \\        try writer.print("resume={d}\n", .{resumed});
    \\        answer = resumed + 1;
    \\    }
    \\    try writer.writeAll("branch=after\n");
    \\    try writer.print("final={d}\n", .{answer});
    \\}
;

const dynamic_callee_source =
    \\fn helper(writer: anytype) anyerror!i32 {
    \\    try writer.writeAll("helper=enter\n");
    \\    try writer.writeAll("helper=exit\n");
    \\    return 42;
    \\}
    \\
    \\pub fn run(writer: anytype) anyerror!void {
    \\    const callee = helper;
    \\    const answer = try callee(writer);
    \\    try writer.print("final={d}\n", .{answer});
    \\}
;

const renamed_helper_source =
    \\fn helper(writer: anytype) anyerror!i32 {
    \\    try writer.writeAll("helper=enter\n");
    \\    const resumed: i32 = 41;
    \\    try writer.print("resume={d}\n", .{resumed});
    \\    try writer.writeAll("helper=exit\n");
    \\    return resumed + 1;
    \\}
    \\
    \\fn alternate(writer: anytype) anyerror!i32 {
    \\    return helper(writer);
    \\}
    \\
    \\pub fn run(writer: anytype) anyerror!void {
    \\    const answer = try alternate(writer);
    \\    try writer.print("final={d}\n", .{answer});
    \\}
;

test "source-lowering rejection corpus stays fail-closed" {
    var dead_code = try source_lowering.inspectInlineSource(std.testing.allocator, .{
        .case_id = "source.branch_resume",
        .source_path = "test/source_lowering_corpus/fixtures/branch_resume.zig",
        .entry_symbol = "run",
        .surface_kind = .source_case,
    }, dead_code_source);
    defer dead_code.deinit(std.testing.allocator);
    try std.testing.expect(!dead_code.isAccepted());
    try std.testing.expectEqualStrings("unsupported_shape", dead_code.diagnostics[0].code);

    var dynamic_callee = try source_lowering.inspectInlineSource(std.testing.allocator, .{
        .case_id = "source.helper_call_resume",
        .source_path = "test/source_lowering_corpus/fixtures/helper_call_resume.zig",
        .entry_symbol = "run",
        .surface_kind = .source_case,
    }, dynamic_callee_source);
    defer dynamic_callee.deinit(std.testing.allocator);
    try std.testing.expect(!dynamic_callee.isAccepted());
    try std.testing.expectEqualStrings("unsupported_shape", dynamic_callee.diagnostics[0].code);

    var renamed_helper = try source_lowering.inspectInlineSource(std.testing.allocator, .{
        .case_id = "source.helper_call_resume",
        .source_path = "test/source_lowering_corpus/fixtures/helper_call_resume.zig",
        .entry_symbol = "run",
        .surface_kind = .source_case,
    }, renamed_helper_source);
    defer renamed_helper.deinit(std.testing.allocator);
    try std.testing.expect(!renamed_helper.isAccepted());
    try std.testing.expectEqualStrings("unsupported_shape", renamed_helper.diagnostics[0].code);

    var wrong_entry = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "example.define_basic",
        .source_path = "examples/define_basic.zig",
        .entry_symbol = "runCounter",
        .surface_kind = .example,
    });
    defer wrong_entry.deinit(std.testing.allocator);
    try std.testing.expect(!wrong_entry.isAccepted());
    try std.testing.expectEqualStrings("unsupported_shape", wrong_entry.diagnostics[0].code);
}
