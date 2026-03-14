const shift = @import("shift");

const fake_cap = struct {};

comptime {
    _ = shift.effect.optional.request(fake_cap, 123);
}
