const shift = @import("shift");

const Prompt = shift.Prompt(void, void);

const Machine = struct {
    pub const Answer = void;
    pub const Error = error{};
    pub const Frame = union(enum) { start: void };
    pub const Resume = union(enum) { start: void, tick: void };
    pub const Suspend = union(enum) {
        tick: struct {
            prompt: *Prompt,
            request: void,
            next: Frame,
        },
    };
    pub fn step(frame: Frame, resume_value: Resume) (shift.Error || Error)!shift.Step(Frame, Suspend, Answer) {
        _ = frame;
        _ = resume_value;
        unreachable;
    }
};

comptime {
    const Pending = shift.Pending(Machine);
    _ = Pending.discontinue;
}
