const portable_core = @import("portable_core");
const prompt_support = @import("prompt_support");
const std = @import("std");

test "prompt initWithToken preserves the supplied token" {
    const NoError = error{};
    const DemoPrompt = prompt_support.Prompt(.resume_then_transform, void, void, NoError);
    const prompt = DemoPrompt.initWithToken(41);
    try std.testing.expectEqual(@as(usize, 41), prompt.token);
}

test "prompt initWithSource draws distinct tokens from the supplied source" {
    const NoError = error{};
    const DemoPrompt = prompt_support.Prompt(.resume_then_transform, void, void, NoError);
    var source = portable_core.PromptTokenSource{};

    const first = DemoPrompt.initWithSource(&source);
    const second = DemoPrompt.initWithSource(&source);

    try std.testing.expect(first.token != second.token);
    try std.testing.expect(source.next_token == 3);
}

test "prompt initWithSource keeps tokens distinct across independent sources" {
    const NoError = error{};
    const DemoPrompt = prompt_support.Prompt(.resume_then_transform, void, void, NoError);
    var first_source = portable_core.PromptTokenSource{};
    var second_source = portable_core.PromptTokenSource{};

    const first = DemoPrompt.initWithSource(&first_source);
    const second = DemoPrompt.initWithSource(&second_source);

    try std.testing.expect(first.token != second.token);
}

test "prompt token source keeps tokens distinct across concurrent allocation" {
    var source = portable_core.PromptTokenSource{};
    var tokens = [_]usize{0} ** 256;
    var threads: [8]std.Thread = undefined;

    const worker = struct {
        fn run(shared: *portable_core.PromptTokenSource, out: []usize) void {
            for (out) |*slot| {
                slot.* = shared.allocate();
                std.Thread.yield() catch {};
            }
        }
    };

    for (&threads, 0..) |*thread, index| {
        const start = index * 32;
        thread.* = try std.Thread.spawn(.{}, worker.run, .{ &source, tokens[start .. start + 32] });
    }
    for (&threads) |thread| thread.join();

    var seen = std.AutoHashMap(usize, void).init(std.testing.allocator);
    defer seen.deinit();
    for (tokens) |token| {
        const entry = try seen.getOrPut(token);
        try std.testing.expect(!entry.found_existing);
    }
    try std.testing.expectEqual(@as(usize, 257), source.next_token);
}
