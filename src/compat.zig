const error_witness = @import("error_witness");
const lowered_machine = @import("lowered_machine");
const op_compat = @import("op_compat.zig");
const program_api = @import("program_api.zig");
const root_decl_api = @import("root_decl_api.zig");

/// Explicit compatibility namespace for the prior root-kernel front door.
pub const Runtime = lowered_machine.Runtime;
/// Public runtime misuse and semantic-contract errors surfaced by `shift`.
pub const RuntimeError = lowered_machine.RuntimeError;
/// Stable public error-witness schema.
pub const ErrorWitnessV1 = error_witness.ErrorWitnessV1;
/// Public declaration namespace.
pub const Decl = root_decl_api.Decl;
/// Public op-descriptor namespace.
pub const Op = op_compat.Op;
/// Root-level choice-decision helper for the front-door API.
pub const Decision = program_api.Decision;
/// Public program builder.
pub const Program = program_api.Program;

/// Run one program with explicit runtime ownership and bindings.
pub inline fn run(runtime: *Runtime, comptime ProgramType: type, bindings: ProgramType.Bindings) program_api.RunReturnType(ProgramType) {
    return program_api.runAt(@src(), runtime, ProgramType, bindings);
}

test {
    _ = Decl;
    _ = Decision;
    _ = ErrorWitnessV1;
    _ = Op;
    _ = Program;
    _ = Runtime;
    _ = RuntimeError;
    _ = run;
}

test "compat run preserves explicit caller program runner arity" {
    const demo_program = Program(.{
        .state = Decl.state(i32),
    }, struct {
        /// Read one state value through the compatibility front door.
        pub fn body(eff: anytype) anyerror!i32 {
            return try eff.state.get();
        }
    });

    var runtime = Runtime.init(@import("std").testing.allocator);
    defer runtime.deinit();

    const result = try run(&runtime, demo_program, .{ .state = 7 });
    try @import("std").testing.expectEqual(@as(i32, 7), result.outputs.state);
    try @import("std").testing.expectEqual(@as(i32, 7), result.value);
}
