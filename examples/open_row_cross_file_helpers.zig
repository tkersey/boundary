/// Mark the query helper as exercised by the cross-file writer example.
pub fn queueQuery(_: anytype) void {
    // Intentionally empty: the call itself is the witness.
}

/// Keep one supported cross-file helper body shape available to lowering.
pub fn advanceState() void {
    var keep_running = true;
    while (keep_running) {
        keep_running = false;
    }
}
