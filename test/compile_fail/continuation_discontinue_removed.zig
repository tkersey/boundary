const shift = @import("shift");

const tag = struct {};
const NoError = error{};

comptime {
    _ = shift.Continuation(void, tag, void, NoError).discontinue;
}
