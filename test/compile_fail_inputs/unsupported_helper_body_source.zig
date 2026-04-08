fn helper() void {
    var keep_running = true;
    while (keep_running) {
        keep_running = false;
    }
}

/// Retained compile-fail entry used to prove unsupported helper bodies fail closed.
pub fn runBody() void {
    helper();
}
