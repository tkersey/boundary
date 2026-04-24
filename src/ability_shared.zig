const artifact_api = @import("artifact_api");
const builtin = @import("builtin");
const effect_root = @import("effect/root.zig");
const error_witness = @import("error_witness");
const interpreter_api = @import("interpreter");
const ir_api = @import("ir_api");
const lowered_machine = @import("lowered_machine");
const lowering_api = @import("lowering_api");
const with_api = @import("with_api.zig");

/// Shared ArtifactV1 codec and helpers used by the retained public roots.
pub const artifact = artifact_api;
/// Public effect family and handler constructors retained at the root surface.
pub const effect = effect_root;
/// Canonical lowered runtime retained at the root surface.
pub const Runtime = lowered_machine.Runtime;
/// Public runtime misuse and semantic-contract errors retained at the root surface.
pub const RuntimeError = lowered_machine.RuntimeError;
/// Public `With` helper retained at the root surface.
pub const With = with_api.With;
/// Lower-level `WithFnReturnType` helper retained for root wrappers.
pub const WithFnReturnType = with_api.WithFnReturnType;
/// Lower-level `with(...)` helper retained for sibling wrappers.
pub const with = with_api.with;
/// Explicit caller-owned `with(...)` helper retained for root wrappers.
pub const withCallerSource = with_api.withCallerSource;

/// Interpreter namespace retained for compatibility surfaces.
pub const interpreter = interpreter_api;
/// Public semantic-error witness surface.
pub const ErrorWitnessV1 = error_witness.ErrorWitnessV1;

/// Retained explicit IR compatibility surface shared by `ability` and `ability_compile`.
// zlinter-disable-next-line declaration_naming - retained public API contract is ability.ir
pub const ir = ir_api;
/// Public lowering namespace retained for shared build wiring.
pub const lowering = lowering_api;
/// Public lowering entrypoint retained for shared build wiring.
pub const lower = lowering_api.lower;
/// Internal lowered runtime surface re-exported for sibling wrapper modules.
pub const lowered_machine_internal = lowered_machine;
/// Internal program-plan surface re-exported for sibling wrapper modules.
pub const internal_program_plan = @import("internal_program_plan");
/// Test-only anonymous-body lowering helper for parity probes.
pub const debug_anonymous_body_synthesis = if (builtin.is_test) @import("internal/anonymous_body_synthesis.zig") else struct {};

test "lexical manifest adapter stays buildable under the shared harness" {
    const lexical_manifest = @import("internal/lexical_manifest.zig");
    const state = @import("effect/state.zig");
    const std = @import("std");

    const Handlers = struct {
        state: state.LexicalDescriptor(i32, error{}),
    };
    const manifest_shape = lexical_manifest.Manifest(Handlers);

    try std.testing.expectEqual(@as(usize, 1), manifest_shape.row().requirements.len);
}

test "anonymous body synthesis helper stays buildable under the shared harness" {
    const std = @import("std");
    const synthesis = @import("internal/anonymous_body_synthesis.zig");

    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = "/tmp/probe.zig",
        .line = 5,
        .column = 34,
        .fn_name = "probe",
    };
    const source =
        \\const ability = @import("ability");
        \\
        \\pub fn probe() !void {
        \\    _ = try ability.withOwnedSource(@src(), @embedFile(@src().file), .{}, undefined, .{}, struct {
        \\        pub fn body(eff: anytype) anyerror!void { _ = eff; }
        \\    });
        \\}
    ;
    const witness_body = struct {
        /// Keep this witness body explicit for the shared-harness proof.
        pub fn body(eff: anytype) anyerror!void {
            _ = eff;
        }
    };
    const synthetic = comptime synthesis.syntheticSourceWithEntry(
        caller,
        witness_body,
        source,
        .owned_source,
        "__ability_with_entry_l5_c34",
        null,
    ).?;

    try std.testing.expect(std.mem.containsAtLeast(u8, synthetic, 1, "pub fn __ability_with_entry_l5_c34"));
}
