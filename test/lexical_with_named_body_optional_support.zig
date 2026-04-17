const shift = @import("lexical_runtime_internal");

fn ExecResult(comptime T: type) type {
    return (shift.RuntimeError || error{ OutOfMemory, BodyOops, ContinueOops, HandlerOops, AfterOops })!T;
}

/// Trigger the optional return-now branch through the named-body path.
pub fn namedOptionalReturnNowBody(eff: anytype) ExecResult([]const u8) {
    return try eff.optional.request(struct {
        /// This continuation stays unreachable in the return-now branch.
        pub fn apply(_: i32, _: anytype) ExecResult([]const u8) {
            return "unused";
        }
    });
}

/// Trigger the optional resumed-answer branch through the named-body path.
pub fn namedOptionalResumeBody(eff: anytype) ExecResult([]const u8) {
    return try eff.optional.request(struct {
        /// Return the canonical resumed answer for this named-body test.
        pub fn apply(_: i32, _: anytype) ExecResult([]const u8) {
            return "answer=42";
        }
    });
}

/// Return the resumed bool answer through the named-body path.
pub fn namedOptionalResumeBoolBody(eff: anytype) ExecResult(bool) {
    return try eff.optional.request(struct {
        /// Return the canonical resumed bool answer for this named-body test.
        pub fn apply(_: i32, _: anytype) ExecResult(bool) {
            return true;
        }
    });
}

/// Return the resumed usize answer through the named-body path.
pub fn namedOptionalResumeUsizeBody(eff: anytype) ExecResult(usize) {
    return try eff.optional.request(struct {
        /// Return the canonical resumed usize answer for this named-body test.
        pub fn apply(_: i32, _: anytype) ExecResult(usize) {
            return 1;
        }
    });
}

/// Return the resumed hexadecimal usize answer through the named-body path.
pub fn namedOptionalResumeHexUsizeBody(eff: anytype) ExecResult(usize) {
    return try eff.optional.request(struct {
        /// Return the canonical hexadecimal usize answer for this named-body test.
        pub fn apply(_: i32, _: anytype) ExecResult(usize) {
            return 0xff;
        }
    });
}

/// Return the resumed large usize answer through the named-body path.
pub fn namedOptionalResumeLargeUsizeBody(eff: anytype) ExecResult(usize) {
    return try eff.optional.request(struct {
        /// Return the canonical resumed large usize answer for this named-body test.
        pub fn apply(_: i32, _: anytype) ExecResult(usize) {
            return 5_000_000_000;
        }
    });
}
