const compiler = @import("compiler");
const std = @import("std");

fn printUsage() !void {
    var buffer: [256]u8 = undefined;
    var writer = std.fs.File.stderr().writer(&buffer);
    const stderr = &writer.interface;
    try stderr.writeAll(
        \\usage: shiftc --input <file.shift> --zig <out.zig> --map <out.map.json> --cert <out.linear.json>
        \\       shiftc --check --input <file.shift> --zig <out.zig> --map <out.map.json> --cert <out.linear.json>
        \\
    );
    try stderr.flush();
}

fn emitDiagnostics(diags: []const compiler.Diagnostic) !void {
    var buffer: [512]u8 = undefined;
    var writer = std.fs.File.stderr().writer(&buffer);
    const stderr = &writer.interface;
    for (diags) |diag| try stderr.print("line {d}: {s}\n", .{ diag.line, diag.message });
    try stderr.flush();
}

pub fn main() anyerror!void {
    const allocator = std.heap.smp_allocator;

    var args = std.process.args();
    _ = args.skip();

    var input_path: ?[]const u8 = null;
    var zig_path: ?[]const u8 = null;
    var map_path: ?[]const u8 = null;
    var cert_path: ?[]const u8 = null;
    var check_only = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--check")) {
            check_only = true;
        } else if (std.mem.eql(u8, arg, "--input")) {
            input_path = args.next();
        } else if (std.mem.eql(u8, arg, "--zig")) {
            zig_path = args.next();
        } else if (std.mem.eql(u8, arg, "--map")) {
            map_path = args.next();
        } else if (std.mem.eql(u8, arg, "--cert")) {
            cert_path = args.next();
        } else {
            try printUsage();
            return error.InvalidArguments;
        }
    }

    const input = input_path orelse {
        try printUsage();
        return error.InvalidArguments;
    };
    const zig_out = zig_path orelse {
        try printUsage();
        return error.InvalidArguments;
    };
    const map_out = map_path orelse {
        try printUsage();
        return error.InvalidArguments;
    };
    const cert_out = cert_path orelse {
        try printUsage();
        return error.InvalidArguments;
    };

    const source = try std.fs.cwd().readFileAlloc(allocator, input, 1024 * 1024);
    defer allocator.free(source);

    var diagnostics = compiler.DiagnosticList.init(allocator);
    defer diagnostics.deinit();

    const artifact = compiler.compileSource(allocator, input, source, &diagnostics) catch |err| {
        if (diagnostics.items.items.len != 0) {
            try emitDiagnostics(diagnostics.items.items);
            std.process.exit(1);
        }
        return err;
    };
    defer compiler.freeArtifact(allocator, artifact);

    if (check_only) {
        const existing_zig = try std.fs.cwd().readFileAlloc(allocator, zig_out, 1024 * 1024);
        defer allocator.free(existing_zig);
        const existing_map = try std.fs.cwd().readFileAlloc(allocator, map_out, 1024 * 1024);
        defer allocator.free(existing_map);
        const existing_cert = try std.fs.cwd().readFileAlloc(allocator, cert_out, 1024 * 1024);
        defer allocator.free(existing_cert);

        if (!std.mem.eql(u8, existing_zig, artifact.zig) or
            !std.mem.eql(u8, existing_map, artifact.source_map_json) or
            !std.mem.eql(u8, existing_cert, artifact.certificate_json))
        {
            return error.GeneratedArtifactsStale;
        }
        return;
    }

    try std.fs.cwd().writeFile(.{ .sub_path = zig_out, .data = artifact.zig });
    try std.fs.cwd().writeFile(.{ .sub_path = map_out, .data = artifact.source_map_json });
    try std.fs.cwd().writeFile(.{ .sub_path = cert_out, .data = artifact.certificate_json });
}
