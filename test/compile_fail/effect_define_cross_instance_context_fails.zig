const prompt_support = @import("prompt_support");
const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const Counter = shift.effect.Define(.{
    .mode = prompt_support.PromptMode.resume_then_transform,
    .state_type = i32,
    .error_set_type = NoError,
    .ops = .{
        shift.effect.ops.Transform("get", void, i32),
    },
});

const Handler = struct {
    state: i32,

    /// Read the generated state cell once.
    pub fn get(self: *@This()) i32 {
        return self.state;
    }

    /// Preserve the enclosing answer after a generated read.
    pub fn afterGet(_: *@This(), answer: i32) i32 {
        return answer;
    }
};

const demo = struct {
    var runtime_ptr: ?*shift.Runtime = null;
    var inner_ptr: ?*const Counter.Instance = null;

    /// Open a nested generated-family handle and intentionally reuse the outer capability.
    pub fn outer(comptime OuterCap: type, _: anytype) shift.ResetError(NoError)!i32 {
        const result = try Counter.handle(i32, runtime_ptr.?, inner_ptr.?, Handler{ .state = 0 }, struct {
            /// Attempt to call the generated family with the wrong capability.
            pub fn program(comptime InnerCap: type, inner_ctx: anytype) @TypeOf(Counter.computeProgram(InnerCap, inner_ctx, struct {
                /// Attempt to read generated state through the wrong capability.
                pub fn run(_: type, program_ctx: anytype) shift.ResetError(NoError)!i32 {
                    return try Counter.Op(.get).perform(OuterCap, program_ctx);
                }
            })) {
                return Counter.computeProgram(InnerCap, inner_ctx, struct {
                    /// Attempt to read generated state through the wrong capability.
                    pub fn run(_: type, program_ctx: anytype) shift.ResetError(NoError)!i32 {
                        return try Counter.Op(.get).perform(OuterCap, program_ctx);
                    }
                });
            }
        });
        return result.value;
    }
};

/// Trigger the generated-family cross-instance compile failure.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    var outer_instance = Counter.Instance.init();
    var inner_instance = Counter.Instance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    _ = try Counter.handle(i32, &runtime, &outer_instance, Handler{ .state = 0 }, struct {
        /// Re-enter the nested generated-family misuse probe.
        pub fn program(comptime OuterCap: type, ctx: anytype) @TypeOf(Counter.computeProgram(OuterCap, ctx, struct {
            /// Re-enter the nested generated-family misuse probe.
            pub fn run(_: type, _: anytype) shift.ResetError(NoError)!i32 {
                return try demo.outer(OuterCap, {});
            }
        })) {
            return Counter.computeProgram(OuterCap, ctx, struct {
                /// Re-enter the nested generated-family misuse probe.
                pub fn run(_: type, _: anytype) shift.ResetError(NoError)!i32 {
                    return try demo.outer(OuterCap, {});
                }
            });
        }
    });
}
