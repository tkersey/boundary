/// Recurse through the retained imported-helper path while counting down shared state.
pub fn countdown(eff: anytype) anyerror!void {
    const remaining = try eff.state.get();
    if (remaining == 0) return;
    try eff.writer.tell("cross");
    try eff.state.set(remaining - 1);
    try countdown(eff);
}
