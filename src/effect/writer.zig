const algebraic = @import("algebraic.zig");
const effect_schema = @import("../effect_schema.zig");
const family = @import("family.zig");
const lexical_with = @import("../with_api.zig");
const lowered_machine = @import("lowered_machine");
const shift = lowered_machine;
const std = @import("std");

fn WriterState(comptime ItemType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        first_item: ?ItemType = null,
        items: std.ArrayList(ItemType) = .empty,

        /// Build one empty writer state backed by the supplied allocator.
        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{ .allocator = allocator };
        }

        /// Release any storage retained by the writer state.
        pub fn deinit(self: *@This()) void {
            self.items.deinit(self.allocator);
        }

        /// Append one item into the writer log state.
        pub fn append(self: *@This(), item: ItemType) std.mem.Allocator.Error!void {
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

        /// Materialize the accumulated writer log as an owned slice.
        pub fn intoOwnedSlice(self: *@This()) ![]ItemType {
            if (self.items.items.len != 0) {
                return try self.items.toOwnedSlice(self.allocator);
            }

            if (self.first_item) |item| {
                const slice = try self.allocator.alloc(ItemType, 1);
                slice[0] = item;
                self.first_item = null;
                return slice;
            }

            return try self.allocator.alloc(ItemType, 0);
        }
    };
}

/// Prompt-backed effect instance for an append-only writer family.
pub fn Instance(comptime ItemType: type, comptime ErrorSetType: type) type {
    return family.Instance(WriterState(ItemType), ErrorSetType);
}

/// Final writer log plus body answer returned from a handled writer program.
pub fn HandleResult(comptime ItemType: type, comptime ValueType: type) type {
    return struct {
        items: []ItemType,
        value: ValueType,
    };
}

const HandleWithErrorSetTypes = struct {
    Item: type,
    Answer: type,
    ErrorSet: type,
};

/// Lexical writer handle used by `shift.withAt(@src(), ...)`.
pub fn LexicalHandle(comptime Cap: type, comptime ContextPtrType: type, comptime ItemType: type) type {
    return struct {
        ctx: ?ContextPtrType,

        /// Append one item through the lexical writer handle.
        pub fn tell(self: @This(), item: ItemType) lowered_machine.ResetError(family.ContextErrorSetType(ContextPtrType))!void {
            try algebraic.writerTell(Cap, self.ctx.?, item);
        }
    };
}

/// Descriptor value used by `shift.withAt(@src(), ...)` for the built-in writer family.
pub fn LexicalDescriptor(comptime ItemType: type, comptime ErrorSetType: type) type {
    return struct {
        /// Shared error set carried by the lexical writer descriptor.
        pub const ErrorSet = ErrorSetType;
        /// Preview-only state placeholder for lexical writer contexts.
        pub const State = void;
        /// Final writer log output produced by the lexical writer descriptor.
        pub const Output = []ItemType;

        allocator: std.mem.Allocator,

        /// Resolve the lexical writer handle type for one exact context.
        pub fn HandleType(comptime Cap: type, comptime ContextPtrType: type) type {
            return LexicalHandle(Cap, ContextPtrType, ItemType);
        }

        /// Bind one lexical writer handle to the active exact context.
        pub fn bindLexical(self: @This(), comptime Cap: type, ctx: anytype) HandleType(Cap, @TypeOf(ctx)) {
            _ = self;
            return .{ .ctx = ctx };
        }

        /// Return the shared binding schema for this lexical descriptor under one requirement label.
        pub fn BindingSchema(comptime requirement_label: [:0]const u8) type {
            return effect_schema.Binding(requirement_label, Schema(ItemType, ErrorSetType), struct {});
        }

        /// Run one lexical writer descriptor through the existing writer family.
        pub fn run(self: @This(), comptime AnswerType: type, comptime RunErrorSetType: type, run_ctx: anytype, comptime Body: type) lowered_machine.ResetError(RunErrorSetType)!lexical_with.DescriptorResult(Output, AnswerType) {
            var instance = family.Instance(WriterState(ItemType), ErrorSetType).init();
            const writer_contract = struct {
                /// Item type carried by this lexical writer helper.
                pub const Item = ItemType;
                /// Answer type carried by this lexical writer helper.
                pub const Answer = AnswerType;
                /// Writer state type carried by this lexical writer helper.
                pub const WriterStateType = WriterState(ItemType);
            };
            const result = try algebraic.handleWriterWithErrorSetLexicalAt(writer_contract, RunErrorSetType, @TypeOf(run_ctx).caller_source, .{
                .runtime = run_ctx.runtime,
                .instance = &instance,
                .allocator = self.allocator,
                .lexical_state = @constCast(run_ctx.lexical_state),
            }, Body);
            return .{
                .output = result.items,
                .value = result.value,
            };
        }
    };
}

/// Create one lexical writer descriptor for `shift.withAt(@src(), ...)`.
pub fn use(comptime ItemType: type, allocator: std.mem.Allocator) LexicalDescriptor(ItemType, error{}) {
    return .{ .allocator = allocator };
}

/// Shared effect schema for the built-in writer family.
pub fn Schema(comptime ItemType: type, comptime ErrorSetType: type) type {
    return effect_schema.writer_accumulator(ItemType, ErrorSetType);
}

/// Append one item to the current writer log.
pub inline fn tell(
    comptime Cap: type,
    ctx: anytype,
    item: anytype,
) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!void {
    return try algebraic.writerTell(Cap, ctx, item);
}

/// Build one explicit writer body program with no prompt operation.
pub inline fn computeProgram(
    comptime Cap: type,
    ctx: anytype,
    comptime Thunk: type,
) @TypeOf(family.computeProgram(Cap, ctx, Thunk)) {
    return family.computeProgram(Cap, ctx, Thunk);
}

/// Run a writer effect body and return the accumulated log plus the body answer.
// zlinter-disable max_positional_args - public caller provenance and writer inputs stay explicit at this compatibility wrapper.
pub inline fn handle(
    comptime ItemType: type,
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    allocator: std.mem.Allocator,
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!HandleResult(ItemType, AnswerType) {
    return try handleAt(@src(), ItemType, AnswerType, runtime, instance, allocator, Body);
}

/// Run a writer effect body with explicit caller provenance and return the accumulated log plus the body answer.
// zlinter-disable max_positional_args - public caller provenance and writer inputs stay explicit at this compatibility wrapper.
pub fn handleAt(
    comptime caller_source: std.builtin.SourceLocation,
    comptime ItemType: type,
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    allocator: std.mem.Allocator,
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!HandleResult(ItemType, AnswerType) {
    const item_type = ItemType;
    const answer_type = AnswerType;
    const result = try algebraic.handleWriter(caller_source, struct {
        /// Item type threaded through the shared writer engine adapter.
        pub const Item = item_type;
        /// Final answer type threaded through the shared writer engine adapter.
        pub const Answer = answer_type;
        /// Exact writer state type used by the shared writer engine adapter.
        pub const WriterStateType = WriterState(item_type);
    }, runtime, instance, allocator, Body);
    return .{
        .items = result.items,
        .value = result.value,
    };
}

/// Public `handleWithErrorSet` helper.
pub inline fn handleWithErrorSet(
    comptime Types: HandleWithErrorSetTypes,
    runtime: *shift.Runtime,
    instance: anytype,
    allocator: std.mem.Allocator,
    comptime Body: type,
) lowered_machine.ResetError(Types.ErrorSet)!HandleResult(Types.Item, Types.Answer) {
    return try handleWithErrorSetAt(@src(), Types, runtime, instance, allocator, Body);
}

/// Public `handleWithErrorSetAt` helper.
pub fn handleWithErrorSetAt(
    comptime caller_source: std.builtin.SourceLocation,
    comptime Types: HandleWithErrorSetTypes,
    runtime: *shift.Runtime,
    instance: anytype,
    allocator: std.mem.Allocator,
    comptime Body: type,
) lowered_machine.ResetError(Types.ErrorSet)!HandleResult(Types.Item, Types.Answer) {
    const ItemType = Types.Item;
    const AnswerType = Types.Answer;
    const result = try algebraic.handleWriterWithErrorSet(caller_source, struct {
        /// Public `Item` declaration.
        pub const Item = ItemType;
        /// Public `Answer` declaration.
        pub const Answer = AnswerType;
        /// Public `WriterStateType` declaration.
        pub const WriterStateType = WriterState(ItemType);
    }, Types.ErrorSet, runtime, instance, allocator, Body);
    return .{
        .items = result.items,
        .value = result.value,
    };
}

test "writer instance shell stays prompt-sized" {
    const WriterInstance = Instance([]const u8, error{});
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(WriterInstance));
}

test "writer handle accumulates items in order" {
    const NoError = error{};
    const WriterInstance = Instance([]const u8, NoError);
    const demo = struct {
        /// Append two items and then return normally.
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(family.computeProgram(Cap, ctx, struct {
            /// Append two items and then return normally.
            pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
                try tell(ProgramCap, program_ctx, "a");
                try tell(ProgramCap, program_ctx, "b");
                return "done";
            }
        })) {
            return family.computeProgram(Cap, ctx, struct {
                /// Append two items and then return normally.
                pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
                    try tell(ProgramCap, program_ctx, "a");
                    try tell(ProgramCap, program_ctx, "b");
                    return "done";
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = WriterInstance.init();
    const result = try handleAt(@src(), []const u8, []const u8, &runtime, &instance, std.testing.allocator, demo);
    defer std.testing.allocator.free(result.items);
    try std.testing.expectEqual(@as(usize, 2), result.items.len);
    try std.testing.expectEqualStrings("a", result.items[0]);
    try std.testing.expectEqualStrings("b", result.items[1]);
    try std.testing.expectEqualStrings("done", result.value);
}

test "public writer handleWithErrorSet preserves caller provenance" {
    const NoError = error{};
    const WriterInstance = Instance([]const u8, NoError);

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = WriterInstance.init();

    const result = try handleWithErrorSet(.{
        .Item = []const u8,
        .Answer = []const u8,
        .ErrorSet = NoError,
    }, &runtime, &instance, std.testing.allocator, struct {
        /// Return the exact caller-owned source file observed through the public writer wrapper.
        pub fn body(comptime Cap: type, ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
            _ = Cap;
            return @TypeOf(ctx.*).caller_source.?.file;
        }
    });
    defer std.testing.allocator.free(result.items);

    try std.testing.expectEqual(@as(usize, 0), result.items.len);
    try std.testing.expectEqualStrings(@src().file, result.value);
}

test "public writer handle preserves caller provenance" {
    const NoError = error{};
    const WriterInstance = Instance([]const u8, NoError);

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = WriterInstance.init();

    const result = try handle([]const u8, []const u8, &runtime, &instance, std.testing.allocator, struct {
        /// Return the exact caller-owned source file observed through the public writer wrapper.
        pub fn body(comptime Cap: type, ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
            _ = Cap;
            return @TypeOf(ctx.*).caller_source.?.file;
        }
    });
    defer std.testing.allocator.free(result.items);

    try std.testing.expectEqual(@as(usize, 0), result.items.len);
    try std.testing.expectEqualStrings(@src().file, result.value);
}

test "nested same-shaped writer handles get distinct capability types" {
    const NoError = error{};
    const WriterInstance = Instance([]const u8, NoError);
    const demo = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var inner_ptr: ?*const WriterInstance = null;

        /// Open an inner writer handle and prove its capability differs from the outer one.
        pub fn outer(comptime OuterCap: type, _: anytype) lowered_machine.ResetError(NoError)![]const u8 {
            const result = try handleAt(@src(), []const u8, []const u8, runtime_ptr.?, inner_ptr.?, std.testing.allocator, struct {
                /// Reject capability-type collapse inside the nested writer handle.
                pub fn program(comptime InnerCap: type, inner_ctx: anytype) @TypeOf(family.computeProgram(InnerCap, inner_ctx, struct {
                    /// Return a neutral value from the nested writer body.
                    pub fn run(_: type, _: anytype) []const u8 {
                        return "done";
                    }
                })) {
                    comptime if (OuterCap == InnerCap) {
                        @compileError("nested writer handles must receive distinct capability types");
                    };
                    return family.computeProgram(InnerCap, inner_ctx, struct {
                        /// Return a neutral value from the nested writer body.
                        pub fn run(_: type, _: anytype) []const u8 {
                            return "done";
                        }
                    });
                }
            });
            defer std.testing.allocator.free(result.items);
            return result.value;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var outer_instance = WriterInstance.init();
    var inner_instance = WriterInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    const result = try handleAt(@src(), []const u8, []const u8, &runtime, &outer_instance, std.testing.allocator, struct {
        /// Enter the outer writer handle and hand its capability inward.
        pub fn program(comptime OuterCap: type, ctx: anytype) @TypeOf(family.computeProgram(OuterCap, ctx, struct {
            /// Re-enter the nested writer witness through the outer capability.
            pub fn run(_: type, _: anytype) lowered_machine.ResetError(NoError)![]const u8 {
                return try demo.outer(OuterCap, {});
            }
        })) {
            return family.computeProgram(OuterCap, ctx, struct {
                /// Re-enter the nested writer witness through the outer capability.
                pub fn run(_: type, _: anytype) lowered_machine.ResetError(NoError)![]const u8 {
                    return try demo.outer(OuterCap, {});
                }
            });
        }
    });
    defer std.testing.allocator.free(result.items);
    try std.testing.expectEqualStrings("done", result.value);
}
