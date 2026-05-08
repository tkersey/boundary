// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

fn mustInstruction(result: anyerror!ability.ir.plan.Instruction) ability.ir.plan.Instruction {
    return result catch |err| @compileError("invalid resource instruction: " ++ @errorName(err));
}

fn mustPlan(result: anyerror!ability.ir.ProgramPlan) ability.ir.ProgramPlan {
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
        pub fn dispatch(_: *const @This()) !ability.effect.choice.Decision(i32, i32) {
            return ability.effect.choice.Decision(i32, i32).returnNow(90);
        }
    },
};

fn resourcePlan(comptime mode: ResourceMode) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const outer = ability.ir.builder.local(root, 0);
    const inner = ability.ir.builder.local(root, 1);
    const value = ability.ir.builder.local(root, 2);
    const instruction_count = switch (mode) {
        .normal => 6,
        .exception_escape => 6,
        .optional_escape => 6,
    };
    const instructions = comptime blk: {
        var buffer: [instruction_count]ability.ir.plan.Instruction = undefined;
        buffer[0] = mustInstruction(ability.ir.builder.callOp(root, outer, ability.ir.builder.op(root, 0), null));
        buffer[1] = mustInstruction(ability.ir.builder.callOp(root, inner, ability.ir.builder.op(root, 0), null));
        buffer[2] = mustInstruction(ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 1), inner));
        buffer[3] = mustInstruction(ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 1), outer));
        switch (mode) {
            .normal => {
                buffer[4] = .{ .kind = .const_i32, .dst = value.index, .operand = 12 };
                buffer[5] = mustInstruction(ability.ir.builder.returnValue(root, value));
            },
            .exception_escape => {
                buffer[4] = .{ .kind = .const_i32, .dst = value.index, .operand = 80 };
                buffer[5] = mustInstruction(ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 2), value));
            },
            .optional_escape => {
                buffer[4] = mustInstruction(ability.ir.builder.callOp(root, value, ability.ir.builder.op(root, 2), null));
                buffer[5] = mustInstruction(ability.ir.builder.returnValue(root, value));
            },
        }
        break :blk buffer;
    };
    const requirement_count: u16 = if (mode == .normal) 1 else 2;
    const requirements = switch (mode) {
        .normal => [_]ability.ir.plan.Requirement{.{
            .label = "resource",
            .first_op = 0,
            .op_count = 2,
            .lifecycle_tag = .resource_bracket,
        }},
        .exception_escape => [_]ability.ir.plan.Requirement{
            .{ .label = "resource", .first_op = 0, .op_count = 2, .lifecycle_tag = .resource_bracket },
            .{ .label = "exception", .first_op = 2, .op_count = 1, .lifecycle_tag = .abort_catch },
        },
        .optional_escape => [_]ability.ir.plan.Requirement{
            .{ .label = "resource", .first_op = 0, .op_count = 2, .lifecycle_tag = .resource_bracket },
            .{ .label = "optional", .first_op = 2, .op_count = 1, .lifecycle_tag = .choice_policy },
        },
    };
    const ops = switch (mode) {
        .normal => [_]ability.ir.plan.Op{
            .{ .requirement_index = 0, .op_name = "acquire", .mode = .transform, .payload_codec = .unit, .resume_codec = .product, .resume_schema_index = 0 },
            .{ .requirement_index = 0, .op_name = "release", .mode = .transform, .payload_codec = .product, .payload_schema_index = 0, .resume_codec = .unit },
        },
        .exception_escape => [_]ability.ir.plan.Op{
            .{ .requirement_index = 0, .op_name = "acquire", .mode = .transform, .payload_codec = .unit, .resume_codec = .product, .resume_schema_index = 0 },
            .{ .requirement_index = 0, .op_name = "release", .mode = .transform, .payload_codec = .product, .payload_schema_index = 0, .resume_codec = .unit },
            .{ .requirement_index = 1, .op_name = "throw", .mode = .abort, .payload_codec = .i32, .resume_codec = .unit },
        },
        .optional_escape => [_]ability.ir.plan.Op{
            .{ .requirement_index = 0, .op_name = "acquire", .mode = .transform, .payload_codec = .unit, .resume_codec = .product, .resume_schema_index = 0 },
            .{ .requirement_index = 0, .op_name = "release", .mode = .transform, .payload_codec = .product, .payload_schema_index = 0, .resume_codec = .unit },
            .{ .requirement_index = 1, .op_name = "request", .mode = .choice, .payload_codec = .unit, .resume_codec = .i32 },
        },
    };
    const schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Resource),
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const fields = [_]ability.ir.ValueFieldPlan{.{
        .name = "id",
        .codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = if (mode == .exception_escape) .return_unit else .return_value }};

    return mustPlan(ability.ir.builder.finish(.{
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

fn runWithBody(runtime: *ability.Runtime, comptime Body: type, fail_id: i32) !RunSummary {
    var events = [_]i32{0} ** 4;
    var count: usize = 0;
    var next_id: i32 = 1;
    const Program = ability.program(Body.compiled_plan.label, ResourceHandlers, Body);
    var result = try Program.run(runtime, .{
        .acquire = .{ .next_id = &next_id, .events = &events, .count = &count },
        .release = .{ .events = &events, .count = &count, .fail_id = fail_id },
        .throw = .{},
        .request = .{},
    });
    defer result.deinit();
    return .{ .value = result.value, .events = events, .count = count };
}

pub fn runNormal(runtime: *ability.Runtime) !RunSummary {
    return runWithBody(runtime, NormalBody, 0);
}

pub fn runExceptionEscape(runtime: *ability.Runtime) !RunSummary {
    return runWithBody(runtime, ExceptionBody, 0);
}

pub fn runOptionalEscape(runtime: *ability.Runtime) !RunSummary {
    return runWithBody(runtime, OptionalBody, 0);
}

pub fn runReleaseFailure(runtime: *ability.Runtime) !void {
    _ = try runWithBody(runtime, NormalBody, 2);
}

pub fn run(writer: anytype) !void {
    var runtime = ability.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const normal = try runNormal(&runtime);
    const exception = try runExceptionEscape(&runtime);
    const optional = try runOptionalEscape(&runtime);
    const Program = ability.program("plan-native-resource-normal", ResourceHandlers, NormalBody);

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
