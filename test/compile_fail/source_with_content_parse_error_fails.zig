const shift = @import("shift");
const std = @import("std");

comptime {
    @setEvalBranchQuota(1_000_000);
    const absolute_repo_path = "/tmp/source_with_content_parse_error_fails.zig";
    const malformed_source =
        \\pub fn runBody(eff: anytype) !void {
        \\    _ = try eff.state.get();
        \\}
        \\
        \\fn broken() void {
        \\    _ = ;
        \\}
    ;
    _ = shift.lower(.{
        .repo_path = absolute_repo_path,
        .caller_file = absolute_repo_path,
        .caller_hash = std.hash.Wyhash.hash(0, malformed_source),
        .caller_source = malformed_source,
    }, .{
        .label = "compile_fail.source_with_content_parse_error",
        .entry_symbol = "runBody",
        .row = shift.ir.rowFromSpec(.{
            .state = .{
                .get = shift.ir.Transform(void, i32),
            },
        }),
    });
}
