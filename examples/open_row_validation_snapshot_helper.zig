/// Advance state through the retained straight-line helper subset used by snapshot-drift validation.
pub fn advanceState(eff: anytype) anyerror!void {
    const before = try eff.state.get();
    try eff.state.set(before + 2);
}
