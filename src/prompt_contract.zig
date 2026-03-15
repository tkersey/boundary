const std = @import("std");

/// Opaque prompt-identity token shared by canonical and compat prompt values.
pub const PromptToken = usize;

var prompt_token_mutex: std.Thread.Mutex = .{};
var next_prompt_token: PromptToken = 1;

fn allocatePromptToken() PromptToken {
    prompt_token_mutex.lock();
    defer prompt_token_mutex.unlock();
    const token = next_prompt_token;
    next_prompt_token += 1;
    return token;
}

/// Comptime-selected handler protocol attached to a prompt value.
pub const PromptMode = enum {
    direct_return,
    resume_or_return,
    resume_then_transform,
};

/// Handler decision for zero-or-one-resume prompt modes.
pub fn ResumeOrReturn(
    comptime ResumeType: type,
    comptime OutAnswerType: type,
) type {
    return union(enum) {
        resume_with: ResumeType,
        return_now: OutAnswerType,

        /// Complete the enclosing prompt without resuming the captured continuation.
        pub fn returnNow(value: OutAnswerType) @This() {
            return .{ .return_now = value };
        }

        /// Resume once with `value`, then let the handler's `afterResume` complete the enclosing answer.
        pub fn resumeWith(value: ResumeType) @This() {
            return .{ .resume_with = value };
        }
    };
}

/// First-class prompt value for one-shot `shift/reset`.
pub fn Prompt(
    comptime mode_type: PromptMode,
    comptime InAnswerType: type,
    comptime OutAnswerType: type,
    comptime ErrorSetType: type,
) type {
    return struct {
        /// Comptime-selected handler protocol for this prompt.
        pub const mode = mode_type;
        /// Answer type produced by the resumed subcontinuation.
        pub const InAnswer = InAnswerType;
        /// Enclosing answer type of the delimited computation.
        pub const OutAnswer = OutAnswerType;
        /// User error set carried through this prompt value.
        pub const ErrorSet = ErrorSetType;

        token: PromptToken,

        /// Create a fresh prompt value with distinct delimiter identity.
        pub fn init() @This() {
            return .{ .token = allocatePromptToken() };
        }
    };
}
