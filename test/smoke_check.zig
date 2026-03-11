const shift = @import("shift");

fn expect(ok: bool) error{SmokeCheckFailed}!void {
    if (!ok) return error.SmokeCheckFailed;
}

pub fn main() error{SmokeCheckFailed}!void {
    try expect(shift.generated.basic_resume.basicResume() == 42);
    try expect(shift.generated.no_capture.noCapture(41) == 42);
    try expect(std.mem.eql(u8, shift.generated.workflow.workflow("publish"), "completed"));
}

const std = @import("std");
