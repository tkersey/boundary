const shift = @import("shift");

fn expect(ok: bool) error{SizeCheckFailed}!void {
    if (!ok) return error.SizeCheckFailed;
}

pub fn main() error{SizeCheckFailed}!void {
    try expect(@hasDecl(shift, "compiler"));
    try expect(@hasDecl(shift, "generated"));
    try expect(@hasDecl(shift, "legacy"));
    try expect(!@hasDecl(shift, "Prompt"));
    try expect(!@hasDecl(shift, "Pending"));
    try expect(@TypeOf(shift.generated.basic_resume.basicResume()) == i32);
    try expect(@TypeOf(shift.generated.workflow.workflow("publish")) == []const u8);
}
