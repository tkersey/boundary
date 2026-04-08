/// Return the caller-provided label through the imported helper ABI path.
pub fn classify(label: []const u8, _: i32, _: anytype) ![]const u8 {
    return label;
}
