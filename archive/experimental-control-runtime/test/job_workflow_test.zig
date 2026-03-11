const job_workflow = @import("job_workflow");
const shift = @import("shift");
const std = @import("std");

test "approved scenario completes with nested audit trace" {
    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const result = try job_workflow.runScenario(&runtime, .approved, &writer);

    try std.testing.expectEqual(job_workflow.ScenarioResult.completed, result);
    try std.testing.expectEqualStrings(
        "log=queued ingest\n" ++
            "log=critical metadata prepared\n" ++
            "log=nested audit started\n" ++
            "approval=ingest\n" ++
            "log=nested audit finished\n" ++
            "result=completed\n",
        writer.buffered(),
    );
}

test "rejected scenario recovers after discontinue" {
    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const result = try job_workflow.runScenario(&runtime, .rejected, &writer);

    try std.testing.expectEqual(job_workflow.ScenarioResult.recovered, result);
    try std.testing.expectEqualStrings(
        "log=queued publish\n" ++
            "log=critical metadata prepared\n" ++
            "approval=publish\n" ++
            "log=recovered publish skipped\n" ++
            "result=recovered\n",
        writer.buffered(),
    );
}

test "cancelled scenario returns terminal cancellation" {
    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const result = try job_workflow.runScenario(&runtime, .cancelled, &writer);

    try std.testing.expectEqual(job_workflow.ScenarioResult.cancelled, result);
    try std.testing.expectEqualStrings(
        "log=queued cleanup\n" ++
            "log=critical metadata prepared\n" ++
            "approval=cleanup\n" ++
            "result=cancelled\n",
        writer.buffered(),
    );
}

test "showcase output stays stable" {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try job_workflow.runShowcase(&writer);

    try std.testing.expectEqualStrings(
        "scenario=approved\n" ++
            "log=queued ingest\n" ++
            "log=critical metadata prepared\n" ++
            "log=nested audit started\n" ++
            "approval=ingest\n" ++
            "log=nested audit finished\n" ++
            "result=completed\n" ++
            "\n" ++
            "scenario=rejected\n" ++
            "log=queued publish\n" ++
            "log=critical metadata prepared\n" ++
            "approval=publish\n" ++
            "log=recovered publish skipped\n" ++
            "result=recovered\n" ++
            "\n" ++
            "scenario=cancelled\n" ++
            "log=queued cleanup\n" ++
            "log=critical metadata prepared\n" ++
            "approval=cleanup\n" ++
            "result=cancelled\n",
        writer.buffered(),
    );
}

test "guarded suspension is rejected" {
    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    try std.testing.expectError(error.ShiftForbidden, job_workflow.proveGuardRejectsSuspend(&runtime));
}

test "writer failure still drains the runtime" {
    var runtime = shift.Runtime.init(std.testing.allocator, .{});

    var buffer: [8]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);

    try std.testing.expectError(error.WriteFailed, job_workflow.runScenario(&runtime, .approved, &writer));
    try runtime.deinitChecked();
}
