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

    try std.testing.expectEqual(@as(usize, 1), first.token);
    try std.testing.expectEqual(@as(usize, 2), second.token);
}

test "prompt token source keeps tokens distinct across concurrent allocation" {
    var source = portable_core.PromptTokenSource{};
    var seen = [_]bool{false} ** 257;
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

    for (tokens) |token| {
        try std.testing.expect(token >= 1 and token <= 256);
        try std.testing.expect(!seen[token]);
        seen[token] = true;
    }
    try std.testing.expectEqual(@as(usize, 257), source.next_token);
}
