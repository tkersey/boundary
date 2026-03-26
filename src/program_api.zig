const decision_api = @import("decision_api.zig");
const lowered_machine = @import("lowered_machine");
const family_builder = @import("internal/family_builder.zig");
const manifest_api = @import("internal/program_manifest.zig");
const op_api = @import("op_api.zig");
const program_runtime = @import("internal/program_runtime.zig");
const std = @import("std");

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

pub const Decision = decision_api.Decision;

pub const ops = struct {
    pub const transform = op_api.Transform;
    pub const choice = op_api.Choice;
    pub const abort = op_api.Abort;
};

fn StateDeclType(comptime StateType: type) type {
    return struct {
        pub const kind = DeclarationKind.state;
        pub const Value = StateType;
    };
}

fn ReaderDeclType(comptime EnvType: type) type {
    return struct {
        pub const kind = DeclarationKind.reader;
        pub const Value = EnvType;
    };
}

fn OptionalDeclType(comptime ResumeType: type, comptime PolicyType: type) type {
    return struct {
        pub const kind = DeclarationKind.optional;
        pub const Resume = ResumeType;
        pub const Policy = PolicyType;
    };
}

fn ExceptionDeclType(comptime PayloadType: type, comptime CatchType: type) type {
    return struct {
        pub const kind = DeclarationKind.exception;
        pub const Payload = PayloadType;
        pub const Catch = CatchType;
    };
}

fn ResourceDeclType(comptime ResourceType: type, comptime ManagerType: type) type {
    return struct {
        pub const kind = DeclarationKind.resource;
        pub const Resource = ResourceType;
        pub const Manager = ManagerType;
    };
}

fn WriterDeclType(comptime ItemType: type) type {
    return struct {
        pub const kind = DeclarationKind.writer;
        pub const Item = ItemType;
    };
}

fn FamilyDeclType(comptime spec: anytype, comptime HandlerType: type) type {
    const generated_family = family_builder.Build(spec);
    return struct {
        pub const kind = DeclarationKind.family;
        pub const generated = generated_family;
        pub const Handler = HandlerType;
    };
}

pub const decl = struct {
    pub fn state(comptime StateType: type) StateDeclType(StateType) {
        return .{};
    }

    pub fn reader(comptime EnvType: type) ReaderDeclType(EnvType) {
        return .{};
    }

    pub fn optional(comptime ResumeType: type, comptime PolicyType: type) OptionalDeclType(ResumeType, PolicyType) {
        return .{};
    }

    pub fn exception(comptime PayloadType: type, comptime CatchType: type) ExceptionDeclType(PayloadType, CatchType) {
        return .{};
    }

    pub fn resource(comptime ResourceType: type, comptime ManagerType: type) ResourceDeclType(ResourceType, ManagerType) {
        return .{};
    }

    pub fn writer(comptime ItemType: type) WriterDeclType(ItemType) {
        return .{};
    }

    pub fn family(comptime spec: anytype, comptime HandlerType: type) FamilyDeclType(spec, HandlerType) {
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
        .family => DeclType.generated.definition.mode == .resume_then_transform,
    };
}

fn BindingFieldType(comptime DeclType: type) type {
    return switch (DeclType.kind) {
        .state, .reader => DeclType.Value,
        .family => DeclType.Handler,
        else => unreachable,
    };
}

fn HandlerFieldType(comptime DeclType: type) type {
    return switch (DeclType.kind) {
        .state => @import("effect/state.zig").LexicalDescriptor(DeclType.Value, error{}),
        .reader => @import("effect/reader.zig").LexicalDescriptor(DeclType.Value, error{}),
        .optional => @TypeOf(@import("effect/optional.zig").use(DeclType.Resume, DeclType.Policy)),
        .exception => @TypeOf(@import("effect/exception.zig").use(DeclType.Payload, DeclType.Catch)),
        .resource => @TypeOf(@import("effect/resource.zig").use(DeclType.Resource, DeclType.Manager)),
        .writer => @import("effect/writer.zig").LexicalDescriptor(DeclType.Item, error{}),
        .family => @TypeOf(DeclType.generated.use(.{ .handler = @as(DeclType.Handler, undefined) })),
    };
}

fn HandlerBundleType(comptime DeclarationsType: type) type {
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
            .type = HandlerFieldType(field.type),
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(HandlerFieldType(field.type)),
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

fn BindingsType(comptime DeclarationsType: type) type {
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
        const BindingType = BindingFieldType(field.type);
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
) HandlerBundleType(@TypeOf(ProgramType.declarations)) {
    const Bundle = HandlerBundleType(@TypeOf(ProgramType.declarations));
    var bundle: Bundle = undefined;
    const fields = @typeInfo(@TypeOf(ProgramType.declarations)).@"struct".fields;

    inline for (fields) |field| {
        const DeclType = field.type;
        const value = switch (DeclType.kind) {
            .state => @import("effect/state.zig").use(@field(bindings, field.name)),
            .reader => @import("effect/reader.zig").use(@field(bindings, field.name)),
            .optional => @import("effect/optional.zig").use(DeclType.Resume, DeclType.Policy),
            .exception => @import("effect/exception.zig").use(DeclType.Payload, DeclType.Catch),
            .resource => @import("effect/resource.zig").use(DeclType.Resource, DeclType.Manager),
            .writer => @import("effect/writer.zig").use(DeclType.Item, runtime.allocator),
            .family => DeclType.generated.use(.{ .handler = @field(bindings, field.name) }),
        };
        @field(bundle, field.name) = value;
    }

    return bundle;
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
        pub const Bindings = BindingsType(DeclarationsType);
        pub const internal_manifest = manifest_api.Build(DeclarationKind, declaration_values, hasBinding, hasOutput);
        pub const declarations = declaration_values;

        pub fn run(runtime: *lowered_machine.Runtime, bindings: Bindings) RunReturnType(@This()) {
            return programRun(runtime, @This(), bindings);
        }
    };
}

pub fn RunReturnType(comptime ProgramType: type) type {
    return program_runtime.RunReturnType(HandlerBundleType(@TypeOf(ProgramType.declarations)), ProgramType.Body);
}

fn programRun(runtime: *lowered_machine.Runtime, comptime ProgramType: type, bindings: ProgramType.Bindings) RunReturnType(ProgramType) {
    const handlers = buildHandlers(ProgramType, runtime, bindings);
    return program_runtime.run(runtime, handlers, ProgramType.Body);
}

pub fn run(runtime: *lowered_machine.Runtime, comptime ProgramType: type, bindings: ProgramType.Bindings) RunReturnType(ProgramType) {
    return programRun(runtime, ProgramType, bindings);
}

test "program manifest records declaration metadata and outputs" {
    const Counter = decl.family(.{
        .state_type = i32,
        .ops = .{
            ops.transform("get", void, i32),
            ops.transform("set", i32, void),
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

    const demo_program = Program(.{
        .state = decl.state(i32),
        .reader = decl.reader(i32),
        .counter = Counter,
        .writer = decl.writer([]const u8),
    }, struct {
        pub fn body(_: anytype) i32 {
            return 0;
        }
    });

    const Manifest = manifest_api.Of(demo_program);
    try std.testing.expectEqual(@as(usize, 4), Manifest.declaration_count);
    try std.testing.expectEqualStrings("state", Manifest.entries[0].name);
    try std.testing.expectEqualStrings("state", Manifest.entries[0].kind);
    try std.testing.expect(Manifest.entries[0].has_binding);
    try std.testing.expect(Manifest.entries[0].has_output);
    try std.testing.expectEqualStrings("family", Manifest.entries[2].kind);
    try std.testing.expectEqual(@as(usize, 2), Manifest.entries[2].op_count);
    try std.testing.expectEqual(@as(usize, 3), Manifest.outputs.len);
    try std.testing.expectEqualStrings("counter", Manifest.outputs[1]);
}

test "program run executes through the new front door" {
    const demo_program = Program(.{
        .state = decl.state(i32),
    }, struct {
        pub fn body(eff: anytype) !i32 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            return before + (try eff.state.get());
        }
    });

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try run(&runtime, demo_program, .{ .state = 5 });
    try std.testing.expectEqual(@as(i32, 6), result.outputs.state);
    try std.testing.expectEqual(@as(i32, 11), result.value);
}
