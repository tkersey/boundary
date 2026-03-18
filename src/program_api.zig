const effect = @import("effect/root.zig");
const lowered_machine = @import("lowered_machine");
const prompt_contract = @import("prompt_contract_support");
const std = @import("std");
const with_api = @import("with_api.zig");

pub const DeclarationKind = enum {
    state,
    reader,
    optional,
    exception,
    resource,
    writer,
    family,
};

pub const DeclarationMeta = struct {
    name: []const u8,
    kind: DeclarationKind,
    has_binding: bool,
    has_output: bool,
    op_count: usize,
};

pub const Decision = effect.choice.Decision;

pub const Op = struct {
    pub const transform = effect.ops.Transform;
    pub const choice = effect.ops.Choice;
    pub const abort = effect.ops.Abort;
};

fn StateDecl(comptime StateType: type) type {
    return struct {
        pub const kind = DeclarationKind.state;
        pub const Value = StateType;
    };
}

fn ReaderDecl(comptime EnvType: type) type {
    return struct {
        pub const kind = DeclarationKind.reader;
        pub const Value = EnvType;
    };
}

fn OptionalDecl(comptime ResumeType: type, comptime PolicyType: type) type {
    return struct {
        pub const kind = DeclarationKind.optional;
        pub const Resume = ResumeType;
        pub const Policy = PolicyType;
    };
}

fn ExceptionDecl(comptime PayloadType: type, comptime CatchType: type) type {
    return struct {
        pub const kind = DeclarationKind.exception;
        pub const Payload = PayloadType;
        pub const Catch = CatchType;
    };
}

fn ResourceDecl(comptime ResourceType: type, comptime ManagerType: type) type {
    return struct {
        pub const kind = DeclarationKind.resource;
        pub const Resource = ResourceType;
        pub const Manager = ManagerType;
    };
}

fn WriterDecl(comptime ItemType: type) type {
    return struct {
        pub const kind = DeclarationKind.writer;
        pub const Item = ItemType;
    };
}

fn FamilyDecl(comptime spec: anytype, comptime HandlerType: type) type {
    const GeneratedFamily = effect.Define(spec);
    return struct {
        pub const kind = DeclarationKind.family;
        pub const Generated = GeneratedFamily;
        pub const Handler = HandlerType;
    };
}

pub const Decl = struct {
    pub fn state(comptime StateType: type) StateDecl(StateType) {
        return .{};
    }

    pub fn reader(comptime EnvType: type) ReaderDecl(EnvType) {
        return .{};
    }

    pub fn optional(comptime ResumeType: type, comptime PolicyType: type) OptionalDecl(ResumeType, PolicyType) {
        return .{};
    }

    pub fn exception(comptime PayloadType: type, comptime CatchType: type) ExceptionDecl(PayloadType, CatchType) {
        return .{};
    }

    pub fn resource(comptime ResourceType: type, comptime ManagerType: type) ResourceDecl(ResourceType, ManagerType) {
        return .{};
    }

    pub fn writer(comptime ItemType: type) WriterDecl(ItemType) {
        return .{};
    }

    pub fn family(comptime spec: anytype, comptime HandlerType: type) FamilyDecl(spec, HandlerType) {
        return .{};
    }
};

fn hasBinding(comptime DeclType: type) bool {
    return switch (DeclType.kind) {
        .state, .reader, .family => true,
        .optional, .exception, .resource, .writer => false,
    };
}

fn hasOutput(comptime DeclType: type) bool {
    return switch (DeclType.kind) {
        .state, .writer => true,
        .reader, .optional, .exception, .resource => false,
        .family => DeclType.Generated.definition.mode == .resume_then_transform,
    };
}

fn bindingFieldType(comptime DeclType: type) type {
    return switch (DeclType.kind) {
        .state, .reader => DeclType.Value,
        .family => DeclType.Handler,
        else => unreachable,
    };
}

fn handlerFieldType(comptime DeclType: type) type {
    return switch (DeclType.kind) {
        .state => effect.state.LexicalDescriptor(DeclType.Value, error{}),
        .reader => effect.reader.LexicalDescriptor(DeclType.Value, error{}),
        .optional => @TypeOf(effect.optional.use(DeclType.Resume, DeclType.Policy)),
        .exception => @TypeOf(effect.exception.use(DeclType.Payload, DeclType.Catch)),
        .resource => @TypeOf(effect.resource.use(DeclType.Resource, DeclType.Manager)),
        .writer => effect.writer.LexicalDescriptor(DeclType.Item, error{}),
        .family => @TypeOf(DeclType.Generated.use(.{ .handler = @as(DeclType.Handler, undefined) })),
    };
}

fn handlerBundleType(comptime DeclarationsType: type) type {
    const fields = @typeInfo(DeclarationsType).@"struct".fields;
    var out_fields = [_]std.builtin.Type.StructField{.{
        .name = "",
        .type = void,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = @alignOf(void),
    }} ** fields.len;

    inline for (fields, 0..) |field, index| {
        out_fields[index] = .{
            .name = field.name,
            .type = handlerFieldType(field.type),
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(handlerFieldType(field.type)),
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &out_fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

fn bindingsType(comptime DeclarationsType: type) type {
    const fields = @typeInfo(DeclarationsType).@"struct".fields;
    var out_fields = [_]std.builtin.Type.StructField{.{
        .name = "",
        .type = void,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = @alignOf(void),
    }} ** fields.len;
    var count: usize = 0;

    inline for (fields) |field| {
        if (!hasBinding(field.type)) continue;
        const BindingType = bindingFieldType(field.type);
        out_fields[count] = .{
            .name = field.name,
            .type = BindingType,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(BindingType),
        };
        count += 1;
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = out_fields[0..count],
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

fn buildHandlers(
    comptime ProgramType: type,
    runtime: *lowered_machine.Runtime,
    bindings: ProgramType.Bindings,
) handlerBundleType(@TypeOf(ProgramType.declarations)) {
    const Bundle = handlerBundleType(@TypeOf(ProgramType.declarations));
    var bundle: Bundle = undefined;
    const fields = @typeInfo(@TypeOf(ProgramType.declarations)).@"struct".fields;

    inline for (fields) |field| {
        const DeclType = field.type;
        const value = switch (DeclType.kind) {
            .state => effect.state.use(@field(bindings, field.name)),
            .reader => effect.reader.use(@field(bindings, field.name)),
            .optional => effect.optional.use(DeclType.Resume, DeclType.Policy),
            .exception => effect.exception.use(DeclType.Payload, DeclType.Catch),
            .resource => effect.resource.use(DeclType.Resource, DeclType.Manager),
            .writer => effect.writer.use(DeclType.Item, runtime.allocator),
            .family => DeclType.Generated.use(.{ .handler = @field(bindings, field.name) }),
        };
        @field(bundle, field.name) = value;
    }

    return bundle;
}

fn buildManifest(comptime declaration_values: anytype) type {
    const fields = @typeInfo(@TypeOf(declaration_values)).@"struct".fields;
    comptime var metas = [_]DeclarationMeta{.{
        .name = "",
        .kind = .state,
        .has_binding = false,
        .has_output = false,
        .op_count = 0,
    }} ** fields.len;
    comptime var output_names = [_][]const u8{""} ** fields.len;
    comptime var output_count: usize = 0;

    inline for (fields, 0..) |field, index| {
        metas[index] = .{
            .name = field.name,
            .kind = field.type.kind,
            .has_binding = hasBinding(field.type),
            .has_output = hasOutput(field.type),
            .op_count = switch (field.type.kind) {
                .family => field.type.Generated.definition.op_count,
                else => 0,
            },
        };
        if (hasOutput(field.type)) {
            output_names[output_count] = field.name;
            output_count += 1;
        }
    }

    const manifest_entries = metas;
    const manifest_outputs = blk: {
        comptime var compact = [_][]const u8{""} ** output_count;
        inline for (0..output_count) |index| {
            compact[index] = output_names[index];
        }
        break :blk compact;
    };

    return struct {
        pub const declaration_count = fields.len;
        pub const entries = manifest_entries;
        pub const outputs = manifest_outputs[0..];
    };
}

fn assertDeclarations(comptime DeclarationsType: type) void {
    const info = @typeInfo(DeclarationsType);
    if (info != .@"struct") @compileError("shift.Program declarations must be a struct literal or struct value");
    if (info.@"struct".fields.len == 0) @compileError("shift.Program declarations must declare at least one field");
    inline for (info.@"struct".fields) |field| {
        if (!@hasDecl(field.type, "kind")) @compileError(@typeName(field.type) ++ " is not a shift.Decl.* declaration");
    }
}

pub fn Program(comptime declaration_values: anytype, comptime BodyType: type) type {
    const DeclarationsType = @TypeOf(declaration_values);
    comptime assertDeclarations(DeclarationsType);
    return struct {
        pub const Body = BodyType;
        pub const Bindings = bindingsType(DeclarationsType);
        pub const Manifest = buildManifest(declaration_values);
        pub const declarations = declaration_values;

        pub fn run(runtime: *lowered_machine.Runtime, bindings: Bindings) RunReturnType(@This()) {
            return program_run(runtime, @This(), bindings);
        }
    };
}

pub fn RunReturnType(comptime ProgramType: type) type {
    return with_api.WithFnReturnType(handlerBundleType(@TypeOf(ProgramType.declarations)), ProgramType.Body);
}

fn program_run(runtime: *lowered_machine.Runtime, comptime ProgramType: type, bindings: ProgramType.Bindings) RunReturnType(ProgramType) {
    const handlers = buildHandlers(ProgramType, runtime, bindings);
    return with_api.with(runtime, handlers, ProgramType.Body);
}

pub fn run(runtime: *lowered_machine.Runtime, comptime ProgramType: type, bindings: ProgramType.Bindings) RunReturnType(ProgramType) {
    return program_run(runtime, ProgramType, bindings);
}

test "program manifest records declaration metadata and outputs" {
    const Counter = Decl.family(.{
        .state_type = i32,
        .ops = .{
            Op.transform("get", void, i32),
            Op.transform("set", i32, void),
        },
    }, struct {
        state: i32,

        pub fn get(self: *@This()) i32 {
            return self.state;
        }

        pub fn afterGet(_: *@This(), answer: i32) i32 {
            return answer;
        }

        pub fn set(self: *@This(), value: i32) void {
            self.state = value;
        }

        pub fn afterSet(_: *@This(), answer: i32) i32 {
            return answer;
        }
    });

    const Demo = Program(.{
        .state = Decl.state(i32),
        .reader = Decl.reader(i32),
        .counter = Counter,
        .writer = Decl.writer([]const u8),
    }, struct {
        pub fn body(_: anytype) i32 {
            return 0;
        }
    });

    try std.testing.expectEqual(@as(usize, 4), Demo.Manifest.declaration_count);
    try std.testing.expectEqualStrings("state", Demo.Manifest.entries[0].name);
    try std.testing.expect(Demo.Manifest.entries[0].has_binding);
    try std.testing.expect(Demo.Manifest.entries[0].has_output);
    try std.testing.expectEqual(DeclarationKind.family, Demo.Manifest.entries[2].kind);
    try std.testing.expectEqual(@as(usize, 2), Demo.Manifest.entries[2].op_count);
    try std.testing.expectEqual(@as(usize, 3), Demo.Manifest.outputs.len);
    try std.testing.expectEqualStrings("counter", Demo.Manifest.outputs[1]);
}

test "program run executes through the new front door" {
    const Demo = Program(.{
        .state = Decl.state(i32),
    }, struct {
        pub fn body(eff: anytype) !i32 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            return before + (try eff.state.get());
        }
    });

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try run(&runtime, Demo, .{ .state = 5 });
    try std.testing.expectEqual(@as(i32, 6), result.outputs.state);
    try std.testing.expectEqual(@as(i32, 11), result.value);
}
