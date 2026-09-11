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
/// Optional verification data. Records borrow the compiler's current arena only
/// for the callback; a consumer retaining them must own its copies.
pub const EvidencePhase = enum { lowered, custody, direct, canonical };
pub const EvidenceObserver = struct {
    context: *anyopaque,
    program: *const fn (*anyopaque, EvidencePhase, p.Program) error{OutOfMemory}!void,
};
pub const Options = struct {
    diagnostic: ?*Diagnostic = null,
    observer: ?Observer = null,
    evidence: ?EvidenceObserver = null,

    pub fn stage(self: Options, next: Stage) void {
        if (self.diagnostic) |d| d.phase = next;
        if (self.observer) |observer| observer.enter(observer.context, next);
    }

    pub fn observeProgram(self: Options, phase: EvidencePhase, value: p.Program) error{OutOfMemory}!void {
        if (self.evidence) |observer| try observer.program(observer.context, phase, value);
    }
};
