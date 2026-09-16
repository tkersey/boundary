//! Generic pure-codec wasm32 agreement probe. No evaluator or authored code is linked.
const std = @import("std");
const data = @import("boundary_data_v2");
var input: [1 << 20]u8 = undefined;
var output: [1 << 20]u8 = undefined;
var scratch: [8 << 20]u8 = undefined;
var program_identity: [32]u8 = undefined;

export fn program_identity_ptr() usize {
    return @intFromPtr(&program_identity);
}

export fn program_encode(length: usize) usize {
    if (length > input.len) return 0;
    var storage = std.heap.FixedBufferAllocator.init(&scratch);
    const allocator = storage.allocator();
    var decoded = data.program_image.decode(allocator, input[0..length]) catch return 0;
    defer decoded.deinit();
    program_identity = decoded.identity;
    const encoded = data.program_image.encode(allocator, decoded.program, &output) catch return 0;
    return encoded.len;
}

export fn state_encode(length: usize) usize {
    if (length > input.len) return 0;
    var storage = std.heap.FixedBufferAllocator.init(&scratch);
    const allocator = storage.allocator();
    var decoded = data.state_image.decodeGraph(allocator, input[0..length]) catch return 0;
    defer decoded.deinit();
    const encoded = data.state_image.encode(allocator, decoded.state, &output) catch return 0;
    return encoded.len;
}

export fn compact_input_ptr() usize {
    return @intFromPtr(&input);
}

export fn compact_output_ptr() usize {
    return @intFromPtr(&output);
}

export fn compact_encode(length: usize) usize {
    if (length > input.len) return 0;
    var storage = std.heap.FixedBufferAllocator.init(&scratch);
    const allocator = storage.allocator();
    var decoded = data.image.decode(allocator, input[0..length]) catch return 0;
    defer decoded.deinit();
    const encoded = data.compact_image.encode(allocator, decoded.program, &output) catch return 0;
    return encoded.len;
}
