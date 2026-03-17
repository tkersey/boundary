const shift = @import("shift");
const std = @import("std");

const no_state = struct {};
const fail = shift.algebraic.AbortOp("fail", []const u8);
const Validation = shift.algebraic.Program([]const u8, .{fail});

/// Write the algebraic abortive-validation transcript through the public builder surface.
pub fn run(writer: anytype) anyerror!void {
    const transcript = struct {
        threadlocal var abort_line: []const u8 = "";
    };

    const abort_handler = struct {
        /// Validate one missing name and return the canonical algebraic abort answer.
        pub fn directReturn(_: no_state, payload: []const u8) []const u8 {
            transcript.abort_line = payload;
            return "error=missing-name";
        }
    };

    const configured = Validation.handlers(.{
        shift.algebraic.handleAbort(fail, no_state{}, abort_handler),
    });

    const body = struct {
        /// Trigger the algebraic abortive operation directly.
        pub fn program(ctx: *@TypeOf(configured).Context) @TypeOf(ctx.performProgram(fail, "missing-name", struct {
            /// This algebraic abort continuation must never run.
            pub fn apply(_: noreturn) []const u8 {
                unreachable;
            }
        })) {
            return ctx.performProgram(fail, "missing-name", struct {
                /// This algebraic abort continuation must never run.
                pub fn apply(_: noreturn) []const u8 {
                    unreachable;
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    transcript.abort_line = "";
    try writer.writeAll("validate=name\n");
    const result = try configured.run(&runtime, body);
    try writer.print("abort={s}\n", .{transcript.abort_line});
    try writer.print("final={s}\n", .{result});
}

/// Run the algebraic abortive-validation example.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
