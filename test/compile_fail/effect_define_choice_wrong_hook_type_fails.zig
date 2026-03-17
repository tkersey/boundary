const prompt_support = @import("prompt_support");
const shift = @import("shift");
const shift_internal = @import("shift_internal");
const std = @import("std");

const NoError = error{};
const Picker = shift.effect.Define(.{
    .mode = prompt_support.PromptMode.resume_or_return,
    .state_type = i32,
    .error_set_type = NoError,
    .ops = .{
        shift.effect.ops.Choice("pick", void, i32),
    },
});

const bad_handler = struct {
    /// Deliberately return the wrong type for one generated choice op.
    pub fn pick(_: *@This()) i32 {
        return 41;
    }

    /// Preserve the enclosing answer unchanged.
    pub fn afterPick(_: *@This(), answer: []const u8) []const u8 {
        return answer;
    }
};

/// Trigger the generated-family wrong-choice-hook-type compile failure.
pub fn main() anyerror!void {
    var runtime = shift_internal.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    var instance = Picker.Instance.init();
    _ = try Picker.handle([]const u8, &runtime, &instance, bad_handler{}, struct {
        /// Attempt to build one generated choice program with an invalid handler bundle.
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(Picker.Op(.pick).program(Cap, ctx, struct {
            /// Produce one late answer for the invalid generated choice handler.
            pub fn apply(_: i32) []const u8 {
                return "late";
            }
        })) {
            return Picker.Op(.pick).program(Cap, ctx, struct {
                /// Produce one late answer for the invalid generated choice handler.
                pub fn apply(_: i32) []const u8 {
                    return "late";
                }
            });
        }
    });
}
