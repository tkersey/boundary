const ability = @import("ability");
const std = @import("std");

const increment_continuation = struct {
    /// Increment the resumed optional value through the public bound-program path.
    pub fn apply(current: i32) i32 {
        return current + 1;
    }
};

test "public optional bound program exposes and executes compiled plan" {
    const OptionalInstance = ability.effect.optional.Instance(i32, error{});
    const policy = struct {
        /// Resume the public optional request with a known test value.
        pub fn resumeOrReturn() ability.effect.choice.Decision(i32, []const u8) {
            return ability.effect.choice.Decision(i32, []const u8).resumeWith(41);
        }

        /// Convert the resumed continuation answer into the enclosing result.
        pub fn afterResume(value: i32) []const u8 {
            if (value != 42) unreachable;
            return "answer=42";
        }
    };
    const demo = struct {
        /// Build the public optional request as a compiled bound program.
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(ability.effect.optional.requestBoundProgram(Cap, ctx, increment_continuation)) {
            const ProgramType = @TypeOf(ability.effect.optional.requestBoundProgram(Cap, ctx, increment_continuation));
            comptime {
                if (!ProgramType.has_compiled_plan) @compileError("public optional bound program must expose a compiled plan");
                const compiled_plan = ProgramType.compiledPlan().?;
                if (compiled_plan.functions[compiled_plan.entry_index].value_codec != .i32) {
                    @compileError("public optional bound program must preserve the resume codec");
                }
                if (compiled_plan.functions[compiled_plan.entry_index].result_codec.? != .string) {
                    @compileError("public optional bound program must preserve the answer codec");
                }
            }
            return ability.effect.optional.requestBoundProgram(Cap, ctx, increment_continuation);
        }
    };

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = OptionalInstance.init();

    const result = try ability.effect.optional.handle([]const u8, &runtime, &instance, policy, demo);
    try std.testing.expectEqualStrings("answer=42", result);
}
