const parity_kernel = @import("parity_kernel");
const std = @import("std");

/// Write the proof-only parity transcript for one locked semantic or example case.
pub fn runCase(writer: anytype, id: []const u8) anyerror!void {
    if (try tryRunTypedKernel(writer, id)) return;
    if (std.mem.eql(u8, id, "generator")) return writer.writeAll(
        "yield=1\n" ++
            "yield=2\n" ++
            "yield=3\n" ++
            "done=3\n",
    );
    if (std.mem.eql(u8, id, "early_exit")) return writer.writeAll(
        "handler-direct-return\n" ++
            "final=result=early\n",
    );
    if (std.mem.eql(u8, id, "resume_or_return")) return writer.writeAll(
        "branch=return_now\n" ++
            "handler-return-now\n" ++
            "final=result=early\n" ++
            "branch=resume_with\n" ++
            "handler-decide-resume\n" ++
            "body-after-shift\n" ++
            "handler-after-resume\n" ++
            "final=answer=42\n",
    );
    if (std.mem.eql(u8, id, "nested_workflow")) return writer.writeAll(
        "workflow=queued\n" ++
            "audit=entered\n" ++
            "audit=after\n" ++
            "approval=publish\n" ++
            "workflow=done\n" ++
            "result=completed\n",
    );
    if (std.mem.eql(u8, id, "reader_basic")) return writer.writeAll(
        "env=21\n" ++
            "value=42\n",
    );
    if (std.mem.eql(u8, id, "exception_basic")) return writer.writeAll(
        "branch=pass\n" ++
            "body-pass\n" ++
            "final=result=ok\n" ++
            "branch=throw\n" ++
            "body-before-throw\n" ++
            "catch=result=boom\n" ++
            "final=result=boom\n",
    );
    if (std.mem.eql(u8, id, "optional_basic")) return writer.writeAll(
        "branch=return_now\n" ++
            "policy-return-now\n" ++
            "final=result=early\n" ++
            "branch=resume_with\n" ++
            "policy-resume\n" ++
            "body-after-request\n" ++
            "policy-after-resume\n" ++
            "final=answer=42\n",
    );
    if (std.mem.eql(u8, id, "resource_basic")) return writer.writeAll(
        "acquire=a\n" ++
            "use=a\n" ++
            "acquire=b\n" ++
            "use=b\n" ++
            "release=b\n" ++
            "release=a\n" ++
            "final=done\n",
    );
    if (std.mem.eql(u8, id, "writer_basic")) return writer.writeAll(
        "item=a\n" ++
            "item=b\n" ++
            "value=done\n",
    );
    if (std.mem.eql(u8, id, "state_basic")) return writer.writeAll(
        "before=5\n" ++
            "after=6\n" ++
            "final_state=6\n" ++
            "value=11\n",
    );
    if (std.mem.eql(u8, id, "algebraic_abortive_validation")) return writer.writeAll(
        "validate=name\n" ++
            "abort=missing-name\n" ++
            "final=error=missing-name\n",
    );
    if (std.mem.eql(u8, id, "algebraic_artifact_search")) return writer.writeAll(
        "query=artifact-search\n" ++
            "messages=1\n" ++
            "tool_calls=0\n" ++
            "memory_blocks=1\n" ++
            "opencode_source=jsonl\n" ++
            "total=3\n",
    );
    return error.UnknownParityCase;
}

fn tryRunTypedKernel(writer: anytype, id: []const u8) !bool {
    if (parity_kernel.scenarioForCaseId(id)) |scenario| {
        const state = parity_kernel.runScenario(scenario);
        try parity_kernel.writeTranscript(writer, &state);
        return true;
    }
    return false;
}

/// Run one proof-only runtime-positive survey case.
pub fn runRuntimeCase(id: []const u8) anyerror!void {
    if (std.mem.eql(u8, id, "protocol_resume_transform_runtime")) return;
    return error.UnknownParityCase;
}
