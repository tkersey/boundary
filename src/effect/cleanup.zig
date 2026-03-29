const portable_core = @import("portable_core");

/// Type-erased cleanup frame used to unwind bracketed resource handles.
pub const Frame = portable_core.CleanupFrame;
/// Explicit cleanup stack owner.
pub const Stack = portable_core.CleanupStack;

/// Return the current cleanup stack marker.
pub fn checkpoint() ?*Frame {
    return portable_core.compatCleanupStack().checkpoint();
}

/// Push one cleanup frame onto the active unwind stack.
pub fn push(frame: *Frame) void {
    portable_core.compatCleanupStack().push(frame);
}

/// Unwind cleanup frames until `marker` becomes the active frame again.
pub fn unwindTo(marker: ?*Frame) anyerror!void {
    return portable_core.compatCleanupStack().unwindTo(marker);
}
