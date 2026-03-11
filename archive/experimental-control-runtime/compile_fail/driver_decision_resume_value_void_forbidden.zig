const shift = @import("shift");

comptime {
    const decision: shift.driver.Decision(shift.Prompt(void, void, void, error{})) = .{ .resume_value = {} };
    _ = decision;
}
