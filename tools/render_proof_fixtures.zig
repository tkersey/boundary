const parity_scenarios = @import("parity_scenarios");
const std = @import("std");

fn fixtureDir() []const u8 {
    return "test/example_proof/fixtures";
}

fn usage() noreturn {
    std.debug.print("usage: shift-proof-fixture-render <write|check>\n", .{});
    std.process.exit(1);
}

fn fixturePath(allocator: std.mem.Allocator, fixture_name: []const u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ fixtureDir(), fixture_name });
}

fn checkFixture(allocator: std.mem.Allocator, fixture_name: []const u8, expected: []const u8) !void {
    const path = try fixturePath(allocator, fixture_name);
    defer allocator.free(path);

    const actual = try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
    defer allocator.free(actual);

    if (!std.mem.eql(u8, actual, expected)) {
        std.debug.print("fixture drift: {s}\n", .{fixture_name});
        return error.FixtureDrift;
    }
}

fn writeFixture(fixture_name: []const u8, expected: []const u8) !void {
    var dir = try std.fs.cwd().openDir(fixtureDir(), .{});
    defer dir.close();
    try dir.writeFile(.{
        .sub_path = fixture_name,
        .data = expected,
    });
}

/// Render or check generator-owned proof fixtures from the canonical scenario registry.
pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    if (args.len != 2) usage();
    const mode = args[1];

    if (!std.mem.eql(u8, mode, "check") and !std.mem.eql(u8, mode, "write")) usage();

    for (parity_scenarios.scenarios) |scenario| {
        const fixture_name = scenario.fixture_name orelse continue;
        if (std.mem.eql(u8, mode, "check")) {
            try checkFixture(allocator, fixture_name, scenario.expected_transcript);
        } else {
            try writeFixture(fixture_name, scenario.expected_transcript);
        }
    }
}
