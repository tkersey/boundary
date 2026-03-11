const shift = @import("shift");

const NoError = error{};
const DemoPrompt = shift.Prompt(void, void, NoError);

comptime {
    _ = shift.Continuation(void, DemoPrompt).discontinue;
}
