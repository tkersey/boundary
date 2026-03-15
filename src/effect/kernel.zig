/// Build a specialized deep, one-shot family kernel for one state cell and answer type.
pub fn Family(comptime State: type, comptime Answer: type, comptime ErrorSet: type) type {
    _ = Answer;
    return struct {
        /// Active family frame while one handled body is running.
        pub threadlocal var active_frame: ?*Frame = null;

        /// Internal family frame holding the current state cell.
        pub const Frame = struct {
            state: State,
        };

        /// Internal family context placeholder retained for compatibility with older compiled call sites.
        pub const context = struct {
            /// The canonical surface no longer supports raw effect kernel perform-capture.
            pub inline fn perform(_: *@This(), comptime Op: type, _: Op.Payload) ErrorSet!Op.Resume {
                @compileError("effect kernel perform-capture is no longer part of the canonical runtime; use family-specific helpers");
            }
        };

        /// Final family state plus the resumed body answer.
        pub fn Result(comptime Value: type) type {
            return struct {
                state: State,
                value: Value,
            };
        }
    };
}
