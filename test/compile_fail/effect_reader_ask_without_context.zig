const shift = @import("shift");

const fake_cap = struct {};

comptime {
    _ = shift.effect.reader.ask(fake_cap, 123);
}
