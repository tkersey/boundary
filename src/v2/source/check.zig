// Copyright (c) 2026 Boundary contributors. MIT license.
//! Source scopes and result types, including mutually recursive lexical captures.
const std = @import("std");
const data = @import("boundary_data_v2");
const p = data.program;
const ast = @import("ast.zig");
const Error = @import("../source.zig").Error;
pub const Set = std.ArrayList(p.Id);
pub const Facts = struct { values: []Set, terms: []Set, functions: []Set, results: []?p.Id };

pub fn add(allocator: std.mem.Allocator, target: *Set, id: p.Id) Error!bool {
    if (std.mem.indexOfScalar(p.Id, target.items, id) != null) return false;
    try target.append(allocator, id);
    return true;
}
pub fn merge(allocator: std.mem.Allocator, target: *Set, source: []const p.Id, excluded: []const p.Id) Error!bool {
    var changed = false;
    for (source) |id| if (std.mem.indexOfScalar(p.Id, excluded, id) == null) {
        changed = try add(allocator, target, id) or changed;
    };
    return changed;
}
fn sets(allocator: std.mem.Allocator, length: usize) Error![]Set {
    const result = try allocator.alloc(Set, length);
    for (result) |*set| set.* = .empty;
    return result;
}
fn computation(source: ast.Module, value_id: p.Id) Error!p.ComputationType {
    if (value_id >= source.values.len) return error.InvalidReference;
    const schema = try data.admission.schemaAt(source.schemas, source.values[@intCast(value_id)].schema);
    if (schema != .internal or schema.internal != .computation) return error.TypeMismatch;
    return schema.internal.computation;
}
fn resumption(source: ast.Module, value_id: p.Id) Error!p.ResumptionType {
    if (value_id >= source.values.len) return error.InvalidReference;
    const schema = try data.admission.schemaAt(source.schemas, source.values[@intCast(value_id)].schema);
    if (schema != .internal or schema.internal != .resumption) return error.TypeMismatch;
    return schema.internal.resumption;
}
fn compatible(left: ?p.Id, right: ?p.Id) Error!?p.Id {
    if (left != null and right != null and left.? != right.?) return error.TypeMismatch;
    return left orelse right;
}

pub fn analyze(allocator: std.mem.Allocator, source: ast.Module) Error!Facts {
    return analyzeDiagnosed(allocator, source, null);
}

pub fn analyzeDiagnosed(allocator: std.mem.Allocator, source: ast.Module, diagnostic: ?*@import("diagnostic.zig").Diagnostic) Error!Facts {
    if (source.entry >= source.functions.len) return error.InvalidReference;
    _ = try data.admission.schemas(allocator, source.schemas);
    try declarationSchemas(source, diagnostic);
    var facts: Facts = .{ .values = try sets(allocator, source.values.len), .terms = try sets(allocator, source.terms.len), .functions = try sets(allocator, source.functions.len), .results = try allocator.alloc(?p.Id, source.terms.len) };
    @memset(facts.results, null);
    for (source.values, 0..) |value, id| {
        if (diagnostic) |d| {
            d.value = id;
            d.variable = if (value.expression == .variable) value.expression.variable else null;
        }
        _ = try data.admission.schemaAt(source.schemas, value.schema);
        switch (value.expression) {
            .variable => |variable| if (variable >= source.variables.len or source.variables[@intCast(variable)] != value.schema) return error.TypeMismatch,
            .literal => |literal| if (literal >= source.constants.len or source.constants[@intCast(literal)].schema != value.schema) return error.TypeMismatch,
            .primitive => |primitive| for (primitive.operands) |operand| {
                if (operand >= id) return error.InvalidSource;
            },
            .lambda => |function| {
                if (function >= source.functions.len) return error.InvalidReference;
                _ = try computation(source, id);
            },
        }
    }
    if (diagnostic) |d| {
        d.value = null;
        d.variable = null;
    }
    var unit: ?p.Id = null;
    for (source.schemas, 0..) |schema, id| if (schema == .unit) {
        unit = id;
        break;
    };
    const term_references = try allocator.alloc(References, source.terms.len);
    for (source.terms, 0..) |term, id| {
        if (diagnostic) |d| d.term = id;
        const references = &term_references[id];
        references.* = .{ .allocator = allocator };
        try references.collect(term);
        for (references.values.items) |value_id| if (value_id >= source.values.len) return error.InvalidReference;
        for (references.terms.items) |term_id| if (term_id >= id) return error.InvalidSource;
        for (references.bound.items) |variable| if (variable >= source.variables.len) return error.InvalidReference;
        facts.results[id] = switch (term) {
            .value => |value_id| source.values[@intCast(value_id)].schema,
            .bind => |bind| blk: {
                _ = try compatible(facts.results[@intCast(bind.value)], source.variables[@intCast(bind.variable)]);
                break :blk if (facts.results[@intCast(bind.value)] == null) null else facts.results[@intCast(bind.next)];
            },
            .conditional => |conditional| blk: {
                if (source.schemas[@intCast(source.values[@intCast(conditional.condition)].schema)] != .boolean) return error.TypeMismatch;
                break :blk try compatible(facts.results[@intCast(conditional.when_true)], facts.results[@intCast(conditional.when_false)]);
            },
            .call => |call| blk: {
                if (call.function >= source.functions.len) return error.InvalidReference;
                break :blk source.functions[@intCast(call.function)].result;
            },
            .apply => |apply| (try computation(source, apply.computation)).result,
            .perform => |perform| blk: {
                if (perform.effect >= source.effects.len) return error.InvalidReference;
                break :blk source.effects[@intCast(perform.effect)].result;
            },
            .handle => |handle| blk: {
                if (handle.handler >= source.handlers.len) return error.InvalidReference;
                break :blk source.handlers[@intCast(handle.handler)].answer;
            },
            .resume_value => |resuming| (try resumption(source, resuming.resumption)).answer,
            .resume_with => |resuming| blk: {
                if (resuming.handler >= source.handlers.len) return error.InvalidReference;
                break :blk source.handlers[@intCast(resuming.handler)].answer;
            },
            .resume_computation => |resuming| (try resumption(source, resuming.resumption)).answer,
            .protect => |protection| (try computation(source, protection.body)).result,
            .with_region => |region| (try computation(source, region.body)).result,
            .dispose => unit orelse return error.TypeMismatch,
            .fail => |value| blk: {
                if (source.values[@intCast(value)].schema != source.failure) return error.TypeMismatch;
                break :blk null;
            },
            .yield_then => |next| facts.results[@intCast(next)],
            .match_sum => |match| blk: {
                const shape = source.schemas[@intCast(source.values[@intCast(match.value)].schema)];
                if (shape != .sum or shape.sum.len != match.cases.len) return error.TypeMismatch;
                var result: ?p.Id = null;
                for (match.cases, shape.sum) |case, schema| {
                    if (source.variables[@intCast(case.variable)] != schema) return error.TypeMismatch;
                    result = try compatible(result, facts.results[@intCast(case.body)]);
                }
                break :blk result;
            },
            .unpack_product => |unpack| blk: {
                const shape = source.schemas[@intCast(source.values[@intCast(unpack.value)].schema)];
                if (shape != .product or shape.product.len != unpack.variables.len) return error.TypeMismatch;
                for (unpack.variables, shape.product, 0..) |variable, schema, index| {
                    if (std.mem.indexOfScalar(p.Id, unpack.variables[0..index], variable) != null)
                        return error.InvalidSource;
                    if (source.variables[@intCast(variable)] != schema) return error.TypeMismatch;
                }
                break :blk facts.results[@intCast(unpack.body)];
            },
        };
    }
    for (source.functions, 0..) |function, id| {
        if (diagnostic) |d| {
            d.function = id;
            d.term = function.body;
        }
        const body = function.body orelse return error.UndefinedFunction;
        if (body >= source.terms.len) return error.InvalidReference;
        for (function.parameters, 0..) |variable, index| {
            if (variable >= source.variables.len or std.mem.indexOfScalar(p.Id, function.parameters[0..index], variable) != null) return error.InvalidSource;
        }
        _ = try compatible(facts.results[@intCast(body)], function.result);
    }
    // Closure/call dependencies are a least fixed point over finite variable sets.
    // Recursive source functions never recursively run the checker.
    var changed = true;
    while (changed) {
        changed = false;
        for (source.values, 0..) |value, id| switch (value.expression) {
            .variable => |variable| {
                changed = try add(allocator, &facts.values[id], variable) or changed;
            },
            .literal => {},
            .primitive => |primitive| for (primitive.operands) |operand| {
                changed = try merge(allocator, &facts.values[id], facts.values[@intCast(operand)].items, &.{}) or changed;
            },
            .lambda => |function| {
                changed = try merge(allocator, &facts.values[id], facts.functions[@intCast(function)].items, &.{}) or changed;
            },
        };
        for (source.terms, 0..) |term, id| {
            const refs = term_references[id];
            for (refs.values.items) |value_id| {
                changed = try merge(allocator, &facts.terms[id], facts.values[@intCast(value_id)].items, &.{}) or changed;
            }
            switch (term) {
                .bind => |bind| {
                    changed = try merge(allocator, &facts.terms[id], facts.terms[@intCast(bind.value)].items, &.{}) or changed;
                    changed = try merge(allocator, &facts.terms[id], facts.terms[@intCast(bind.next)].items, &.{bind.variable}) or changed;
                },
                .match_sum => |match| for (match.cases) |case| {
                    changed = try merge(allocator, &facts.terms[id], facts.terms[@intCast(case.body)].items, &.{case.variable}) or changed;
                },
                .unpack_product => |unpack| {
                    changed = try merge(allocator, &facts.terms[id], facts.terms[@intCast(unpack.body)].items, unpack.variables) or changed;
                },
                else => for (refs.terms.items) |term_id| {
                    changed = try merge(allocator, &facts.terms[id], facts.terms[@intCast(term_id)].items, &.{}) or changed;
                },
            }
            if (term == .call) {
                changed = try merge(allocator, &facts.terms[id], facts.functions[@intCast(term.call.function)].items, &.{}) or changed;
            }
        }
        for (source.functions, 0..) |function, id| {
            changed = try merge(allocator, &facts.functions[id], facts.terms[@intCast(function.body.?)].items, function.parameters) or changed;
        }
    }
    for (facts.values) |*set| std.mem.sort(p.Id, set.items, {}, std.sort.asc(p.Id));
    for (facts.terms) |*set| std.mem.sort(p.Id, set.items, {}, std.sort.asc(p.Id));
    for (facts.functions) |*set| std.mem.sort(p.Id, set.items, {}, std.sort.asc(p.Id));
    if (facts.functions[@intCast(source.entry)].items.len != 0) {
        if (diagnostic) |d| {
            d.function = source.entry;
            d.term = source.functions[@intCast(source.entry)].body;
            d.variable = facts.functions[@intCast(source.entry)].items[0];
        }
        return error.UnboundVariable;
    }
    for (source.handlers) |handler| {
        try checkHandlerCapture(source, facts, handler.return_function, diagnostic);
        for (handler.clauses) |clause| try checkHandlerCapture(source, facts, clause.function, diagnostic);
    }
    if (diagnostic) |d| {
        d.function = null;
        d.term = null;
        d.value = null;
        d.variable = null;
    }
    return facts;
}

fn declarationSchemas(source: ast.Module, diagnostic: ?*@import("diagnostic.zig").Diagnostic) Error!void {
    _ = try data.admission.schemaAt(source.schemas, source.failure);
    for (source.variables) |schema| _ = try data.admission.schemaAt(source.schemas, schema);
    for (source.constants) |constant| _ = try data.admission.schemaAt(source.schemas, constant.schema);
    for (source.resources) |resource| _ = try data.admission.schemaAt(source.schemas, resource.representation);
    for (source.effects) |effect| {
        _ = try data.admission.schemaAt(source.schemas, effect.payload);
        _ = try data.admission.schemaAt(source.schemas, effect.result);
        for (effect.bodies) |schema| _ = try data.admission.schemaAt(source.schemas, schema);
    }
    for (source.handlers) |handler| {
        _ = try data.admission.schemaAt(source.schemas, handler.input);
        _ = try data.admission.schemaAt(source.schemas, handler.answer);
        for (handler.state) |schema| _ = try data.admission.schemaAt(source.schemas, schema);
        for (handler.clauses) |clause| _ = try data.admission.schemaAt(source.schemas, clause.resumption);
    }
    for (source.functions, 0..) |function, id| {
        if (diagnostic) |d| {
            d.function = id;
            d.term = function.body;
        }
        _ = try data.admission.schemaAt(source.schemas, function.result);
    }
    if (diagnostic) |d| {
        d.function = null;
        d.term = null;
    }
}

fn checkHandlerCapture(source: ast.Module, facts: Facts, function: p.Id, diagnostic: ?*@import("diagnostic.zig").Diagnostic) Error!void {
    if (diagnostic) |d| {
        d.function = function;
        d.term = if (function < source.functions.len) source.functions[@intCast(function)].body else null;
        d.variable = null;
    }
    if (function >= source.functions.len) return error.UnboundVariable;
    const free = facts.functions[@intCast(function)].items;
    if (free.len != 0) {
        if (diagnostic) |d| d.variable = free[0];
        return error.UnboundVariable;
    }
}

pub const References = struct {
    allocator: std.mem.Allocator,
    values: Set = .empty,
    terms: Set = .empty,
    bound: Set = .empty,
    pub fn collect(self: *References, term: ast.Term) Error!void {
        switch (term) {
            .value, .dispose, .fail => |value| try self.values.append(self.allocator, value),
            .bind => |bind| {
                try self.terms.appendSlice(self.allocator, &.{ bind.value, bind.next });
                try self.bound.append(self.allocator, bind.variable);
            },
            .conditional => |conditional| {
                try self.values.append(self.allocator, conditional.condition);
                try self.terms.appendSlice(self.allocator, &.{ conditional.when_true, conditional.when_false });
            },
            .call => |call| try self.values.appendSlice(self.allocator, call.arguments),
            .apply => |apply| {
                try self.values.append(self.allocator, apply.computation);
                try self.values.appendSlice(self.allocator, apply.arguments);
            },
            .perform => |perform| {
                try self.values.append(self.allocator, perform.payload);
                if (perform.capability) |cap| try self.values.append(self.allocator, cap);
                try self.values.appendSlice(self.allocator, perform.bodies);
                try self.values.appendSlice(self.allocator, perform.use_site_capabilities);
            },
            .handle => |handle| {
                try self.values.append(self.allocator, handle.body);
                try self.values.appendSlice(self.allocator, handle.arguments);
                try self.values.appendSlice(self.allocator, handle.state);
            },
            .resume_value => |resuming| try self.values.appendSlice(self.allocator, &.{ resuming.resumption, resuming.argument }),
            .resume_with => |resuming| {
                try self.values.appendSlice(self.allocator, &.{ resuming.resumption, resuming.argument });
                try self.values.appendSlice(self.allocator, resuming.state);
            },
            .resume_computation => |resuming| try self.values.appendSlice(self.allocator, &.{ resuming.resumption, resuming.computation }),
            .protect => |protection| {
                try self.values.appendSlice(self.allocator, &.{ protection.body, protection.cleanup });
                try self.values.appendSlice(self.allocator, protection.arguments);
                if (protection.resource) |resource| try self.values.append(self.allocator, resource);
            },
            .with_region => |region| {
                try self.values.append(self.allocator, region.body);
                try self.values.appendSlice(self.allocator, region.arguments);
            },
            .yield_then => |next| try self.terms.append(self.allocator, next),
            .match_sum => |match| {
                try self.values.append(self.allocator, match.value);
                for (match.cases) |case| {
                    try self.bound.append(self.allocator, case.variable);
                    try self.terms.append(self.allocator, case.body);
                }
            },
            .unpack_product => |unpack| {
                try self.values.append(self.allocator, unpack.value);
                try self.terms.append(self.allocator, unpack.body);
                try self.bound.appendSlice(self.allocator, unpack.variables);
            },
        }
    }
};
