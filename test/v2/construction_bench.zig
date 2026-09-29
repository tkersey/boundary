const std = @import("std");
const boundary = @import("boundary");
const data = @import("boundary_data");
const source = boundary.source;
const p = data.program;
const fields = .{ "schemas", "constants", "variables", "values", "terms", "functions" };
const Counters = struct {
    pointers: [fields.len]usize = @splat(0),
    lengths: [fields.len]usize = @splat(0),
    relocated_records: usize = 0,
    relocated_bytes: usize = 0,
    literal_linear_scan_visits: usize = 0,
    fn observe(self: *@This(), b: *source.Builder) void {
        inline for (fields, 0..) |field, i| {
            const items = @field(b, field).items;
            const pointer = if (items.len == 0) 0 else @intFromPtr(items.ptr);
            if (pointer != self.pointers[i]) {
                self.relocated_records += self.lengths[i];
                self.relocated_bytes += self.lengths[i] * @sizeOf(@TypeOf(items[0]));
            }
            self.pointers[i] = pointer;
            self.lengths[i] = items.len;
        }
    }
};
const Observation = struct { records: usize, constants: usize, terms: usize, calls: usize, checksum: u64, relocated_records: usize, relocated_bytes: usize, literal_linear_scan_visits: usize };
fn build(comptime count: bool, a: std.mem.Allocator, n: usize, distinct: bool) !Observation {
    var b = source.Builder.init(a);
    defer b.deinit();
    var c: Counters = .{};
    const integer = try b.scalar(u64);
    if (count) c.observe(&b);
    const unit = try b.scalar(void);
    if (count) c.observe(&b);
    const entry = try b.declare(&.{integer}, integer, &.{}, &.{});
    if (count) c.observe(&b);
    const variables = try b.allocator().alloc(p.Id, n);
    const terms = try b.allocator().alloc(p.Id, n);
    var previous = try b.reference(b.parameter(entry, 0));
    if (count) c.observe(&b);
    var checksum: u64 = 0;
    var calls: usize = 0;
    for (0..n) |i| {
        // Native configuration is evaluated once for each authored occurrence.
        const config: u64 = if (distinct) @as(u64, @intCast(i)) *% 65537 +% 1 else 7;
        checksum ^= config;
        calls += 1;
        if (count) {
            var bytes: [8]u8 = undefined;
            std.mem.writeInt(u64, &bytes, config, .little);
            // Exact comparison count for the current Builder.literal loop,
            // reconstructed from its actual pre-call catalog; not wall time.
            for (b.constants.items) |literal| {
                c.literal_linear_scan_visits += 1;
                if (literal.schema == integer and std.mem.eql(u8, literal.bytes, &bytes)) break;
            }
        }
        const value = try b.constant(u64, config);
        if (count) c.observe(&b);
        const operation = try b.primitive(integer, .integer_bit_xor, &.{ previous, value }, 0);
        if (count) c.observe(&b);
        terms[i] = try b.pure(operation);
        if (count) c.observe(&b);
        variables[i] = try b.variable(integer);
        if (count) c.observe(&b);
        previous = try b.reference(variables[i]);
        if (count) c.observe(&b);
    }
    var body = try b.pure(previous);
    if (count) c.observe(&b);
    var i = n;
    while (i != 0) {
        i -= 1;
        body = try b.bind(variables[i], terms[i], body);
        if (count) c.observe(&b);
    }
    try b.define(entry, body);
    const module = b.module(entry, unit);
    if (module.terms.len != n * 2 + 1 or module.values.len != n * 3 + 1 or calls != n) return error.IncorrectConstruction;
    return .{ .records = module.values.len + module.terms.len + module.variables.len, .constants = module.constants.len, .terms = module.terms.len, .calls = calls, .checksum = checksum, .relocated_records = c.relocated_records, .relocated_bytes = c.relocated_bytes, .literal_linear_scan_visits = c.literal_linear_scan_visits };
}
pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    for ([_]bool{ false, true }) |distinct| for ([_]usize{ 512, 1024, 2048 }) |n| {
        var samples: [9]u64 = undefined;
        for (0..12) |window| {
            const start = std.Io.Clock.awake.now(init.io);
            const observation = try build(false, init.gpa, n, distinct);
            const ns: u64 = @intCast(start.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds);
            if (observation.calls != n) return error.LostEmitter;
            if (window >= 3) samples[window - 3] = ns;
        }
        var counted = std.testing.FailingAllocator.init(init.gpa, .{});
        const counts = try build(true, counted.allocator(), n, distinct);
        if (counted.allocated_bytes != counted.freed_bytes) return error.Leak;
        try std.json.Stringify.value(.{ .mode = if (distinct) "distinct-configurations" else "shared-literal", .n = n, .samples_ns = samples, .counts = counts, .arena_allocations = counted.allocations, .allocated_bytes = counted.allocated_bytes }, .{}, &out.interface);
        try out.interface.writeByte('\n');
        try out.interface.flush();
    };
}
