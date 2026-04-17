const shift = @import("lexical_runtime_internal");

fn ExecResult(comptime T: type) type {
    return (shift.RuntimeError || error{ OutOfMemory, BodyOops, ContinueOops, HandlerOops, AfterOops })!T;
}

/// Return the canonical generated-choice answer through the named-body path.
pub fn namedGeneratedChoiceBody(eff: anytype) ExecResult([]const u8) {
    return try eff.picker.pick.perform(41, struct {
        /// Return the canonical resumed answer for this generated-choice test.
        pub fn apply(_: i32, _: anytype) ExecResult([]const u8) {
            return "answer=42";
        }
    });
}

/// Return the underscored generated-choice answer through the named-body path.
pub fn namedGeneratedChoiceUnderscoreBody(eff: anytype) ExecResult([]const u8) {
    return try eff.picker.pick_item.perform(41, struct {
        /// Return the canonical resumed answer for this underscored generated-choice test.
        pub fn apply(_: i32, _: anytype) ExecResult([]const u8) {
            return "answer=42";
        }
    });
}
