const std = @import("std");

pub const Error = error{
    AlreadyResolved,
    CrossThread,
    OutOfMemory,
    OwnerAliased,
    PromptAliased,
    ResumeMismatch,
    RuntimeBusy,
    RuntimeDestroyed,
};

pub const SetupError = error{};

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    thread_id: std.Thread.Id,
    owner_cookie: usize = 0,
    state: enum {
        alive,
        destroyed,
    } = .alive,
    active_owner_count: usize = 0,
    retired_owner_states: ?*RetiredOwnerNode = null,

    pub const Options = struct {};

    pub fn init(allocator: std.mem.Allocator, options: Options) Runtime {
        _ = options;
        return .{
            .allocator = allocator,
            .thread_id = std.Thread.getCurrentId(),
        };
    }

    pub fn deinit(self: *Runtime) void {
        self.deinitChecked() catch |err| switch (err) {
            error.CrossThread, error.RuntimeBusy => unreachable,
            else => unreachable,
        };
    }

    pub fn deinitChecked(self: *Runtime) Error!void {
        try self.ensureThread();
        if (self.state == .destroyed) return error.RuntimeDestroyed;
        if (self.active_owner_count != 0) return error.RuntimeBusy;
        var node = self.retired_owner_states;
        while (node) |current| {
            const next = current.next;
            current.deinitFn(current.ptr, self.allocator);
            self.allocator.destroy(current);
            node = next;
        }
        self.retired_owner_states = null;
        self.state = .destroyed;
    }

    fn ensureThread(self: *Runtime) Error!void {
        if (self.thread_id != std.Thread.getCurrentId()) return error.CrossThread;
        if (self.owner_cookie == 0) {
            self.owner_cookie = @intFromPtr(self);
        } else if (self.owner_cookie != @intFromPtr(self)) {
            return error.RuntimeBusy;
        }
        if (self.state == .destroyed) return error.RuntimeDestroyed;
    }
};

const RetiredOwnerNode = struct {
    next: ?*RetiredOwnerNode = null,
    ptr: *anyopaque,
    deinitFn: *const fn (*anyopaque, std.mem.Allocator) void,
};

pub fn Prompt(comptime RequestType: type, comptime ResumeType: type) type {
    return struct {
        marker: u8 = 0,
        owner_cookie: usize = 0,

        pub const Request = RequestType;
        pub const Resume = ResumeType;

        pub fn init() @This() {
            return .{};
        }
    };
}

pub fn Step(comptime _: type, comptime Suspend: type, comptime Answer: type) type {
    return union(enum) {
        complete: Answer,
        @"suspend": Suspend,
    };
}

pub fn Outcome(comptime Machine: type) type {
    return union(enum) {
        complete: Machine.Answer,
        pending: Pending(Machine),
    };
}

fn ResumeError(comptime Machine: type) type {
    return Error || Machine.Error;
}

fn StepOf(comptime Machine: type) type {
    return Step(Machine.Frame, Machine.Suspend, Machine.Answer);
}

fn OwnerState(comptime Machine: type) type {
    return struct {
        runtime: *Runtime,
        suspension: Machine.Suspend,
        generation: usize = 1,
        owner_cookie: usize = 0,
    };
}

fn retireOwnerState(comptime Machine: type, runtime: *Runtime, state: *OwnerState(Machine)) Error!void {
    const Node = RetiredOwnerNode;
    const node = runtime.allocator.create(Node) catch return error.OutOfMemory;
    node.* = .{
        .ptr = state,
        .deinitFn = struct {
            fn run(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                const typed: *OwnerState(Machine) = @ptrCast(@alignCast(ptr));
                allocator.destroy(typed);
            }
        }.run,
        .next = runtime.retired_owner_states,
    };
    runtime.retired_owner_states = node;
}

fn validatePrompt(prompt: anytype) Error!void {
    const PromptType = @TypeOf(prompt.*);
    if (!@hasField(PromptType, "marker") or !@hasField(PromptType, "owner_cookie")) {
        @compileError(@typeName(PromptType) ++ " must be a shift.Prompt handle");
    }
    if (prompt.owner_cookie == 0) {
        prompt.owner_cookie = @intFromPtr(prompt);
    } else if (prompt.owner_cookie != @intFromPtr(prompt)) {
        return error.PromptAliased;
    }
}

fn validateSuspendPayload(comptime Payload: type, comptime Frame: type) void {
    switch (@typeInfo(Payload)) {
        .@"struct" => {
            if (!@hasField(Payload, "prompt")) @compileError(@typeName(Payload) ++ " must have a prompt field");
            if (!@hasField(Payload, "request")) @compileError(@typeName(Payload) ++ " must have a request field");
            if (!@hasField(Payload, "next")) @compileError(@typeName(Payload) ++ " must have a next field");
            if (@FieldType(Payload, "next") != Frame) @compileError(@typeName(Payload) ++ ".next must be Machine.Frame");
        },
        else => @compileError("Suspend union payloads must be structs"),
    }
}

fn validateMachineContract(comptime Machine: type) void {
    if (!@hasDecl(Machine, "Answer")) @compileError(@typeName(Machine) ++ " must declare Answer");
    if (!@hasDecl(Machine, "Error")) @compileError(@typeName(Machine) ++ " must declare Error");
    if (!@hasDecl(Machine, "Frame")) @compileError(@typeName(Machine) ++ " must declare Frame");
    if (!@hasDecl(Machine, "Resume")) @compileError(@typeName(Machine) ++ " must declare Resume");
    if (!@hasDecl(Machine, "Suspend")) @compileError(@typeName(Machine) ++ " must declare Suspend");
    if (!@hasDecl(Machine, "step")) @compileError(@typeName(Machine) ++ " must declare step(frame, resume)");

    if (@typeInfo(Machine.Resume) != .@"union") @compileError("Machine.Resume must be a tagged union");
    if (@typeInfo(Machine.Suspend) != .@"union") @compileError("Machine.Suspend must be a tagged union");
    if (@typeInfo(Machine.Frame) != .@"union") @compileError("Machine.Frame must be a tagged union");

    if (!@hasField(Machine.Resume, "start")) @compileError("Machine.Resume must include a start field");

    inline for (@typeInfo(Machine.Suspend).@"union".fields) |field| {
        validateSuspendPayload(field.type, Machine.Frame);
        if (!@hasField(Machine.Resume, field.name)) {
            @compileError("Machine.Resume must include a matching '" ++ field.name ++ "' field");
        }
    }
}

fn validateSuspendPrompts(comptime Machine: type, suspension: Machine.Suspend) Error!void {
    if (@typeInfo(Machine.Suspend).@"union".fields.len == 0) return;
    switch (suspension) {
        inline else => |payload| try validatePrompt(payload.prompt),
    }
}

fn nextFrame(comptime Machine: type, suspension: Machine.Suspend) Machine.Frame {
    return switch (suspension) {
        inline else => |payload| payload.next,
    };
}

fn resumeMatches(comptime Machine: type, suspension: Machine.Suspend, resume_value: Machine.Resume) bool {
    const suspend_tag = std.meta.activeTag(suspension);
    const resume_tag = std.meta.activeTag(resume_value);
    return std.mem.eql(u8, @tagName(suspend_tag), @tagName(resume_tag));
}

fn stepMachine(
    comptime Machine: type,
    runtime: *Runtime,
    frame: Machine.Frame,
    resume_value: Machine.Resume,
) ResumeError(Machine)!Outcome(Machine) {
    try runtime.ensureThread();
    const step_result = try Machine.step(frame, resume_value);
    switch (step_result) {
        .complete => |answer| return .{ .complete = answer },
        .@"suspend" => |suspension| {
            try validateSuspendPrompts(Machine, suspension);
            const state = runtime.allocator.create(OwnerState(Machine)) catch return error.OutOfMemory;
            state.* = .{
                .runtime = runtime,
                .suspension = suspension,
            };
            runtime.active_owner_count += 1;
            return .{
                .pending = .{
                    .state = state,
                    .generation = state.generation,
                },
            };
        },
    }
}

pub fn Pending(comptime Machine: type) type {
    validateMachineContract(Machine);
    return struct {
        const Self = @This();

        state: ?*OwnerState(Machine),
        generation: usize,

        fn prepare(self: *Self) Error!*OwnerState(Machine) {
            const state = self.state orelse return error.AlreadyResolved;
            try state.runtime.ensureThread();
            if (state.generation != self.generation) return error.OwnerAliased;
            if (state.owner_cookie == 0) {
                state.owner_cookie = @intFromPtr(self);
            } else if (state.owner_cookie != @intFromPtr(self)) {
                return error.OwnerAliased;
            }
            self.state = null;
            return state;
        }

        pub fn @"suspend"(self: *const Self) Machine.Suspend {
            return self.state.?.suspension;
        }

        pub fn escape(self: *Self) Error!EscapedOwner(Machine) {
            const state = self.state orelse return error.AlreadyResolved;
            self.state = null;
            return .{
                .state = state,
                .generation = state.generation,
            };
        }

        pub fn @"resume"(self: *Self, resume_value: Machine.Resume) ResumeError(Machine)!Outcome(Machine) {
            const state = try self.prepare();
            defer {
                state.runtime.active_owner_count -= 1;
                state.owner_cookie = 0;
                state.generation += 1;
                retireOwnerState(Machine, state.runtime, state) catch {};
            }
            if (!resumeMatches(Machine, state.suspension, resume_value)) return error.ResumeMismatch;
            return try stepMachine(Machine, state.runtime, nextFrame(Machine, state.suspension), resume_value);
        }
    };
}

pub fn EscapedOwner(comptime Machine: type) type {
    validateMachineContract(Machine);
    return struct {
        const Self = @This();

        state: ?*OwnerState(Machine),
        generation: usize,

        fn prepare(self: *Self) Error!*OwnerState(Machine) {
            const state = self.state orelse return error.AlreadyResolved;
            try state.runtime.ensureThread();
            if (state.generation != self.generation) return error.OwnerAliased;
            if (state.owner_cookie == 0) {
                state.owner_cookie = @intFromPtr(self);
            } else if (state.owner_cookie != @intFromPtr(self)) {
                return error.OwnerAliased;
            }
            self.state = null;
            return state;
        }

        pub fn @"suspend"(self: *const Self) Machine.Suspend {
            return self.state.?.suspension;
        }

        pub fn @"resume"(self: *Self, resume_value: Machine.Resume) ResumeError(Machine)!Outcome(Machine) {
            const state = try self.prepare();
            defer {
                state.runtime.active_owner_count -= 1;
                state.owner_cookie = 0;
                state.generation += 1;
                retireOwnerState(Machine, state.runtime, state) catch {};
            }
            if (!resumeMatches(Machine, state.suspension, resume_value)) return error.ResumeMismatch;
            return try stepMachine(Machine, state.runtime, nextFrame(Machine, state.suspension), resume_value);
        }

        pub fn deinit(self: *Self) void {
            self.deinitChecked() catch |err| switch (err) {
                error.AlreadyResolved => return,
                error.CrossThread => unreachable,
                else => unreachable,
            };
        }

        pub fn deinitChecked(self: *Self) Error!void {
            const state = self.state orelse return error.AlreadyResolved;
            try state.runtime.ensureThread();
            self.state = null;
            state.runtime.active_owner_count -= 1;
            state.owner_cookie = 0;
            state.generation += 1;
            try retireOwnerState(Machine, state.runtime, state);
        }
    };
}

pub fn run(comptime Machine: type, runtime: *Runtime, initial: Machine.Frame) ResumeError(Machine)!Outcome(Machine) {
    validateMachineContract(Machine);
    return stepMachine(Machine, runtime, initial, .{ .start = {} });
}
