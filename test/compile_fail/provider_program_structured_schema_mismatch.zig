// zlinter-disable declaration_naming require_doc_comment
const ability = @import("ability");

const SourcePayload = struct {
    amount: i32,
};

const HandlerPayload = struct {
    approved: bool,
};

const SourceSchemas = ability.ir.schema.Registry(.{SourcePayload});
const HandlerSchemas = ability.ir.schema.Registry(.{HandlerPayload});

const SourceProtocol = ability.ir.schema.Protocol(.{
    .label = "structured",
    .ops = .{ability.ir.schema.transform("step", SourcePayload, SourcePayload)},
});

const SourceRows = SourceProtocol.Rows(struct {}, .{
    .requirement_index = 0,
    .first_op = 0,
    .schema_refs = SourceSchemas.schema_refs,
});
const SourceStep = SourceRows.op("step");

const source_compiled = ability.ir.builder.semantic.finish(.{
    .label = "provider-program-structured-schema-mismatch",
    .ir_hash = 0x7070736d01,
    .entry = "run",
    .schemas = SourceSchemas,
    .requirements = &.{SourceRows.requirement},
    .ops = &SourceRows.ops,
    .functions = .{.{
        .symbol_name = "run",
        .requirements = ability.ir.builder.semantic.span(0, 1),
        .params = .{ability.ir.builder.semantic.param("payload", SourcePayload)},
        .locals = .{ability.ir.builder.semantic.local("result", SourcePayload)},
        .result = SourcePayload,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{
                ability.ir.builder.semantic.call(SourceStep, .{
                    .dst = "result",
                    .payload = "payload",
                    .label = "structured.step",
                }),
            },
            .terminator = ability.ir.builder.semantic.returnValue("result"),
        }},
    }},
}) catch |err| @compileError("invalid source plan: " ++ @errorName(err));

const SourceBody = struct {
    pub const value_schema_types = SourceSchemas.value_schema_types;
    pub const site_metadata = source_compiled.site_metadata;
    pub const compiled_plan = source_compiled.plan;
};
const SourceProgram = ability.program("provider-program-structured-schema-mismatch", struct {}, SourceBody);
const Site = SourceProgram.protocol.operationSite("structured", "step", 0);

const handler_compiled = ability.ir.builder.semantic.finish(.{
    .label = "provider-program-structured-schema-mismatch-handler",
    .ir_hash = 0x7070736d02,
    .entry = "run",
    .schemas = HandlerSchemas,
    .functions = .{.{
        .symbol_name = "run",
        .params = .{ability.ir.builder.semantic.param("payload", HandlerPayload)},
        .locals = .{},
        .result = HandlerPayload,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{},
            .terminator = ability.ir.builder.semantic.returnValue("payload"),
        }},
    }},
}) catch |err| @compileError("invalid handler plan: " ++ @errorName(err));

const HandlerBody = struct {
    pub const value_schema_types = HandlerSchemas.value_schema_types;
    pub const compiled_plan = handler_compiled.plan;
};
const HandlerProgram = ability.program("provider-program-structured-schema-mismatch-handler", struct {}, HandlerBody);

const Decl = SourceProgram.Exchange.ProviderHandler.program(.{
    .label = "bad-structured-provider-program-mapping",
    .op = Site,
    .program = HandlerProgram,
    .map_request = .payload_to_args,
    .map_result = .result_to_resume,
});

comptime {
    _ = Decl.provider_program_mapping_fingerprint;
}
