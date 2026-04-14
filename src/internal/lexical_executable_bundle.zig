const effect_schema = @import("../effect_schema.zig");
const std = @import("std");

fn bindingFamily(comptime BindingSchema: type) type {
    if (@hasDecl(BindingSchema, "family")) return BindingSchema.family;
    if (@hasDecl(BindingSchema, "Family")) return BindingSchema.Family;
    @compileError("binding schema must expose family metadata");
}

fn bindingLifecycle(comptime DescriptorType: type, comptime requirement_label: [:0]const u8) effect_schema.LifecycleTag {
    return bindingFamily(DescriptorType.BindingSchema(requirement_label)).lifecycle_tag;
}

fn outputType(comptime DescriptorType: type, comptime requirement_label: [:0]const u8) type {
    return bindingFamily(DescriptorType.BindingSchema(requirement_label)).Output;
}

fn policyType(comptime DescriptorType: type, comptime requirement_label: [:0]const u8) type {
    return bindingFamily(DescriptorType.BindingSchema(requirement_label)).Policy;
}

fn catchType(comptime DescriptorType: type, comptime requirement_label: [:0]const u8) type {
    return bindingFamily(DescriptorType.BindingSchema(requirement_label)).Catch;
}

fn managerType(comptime DescriptorType: type, comptime requirement_label: [:0]const u8) type {
    return bindingFamily(DescriptorType.BindingSchema(requirement_label)).Manager;
}

fn writerItemType(comptime DescriptorType: type, comptime requirement_label: [:0]const u8) type {
    return bindingFamily(DescriptorType.BindingSchema(requirement_label)).Item;
}

fn stateFieldType(comptime DescriptorType: type) type {
    return DescriptorType.State;
}

fn descriptorFieldType(comptime DescriptorType: type) type {
    return if (@hasField(DescriptorType, "handler")) @FieldType(DescriptorType, "handler") else DescriptorType;
}

fn StateHandler(comptime StateType: type) type {
    return struct {
        value: StateType,

        pub fn get(self: *@This()) StateType {
            return self.value;
        }

        pub fn set(self: *@This(), value: StateType) void {
            self.value = value;
        }

        pub fn finish(self: *@This()) StateType {
            return self.value;
        }
    };
}

fn ReaderHandler(comptime StateType: type) type {
    return struct {
        environment: StateType,

        pub fn ask(self: *@This()) StateType {
            return self.environment;
        }
    };
}

fn WriterAccumulator(comptime ItemType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        first_item: ?ItemType = null,
        items: std.ArrayList(ItemType) = .empty,
        finished: bool = false,

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{ .allocator = allocator };
        }

        pub fn tell(self: *@This(), item: ItemType) std.mem.Allocator.Error!void {
            if (self.first_item == null and self.items.items.len == 0) {
                self.first_item = item;
                return;
            }
            if (self.items.items.len == 0) {
                try self.items.ensureTotalCapacity(self.allocator, 2);
                self.items.appendAssumeCapacity(self.first_item.?);
                self.first_item = null;
            }
            try self.items.append(self.allocator, item);
        }

        pub fn finish(self: *@This()) ![]ItemType {
            if (self.finished) return error.ProgramContractViolation;
            self.finished = true;
            if (self.items.items.len != 0) return try self.items.toOwnedSlice(self.allocator);
            if (self.first_item) |item| {
                const slice = try self.allocator.alloc(ItemType, 1);
                slice[0] = item;
                self.first_item = null;
                return slice;
            }
            return try self.allocator.alloc(ItemType, 0);
        }

        pub fn deinit(self: *@This()) void {
            if (self.finished) return;
            self.items.deinit(self.allocator);
        }
    };
}

fn OptionalHandler(comptime Policy: type) type {
    return struct {
        pub fn request(_: *@This()) @typeInfo(@TypeOf(Policy.resumeOrReturn)).@"fn".return_type.? {
            return Policy.resumeOrReturn();
        }

        pub fn afterRequest(_: *@This(), answer: anytype) @TypeOf(Policy.afterResume(answer)) {
            return Policy.afterResume(answer);
        }
    };
}

fn callableReturnType(comptime callable: anytype) type {
    return switch (@typeInfo(@TypeOf(callable))) {
        .@"fn" => @typeInfo(@TypeOf(callable)).@"fn".return_type.?,
        .pointer => |pointer| switch (@typeInfo(pointer.child)) {
            .@"fn" => @typeInfo(pointer.child).@"fn".return_type.?,
            else => @compileError("callable return type helper requires a function"),
        },
        else => @compileError("callable return type helper requires a function"),
    };
}

fn ExceptionHandler(comptime Catch: type, comptime PayloadType: type) type {
    return struct {
        pub fn throw(_: *@This(), payload: PayloadType) callableReturnType(Catch.directReturn) {
            return Catch.directReturn(payload);
        }
    };
}

fn ResourceHandler(comptime Manager: type, comptime ResourceType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        resources: std.ArrayList(ResourceType) = .empty,
        cleaned: bool = false,

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{ .allocator = allocator };
        }

        pub fn acquire(self: *@This()) !ResourceType {
            const resource = if (@TypeOf(Manager.acquire) == fn () ResourceType)
                Manager.acquire()
            else
                try Manager.acquire();
            try self.resources.append(self.allocator, resource);
            return resource;
        }

        pub fn deinit(self: *@This()) !void {
            if (self.cleaned) return;
            self.cleaned = true;
            var first_error: ?anyerror = null;
            while (self.resources.items.len != 0) {
                const resource = self.resources.items[self.resources.items.len - 1];
                self.resources.items.len -= 1;
                if (@TypeOf(Manager.release) == fn (ResourceType) void) {
                    Manager.release(resource);
                } else {
                    Manager.release(resource) catch |err| {
                        if (first_error == null) first_error = err;
                    };
                }
            }
            self.resources.deinit(self.allocator);
            if (first_error) |err| return err;
        }
    };
}

fn ExecutableFieldType(comptime DescriptorType: type, comptime requirement_label: [:0]const u8) type {
    return switch (bindingLifecycle(DescriptorType, requirement_label)) {
        .state_cell => StateHandler(stateFieldType(DescriptorType)),
        .reader_environment => ReaderHandler(stateFieldType(DescriptorType)),
        .writer_accumulator => WriterAccumulator(writerItemType(DescriptorType, requirement_label)),
        .choice_policy => OptionalHandler(policyType(DescriptorType, requirement_label)),
        .abort_catch => ExceptionHandler(catchType(DescriptorType, requirement_label), stateFieldType(DescriptorType)),
        .resource_bracket => ResourceHandler(managerType(DescriptorType, requirement_label), stateFieldType(DescriptorType)),
        .generated_family => descriptorFieldType(DescriptorType),
        else => @compileError("unsupported lexical executable bundle lifecycle"),
    };
}

fn initField(comptime DescriptorType: type, comptime requirement_label: [:0]const u8, descriptor: DescriptorType, runtime_allocator: std.mem.Allocator) ExecutableFieldType(DescriptorType, requirement_label) {
    const lifecycle = comptime bindingLifecycle(DescriptorType, requirement_label);
    if (lifecycle == .state_cell) {
        return .{ .value = descriptor.initial_state };
    }
    if (lifecycle == .reader_environment) {
        return .{ .environment = descriptor.environment };
    }
    if (lifecycle == .writer_accumulator) {
        return ExecutableFieldType(DescriptorType, requirement_label).init(descriptor.allocator);
    }
    if (lifecycle == .choice_policy) {
        return .{};
    }
    if (lifecycle == .abort_catch) {
        return .{};
    }
    if (lifecycle == .resource_bracket) {
        return ExecutableFieldType(DescriptorType, requirement_label).init(runtime_allocator);
    }
    if (lifecycle == .generated_family) {
        return descriptor.handler;
    }
    unreachable;
}

pub fn BundleType(comptime HandlersType: type) type {
    const fields = @typeInfo(HandlersType).@"struct".fields;
    var bundle_fields: [fields.len]std.builtin.Type.StructField = undefined;
    inline for (fields, 0..) |field, index| {
        bundle_fields[index] = .{
            .name = field.name,
            .type = ExecutableFieldType(field.type, field.name),
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(ExecutableFieldType(field.type, field.name)),
        };
    }
    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &bundle_fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

pub fn fromLexicalState(lexical_state: anytype) BundleType(std.meta.Child(@TypeOf(lexical_state.handlers_ptr))) {
    const HandlersType = std.meta.Child(@TypeOf(lexical_state.handlers_ptr));
    var bundle: BundleType(HandlersType) = undefined;
    inline for (@typeInfo(HandlersType).@"struct".fields) |field| {
        @field(bundle, field.name) = initField(field.type, field.name, @field(lexical_state.handlers_ptr.*, field.name), lexical_state.runtime.allocator);
    }
    return bundle;
}

pub fn deinit(bundle_ptr: anytype) !void {
    const Bundle = std.meta.Child(@TypeOf(bundle_ptr));
    inline for (std.meta.fields(Bundle)) |field| {
        if (@hasDecl(field.type, "deinit")) {
            const result = @field(bundle_ptr.*, field.name).deinit();
            if (@typeInfo(@TypeOf(result)) == .error_union) {
                try result;
            }
        }
    }
}

test "state executable bundle wrapper mutates and finishes" {
    const state = @import("../effect/state.zig");
    const Handlers = struct {
        state: state.LexicalDescriptor(i32, error{}),
    };
    var runtime = @import("lowered_machine").Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var handlers: Handlers = .{ .state = state.use(@as(i32, 4)) };
    const lexical_state = struct {
        runtime: *@import("lowered_machine").Runtime,
        handlers_ptr: *Handlers,
    }{ .runtime = &runtime, .handlers_ptr = &handlers };
    var bundle = fromLexicalState(lexical_state);
    try std.testing.expectEqual(@as(i32, 4), bundle.state.get());
    bundle.state.set(9);
    try std.testing.expectEqual(@as(i32, 9), bundle.state.finish());
}
