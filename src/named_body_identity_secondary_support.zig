/// Advance the named-body identity secondary support witness through one state step.
pub fn witnessOverride(eff: anytype) anyerror!i32 {
    const before = try eff.state.get();
    try eff.state.set(before + 20);
    return try eff.state.get();
}
