// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

fn unitPlan(comptime label: []const u8, comptime hash: u64) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .result_codec = .unit,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 0,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 0,
    }};
    const blocks = [_]boundary.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_unit }};
    return boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = hash,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &.{},
    }) catch unreachable;
}

const SourceProgram = boundary.program("boundary-target-residual-source", struct {}, struct {
    pub const compiled_plan = unitPlan("boundary-target-residual-source", 0xC781_F301);
});

const OtherProgram = boundary.program("boundary-target-residual-other", struct {}, struct {
    pub const compiled_plan = unitPlan("boundary-target-residual-other", 0xC781_F302);
});

comptime {
    @setEvalBranchQuota(200_000);
    const Evidence = SourceProgram.Evidence;
    const Closure = SourceProgram.BoundaryClosure;
    const Elaboration = Closure.Elaboration;
    const source_ref = Evidence.refFor(Evidence.domains.program_plan, SourceProgram.compiled_plan.hash(), .{ .label = SourceProgram.contract.label });
    const graph = Closure.Graph.init("boundary-target-residual-mismatch-graph", &.{}, &.{}, &.{});
    const report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
    });
    const certificate = Closure.Certificate.init(report, graph, Closure.Policy.auditOnly(), &.{});
    const input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = report,
        .closure_certificate = certificate,
        .source_program_ref = source_ref,
        .policy = Elaboration.Policy.auditOnly(),
    };
    const Body = Elaboration.FromResidual(input, SourceProgram, .{ .label = "boundary-target-residual-source-body" });
    _ = Elaboration.Target.FromBodyWithProgram(Body, OtherProgram, .{
        .label = "boundary-target-residual-mismatch-target",
        .input = input,
        .policy = Elaboration.Target.Policy.auditOnly(),
    });
}
