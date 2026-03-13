const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const ApprovalPrompt = shift.Prompt(.resume_then_transform, []const u8, []const u8, NoError);
const AuditPrompt = shift.Prompt(.resume_then_transform, void, void, NoError);

pub fn run(writer: anytype) anyerror!void {
    const demo = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var approval_prompt_ptr: ?*const ApprovalPrompt = null;
        var audit_prompt_ptr: ?*const AuditPrompt = null;
        var transcript = [_][]const u8{ "", "", "", "", "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        const approval_handle = struct {
            pub fn resumeValue() bool {
                note("approval=publish");
                return true;
            }

            pub fn afterResume(value: []const u8) []const u8 {
                return value;
            }
        };

        const audit_handle = struct {
            pub fn resumeValue() void {
                note("audit=entered");
            }

            pub fn afterResume(_: void) void {
                // Intentionally empty: the resumed audit body owns completion.
            }
        };

        fn auditBody() shift.ResetError(NoError)!void {
            _ = try shift.shift(void, audit_prompt_ptr.?, audit_handle);
            note("audit=after");
            _ = try shift.shift(bool, approval_prompt_ptr.?, approval_handle);
        }

        fn body() shift.ResetError(NoError)![]const u8 {
            note("workflow=queued");
            try shift.reset(runtime_ptr.?, audit_prompt_ptr.?, auditBody);
            note("workflow=done");
            return "result=completed";
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var approval_prompt = ApprovalPrompt.init();
    var audit_prompt = AuditPrompt.init();
    demo.runtime_ptr = &runtime;
    demo.approval_prompt_ptr = &approval_prompt;
    demo.audit_prompt_ptr = &audit_prompt;
    demo.transcript_len = 0;

    const answer = try shift.reset(&runtime, &approval_prompt, demo.body);
    for (demo.transcript[0..demo.transcript_len]) |line| try writer.print("{s}\n", .{line});
    try writer.print("{s}\n", .{answer});
}

/// Run the nested workflow example using only the public shift surface.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
