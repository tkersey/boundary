const std = @import("std");
const Config = std.Build.Configuration;
const Step = struct { index: u32, name: []const u8, kind: []const u8, dependencies: []u32 };
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const path = args.next() orelse return error.MissingConfiguration;
    if (args.next() != null) return error.UnexpectedArgument;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(16 << 20));
    var header_reader: std.Io.Reader = .fixed(bytes);
    const h = try header_reader.takeStruct(Config.Header, .native);
    if (h.steps_len > 65536 or h.generated_files_len > 65536 or h.extra_len > 4 << 20 or h.string_bytes_len > 8 << 20)
        return error.ConfigurationLimit;
    const expected = @sizeOf(Config.Header) + @as(usize, h.string_bytes_len) +
        @as(usize, h.steps_len) * @sizeOf(Config.Step) +
        @as(usize, h.path_deps_len) * @sizeOf(Config.PathDep) +
        @as(usize, h.unlazy_deps_len) * @sizeOf(Config.String) +
        @as(usize, h.system_integrations_len) * @sizeOf(Config.SystemIntegration) +
        @as(usize, h.available_options_len) * @sizeOf(Config.AvailableOption) +
        @as(usize, h.search_prefixes_len) * @sizeOf(Config.String) +
        @as(usize, h.extra_len) * @sizeOf(u32);
    if (expected != bytes.len) return error.InvalidConfigurationLength;
    var reader: std.Io.Reader = .fixed(bytes);
    const config = try Config.load(a, &reader);
    const steps = try a.alloc(Step, config.steps.len);
    for (config.steps, steps, 0..) |step, *out, index| {
        const deps = step.deps.slice(&config);
        const dependencies = try a.alloc(u32, deps.len);
        for (deps, dependencies) |dep, *value| {
            value.* = @backingInt(dep);
            if (value.* >= steps.len) return error.InvalidStepDependency;
        }
        out.* = .{ .index = @intCast(index), .name = step.name.slice(&config),
            .kind = @tagName(step.extended.get(config.extra)), .dependencies = dependencies };
    }
    const output = try std.json.Stringify.valueAlloc(a, .{ .steps = steps, .default_step = @backingInt(config.default_step),
        .generated_files = config.generated_files_len, .configuration_cache_poisoned = config.poisoned }, .{});
    try std.Io.File.stdout().writeStreamingAll(init.io, output);
}
