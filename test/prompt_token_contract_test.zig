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
