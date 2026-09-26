//! Caller-owned diagnostics and optional compilation phase observations.
const data = @import("boundary_data");
const p = data.program;
pub const Stage = enum {
    source_copy,
    source_check,
    lowering,
    target_check,
    direct_optimization,
    canonicalization,
    coalescing,
    complete,
};
pub const Diagnostic = struct {
    phase: Stage = .source_copy,
    code: ?anyerror = null,
    function: ?p.Id = null,
    term: ?p.Id = null,
    value: ?p.Id = null,
    variable: ?p.Id = null,
    /// `function` is a representative when this summary is ambiguous.
    origins: Origins = .{},
    target: data.admission.Diagnostic = .{},
};
pub const Origins = data.admission.Origins;
pub const Observer = struct {
    context: *anyopaque,
    enter: *const fn (*anyopaque, Stage) void,
};
/// A source variable retained at an effect boundary, derived by target liveness.
pub const CaptureObserver = struct {
    context: *anyopaque,
    capture: *const fn (*anyopaque, p.Id, p.Id) void,
    closure: *const fn (*anyopaque, p.Id, p.Id) void,
};
pub const Options = struct {
    diagnostic: ?*Diagnostic = null,
    observer: ?Observer = null,
    captures: ?CaptureObserver = null,
    coalescing: data.coalescing.Options = .{},

    pub fn stage(self: Options, next: Stage) void {
        if (self.diagnostic) |d| d.phase = next;
        if (self.observer) |observer| observer.enter(observer.context, next);
    }
};
