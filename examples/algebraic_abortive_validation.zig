const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const fail_validation = shift.algebraic.AbortOp("fail_validation", []const u8);
const validation_program = shift.algebraic.Program([]const u8, NoError, .{fail_validation});

const ValidationState = struct {
    lines: [4][]const u8 = [_][]const u8{""} ** 4,
    len: usize = 0,

    fn note(self: *ValidationState, line: []const u8) void {
        self.lines[self.len] = line;
        self.len += 1;
    }
};

var state = ValidationState{};

const fail_validation_handler = struct {
    /// Convert the abortive validation payload into the final result.
    pub fn directReturn(state_ptr: *ValidationState, payload: []const u8) []const u8 {
        state_ptr.note("abort=missing-name");
        return payload;
    }
};

const configured = validation_program.handlers(.{
    shift.algebraic.handleAbort(fail_validation, &state, fail_validation_handler),
});

const body = struct {
    /// Run the abortive validation witness body.
    pub fn body(ctx: *@TypeOf(configured).Context) shift.ResetError(NoError)![]const u8 {
        state.note("validate=name");
        try ctx.perform(fail_validation, "error=missing-name");
        return "ok";
    }
};

/// Write the exact-output abortive-validation transcript for this example.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    state = .{};
    const result = try configured.run(&runtime, body);

    var i: usize = 0;
    while (i < state.len) : (i += 1) {
        try writer.print("{s}\n", .{state.lines[i]});
    }
    try writer.print("final={s}\n", .{result});
}

/// Run the exact-output abortive-validation example.
pub fn main() anyerror!void {
    var stdout_writer = std.fs.File.stdout().writer(&.{});
    const stdout = &stdout_writer.interface;
    try run(stdout);
}
