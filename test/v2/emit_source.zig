//! Emit one source term tree or its compiled data, without linking an evaluator.
const std = @import("std");
const boundary = @import("boundary");
const options = @import("source_options");

pub fn main(init: std.process.Init) !void {
    var builder = boundary.source.Builder.init(init.gpa);
    defer builder.deinit();
    const module = try switch (options.example) {
        0 => boundary.source.examples.lexical(&builder),
        1 => boundary.source.examples.deep(&builder),
        2 => boundary.source.examples.recursive(&builder),
        3 => boundary.source.examples.choicesAll(&builder),
        4 => boundary.source.examples.choicesFirst(&builder),
        5 => boundary.source.examples.generator(&builder),
        6 => boundary.source.examples.stateLocal(&builder),
        7 => boundary.source.examples.stateShared(&builder),
        8 => boundary.source.examples.resourceScalar(&builder),
        9 => boundary.source.examples.resourcePair(&builder),
        10 => boundary.source.examples.answers(&builder),
        11 => boundary.source.examples.scopedReader(&builder),
        12 => boundary.source.examples.writerRaise(&builder),
        13 => boundary.source.examples.schedulerFifo(&builder),
        14 => boundary.source.examples.queensDfs(&builder),
        15 => boundary.source.examples.queensBfs(&builder),
        16 => boundary.source.examples.cellOrder(&builder),
        17 => boundary.source.examples.nested(&builder),
        18 => boundary.source.examples.shallow(&builder),
        19 => boundary.source.examples.injection(&builder),
        20 => boundary.source.examples.indexed(&builder),
        21 => boundary.source.examples.abortCustody(&builder),
        22 => boundary.source.examples.unwind(&builder),
        23 => boundary.source.examples.reentrant(&builder),
        24 => boundary.source.examples.cloned(&builder),
        25 => boundary.source.examples.clauseAbort(&builder),
        26 => boundary.source.examples.boundedValues(&builder),
        27 => boundary.source.examples.scalarContracts(&builder),
        28 => boundary.source.examples.ownership(&builder),
        29 => boundary.source.examples.shallowResumptions(&builder),
        30 => boundary.source.examples.shallowInjection(&builder),
        31 => boundary.source.examples.handleOperandOrder(&builder),
        32 => boundary.source.examples.protectOperandOrder(&builder),
        33 => boundary.source.examples.successorState(&builder),
        34 => boundary.source.examples.clausePayload(&builder),
        35 => boundary.source.examples.yieldingCleanup(&builder),
        36 => boundary.source.examples.borrowOperands(&builder),
        else => @compileError("unknown source example"),
    };
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    if (options.source) {
        try std.json.Stringify.value(module, .{ .emit_strings_as_arrays = true }, &output.interface);
        try output.interface.writeByte('\n');
    } else {
        var compiled = try boundary.program.compile(init.gpa, module);
        defer compiled.deinit();
        const bytes = try init.gpa.alloc(u8, try boundary.image_v2.encodedLength(compiled.program));
        defer init.gpa.free(bytes);
        _ = try compiled.encode(init.gpa, bytes);
        try output.interface.writeAll(bytes);
    }
    try output.interface.flush();
}
