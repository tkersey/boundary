// zlinter-disable declaration_naming field_naming field_ordering require_doc_comment no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

fn mustInstruction(result: anyerror!boundary.ir.plan.Instruction) boundary.ir.plan.Instruction {
    return result catch |err| @compileError("invalid resource instruction: " ++ @errorName(err));
}

fn mustPlan(result: anyerror!boundary.ir.ProgramPlan) boundary.ir.ProgramPlan {
    return result catch |err| @compileError("invalid resource plan: " ++ @errorName(err));
}

pub const Resource = struct {
    id: i32,
};

pub const RunSummary = struct {
    value: i32,
    events: [4]i32,
    count: usize,
};

const ResourceMode = enum {
    normal,
    exception_escape,
    optional_escape,
};

const ResourceHandlers = struct {
    acquire: struct {
        next_id: *i32,
        events: *[4]i32,
        count: *usize,

        pub fn dispatch(self: *const @This()) !Resource {
            const id = self.next_id.*;
            self.next_id.* += 1;
            self.events[self.count.*] = id;
            self.count.* += 1;
            return .{ .id = id };
        }
    },
    release: struct {
        events: *[4]i32,
        count: *usize,
        fail_id: i32,

        pub fn dispatch(self: *const @This(), resource: Resource) !void {
            if (resource.id == self.fail_id) return error.ReleaseFailed;
            self.events[self.count.*] = -resource.id;
            self.count.* += 1;
        }
    },
    throw: struct {
        pub fn dispatch(_: *const @This(), payload: i32) !i32 {
            return payload;
        }
    },
    request: struct {
        pub fn dispatch(_: *const @This()) !boundary.effect.choice.Decision(i32, i32) {
            return boundary.effect.choice.Decision(i32, i32).returnNow(90);
        }
    },
};

fn resourcePlan(comptime mode: ResourceMode) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const outer = boundary.ir.builder.local(root, 0);
    const inner = boundary.ir.builder.local(root, 1);
    const value = boundary.ir.builder.local(root, 2);
    const instruction_count = switch (mode) {
        .normal => 6,
        .exception_escape => 6,
        .optional_escape => 6,
    };
    const instructions = comptime blk: {
        var buffer: [instruction_count]boundary.ir.plan.Instruction = undefined;
        buffer[0] = mustInstruction(boundary.ir.builder.callOp(root, outer, boundary.ir.builder.op(root, 0), null));
        buffer[1] = mustInstruction(boundary.ir.builder.callOp(root, inner, boundary.ir.builder.op(root, 0), null));
        buffer[2] = mustInstruction(boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 1), inner));
        buffer[3] = mustInstruction(boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 1), outer));
        switch (mode) {
            .normal => {
                buffer[4] = .{ .kind = .const_i32, .dst = value.index, .operand = 12 };
                buffer[5] = mustInstruction(boundary.ir.builder.returnValue(root, value));
            },
            .exception_escape => {
                buffer[4] = .{ .kind = .const_i32, .dst = value.index, .operand = 80 };
                buffer[5] = mustInstruction(boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 2), value));
            },
            .optional_escape => {
                buffer[4] = mustInstruction(boundary.ir.builder.callOp(root, value, boundary.ir.builder.op(root, 2), null));
                buffer[5] = mustInstruction(boundary.ir.builder.returnValue(root, value));
            },
        }
        break :blk buffer;
    };
    const ResourceRows = boundary.ir.schema.LowerBinding(
        boundary.ir.schema.Binding("resource", boundary.effect.resource.Schema(Resource, error{ReleaseFailed}, void), void),
        .{
            .requirement_index = 0,
            .first_op = 0,
            .schema_refs = boundary.ir.schema.SchemaRefs(.{
                boundary.ir.schema.ref(Resource, 0),
            }),
        },
    );
    const ExceptionRows = boundary.ir.schema.LowerBinding(
        boundary.ir.schema.Binding("exception", boundary.effect.exception.Schema(i32, error{}, void), void),
        .{ .requirement_index = 1, .first_op = ResourceRows.op_count },
    );
    const OptionalRows = boundary.ir.schema.LowerBinding(
        boundary.ir.schema.Binding("optional", boundary.effect.optional.Schema(i32, error{}, void), void),
        .{ .requirement_index = 1, .first_op = ResourceRows.op_count },
    );
    const requirement_count: u16 = if (mode == .normal) 1 else 2;
    const requirements = switch (mode) {
        .normal => [_]boundary.ir.plan.Requirement{ResourceRows.requirement},
        .exception_escape => [_]boundary.ir.plan.Requirement{
            ResourceRows.requirement,
            ExceptionRows.requirement,
        },
        .optional_escape => [_]boundary.ir.plan.Requirement{
            ResourceRows.requirement,
            OptionalRows.requirement,
        },
    };
    const ops = switch (mode) {
        .normal => ResourceRows.ops,
        .exception_escape => ResourceRows.ops ++ ExceptionRows.ops,
        .optional_escape => ResourceRows.ops ++ OptionalRows.ops,
    };
    const schemas = [_]boundary.ir.ValueSchemaPlan{.{
        .label = @typeName(Resource),
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const fields = [_]boundary.ir.ValueFieldPlan{.{
        .name = "id",
        .codec = .i32,
    }};
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = if (mode == .exception_escape) .return_unit else .return_value }};

    return mustPlan(boundary.ir.builder.finish(.{
        .label = switch (mode) {
            .normal => "plan-native-resource-normal",
            .exception_escape => "plan-native-resource-exception",
            .optional_escape => "plan-native-resource-optional",
        },
        .ir_hash = switch (mode) {
            .normal => 80,
            .exception_escape => 81,
            .optional_escape => 82,
        },
        .entry = root,
        .functions = &.{.{
            .symbol_name = "run",
            .value_codec = if (mode == .exception_escape) .unit else .i32,
            .result_codec = .i32,
            .first_requirement = 0,
            .requirement_count = requirement_count,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 3,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = @intCast(instructions.len),
        }},
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &schemas,
        .value_fields = &fields,
        .value_variants = &.{},
        .locals = &.{
            .{ .codec = .product, .schema_index = 0 },
            .{ .codec = .product, .schema_index = 0 },
            .{ .codec = .i32 },
        },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }));
}

const NormalBody = struct {
    pub const Error = error{ReleaseFailed};
    pub const value_schema_types = .{Resource};
    pub const compiled_plan = resourcePlan(.normal);
};

const ExceptionBody = struct {
    pub const Error = error{ReleaseFailed};
    pub const value_schema_types = .{Resource};
    pub const compiled_plan = resourcePlan(.exception_escape);
};

const OptionalBody = struct {
    pub const Error = error{ReleaseFailed};
    pub const value_schema_types = .{Resource};
    pub const compiled_plan = resourcePlan(.optional_escape);
};

fn runWithBody(runtime: *boundary.Runtime, comptime Body: type, fail_id: i32) !RunSummary {
    var events = [_]i32{0} ** 4;
    var count: usize = 0;
    var next_id: i32 = 1;
    const Program = boundary.program(Body.compiled_plan.label, ResourceHandlers, Body);
    var result = try Program.run(runtime, .{
        .acquire = .{ .next_id = &next_id, .events = &events, .count = &count },
        .release = .{ .events = &events, .count = &count, .fail_id = fail_id },
        .throw = .{},
        .request = .{},
    });
    defer result.deinit();
    return .{ .value = result.value, .events = events, .count = count };
}

pub fn runNormal(runtime: *boundary.Runtime) !RunSummary {
    return runWithBody(runtime, NormalBody, 0);
}

pub fn runExceptionEscape(runtime: *boundary.Runtime) !RunSummary {
    return runWithBody(runtime, ExceptionBody, 0);
}

pub fn runOptionalEscape(runtime: *boundary.Runtime) !RunSummary {
    return runWithBody(runtime, OptionalBody, 0);
}

pub fn runReleaseFailure(runtime: *boundary.Runtime) !void {
    _ = try runWithBody(runtime, NormalBody, 2);
}

pub fn run(writer: anytype) !void {
    var runtime = boundary.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const normal = try runNormal(&runtime);
    const exception = try runExceptionEscape(&runtime);
    const optional = try runOptionalEscape(&runtime);
    const Program = boundary.program("plan-native-resource-normal", ResourceHandlers, NormalBody);

    try writer.print("normal={d} events={d},{d},{d},{d}\n", .{ normal.value, normal.events[0], normal.events[1], normal.events[2], normal.events[3] });
    try writer.print("exception={d} optional={d}\n", .{ exception.value, optional.value });
    try writer.print("contract={s}:{s} acquire={s} release={s}\n", .{
        Program.contract.requirements[0].label,
        @tagName(Program.contract.requirements[0].lifecycle_tag),
        Program.contract.ops[0].op_name,
        Program.contract.ops[1].op_name,
    });
}

/// Run the plan-native resource example.
pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
