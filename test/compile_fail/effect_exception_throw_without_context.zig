const shift = @import("shift");

const fake_cap = struct {};

comptime {
    _ = shift.effect.exception.throw(fake_cap, 123, 1);
}
