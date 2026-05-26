// zlinter-disable declaration_naming field_ordering require_doc_comment no_hidden_allocations no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

const semantic = boundary.ir.builder.semantic;

const compiled = semantic.finish(.{
    .label = "world-surface-strict-residual",
    .ir_hash = 0x7773747269637402,
    .entry = "run",
    .functions = .{.{
        .symbol_name = "run",
        .params = .{},
        .locals = .{semantic.local("decision", i32)},
        .result = i32,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{semantic.constI32("decision", 1)},
            .terminator = semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid world surface strict residual: " ++ @errorName(err));

const Program = boundary.program("world-surface-strict-residual", struct {}, struct {
    pub const compiled_plan = compiled.plan;
});
const Closure = Program.BoundaryClosure;
const Elaboration = Closure.Elaboration;
const program_ref = Program.Evidence.refFor(Program.Evidence.domains.program_plan, Program.compiled_plan.hash(), .{ .label = Program.contract.label });
const closure_graph = Closure.Graph.init("world-surface-strict-graph", &.{}, &.{}, &.{});
const closure_report = Closure.Report.init(.{
    .graph_fingerprint = closure_graph.fingerprint,
    .effect_free_root_refs = &.{program_ref},
});
const closure_policy = Closure.Policy.auditOnly();
const closure_certificate = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk Closure.Certificate.init(closure_report, closure_graph, closure_policy, &.{});
};
const elaboration_policy = blk: {
    var policy = Elaboration.Policy.auditOnly();
    policy.closure_policy = closure_policy;
    break :blk policy;
};
const elaboration_input = Elaboration.Input{
    .closure_graph = closure_graph,
    .closure_report = closure_report,
    .closure_certificate = closure_certificate,
    .source_program_ref = program_ref,
    .policy = elaboration_policy,
};
const Target = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk Elaboration.Target.compileComptime(.{
        .label = "world-surface-strict-target",
        .input = elaboration_input,
        .policy = Elaboration.Target.Policy.auditOnly(),
    });
};

pub fn run(writer: anytype) !void {
    Target.assertNormalForm(.strict_closed);
    Target.assertWorldSurfaceReady();
    Target.assertNoSearchHotPath();

    var runtime = boundary.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    var result = try Program.run(&runtime, Program.Handlers{});
    defer result.deinit();

    try writer.print("closure_certificate_fingerprint={x}\n", .{closure_certificate.certificate_fingerprint});
    try writer.print("target_certificate_fingerprint={x}\n", .{Target.Certificate.certificate_fingerprint});
    try writer.print("world_surface_fingerprint={x}\n", .{Target.WorldSurface.surface_fingerprint});
    try writer.print("normal_form={s}\n", .{@tagName(Target.NormalForm.kind)});
    try writer.print("final_result={d}\n", .{result.value});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
