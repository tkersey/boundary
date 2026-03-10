const shift = @import("shift");
const std = @import("std");

test "pending and escaped-owner shells stay compact" {
    const demo_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = void;
        /// Resume value type.
        pub const Resume = void;
        /// Final answer type.
        pub const Answer = void;
        /// User error surface.
        pub const ErrorSet = error{};
    };
    try std.testing.expect(@sizeOf(shift.Pending(demo_spec)) <= 2 * @sizeOf(usize));
    try std.testing.expect(@sizeOf(shift.EscapedOwner(demo_spec)) <= 3 * @sizeOf(usize));
}

test "void resume specializations expose payloadless proceed helpers" {
    const void_resume_spec = struct {
        /// Prompt tag for the payloadless resume probe.
        pub const tag = struct {};
        /// The probe emits no request payload.
        pub const Request = void;
        /// The probe accepts no resume payload.
        pub const Resume = void;
        /// The probe completes without a value.
        pub const Answer = void;
        /// The probe has no user-owned error surface.
        pub const ErrorSet = error{};
    };

    try std.testing.expect(@hasDecl(shift.Pending(void_resume_spec), "proceed"));
    try std.testing.expect(!@hasDecl(shift.Pending(void_resume_spec), "resumeWith"));
    try std.testing.expect(@hasDecl(shift.EscapedOwner(void_resume_spec), "proceed"));
    try std.testing.expect(!@hasDecl(shift.EscapedOwner(void_resume_spec), "resumeWith"));
}

test "value-carrying resume specializations omit payloadless proceed helpers" {
    const value_resume_spec = struct {
        /// Prompt tag for the value-carrying resume probe.
        pub const tag = struct {};
        /// The probe emits no request payload.
        pub const Request = void;
        /// The probe accepts an integer resume payload.
        pub const Resume = i32;
        /// The probe completes without a value.
        pub const Answer = void;
        /// The probe has no user-owned error surface.
        pub const ErrorSet = error{};
    };

    try std.testing.expect(!@hasDecl(shift.Pending(value_resume_spec), "proceed"));
    try std.testing.expect(@hasDecl(shift.Pending(value_resume_spec), "resumeWith"));
    try std.testing.expect(!@hasDecl(shift.EscapedOwner(value_resume_spec), "proceed"));
    try std.testing.expect(@hasDecl(shift.EscapedOwner(value_resume_spec), "resumeWith"));
}

test "runtime defaults stay explicit" {
    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    try std.testing.expectEqual(@as(usize, 256 * 1024), runtime.options.stack_bytes);
    try std.testing.expectEqual(@as(usize, 1), runtime.options.guard_pages);
}

test "pending and escaped owners keep discontinue for anyerror" {
    const anyerror_spec = struct {
        /// Prompt tag for the anyerror surface probe.
        pub const tag = struct {};
        /// The probe emits no request payload.
        pub const Request = void;
        /// The probe accepts no resume payload.
        pub const Resume = void;
        /// The probe completes without a value.
        pub const Answer = void;
        /// The probe uses the open anyerror surface.
        pub const ErrorSet = anyerror;
    };

    try std.testing.expect(@hasDecl(shift.Pending(anyerror_spec), "discontinue"));
    try std.testing.expect(@hasDecl(shift.EscapedOwner(anyerror_spec), "discontinue"));
}
