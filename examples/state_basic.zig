// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

const StateHandlers = struct { initial: i32 };
const StateBody = struct {
    pub fn program(runtime: *ability.Runtime, handlers: StateHandlers) anyerror!struct {
        pub const ability_result_envelope = true;
        value: i32,
        outputs: struct { state: i32 },
    } {
        var instance = ability.effect.state.Instance(i32, error{}).init();
        const result = try ability.effect.state.handle(i32, runtime, &instance, handlers.initial, struct {
            pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(ability.effect.state.computeProgram(Cap, ctx, struct {
                pub fn run(comptime RunCap: type, run_ctx: anytype) !i32 {
                    const before = try ability.effect.state.get(RunCap, run_ctx);
                    try ability.effect.state.set(RunCap, run_ctx, before + 1);
                    const after = try ability.effect.state.get(RunCap, run_ctx);
                    return before + after;
                }
            })) {
                return ability.effect.state.computeProgram(Cap, ctx, struct {
                    pub fn run(comptime RunCap: type, run_ctx: anytype) !i32 {
                        const before = try ability.effect.state.get(RunCap, run_ctx);
                        try ability.effect.state.set(RunCap, run_ctx, before + 1);
                        const after = try ability.effect.state.get(RunCap, run_ctx);
                        return before + after;
                    }
                });
            }
        });
        return .{
            .value = result.value,
            .outputs = .{ .state = result.state },
        };
    }
};

/// Write the state-effect transcript through an explicit reusable program.
pub fn run(writer: anytype) anyerror!void {
    var runtime = ability.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const Program = ability.program("state-basic", StateHandlers, StateBody);
    var result = try Program.run(&runtime, .{ .initial = 5 });
    defer result.deinit();

    try writer.print("before=5\nafter=6\nfinal_state={d}\nvalue={d}\n", .{ result.outputs.state, result.value });
}

/// Run the state-effect example.
pub fn main(init: std.process.Init) anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
