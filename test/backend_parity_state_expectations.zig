const parity_kernel = @import("parity_kernel");
const none = parity_kernel.Value{ .none = {} };

const atm_resume_transform = [_]parity_kernel.TraceCheckpoint{
    .{
        .tag = .atm_resume_prepared,
        .active_prompt = .primary,
        .pending_depth = 1,
        .top_pending_kind = .resume_then_transform,
        .top_pending_prompt = .primary,
        .top_resume_value = .{ .i32 = 41 },
        .final_result = none,
    },
    .{
        .tag = .atm_body_resumed,
        .active_prompt = .primary,
        .pending_depth = 1,
        .top_pending_kind = .resume_then_transform,
        .top_pending_prompt = .primary,
        .top_resume_value = .{ .i32 = 41 },
        .final_result = none,
    },
    .{
        .tag = .atm_terminal,
        .active_prompt = .primary,
        .pending_depth = 0,
        .top_pending_kind = null,
        .top_pending_prompt = null,
        .top_resume_value = none,
        .final_result = .{ .string = "answer=42" },
    },
};

const direct_return = [_]parity_kernel.TraceCheckpoint{
    .{
        .tag = .direct_return_handler,
        .active_prompt = .primary,
        .pending_depth = 1,
        .top_pending_kind = .direct_return,
        .top_pending_prompt = .primary,
        .top_resume_value = none,
        .final_result = none,
    },
    .{
        .tag = .direct_return_terminal,
        .active_prompt = .primary,
        .pending_depth = 0,
        .top_pending_kind = null,
        .top_pending_prompt = null,
        .top_resume_value = none,
        .final_result = .{ .string = "result=early" },
    },
};

const multi_prompt = [_]parity_kernel.TraceCheckpoint{
    .{
        .tag = .multi_prompt_outer_resume,
        .active_prompt = .outer,
        .pending_depth = 1,
        .top_pending_kind = .resume_then_transform,
        .top_pending_prompt = .outer,
        .top_resume_value = .{ .i32 = 41 },
        .final_result = none,
    },
    .{
        .tag = .multi_prompt_terminal,
        .active_prompt = .outer,
        .pending_depth = 0,
        .top_pending_kind = null,
        .top_pending_prompt = null,
        .top_resume_value = none,
        .final_result = .{ .i32 = 42 },
    },
};

const nested_workflow_publish = [_]parity_kernel.TraceCheckpoint{
    .{
        .tag = .nested_workflow_audit_entered,
        .active_prompt = .audit,
        .pending_depth = 1,
        .top_pending_kind = .resume_then_transform,
        .top_pending_prompt = .audit,
        .top_resume_value = none,
        .final_result = none,
    },
    .{
        .tag = .nested_workflow_audit_resumed,
        .active_prompt = .audit,
        .pending_depth = 0,
        .top_pending_kind = null,
        .top_pending_prompt = null,
        .top_resume_value = none,
        .final_result = none,
    },
    .{
        .tag = .nested_workflow_approval,
        .active_prompt = .approval,
        .pending_depth = 1,
        .top_pending_kind = .resume_then_transform,
        .top_pending_prompt = .approval,
        .top_resume_value = .{ .bool = true },
        .final_result = none,
    },
    .{
        .tag = .nested_workflow_terminal,
        .active_prompt = .approval,
        .pending_depth = 0,
        .top_pending_kind = null,
        .top_pending_prompt = null,
        .top_resume_value = none,
        .final_result = .{ .string = "result=completed" },
    },
};

const resume_or_return_resume = [_]parity_kernel.TraceCheckpoint{
    .{
        .tag = .resume_or_return_resume_choice,
        .active_prompt = .primary,
        .pending_depth = 1,
        .top_pending_kind = .resume_or_return,
        .top_pending_prompt = .primary,
        .top_resume_value = .{ .i32 = 41 },
        .final_result = none,
    },
    .{
        .tag = .ror_resume_body,
        .active_prompt = .primary,
        .pending_depth = 1,
        .top_pending_kind = .resume_or_return,
        .top_pending_prompt = .primary,
        .top_resume_value = .{ .i32 = 41 },
        .final_result = none,
    },
    .{
        .tag = .ror_resume_terminal,
        .active_prompt = .primary,
        .pending_depth = 0,
        .top_pending_kind = null,
        .top_pending_prompt = null,
        .top_resume_value = none,
        .final_result = .{ .string = "answer=42" },
    },
};

const resume_or_return_return_now = [_]parity_kernel.TraceCheckpoint{
    .{
        .tag = .ror_return_now_choice,
        .active_prompt = .primary,
        .pending_depth = 1,
        .top_pending_kind = .resume_or_return,
        .top_pending_prompt = .primary,
        .top_resume_value = none,
        .final_result = none,
    },
    .{
        .tag = .ror_return_now_terminal,
        .active_prompt = .primary,
        .pending_depth = 0,
        .top_pending_kind = null,
        .top_pending_prompt = null,
        .top_resume_value = none,
        .final_result = .{ .string = "result=early" },
    },
};

const static_redelim = [_]parity_kernel.TraceCheckpoint{
    .{
        .tag = .static_redelim_outer_resume,
        .active_prompt = .outer,
        .pending_depth = 1,
        .top_pending_kind = .resume_then_transform,
        .top_pending_prompt = .outer,
        .top_resume_value = .{ .i32 = 1 },
        .final_result = none,
    },
    .{
        .tag = .static_redelim_inner_resume,
        .active_prompt = .inner,
        .pending_depth = 2,
        .top_pending_kind = .resume_then_transform,
        .top_pending_prompt = .inner,
        .top_resume_value = .{ .i32 = 2 },
        .final_result = none,
    },
    .{
        .tag = .static_redelim_terminal,
        .active_prompt = .outer,
        .pending_depth = 0,
        .top_pending_kind = null,
        .top_pending_prompt = null,
        .top_resume_value = none,
        .final_result = .{ .i32 = 12 },
    },
};

/// Return the expected typed state trace for one migrated parity case.
pub fn expectedForId(id: []const u8) ?[]const parity_kernel.TraceCheckpoint {
    if (std.mem.eql(u8, id, "atm_resume_transform")) return &atm_resume_transform;
    if (std.mem.eql(u8, id, "direct_return")) return &direct_return;
    if (std.mem.eql(u8, id, "multi_prompt")) return &multi_prompt;
    if (std.mem.eql(u8, id, "nested_workflow_publish")) return &nested_workflow_publish;
    if (std.mem.eql(u8, id, "resume_or_return_resume")) return &resume_or_return_resume;
    if (std.mem.eql(u8, id, "resume_or_return_return_now")) return &resume_or_return_return_now;
    if (std.mem.eql(u8, id, "static_redelim")) return &static_redelim;
    return null;
}

const std = @import("std");
