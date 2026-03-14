const shift = @import("shift");

const fake_cap = struct {};

comptime {
    _ = shift.effect.state.get(fake_cap, 123);
}
