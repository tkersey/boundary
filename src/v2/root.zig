// Copyright (c) 2026 Boundary contributors. MIT license.
pub const package_version = "3.0.0-dev.0";
pub const computation = @import("source.zig");
pub const source = computation;
pub const effect = @import("effect.zig");
pub const handler = struct {
    pub const Definition = data.program.Handler;
    pub const Clause = data.program.Clause;
    pub const Mode = data.program.Mode;
    pub const Resumption = data.program.ResumptionType;
    pub const Use = data.program.Use;
    pub const define = computation.Builder.handler;
};
pub const region = struct {
    pub const create = computation.Builder.region;
    pub const resource = computation.Builder.resource;
    pub const authority = computation.Builder.resourceAuthority;
};
pub const library = struct {
    pub const hyper = @import("library/hyper.zig");
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
pub const data = @import("boundary_data");

test {
    _ = computation;
    _ = library.hyper;
}
