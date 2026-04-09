/// Emit the cross-file query marker through the retained writer surface.
pub fn queueQuery(eff: anytype) anyerror!void {
    try eff.writer.tell("query=cross-file-artifact-search");
}

/// Advance state through the retained straight-line helper subset.
pub fn advanceState(eff: anytype) anyerror!void {
    const before = try eff.state.get();
    try eff.state.set(before + 2);
    try queueQuery(eff);
}
