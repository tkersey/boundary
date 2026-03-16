const shift = @import("shift");
const std = @import("std");
const prompt_support = shift.internal;

const NoError = error{};
const ping = shift.algebraic.TransformOp("ping", void, i32);
const demo = shift.algebraic.Program(i32, NoError, .{ping});

const configured = demo.handlers(.{});

const body = struct {
    /// Provide the compile-fail missing-handler witness program.
    pub fn program(_: *@TypeOf(configured).Context) @TypeOf(prompt_support.frontend.pureProgram(prompt_support.Prompt(.resume_then_transform, i32, i32, NoError), 0)) {
        return prompt_support.frontend.pureProgram(prompt_support.Prompt(.resume_then_transform, i32, i32, NoError), 0);
    }
};

/// Trigger the compile-fail missing-handler witness.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    _ = try configured.run(&runtime, body);
}
