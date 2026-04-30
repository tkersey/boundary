const ability = @import("ability");
const ability_compile = @import("ability_compile");
const std = @import("std");

const source =
    \\pub fn body(eff: anytype) anyerror!i32 {
    \\    _ = try eff.picker.pick.perform(1);
    \\    return try eff.picker.pick.perform(2, struct {
    \\        pub fn apply(value: i32, _: anytype) anyerror!i32 {
    \\            return value;
    \\        }
    \\    });
    \\}
;

test "mixed same-function direct and explicit-continuation op use fails closed" {
    const current_src = @src();
    const caller: std.builtin.SourceLocation = .{
        .module = current_src.module,
        .file = "/tmp/ability-owned-open-row/mixed_same_function_after.zig",
        .line = 1,
        .column = 1,
        .fn_name = "mixedSameFunctionAfterNegative",
    };
    const ProgramType = ability_compile.lower(ability_compile.lowering_api.sourceWithContent(
        "/tmp/ability-owned-open-row/mixed_same_function_after.zig",
        caller,
        source,
    ), .{
        .label = "test.mixed_same_function_after",
        .entry_symbol = "body",
        .row = ability_compile.effect_ir.rowFromSpec(.{
            .picker = .{
                .pick = ability_compile.effect_ir.Transform(i32, i32),
            },
        }),
        .ValueType = i32,
    });

    const Handlers = struct {
        picker: struct {
            /// Return the raw payload so only after metadata controls replay.
            pub fn pick(_: *@This(), payload: i32) i32 {
                return payload;
            }

            /// Transform resumed answers when a callsite legitimately carries after metadata.
            pub fn afterPick(_: *@This(), answer: i32) i32 {
                return answer + 100;
            }
        } = .{},
    };

    try ProgramType.validate(std.testing.allocator);
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var handlers: Handlers = .{};
    _ = try ProgramType.run(&runtime, &handlers);
}
