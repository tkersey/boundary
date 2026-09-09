//! Caller-owned diagnostics and optional compilation phase observations.
const data = @import("boundary_data_v2");
const p = data.program;
pub const Stage = enum { source_copy, source_check, lowering, target_check, direct_optimization, canonicalization, complete };
pub const Diagnostic = struct {
    phase: Stage = .source_copy,
    code: ?anyerror = null,
    function: ?p.Id = null,
    term: ?p.Id = null,
    value: ?p.Id = null,
    variable: ?p.Id = null,
    target: data.admission.Diagnostic = .{},
};
pub const Observer = struct {
    context: *anyopaque,
    enter: *const fn (*anyopaque, Stage) void,
};
pub const Options = struct {
    diagnostic: ?*Diagnostic = null,
    observer: ?Observer = null,

    pub fn stage(self: Options, next: Stage) void {
        if (self.diagnostic) |d| d.phase = next;
        if (self.observer) |observer| observer.enter(observer.context, next);
    }
};
