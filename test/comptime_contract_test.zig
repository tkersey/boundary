const ability = @import("ability");
const ability_compile = @import("ability_compile");
const fixture = @import("ability_agent_vm_fixture_spec.zig");
const std = @import("std");

const comptime_contract_body = struct {
    fn sourceLocation() std.builtin.SourceLocation {
        return @src();
    }

    /// Authoritative source bytes for this public source-backed body witness.
    pub const source = @embedFile("comptime_contract_test.zig");
    /// Comptime hash witness over the same source bytes.
    pub const source_hash = ability.sourceHash(source);
    /// File identity reported by the declaration that owns the source witness.
    pub const source_file = "comptime_contract_test.zig";
    /// Compiler-owned location witness for this declaration.
    pub const source_location = sourceLocation();
    /// Stable named-body identity selected from `source`.
    pub const source_identity = "comptime_contract_test.comptime_contract_body";

    /// Body used to prove source-backed public lexical execution remains compiled.
    pub fn body(eff: anytype) anyerror!i32 {
        const before = try eff.state.get();
        try eff.state.set(before + 2);
        return try eff.state.get();
    }
};

const CompiledFixture = ability_compile.CompileSource(
    fixture.source_path,
    fixture.FixtureSpec,
    .{ .stable_build_fingerprint_seed = "ability-comptime-contract-fixture-v1" },
);

test "public ability.with source witness exposes a comptime execution contract" {
    const Handlers = @TypeOf(.{
        .state = ability.effect.state.use(@as(i32, 7)),
    });
    const ReturnType = @TypeOf(ability.with(
        @as(*ability.Runtime, undefined),
        @as(Handlers, undefined),
        comptime_contract_body,
    ));
    comptime {
        const Result = switch (@typeInfo(ReturnType)) {
            .error_union => |err_union| err_union.payload,
            else => @compileError("ability.with must keep an error-union execution contract"),
        };
        if (!@hasField(Result, "value")) @compileError("ability.with result must include value");
        if (!@hasField(Result, "outputs")) @compileError("ability.with result must include outputs");
        if (comptime_contract_body.source_hash != ability.sourceHash(comptime_contract_body.source)) {
            @compileError("ability.with source-backed body hash witness must be comptime-stable");
        }
    }

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try ability.with(&runtime, .{
        .state = ability.effect.state.use(@as(i32, 7)),
    }, comptime_contract_body);

    try std.testing.expectEqual(@as(i32, 9), result.value);
    try std.testing.expectEqual(@as(i32, 9), result.outputs.state);
}

test "ability_compile CompileSource exposes the lowered runtime plan at comptime" {
    comptime {
        const plan = CompiledFixture.runtime_plan;
        if (!std.mem.eql(u8, plan.label, fixture.FixtureSpec.label)) @compileError("compiled fixture plan label drifted");
        if (plan.functions.len == 0) @compileError("compiled fixture plan must keep static function rows");
        if (plan.blocks.len == 0) @compileError("compiled fixture plan must keep static block rows");
        if (plan.terminators.len == 0) @compileError("compiled fixture plan must keep static terminator rows");
        if (plan.instructions.len == 0) @compileError("compiled fixture plan must keep static instruction rows");
        if (plan.functions[plan.entry_index].parameter_count != 0) {
            @compileError("compiled fixture public artifact entry cannot require runtime-supplied value parameters");
        }
    }

    const bytes = try CompiledFixture.encode(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    var decoded = try CompiledFixture.decode(std.testing.allocator, bytes);
    defer decoded.deinit(std.testing.allocator);

    var found_writer_capability = false;
    for (decoded.capabilities) |capability| {
        if (std.mem.eql(u8, capability.label, "generated/writer@v1")) {
            found_writer_capability = true;
        }
    }
    try std.testing.expect(found_writer_capability);
    try decoded.validate(std.testing.allocator);
}
