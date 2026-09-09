// Copyright (c) 2026 Boundary contributors. MIT license.
pub const package_version = "2.0.0";
pub const computation = @import("source.zig");
pub const source = computation;
pub const effect = @import("effect.zig");
pub const handler = struct {
    pub const Definition = data_v2.program.Handler;
    pub const Clause = data_v2.program.Clause;
    pub const Mode = data_v2.program.Mode;
    pub const Resumption = data_v2.program.ResumptionType;
    pub const Use = data_v2.program.Use;
    pub const define = computation.Builder.handler;
};
pub const region = struct {
    pub const create = computation.Builder.region;
    pub const resource = computation.Builder.resource;
    pub const authority = computation.Builder.resourceAuthority;
};
pub const library = struct {
    pub const choice = @import("library/choice.zig");
    pub const generator = @import("library/generator.zig");
    pub const cleanup = @import("library/cleanup.zig");
    pub const state = @import("library/state.zig");
    pub const reader = @import("library/reader.zig");
    pub const writer = @import("library/writer.zig");
    pub const raise = @import("library/raise.zig");
    pub const scheduler = @import("library/scheduler.zig");
    pub const search = @import("library/search.zig");
};
pub const program = struct {
    pub const lower = computation.emit;
    pub const compile = source.lower;
    pub const compileObserved = source.lowerObserved;
    pub const Diagnostic = source.Diagnostic;
    pub const CompileOptions = source.CompileOptions;
};
pub const data_v2 = @import("boundary_data_v2");
pub const image_v2 = data_v2.image;
pub const snapshot_v2 = data_v2.snapshot;
pub const protocol_v2 = data_v2.protocol;

test {
    _ = computation;
}
