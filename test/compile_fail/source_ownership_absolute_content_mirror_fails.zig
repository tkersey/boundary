const shift_compile = @import("shift_compile");
const std = @import("std");

comptime {
    @setEvalBranchQuota(1_000_000);
    const mirrored_source =
        \\fn queueQuery(eff: anytype) !void {
        \\    try eff.writer.tell("query=artifact-search");
        \\}
        \\
        \\fn advanceState(eff: anytype) !void {
        \\    const before = try eff.state.get();
        \\    try eff.state.set(before + 1);
        \\    try queueQuery(eff);
        \\}
        \\
        \\pub fn runBody(eff: anytype) ![]const u8 {
        \\    try advanceState(eff);
        \\    try eff.writer.tell("workflow=queued");
        \\    return "done";
        \\}
    ;
    const caller_path = "/tmp/downstream_public_lowering_test.zig";
    const repo_path = "/tmp/other_downstream_public_lowering_test.zig";
    _ = shift_compile.lower(.{
        .repo_path = repo_path,
        .caller_file = caller_path,
        .caller_hash = std.hash.Wyhash.hash(0, mirrored_source),
        .caller_source = mirrored_source,
    }, .{
        .label = "compile_fail.source_ownership_absolute_content_mirror",
        .entry_symbol = "runBody",
        .row = shift_compile.ir.rowFromSpec(.{
            .state = .{
                .get = shift_compile.ir.Transform(void, i32),
                .set = shift_compile.ir.Transform(i32, void),
            },
            .writer = .{
                .tell = shift_compile.ir.Transform([]const u8, void),
            },
        }),
        .outputs = &.{
            .{ .label = "state", .OutputType = i32 },
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    });
}
