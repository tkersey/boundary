pub fn runHelper(writer: anytype) anyerror!i32 {
    try writer.writeAll("helper=enter\n");
    const resumed: i32 = 41;
    try writer.print("resume={d}\n", .{resumed});
    try writer.writeAll("helper=exit\n");
    return resumed + 1;
}
