comptime {
    const shift = @import("shift");
    const NoError = error{};
    const DemoPrompt = shift.Prompt(i32, []const u8, NoError);

    const capability_factory = struct {
        fn Make(comptime Marker: type) type {
            return struct {
                const _marker = Marker;
                continuation: *shift.Continuation(i32, DemoPrompt),
            };
        }
    };

    const GeneratedCapability = capability_factory.Make(struct {});
    const continuation: *shift.Continuation(i32, DemoPrompt) = @ptrFromInt(@alignOf(shift.Continuation(i32, DemoPrompt)));
    const capability = GeneratedCapability{ .continuation = continuation };
    const alias = capability;
    _ = alias;
}
