/// Stable ordinary-Zig case id.
pub const ordinary_case_id = "ordinary.typed_error_try";

const DemoError = error{Boom};

fn succeed() DemoError!i32 {
    return 42;
}

fn fail() DemoError!i32 {
    return error.Boom;
}

/// Run the typed-error case with ordinary Zig control flow.
pub fn run(writer: anytype) anyerror!void {
    try writer.writeAll("branch=ok\n");
    const value = try succeed();
    try writer.print("value={d}\n", .{value});

    try writer.writeAll("branch=err\n");
    _ = fail() catch |err| switch (err) {
        error.Boom => {
            try writer.writeAll("error=boom\n");
            try writer.writeAll("final=error=boom\n");
            return;
        },
    };
    unreachable;
}
