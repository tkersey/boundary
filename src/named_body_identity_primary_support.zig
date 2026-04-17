/// Advance the named-body identity primary support witness through one state step.
pub fn namedBodyIdentity(eff: anytype) anyerror!i32 {
    const before = try eff.state.get();
    try eff.state.set(before + 1);
    return try eff.state.get();
}
