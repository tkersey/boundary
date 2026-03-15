const bridge_manifest = @import("direct_style_bridge_manifest");
const early_exit = @import("example_early_exit");
const exception_basic = @import("example_exception_basic");
const generator = @import("example_generator");
const nested_workflow = @import("example_nested_workflow");
const optional_basic = @import("example_optional_basic");
const reader_basic = @import("example_reader_basic");
const resource_basic = @import("example_resource_basic");
const resume_or_return = @import("example_resume_or_return");
const state_basic = @import("example_state_basic");
const std = @import("std");
const witnesses = @import("witnesses_src");
const writer_basic = @import("example_writer_basic");

/// Whether the current stack-runtime baseline supports the given bridge case id.
pub fn supportsCaseId(case_id: []const u8) bool {
    const case = bridge_manifest.find(case_id) orelse return false;
    return case.status == .supported;
}

/// Execute one supported bridge case through the current stack-runtime baseline.
pub fn runCaseId(writer: anytype, case_id: []const u8) anyerror!void {
    const case = bridge_manifest.find(case_id) orelse return error.UnsupportedBridgeCase;
    if (case.status == .blocked) return error.UnsupportedBridgeCase;

    if (case.source_kind == .witness) {
        try witnesses.runWitness(writer, case_id);
        return;
    }

    if (std.mem.eql(u8, case_id, "early_exit")) return early_exit.run(writer);
    if (std.mem.eql(u8, case_id, "generator")) return generator.run(writer);
    if (std.mem.eql(u8, case_id, "resume_or_return")) return resume_or_return.run(writer);
    if (std.mem.eql(u8, case_id, "nested_workflow")) return nested_workflow.run(writer);
    if (std.mem.eql(u8, case_id, "state_basic")) return state_basic.run(writer);
    if (std.mem.eql(u8, case_id, "reader_basic")) return reader_basic.run(writer);
    if (std.mem.eql(u8, case_id, "optional_basic")) return optional_basic.run(writer);
    if (std.mem.eql(u8, case_id, "exception_basic")) return exception_basic.run(writer);
    if (std.mem.eql(u8, case_id, "resource_basic")) return resource_basic.run(writer);
    if (std.mem.eql(u8, case_id, "writer_basic")) return writer_basic.run(writer);
    return error.UnsupportedBridgeCase;
}
