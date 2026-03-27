const exception_effect = @import("effect/exception.zig");
const optional_effect = @import("effect/optional.zig");
const reader_effect = @import("effect/reader.zig");
const resource_effect = @import("effect/resource.zig");
const state_effect = @import("effect/state.zig");
const std = @import("std");
const writer_effect = @import("effect/writer.zig");

/// Bridge builtin handler constructors from the open-row surface to the existing lexical descriptors.
pub fn state(initial_state: anytype) @TypeOf(state_effect.use(initial_state)) {
    return state_effect.use(initial_state);
}

/// Bridge builtin handler constructors from the open-row surface to the existing lexical descriptors.
pub fn reader(environment: anytype) @TypeOf(reader_effect.use(environment)) {
    return reader_effect.use(environment);
}

/// Bridge builtin handler constructors from the open-row surface to the existing lexical descriptors.
pub fn writer(comptime ItemType: type, allocator: std.mem.Allocator) @TypeOf(writer_effect.use(ItemType, allocator)) {
    return writer_effect.use(ItemType, allocator);
}

/// Bridge builtin handler constructors from the open-row surface to the existing lexical descriptors.
pub fn optional(comptime ResumeType: type, comptime Policy: type) @TypeOf(optional_effect.use(ResumeType, Policy)) {
    return optional_effect.use(ResumeType, Policy);
}

/// Bridge builtin handler constructors from the open-row surface to the existing lexical descriptors.
pub fn exception(comptime PayloadType: type, comptime Catch: type) @TypeOf(exception_effect.use(PayloadType, Catch)) {
    return exception_effect.use(PayloadType, Catch);
}

/// Bridge builtin handler constructors from the open-row surface to the existing lexical descriptors.
pub fn resource(comptime ResourceType: type, comptime Manager: type) @TypeOf(resource_effect.use(ResourceType, Manager)) {
    return resource_effect.use(ResourceType, Manager);
}
