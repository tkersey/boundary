// Independent-process BMO1 witnesses; this executable imports data only.
const std = @import("std");
const data = @import("boundary_data");
const ir = data.activation;
const schemas: []const data.program.Schema = &.{ .u64, .unit, .{ .internal = .{ .computation = .{ .parameters = &.{0}, .result = 0, .capture_bound = &.{ 0, 0 }, .use = .reusable } } } };
const provider: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = schemas,
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{0}, .layout = .{ .slots = &.{0} }, .result = 0 },
        .{ .entry = 1, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 2 } }, .result = 2 },
        .{ .entry = 2, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 0, 0, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 2, .opcode = .computation, .immediate = 0, .operands = &.{ 0, 1 } }}, .terminator = .{ .return_value = 2 } },
        .{ .function = 2, .instructions = &.{.{ .destination = 3, .opcode = .integer_bit_xor, .operands = &.{ 0, 2 } }}, .terminator = .{ .return_value = 3 } },
    },
    .scopes = .{ .captures = &.{.{ .fields = &.{ 0, 0 }, .use = .reusable }} },
    .constructors = &.{.{ .function = 2, .capture = 0, .schema = 2 }},
};
const client: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = schemas,
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 0, 0, 2, 0 } }, .result = 0 },
        .{ .entry = data.relocation.missing, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0 } }, .result = 2 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 0, 1 }, .next = .{ .block = 1, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .apply = .{ .computation = 3, .arguments = &.{2}, .next = .{ .block = 2, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 4 } },
    },
};
const constructor_client: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = schemas,
    .constants = &.{},
    .effects = &.{},
    .functions = &.{ .{ .entry = 0, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 0, 0, 2, 0 } }, .result = 0 }, .{ .entry = 2, .inputs = &.{ 0, 1, 2 }, .layout = .{ .slots = &.{ 0, 0, 0 } }, .result = 0 } },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{.{ .destination = 3, .opcode = .computation, .immediate = 0, .operands = &.{ 0, 1 } }}, .terminator = .{ .apply = .{ .computation = 3, .arguments = &.{2}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 4, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 4 } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 2 } },
    },
    .scopes = .{ .captures = &.{.{ .fields = &.{ 0, 0 }, .use = .reusable }} },
    .constructors = &.{.{ .function = 1, .capture = 0, .schema = 2 }},
};
const thunk_schemas: []const data.program.Schema = &.{ .u64, .unit, .{ .internal = .{ .computation = .{ .parameters = &.{}, .result = 0, .capture_bound = &.{ 0, 2 }, .use = .reusable } } } };
const thunk_provider: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = thunk_schemas,
    .constants = &.{},
    .effects = &.{},
    .functions = &.{ .{ .entry = 0, .inputs = &.{0}, .layout = .{ .slots = &.{0} }, .result = 0 }, .{ .entry = 1, .inputs = &.{0}, .layout = .{ .slots = &.{ 2, 0 } }, .result = 0 } },
    .blocks = &.{ .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 0 } }, .{ .function = 1, .instructions = &.{}, .terminator = .{ .apply = .{ .computation = 0, .arguments = &.{}, .next = .{ .block = 2, .assignments = &.{.{ .destination = 1, .source = .returned }} } } } }, .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 1 } } },
    .scopes = .{ .captures = &.{.{ .fields = &.{2}, .use = .reusable }} },
    .constructors = &.{.{ .function = 1, .capture = 0, .schema = 2 }},
};
const thunk_client: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = thunk_schemas,
    .constants = &.{.{ .schema = 0, .bytes = &.{ 0, 0, 0, 0, 0, 0, 0, 0 } }},
    .effects = &.{},
    .functions = &.{ .{ .entry = 0, .inputs = &.{0}, .layout = .{ .slots = &.{ 0, 2, 2, 0 } }, .result = 0 }, .{ .entry = 2, .inputs = &.{0}, .layout = .{ .slots = &.{0} }, .result = 0 }, .{ .entry = 3, .inputs = &.{0}, .layout = .{ .slots = &.{ 2, 0 } }, .result = 0 } },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{ .{ .destination = 1, .opcode = .computation, .immediate = 0, .operands = &.{0} }, .{ .destination = 2, .opcode = .computation, .immediate = 1, .operands = &.{1} } }, .terminator = .{ .apply = .{ .computation = 2, .arguments = &.{}, .next = .{ .block = 1, .assignments = &.{.{ .destination = 3, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 3 } },
        .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 0 } },
        .{ .function = 2, .instructions = &.{.{ .destination = 1, .opcode = .constant, .immediate = 0 }}, .terminator = .{ .return_value = 1 } },
    },
    .scopes = .{ .captures = &.{ .{ .fields = &.{0}, .use = .reusable }, .{ .fields = &.{2}, .use = .reusable } } },
    .constructors = &.{ .{ .function = 1, .capture = 0, .schema = 2 }, .{ .function = 2, .capture = 1, .schema = 2 } },
};
const sharing_provider: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 0 } }, .result = 0 },
        .{ .entry = 2, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 0, 1 }, .next = .{ .block = 1, .assignments = &.{.{ .destination = 2, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 2 } },
        .{ .function = 1, .instructions = &.{.{ .destination = 2, .opcode = .integer_bit_xor, .operands = &.{ 0, 1 } }}, .terminator = .{ .return_value = 2 } },
    },
};
const sharing_client: ir.Program = .{
    .roots = .{ .entry = 0, .result = 0, .failure = 1 },
    .schemas = &.{ .u64, .unit },
    .constants = &.{},
    .effects = &.{},
    .functions = &.{
        .{ .entry = 0, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 0 } }, .result = 0 },
        .{ .entry = data.relocation.missing, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0 } }, .result = 0 },
        .{ .entry = 3, .inputs = &.{ 0, 1 }, .layout = .{ .slots = &.{ 0, 0, 0 } }, .result = 0 },
    },
    .blocks = &.{
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .call = .{ .function = 1, .arguments = &.{ 0, 1 }, .next = .{ .block = 1, .assignments = &.{.{ .destination = 2, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .call = .{ .function = 2, .arguments = &.{ 2, 1 }, .next = .{ .block = 2, .assignments = &.{.{ .destination = 2, .source = .returned }} } } } },
        .{ .function = 0, .instructions = &.{}, .terminator = .{ .return_value = 2 } },
        .{ .function = 2, .instructions = sharing_provider.blocks[2].instructions, .terminator = .{ .return_value = 2 } },
    },
};
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const mode = args.next() orelse return error.Mode;
    const input = args.next();
    if (args.next() != null) return error.Arguments;
    if (std.mem.eql(u8, mode, "inspect-object")) {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, input orelse return error.Image, init.gpa, .limited(1 << 20));
        defer init.gpa.free(bytes);
        var decoded = try data.component.decode(init.gpa, bytes);
        defer decoded.deinit();
        var xors: usize = 0;
        for (decoded.object.program.blocks) |block| {
            for (block.instructions) |op| xors += @intFromBool(op.opcode == .integer_bit_xor);
        }
        var buffer: [4096]u8 = undefined;
        var out = std.Io.File.stdout().writer(init.io, &buffer);
        try std.json.Stringify.value(.{ .functions = decoded.object.program.functions.len, .xorInstructions = xors }, .{}, &out.interface);
        try out.interface.writeByte('\n');
        try out.interface.flush();
        return;
    }
    if (std.mem.eql(u8, mode, "inspect")) {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, input orelse return error.Image, init.gpa, .limited(1 << 20));
        defer init.gpa.free(bytes);
        var decoded = try data.program_image.decode(init.gpa, bytes);
        defer decoded.deinit();
        var applies: usize = 0;
        var constructions: usize = 0;
        var operands: usize = 0;
        var xors: usize = 0;
        for (decoded.program.blocks) |block| {
            applies += @intFromBool(block.terminator == .apply);
            for (block.instructions) |op| xors += @intFromBool(op.opcode == .integer_bit_xor);
            for (block.instructions) |op| if (op.opcode == .computation) {
                constructions += 1;
                operands += op.operands.len;
            };
        }
        var forwarding: data.thunk_forwarding.Statistics = .{};
        var forwarded = try data.thunk_forwarding.run(init.gpa, decoded.program, &forwarding, .{});
        defer forwarded.deinit();
        var captures: data.capture_reduction.Statistics = .{};
        var reduced = try data.capture_reduction.run(init.gpa, decoded.program, &captures, .{});
        defer reduced.deinit();
        var buffer: [4096]u8 = undefined;
        var out = std.Io.File.stdout().writer(init.io, &buffer);
        try std.json.Stringify.value(.{ .bytes = bytes.len, .functions = decoded.program.functions.len, .constructors = decoded.program.constructors.len, .applies = applies, .constructions = constructions, .captureOperands = operands, .forwardingLawWitnesses = forwarding.wrappers_removed, .deadCaptureWitnesses = captures.fields_removed, .xorInstructions = xors }, .{}, &out.interface);
        try out.interface.writeByte('\n');
        try out.interface.flush();
        return;
    }
    if (input != null) return error.Arguments;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    if (std.mem.eql(u8, mode, "sharing-profile")) {
        var collector = try data.optimization_profile.Collector.init(a, sharing_provider);
        defer collector.deinit();
        var profile = try collector.snapshot(a);
        defer profile.deinit();
        var buffer: [4096]u8 = undefined;
        var out = std.Io.File.stdout().writer(init.io, &buffer);
        try std.json.Stringify.value(profile.record, .{}, &out.interface);
        try out.interface.writeByte('\n');
        try out.interface.flush();
        return;
    }
    if (std.mem.eql(u8, mode, "direct")) {
        var program = constructor_client;
        const functions = try a.dupe(ir.Function, program.functions);
        functions[1].layout = provider.functions[2].layout;
        program.functions = functions;
        const blocks = try a.dupe(ir.Block, program.blocks);
        blocks[2].instructions = provider.blocks[2].instructions;
        blocks[2].terminator = provider.blocks[2].terminator;
        program.blocks = blocks;
        var compiled = try data.closed_compilation.run(a, program, .{ .contract = .semantic });
        defer compiled.deinit();
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(compiled.program));
        _ = try data.program_image.encode(a, compiled.program, bytes);
        var buffer: [4096]u8 = undefined;
        var out = std.Io.File.stdout().writer(init.io, &buffer);
        try out.interface.writeAll(bytes);
        try out.interface.flush();
        return;
    }
    var object: data.component.Object = undefined;
    if (std.mem.eql(u8, mode, "sharing-provider")) {
        object = .{ .program = sharing_provider, .exports = &.{.{ .name = "compute", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{.{ .function = 0 }} };
    } else if (std.mem.eql(u8, mode, "sharing-client")) {
        object = .{ .program = sharing_client, .imports = &.{.{ .name = "compute", .reference = .{ .kind = .function, .id = 1 } }}, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 1 } } };
    } else if (std.mem.eql(u8, mode, "thunk-provider")) {
        const facts = try data.admission.schemas(a, thunk_provider.schemas);
        var flow = try data.borrow_flow.StableFlow.init(a, thunk_provider, facts.exportable);
        const summaries = try a.alloc(data.borrow_contract.Summary, 1);
        summaries[0] = try data.borrow_contract.infer(&flow, 1);
        object = .{ .program = thunk_provider, .exports = &.{.{ .name = "wrapper", .reference = .{ .kind = .constructor, .id = 0 } }}, .borrows = summaries };
    } else if (std.mem.eql(u8, mode, "thunk-client")) {
        object = .{ .program = thunk_client, .imports = &.{.{ .name = "wrapper", .reference = .{ .kind = .constructor, .id = 1 } }}, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 2 } } };
    } else if (std.mem.eql(u8, mode, "provider") or std.mem.eql(u8, mode, "false-summary") or std.mem.eql(u8, mode, "constructor-provider")) {
        const facts = try data.admission.schemas(a, provider.schemas);
        var flow = try data.borrow_flow.StableFlow.init(a, provider, facts.exportable);
        const summary = try a.alloc(data.borrow_contract.Summary, 1);
        const constructor = std.mem.eql(u8, mode, "constructor-provider");
        summary[0] = try data.borrow_contract.infer(&flow, if (constructor) 2 else 1);
        const exports = try a.alloc(data.component.Symbol, 1);
        exports[0] = .{ .name = "factory", .reference = if (constructor) .{ .kind = .constructor, .id = 0 } else .{ .kind = .function, .id = 1 } };
        object = .{ .program = provider, .exports = exports, .borrows = summary };
    } else if (std.mem.eql(u8, mode, "constructor-client")) {
        object = .{ .program = constructor_client, .imports = &.{.{ .name = "factory", .reference = .{ .kind = .constructor, .id = 0 } }}, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 1 } } };
    } else if (std.mem.eql(u8, mode, "client")) {
        object = .{ .program = client, .imports = &.{.{ .name = "factory", .reference = .{ .kind = .function, .id = 1 } }}, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 1, .returned = &.{ .{ .source = .{ .ambient = .evidence } }, .{ .source = .{ .ambient = .region } } } } } };
    } else return error.Mode;
    const bytes = try a.alloc(u8, try data.component.encodedLength(object));
    _ = try data.component.encode(a, object, bytes);
    if (std.mem.eql(u8, mode, "false-summary")) {
        // A canonical untrusted fixture binds the inferred contract to the
        // wrong local function, leaving the exported factory without a summary.
        if (bytes.len < 5 or !std.mem.eql(u8, bytes[bytes.len - 5 ..], &.{ 1, 1, 0, 0, 0 })) return error.UnexpectedSummaryEncoding;
        bytes[bytes.len - 4] = 0;
    }
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    try out.interface.writeAll(bytes);
    try out.interface.flush();
}
