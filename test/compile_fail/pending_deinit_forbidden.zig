const shift = @import("shift");

const spec = struct {
    /// Prompt tag for the compile-fail probe.
    pub const tag = struct {};
    /// The probe emits no request payload.
    pub const Request = void;
    /// The probe accepts no resume payload.
    pub const Resume = void;
    /// The probe completes without a value.
    pub const Answer = void;
    /// The probe has no user-owned error surface.
    pub const ErrorSet = error{};
};

comptime {
    const Pending = shift.Pending(spec);
    _ = Pending.deinit;
}
