const shift = @import("../root.zig");

/// Build a specialized deep, one-shot family kernel for one state cell and answer type.
pub fn Family(comptime State: type, comptime Answer: type, comptime ErrorSet: type) type {
    const PromptType = shift.Prompt(.resume_then_transform, Answer, Answer, ErrorSet);
    return struct {
        /// Prompt type used internally for this specialized family.
        pub const Prompt = PromptType;
        /// Active family frame while one handled body is running.
        pub threadlocal var active_frame: ?*Frame = null;

        /// Internal family frame holding the prompt and current state cell.
        pub const Frame = struct {
            prompt: PromptType,
            state: State,
        };

        /// Internal family context that performs one comptime-specialized operation.
        pub const context = struct {
            /// Perform one family operation specialized by its comptime op tag.
            pub inline fn perform(self: *@This(), comptime Op: type, payload: Op.Payload) shift.ResetError(ErrorSet)!Op.Resume {
                _ = self;
                const handler = struct {
                    threadlocal var active_payload: ?Op.Payload = null;

                    /// Supply the operation result into the resumed body.
                    pub fn resumeValue() shift.ResetError(ErrorSet)!Op.Resume {
                        return try callResume(active_frame.?, active_payload.?);
                    }

                    /// Preserve the resumed answer unchanged for this family kernel.
                    pub fn afterResume(answer: Answer) Answer {
                        return answer;
                    }

                    inline fn callResume(frame: *Frame, payload_value: Op.Payload) shift.ResetError(ErrorSet)!Op.Resume {
                        const apply_fn = switch (@typeInfo(@TypeOf(Op.apply))) {
                            .@"fn" => |function| function,
                            else => @compileError("effect op apply must be a function"),
                        };
                        const ReturnType = apply_fn.return_type orelse @compileError("effect op apply must have an explicit return type");
                        if (ReturnType == Op.Resume) return Op.apply(frame, payload_value);
                        switch (@typeInfo(ReturnType)) {
                            .error_union => |error_union| {
                                if (error_union.error_set != shift.ResetError(ErrorSet) or error_union.payload != Op.Resume) {
                                    @compileError("effect op apply must return Resume or ResetError(ErrorSet)!Resume");
                                }
                                return try Op.apply(frame, payload_value);
                            },
                            else => @compileError("effect op apply must return Resume or ResetError(ErrorSet)!Resume"),
                        }
                    }
                };

                const previous_payload = handler.active_payload;
                handler.active_payload = payload;
                defer {
                    handler.active_payload = previous_payload;
                }

                return try shift.shift(Op.Resume, &active_frame.?.prompt, handler);
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
