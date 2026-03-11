const shift = @import("shift");
const std = @import("std");

const AuditPrompt = shift.Prompt([]const u8, void);
const ApprovalPrompt = shift.Prompt([]const u8, bool);
const state = struct {
    var audit_prompt = AuditPrompt.init();
    var approval_prompt = ApprovalPrompt.init();
};

const Machine = struct {
    pub const Answer = []const u8;
    pub const Error = error{};
    pub const Frame = union(enum) {
        start: []const u8,
        after_audit: []const u8,
        after_approval: void,
    };
    pub const Resume = union(enum) {
        start: void,
        audit: void,
        approval: bool,
    };
    pub const Suspend = union(enum) {
        audit: struct {
            prompt: *AuditPrompt,
            request: []const u8,
            next: Frame,
        },
        approval: struct {
            prompt: *ApprovalPrompt,
            request: []const u8,
            next: Frame,
        },
    };

    pub fn step(frame: Frame, resume_value: Resume) (shift.Error || Error)!shift.Step(Frame, Suspend, Answer) {
        return switch (frame) {
            .start => |job| switch (resume_value) {
                .start => .{ .@"suspend" = .{
                    .audit = .{
                        .prompt = &state.audit_prompt,
                        .request = job,
                        .next = .{ .after_audit = job },
                    },
                } },
                else => unreachable,
            },
            .after_audit => |job| switch (resume_value) {
                .audit => .{ .@"suspend" = .{
                    .approval = .{
                        .prompt = &state.approval_prompt,
                        .request = job,
                        .next = .{ .after_approval = {} },
                    },
                } },
                else => unreachable,
            },
            .after_approval => switch (resume_value) {
                .approval => |approved| .{ .complete = if (approved) "completed" else "rejected" },
                else => unreachable,
            },
        };
    }
};

pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var outcome = try shift.run(Machine, &runtime, .{ .start = "publish" });
    while (true) switch (outcome) {
        .complete => |answer| {
            try stdout.print("result={s}\n", .{answer});
            break;
        },
        .pending => |*pending| {
            const suspension = pending.@"suspend"();
            switch (suspension) {
                .audit => |call| {
                    try stdout.print("audit={s}\n", .{call.request});
                    outcome = try pending.@"resume"(.{ .audit = {} });
                },
                .approval => |call| {
                    try stdout.print("approval={s}\n", .{call.request});
                    var escaped = try pending.escape();
                    outcome = try escaped.@"resume"(.{ .approval = true });
                },
            }
        },
    };

    try stdout.flush();
}
