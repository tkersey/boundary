// Copyright (c) 2026 Boundary contributors. MIT license.
//! Exact word-coordinate GF(2) spaces used by affine capture extraction.
//! A bit selects an entire unsigned word, never a bit lane or nominal object.
const std = @import("std");
pub const max_dimension = 128;
pub const Row = u128;
pub const Error = error{ InvalidAffineSpace, WorkLimit };
pub const Budget = struct {
    remaining: u64,
    pub fn charge(self: *Budget) Error!void {
        if (self.remaining == 0) return error.WorkLimit;
        self.remaining -= 1;
    }
};
pub fn coordinate(index: usize) Row {
    std.debug.assert(index < max_dimension);
    return @as(Row, 1) << @intCast(index);
}
pub fn mask(dimension: usize) Row {
    std.debug.assert(dimension <= max_dimension);
    return if (dimension == max_dimension) std.math.maxInt(Row) else (@as(Row, 1) << @intCast(dimension)) - 1;
}
pub const Space = struct {
    dimension: usize,
    pivots: [max_dimension]Row = @splat(0),
    rank: usize = 0,

    pub fn init(dimension: usize) Error!Space {
        if (dimension > max_dimension) return error.InvalidAffineSpace;
        return .{ .dimension = dimension };
    }
    pub fn insert(self: *Space, input: Row, budget: *Budget) Error!bool {
        if (input & ~mask(self.dimension) != 0) return error.InvalidAffineSpace;
        var row = input;
        for (0..self.dimension) |pivot| {
            try budget.charge();
            if (row & coordinate(pivot) == 0) continue;
            if (self.pivots[pivot] != 0) {
                row ^= self.pivots[pivot];
            } else {
                self.pivots[pivot] = row;
                self.rank += 1;
                return true;
            }
        }
        return false;
    }
    /// Coordinates in the ordered nonzero pivot rows, or null outside this span.
    pub fn coefficients(self: *const Space, input: Row, budget: *Budget) Error!?Row {
        if (input & ~mask(self.dimension) != 0) return error.InvalidAffineSpace;
        var row = input;
        var coefficients_row: Row = 0;
        var basis_index: usize = 0;
        for (0..self.dimension) |pivot| {
            try budget.charge();
            const basis = self.pivots[pivot];
            if (basis == 0) {
                if (row & coordinate(pivot) != 0) return null;
                continue;
            }
            if (row & coordinate(pivot) != 0) {
                row ^= basis;
                coefficients_row ^= coordinate(basis_index);
            }
            basis_index += 1;
        }
        return if (row == 0) coefficients_row else null;
    }
    pub fn rows(self: *const Space, output: *[max_dimension]Row) []const Row {
        var count: usize = 0;
        for (self.pivots[0..self.dimension]) |row| if (row != 0) {
            output[count] = row;
            count += 1;
        };
        return output[0..count];
    }
};

/// Pull a successor observation back through a parallel word update. Each
/// transition row is an expression in the predecessor coordinates.
pub fn pull(row: Row, transition: []const Row, source_dimension: usize, budget: *Budget) Error!Row {
    if (transition.len > max_dimension or source_dimension > max_dimension or row & ~mask(transition.len) != 0) return error.InvalidAffineSpace;
    var result: Row = 0;
    for (transition, 0..) |input, index| {
        try budget.charge();
        if (input & ~mask(source_dimension) != 0) return error.InvalidAffineSpace;
        if (row & coordinate(index) != 0) result ^= input;
    }
    return result;
}

/// Close one control location under every admitted transition. The input space
/// is copied: budget failure cannot expose a partially closed result.
pub fn close(seed: Space, transitions: []const []const Row, budget: *Budget) Error!Space {
    var result = seed;
    var changed = true;
    while (changed) {
        changed = false;
        var buffer: [max_dimension]Row = undefined;
        const basis = result.rows(&buffer);
        for (transitions) |transition| {
            if (transition.len != seed.dimension) return error.InvalidAffineSpace;
            for (basis) |row| {
                const predecessor = try pull(row, transition, seed.dimension, budget);
                changed = try result.insert(predecessor, budget) or changed;
            }
        }
    }
    return result;
}

/// Independent certificate primitive: reconstruct an equation from supplied
/// coefficients rather than invoking the closure finder or elimination routine.
pub fn equation(expected: Row, coefficients_row: Row, basis: []const Row, dimension: usize, budget: *Budget) Error!void {
    if (basis.len > max_dimension or dimension > max_dimension or coefficients_row & ~mask(basis.len) != 0 or expected & ~mask(dimension) != 0) return error.InvalidAffineSpace;
    var actual: Row = 0;
    for (basis, 0..) |row, index| {
        try budget.charge();
        if (row & ~mask(dimension) != 0) return error.InvalidAffineSpace;
        if (coefficients_row & coordinate(index) != 0) actual ^= row;
    }
    if (actual != expected) return error.InvalidAffineSpace;
}

test "rotating three-word future observations close at rank two" {
    var budget: Budget = .{ .remaining = 10000 };
    var seed = try Space.init(3);
    _ = try seed.insert(0b011, &budget);
    _ = try seed.insert(0b110, &budget);
    const closed = try close(seed, &.{&.{ 0b010, 0b100, 0b001 }}, &budget);
    try std.testing.expectEqual(@as(usize, 2), closed.rank);
    var buffer: [max_dimension]Row = undefined;
    const basis = closed.rows(&buffer);
    for (basis) |row| {
        const next = try pull(row, &.{ 0b010, 0b100, 0b001 }, 3, &budget);
        try equation(next, (try closed.coefficients(next, &budget)).?, basis, 3, &budget);
    }
    try std.testing.expectError(error.InvalidAffineSpace, equation(0b001, 1, basis, 3, &budget));
}

test "future reset distinguishes currently equal parity and budgets do not publish partial closure" {
    var budget: Budget = .{ .remaining = 10000 };
    var seed = try Space.init(2);
    _ = try seed.insert(0b11, &budget);
    const closed = try close(seed, &.{&.{ 0, 0b10 }}, &budget);
    try std.testing.expectEqual(@as(usize, 2), closed.rank);
    var exhausted: Budget = .{ .remaining = 0 };
    try std.testing.expectError(error.WorkLimit, close(seed, &.{&.{ 0, 0b10 }}, &exhausted));
    try std.testing.expectEqual(@as(usize, 1), seed.rank);
}

test "generated permutation parity closes at all specified dimensions" {
    for ([_]usize{ 2, 3, 8, 32, 64, 128 }) |n| {
        var budget: Budget = .{ .remaining = 1000000 };
        var seed = try Space.init(n);
        _ = try seed.insert(mask(n), &budget);
        var transition: [max_dimension]Row = undefined;
        for (0..n) |i| transition[i] = coordinate((i + n - 1) % n);
        const closed = try close(seed, &.{transition[0..n]}, &budget);
        try std.testing.expectEqual(@as(usize, 1), closed.rank);
    }
}
