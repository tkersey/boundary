const with_api = @import("with_api");

comptime {
    const Writer = struct {
        finished: bool = false,
        /// Closed handler output type used by this const-safety regression.
        pub const Output = bool;

        /// Mutating finish must not accept a const handler bundle field.
        pub fn finish(self: *@This()) bool {
            self.finished = true;
            return self.finished;
        }
    };
    const Handlers = struct {
        writer: Writer,
    };
    const handlers: Handlers = .{
        .writer = .{},
    };

    _ = with_api.collectClosedOutputs(&handlers);
}
