// Copyright (c) 2026 Boundary contributors. MIT license.
const source = @import("../source.zig");
const p = @import("boundary_data_v2").program;

pub fn exitInfo(builder: *source.Builder, failure: p.Id) source.Error!p.Id {
    const unit = try builder.scalar(void);
    const reason = try builder.schema(.{ .sum = &.{ try builder.schema(.text), try builder.schema(.bytes) } });
    const primary = try builder.schema(.{ .sum = &.{ unit, failure, reason, unit } });
    return builder.schema(.{ .product = &.{ primary, try builder.schema(.{ .sum = &.{ unit, reason } }), try builder.schema(.{ .seq = failure }) } });
}

/// Acquisition is authored before this term. Ownership moves to the obligation;
/// only the protected body receives a borrow, and release receives the owner.
pub fn bracket(builder: *source.Builder, resource: p.Id, loan_region: p.Id, body: p.Id, cleanup: p.Id) source.Error!p.Id {
    return builder.term(.{ .protect = .{ .body = body, .cleanup = cleanup, .resource = resource, .loan_region = loan_region } });
}
