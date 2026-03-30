/// Enqueue one cross-file writer note through the imported helper.
pub fn queueQuery(eff: anytype) anyerror!void {
    const writer = eff.writer;
    try writer.tell("query=cross-file-artifact-search");
}

/// Advance state and enqueue one writer note through the imported helper chain.
pub fn advanceState(eff: anytype) anyerror!void {
    const state = eff.state;
    const before = try state.get();
    try state.set(before + 2);
    try queueQuery(eff);
}
