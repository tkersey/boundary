// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

fn unitPlan() boundary.ir.ProgramPlan {
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
        .label = "boundary-target-missing-residual-program",
        .ir_hash = 0xC781_F201,
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

const Program = boundary.program("boundary-target-missing-residual-program", struct {}, struct {
    pub const compiled_plan = unitPlan();
});

comptime {
    @setEvalBranchQuota(200_000);
    const Evidence = Program.Evidence;
    const Closure = Program.BoundaryClosure;
    const Elaboration = Closure.Elaboration;
    const source_ref = Evidence.refFor(Evidence.domains.program_plan, Program.compiled_plan.hash(), .{ .label = Program.contract.label });
    const graph = Closure.Graph.init("boundary-target-missing-residual-program-graph", &.{}, &.{}, &.{});
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
    _ = Elaboration.Target.compileComptime(.{
        .label = "boundary-target-missing-residual-program-target",
        .input = input,
        .policy = Elaboration.Target.Policy.auditOnly(),
    });
}
