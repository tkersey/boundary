//! Optional admission locations. These are observations, never wire evidence.
const p = @import("program.zig");
pub const Diagnostic = struct {
    phase: enum { roots, schema, constant, effect, function, capture, constructor, handler, block, region } = .roots,
    code: ?anyerror = null,
    schema: ?p.Id = null,
    function: ?p.Id = null,
    block: ?p.Id = null,
    instruction: ?p.Id = null,
    terminator: ?p.TerminatorTag = null,
    callee: ?p.Id = null,
    capture: ?p.Id = null,
    field: ?p.Id = null,
    handler: ?p.Id = null,
    slot: ?p.Id = null,
    effect: ?p.Id = null,
};
