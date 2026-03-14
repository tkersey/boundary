const shift = @import("shift");

const fake_cap = struct {};

comptime {
    _ = shift.effect.writer.tell(fake_cap, 123, "bad");
}
