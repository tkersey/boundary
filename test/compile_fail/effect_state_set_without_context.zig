const shift = @import("shift");

const fake_cap = struct {};

comptime {
    _ = shift.effect.state.set(fake_cap, 123, 1);
}
