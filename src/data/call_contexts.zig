// Copyright (c) 2026 Boundary contributors. MIT license.
//! Closed executable records have one host entry. Constructor and handler
//! entries retain unknown calling contexts; only direct-call-only workers can
//! acquire facts from the complete call-site set. Call argument order is ABI.
const ir = @import("activation.zig");
const p = @import("program.zig");

pub fn unknownEntry(program: ir.Program, function: p.Id) bool {
    if (program.roots.entry == function) return true;
    for (program.constructors) |constructor| if (constructor.function == function) return true;
    for (program.handlers) |handler| {
        if (handler.return_function == function) return true;
        for (handler.clauses) |clause| if (clause.function == function) return true;
    }
    // Nominal resource authority is not an inferred private calling convention.
    for (program.scopes.resources) |resource| {
        for (resource.introducers) |id| if (id == function) return true;
        for (resource.eliminators) |id| if (id == function) return true;
    }
    return false;
}
