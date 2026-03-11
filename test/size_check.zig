const shift = @import("shift");

fn expect(ok: bool) error{SizeCheckFailed}!void {
    if (!ok) return error.SizeCheckFailed;
}

pub fn main() error{SizeCheckFailed}!void {
    const InputPrompt = shift.Prompt(i32, i32);
    const VoidPrompt = shift.Prompt(void, void);

    const ValueMachine = struct {
        pub const Answer = i32;
        pub const Error = error{};
        pub const Frame = union(enum) { start: void };
        pub const Resume = union(enum) { start: void, input: i32 };
        pub const Suspend = union(enum) {
            input: struct {
                prompt: *InputPrompt,
                request: i32,
                next: Frame,
            },
        };
        pub fn step(frame: Frame, resume_value: Resume) (shift.Error || Error)!shift.Step(Frame, Suspend, Answer) {
            _ = frame;
            _ = resume_value;
            unreachable;
        }
    };

    const VoidMachine = struct {
        pub const Answer = void;
        pub const Error = error{};
        pub const Frame = union(enum) { start: void };
        pub const Resume = union(enum) { start: void, tick: void };
        pub const Suspend = union(enum) {
            tick: struct {
                prompt: *VoidPrompt,
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

    try expect(@sizeOf(shift.Pending(ValueMachine)) <= 2 * @sizeOf(usize));
    try expect(@sizeOf(shift.EscapedOwner(ValueMachine)) <= 2 * @sizeOf(usize));

    try expect(@hasDecl(shift.Pending(VoidMachine), "suspend"));
    try expect(@hasDecl(shift.Pending(VoidMachine), "resume"));
    try expect(@hasDecl(shift.Pending(VoidMachine), "escape"));
    try expect(!@hasDecl(shift.Pending(VoidMachine), "resumeWith"));
    try expect(!@hasDecl(shift.Pending(VoidMachine), "proceed"));

    try expect(@hasDecl(shift.EscapedOwner(ValueMachine), "suspend"));
    try expect(@hasDecl(shift.EscapedOwner(ValueMachine), "resume"));
    try expect(@hasDecl(shift.EscapedOwner(ValueMachine), "deinit"));
    try expect(!@hasDecl(shift.EscapedOwner(ValueMachine), "resumeWith"));
    try expect(!@hasDecl(shift.EscapedOwner(ValueMachine), "proceed"));
}
