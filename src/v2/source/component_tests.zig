const std = @import("std");
const source = @import("../source.zig");
const data = @import("boundary_data_v2");
const testing = std.testing;

fn object(provider: bool, boolean: bool) ![]u8 {
    var b = source.Builder.init(testing.allocator);
    defer b.deinit();
    const unit = try b.scalar(void);
    const result = if (boolean) try b.scalar(bool) else try b.scalar(u64);
    const effect = try b.effect(.{ .identity = "component/read", .payload = unit, .result = result });
    const read = try b.declare(&.{}, result, &.{effect}, &.{});
    const main = if (provider) read else try b.declare(&.{}, result, &.{effect}, &.{});
    if (provider) try b.define(read, try b.term(.{ .perform = .{ .effect = effect, .payload = try b.constant(void, {}) } })) else try b.define(main, try b.term(.{ .call = .{ .function = read, .arguments = &.{} } }));
    const symbols = [_]data.component.Symbol{
        .{ .name = "read", .reference = .{ .kind = .effect, .id = effect } },
        .{ .name = "value", .reference = .{ .kind = .function, .id = read } },
    };
    var compiled = try source.component.compile(testing.allocator, b.module(main, unit), .{
        .imports = if (provider) &.{} else &symbols,
        .exports = if (provider) &symbols else &.{.{ .name = "main", .reference = .{ .kind = .function, .id = main } }},
    });
    defer compiled.deinit();
    const bytes = try testing.allocator.alloc(u8, try data.component.encodedLength(compiled.object));
    errdefer testing.allocator.free(bytes);
    _ = try compiled.encode(testing.allocator, bytes);
    return bytes;
}
const bindings = [_]data.linker.Binding{
    .{ .required = .{ .instance = "client", .symbol = "read" }, .supplied = .{ .instance = "library", .symbol = "read" } },
    .{ .required = .{ .instance = "client", .symbol = "value" }, .supplied = .{ .instance = "library", .symbol = "value" } },
};

test "BMO1 links effectful bodies after source owners are gone and ignores instance enumeration order" {
    const provider = try object(true, false);
    defer testing.allocator.free(provider);
    const client = try object(false, false);
    defer testing.allocator.free(client);
    var decoded = try data.component.decode(testing.allocator, client);
    defer decoded.deinit();
    try testing.expectEqual(data.relocation.missing, decoded.object.program.functions[0].entry);
    var output: [8192]u8 = undefined;
    try testing.expectError(error.InvalidReference, data.program_image.encode(testing.allocator, decoded.object.program, &output));
    const instances = [_]data.linker.Instance{ .{ .key = "library", .object = provider }, .{ .key = "client", .object = client } };
    var first = try data.linker.link(testing.allocator, &instances, &bindings, .{ .instance = "client", .symbol = "main" });
    defer first.deinit();
    const reversed = [_]data.linker.Instance{ instances[1], instances[0] };
    const reordered = [_]data.linker.Binding{ bindings[1], bindings[0] };
    var second = try data.linker.link(testing.allocator, &reversed, &reordered, .{ .instance = "client", .symbol = "main" });
    defer second.deinit();
    try testing.expectEqual(try data.program_image.identity(testing.allocator, first.program), try data.program_image.identity(testing.allocator, second.program));
    try testing.expectEqual(1, first.program.effects.len);
    try testing.expectEqual(2, first.program.functions.len);
    @memset(provider, 0xff);
    @memset(client, 0xff);
    _ = try first.encode(testing.allocator, &output);
}

test "public linker rejects missing duplicate wrong-kind and incompatible effect imports" {
    const provider = try object(true, false);
    defer testing.allocator.free(provider);
    const client = try object(false, false);
    defer testing.allocator.free(client);
    const incompatible = try object(true, true);
    defer testing.allocator.free(incompatible);
    const instances = [_]data.linker.Instance{ .{ .key = "library", .object = provider }, .{ .key = "client", .object = client } };
    try testing.expectError(error.UnresolvedImport, data.linker.link(testing.allocator, &instances, &.{}, .{ .instance = "client", .symbol = "main" }));
    try testing.expectError(error.DuplicateBinding, data.linker.link(testing.allocator, &instances, &.{ bindings[0], bindings[0], bindings[1] }, .{ .instance = "client", .symbol = "main" }));
    var wrong = bindings;
    wrong[0].supplied.symbol = "value";
    try testing.expectError(error.IncompatibleInterface, data.linker.link(testing.allocator, &instances, &wrong, .{ .instance = "client", .symbol = "main" }));
    var different = instances;
    different[0].object = incompatible;
    try testing.expectError(error.IncompatibleInterface, data.linker.link(testing.allocator, &different, &bindings, .{ .instance = "client", .symbol = "main" }));
}

test "same-named private declarations remain distinct across explicit component instances" {
    const bytes = try object(true, false);
    defer testing.allocator.free(bytes);
    var linked = try data.linker.link(testing.allocator, &.{ .{ .key = "one", .object = bytes }, .{ .key = "two", .object = bytes } }, &.{}, .{ .instance = "one", .symbol = "value" });
    defer linked.deinit();
    try testing.expectEqual(2, linked.program.effects.len);
    try testing.expectEqualStrings(linked.program.effects[0].identity, linked.program.effects[1].identity);
    try testing.expectEqual(2, linked.program.schemas.len);
}

test "three effectful components link without retaining source and also serve a second wrapper" {
    const examples = source.component_examples;
    const call = try examples.emit(testing.allocator, .call);
    defer testing.allocator.free(call);
    const state = try examples.emit(testing.allocator, .state);
    defer testing.allocator.free(state);
    const suspended = try examples.emit(testing.allocator, .suspended);
    defer testing.allocator.free(suspended);
    const double = try examples.emit(testing.allocator, .double);
    defer testing.allocator.free(double);
    const instances = [_]data.linker.Instance{ .{ .key = "call", .object = call }, .{ .key = "state", .object = state }, .{ .key = "suspend", .object = suspended }, .{ .key = "double", .object = double } };
    var first = try data.linker.link(testing.allocator, instances[0..3], &examples.bindings, .{ .instance = "suspend", .symbol = "main" });
    defer first.deinit();
    var second = try data.linker.link(testing.allocator, &instances, &examples.double_bindings, .{ .instance = "double", .symbol = "main" });
    defer second.deinit();
    try testing.expect(!std.mem.eql(u8, &try data.program_image.identity(testing.allocator, first.program), &try data.program_image.identity(testing.allocator, second.program)));
}

fn capturedFactory(provider: bool, weakened: bool) ![]u8 {
    var b = source.Builder.init(testing.allocator);
    defer b.deinit();
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const callable = try b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{},
        .result = integer,
        .effects = &.{},
        .capture_bound = if (weakened) &.{} else &.{integer},
    } } });
    const factory = try b.declare(&.{}, callable, &.{}, &.{});
    const main = if (provider) factory else try b.declare(&.{}, integer, &.{}, &.{});
    if (provider) {
        const value = try b.variable(integer);
        const body = try b.declare(&.{}, integer, &.{}, &.{});
        try b.define(body, try b.pure(try b.reference(value)));
        try b.define(factory, try b.bind(value, try b.pure(try b.constant(u64, 41)), try b.pure(try b.lambda(body, callable))));
    } else {
        const value = try b.variable(callable);
        try b.define(main, try b.bind(value, try b.term(.{ .call = .{ .function = factory, .arguments = &.{} } }), try b.term(.{ .apply = .{ .computation = try b.reference(value), .arguments = &.{} } })));
    }
    const symbol: data.component.Symbol = .{ .name = "factory", .reference = .{ .kind = .function, .id = factory } };
    var compiled = try source.component.compile(testing.allocator, b.module(main, unit), .{
        .imports = if (provider) &.{} else &.{symbol},
        .exports = if (provider) &.{symbol} else &.{.{ .name = "main", .reference = .{ .kind = .function, .id = main } }},
    });
    defer compiled.deinit();
    const bytes = try testing.allocator.alloc(u8, try data.component.encodedLength(compiled.object));
    errdefer testing.allocator.free(bytes);
    _ = try compiled.encode(testing.allocator, bytes);
    return bytes;
}

test "public linker rejects a falsely weakened callable capture bound" {
    const provider = try capturedFactory(true, false);
    defer testing.allocator.free(provider);
    const client = try capturedFactory(false, false);
    defer testing.allocator.free(client);
    const weakened = try capturedFactory(false, true);
    defer testing.allocator.free(weakened);
    var instances = [_]data.linker.Instance{ .{ .key = "provider", .object = provider }, .{ .key = "client", .object = client } };
    const binding = [_]data.linker.Binding{.{ .required = .{ .instance = "client", .symbol = "factory" }, .supplied = .{ .instance = "provider", .symbol = "factory" } }};
    var valid = try data.linker.link(testing.allocator, &instances, &binding, .{ .instance = "client", .symbol = "main" });
    defer valid.deinit();
    instances[1].object = weakened;
    try testing.expectError(error.IncompatibleInterface, data.linker.link(testing.allocator, &instances, &binding, .{ .instance = "client", .symbol = "main" }));
}

fn failureLink(allocator: std.mem.Allocator, provider: []const u8, client: []const u8) !void {
    var linked = try data.linker.link(allocator, &.{ .{ .key = "library", .object = provider }, .{ .key = "client", .object = client } }, &bindings, .{ .instance = "client", .symbol = "main" });
    defer linked.deinit();
    const bytes = try allocator.alloc(u8, try data.program_image.encodedLength(linked.program));
    defer allocator.free(bytes);
    _ = try linked.encode(allocator, bytes);
}

test "component linking releases every partial owner on allocation failure" {
    const provider = try object(true, false);
    defer testing.allocator.free(provider);
    const client = try object(false, false);
    defer testing.allocator.free(client);
    try testing.checkAllAllocationFailures(testing.allocator, failureLink, .{ provider, client });
}

test "one reusable combinator specializes for two residual effect contexts" {
    var b = source.Builder.init(testing.allocator);
    defer b.deinit();
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const read = try b.effect(.{ .identity = "polymorphic/read", .payload = unit, .result = integer });
    const write = try b.effect(.{ .identity = "polymorphic/write", .payload = integer, .result = unit });
    const first = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{}, .result = integer, .effects = &.{read} } } });
    const second = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{}, .result = integer, .effects = &.{ read, write } } } });
    const twice = @import("../library/combinators.zig").twice;
    const one = try twice(&b, first);
    const two = try twice(&b, second);
    try testing.expect(one != two);
    try testing.expectEqual(one, try twice(&b, first));
    try testing.expectEqual(two, try twice(&b, second));
    var compiled = try source.component.compile(testing.allocator, b.module(one, unit), .{ .exports = &.{
        .{ .name = "read", .reference = .{ .kind = .function, .id = one } },
        .{ .name = "read-write", .reference = .{ .kind = .function, .id = two } },
    } });
    defer compiled.deinit();
    try testing.expectEqualSlices(data.program.Id, &.{read}, compiled.object.program.functions[@intCast(one)].effects);
    try testing.expectEqualSlices(data.program.Id, &.{ read, write }, compiled.object.program.functions[@intCast(two)].effects);
}

test "mutually recursive component implementations link as one closed group" {
    const examples = source.component_examples;
    const even = try examples.emit(testing.allocator, .even);
    defer testing.allocator.free(even);
    const odd = try examples.emit(testing.allocator, .odd);
    defer testing.allocator.free(odd);
    var linked = try data.linker.link(testing.allocator, &.{ .{ .key = "odd", .object = odd }, .{ .key = "even", .object = even } }, &examples.recursive_bindings, .{ .instance = "even", .symbol = "main" });
    defer linked.deinit();
    try testing.expectEqual(2, linked.program.functions.len);
}

test "an unrelated component import cannot hide a local protected borrow escape" {
    var b = source.Builder.init(testing.allocator);
    defer b.deinit();
    const original = try source.examples.resourceScalar(&b);
    const main_bind = b.terms.items[@intCast(b.functions.items[@intCast(original.entry)].body.?)].bind;
    const protected = main_bind.next;
    const body_value = b.terms.items[@intCast(protected)].protect.body;
    const body_function = b.values.items[@intCast(body_value)].expression.lambda;
    const parameter = b.parameter(body_function, 0);
    const borrowed = b.variables.items[@intCast(parameter)];
    var signature = b.schemas.items[@intCast(b.values.items[@intCast(body_value)].schema)].internal.computation;
    signature.result = borrowed;
    b.values.items[@intCast(body_value)].schema = try b.schema(.{ .internal = .{ .computation = signature } });
    b.functions.items[@intCast(body_function)].result = borrowed;
    b.functions.items[@intCast(body_function)].body = try b.pure(try b.reference(parameter));
    const escaped = try b.variable(borrowed);
    const read = try b.term(.{ .call = .{ .function = b.resources.items[0].eliminators[0], .arguments = &.{try b.reference(escaped)} } });
    const next = try b.bind(escaped, protected, read);
    b.functions.items[@intCast(original.entry)].body = try b.bind(main_bind.variable, main_bind.value, next);
    const imported = try b.declare(&.{}, original.failure, &.{}, &.{});
    if (source.component.compile(testing.allocator, b.module(original.entry, original.failure), .{
        .imports = &.{.{ .name = "unused", .reference = .{ .kind = .function, .id = imported } }},
        .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = original.entry } }},
    })) |value| {
        var accepted = value;
        accepted.deinit();
        return error.AcceptedProtectedBorrowEscape;
    } else |err| try testing.expectEqual(error.InvalidOwnership, err);
}

test "component local clause borrowing distinguishes older and fresh capabilities despite imports" {
    inline for (.{ false, true }) |older| inline for (.{ false, true }) |delegated| {
        var b = source.Builder.init(testing.allocator);
        defer b.deinit();
        const original = try @import("clause_payload_example.zig").variant(&b, older, delegated);
        const imported = try b.declare(&.{}, original.failure, &.{}, &.{});
        // A separate, valid implementation really reaches the unknown callee.
        // Deferring it must not defer the locally decidable clause violation.
        const independent = try b.declare(&.{}, original.failure, &.{}, &.{});
        try b.define(independent, try b.term(.{ .call = .{ .function = imported, .arguments = &.{} } }));
        const result = source.component.compile(testing.allocator, b.module(original.entry, original.failure), .{
            .imports = &.{.{ .name = "external", .reference = .{ .kind = .function, .id = imported } }},
            .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = original.entry } }},
        });
        if (older) {
            var compiled = try result;
            compiled.deinit();
        } else if (result) |value| {
            var compiled = value;
            compiled.deinit();
            return error.AcceptedFreshCapabilityInOuterClause;
        } else |err| try testing.expectEqual(error.InvalidOwnership, err);
    };
}
