const shift = @import("shift");

const fake_cap = struct {};

comptime {
    _ = shift.effect.resource.acquire(fake_cap, 123);
}
