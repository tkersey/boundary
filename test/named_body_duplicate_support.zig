const nested = struct {
    /// This same-stem nested helper must not participate in top-level NamedBody disambiguation.
    pub fn namedBodyValidationExpected(_: anytype) anyerror!i32 {
        return 99;
    }
};

comptime {
    _ = nested;
}
