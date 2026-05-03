const ability = @import("ability");
const std = @import("std");

const Counter = ability.effect.Define(.{
    .state_type = i32,
    .ops = .{
        ability.effect.ops.Transform("read", void, i32),
        ability.effect.ops.Transform("write", i32, void),
    },
});

const Approval = ability.effect.Define(.{
    .state_type = void,
    .ops = .{
        ability.effect.ops.Choice("select", i32, i32),
    },
});

const Guard = ability.effect.Define(.{
    .state_type = void,
    .ops = .{
        ability.effect.ops.Abort("reject", []const u8),
    },
});

const CounterHandler = struct {
    state: i32,

    /// Read the current counter state.
    pub fn read(self: *@This()) i32 {
        return self.state;
    }

    /// Preserve the enclosing answer after a read continuation.
    pub fn afterRead(_: *@This(), answer: i32) i32 {
        return answer;
    }

    /// Replace the current counter state.
    pub fn write(self: *@This(), value: i32) void {
        self.state = value;
    }

    /// Preserve the enclosing answer after a write continuation.
    pub fn afterWrite(_: *@This(), answer: i32) i32 {
        return answer;
    }
};

const ApprovalHandler = struct {
    selected: i32,

    /// Resume with the configured approval selection.
    pub fn select(self: *@This(), _: i32) ability.effect.choice.Decision(i32, i32) {
        return ability.effect.choice.Decision(i32, i32).resumeWith(self.selected);
    }

    /// Preserve the enclosing answer after a choice continuation.
    pub fn afterSelect(_: *@This(), answer: i32) i32 {
        return answer;
    }
};

const GuardHandler = struct {
    marker: void = {},

    /// Return the terminal guard answer.
    pub fn reject(_: *@This(), _: []const u8) i32 {
        return -1;
    }
};

const DescriptorHandlers = @TypeOf(.{
    .counter = Counter.use(.{ .handler = CounterHandler{ .state = 5 } }),
    .approval = Approval.use(.{ .handler = ApprovalHandler{ .selected = 8 } }),
    .guard = Guard.use(.{ .handler = GuardHandler{} }),
});

fn contractProgramBody(eff: anytype) anyerror!i32 {
    const before = try eff.counter.read.perform();
    try eff.counter.write.perform(before + 4);
    return try eff.counter.read.perform();
}

const contract_program_body = struct {
    /// Source path for the named body witness.
    pub const source_path = "test/program_contract_view_test.zig";
    /// Entry symbol for the named body witness.
    pub const body_symbol = "contractProgramBody";

    /// Run the generated contract projection fixture body.
    pub fn body(eff: anytype) @TypeOf(contractProgramBody(eff)) {
        return contractProgramBody(eff);
    }
};

const ContractProgram = ability.program(
    "test.generated_program_contract",
    DescriptorHandlers,
    contract_program_body,
    .{ .stable_build_fingerprint_seed = "generated-program-contract-view" },
);

fn contractRequirement(comptime Contract: type, comptime label: []const u8) Contract.Requirement {
    for (Contract.requirements) |requirement| {
        if (std.mem.eql(u8, requirement.label, label)) return requirement;
    }
    @compileError("missing contract requirement: " ++ label);
}

fn contractOp(comptime Contract: type, comptime requirement_label: []const u8, comptime op_name: []const u8) Contract.Operation {
    _ = contractRequirement(Contract, requirement_label);
    for (Contract.ops) |op| {
        if (std.mem.eql(u8, op.requirement_label, requirement_label) and std.mem.eql(u8, op.name, op_name)) return op;
    }
    @compileError("missing contract op: " ++ requirement_label ++ "." ++ op_name);
}

test "generated program contract exposes requirements ops and outputs" {
    comptime {
        const Contract = ContractProgram.contract;
        if (Contract.requirements.len != 4) @compileError(std.fmt.comptimePrint(
            "contract must expose generated requirements, got {d}",
            .{Contract.requirements.len},
        ));
        if (Contract.ops.len != 6) @compileError(std.fmt.comptimePrint(
            "contract must expose generated ops, got {d}",
            .{Contract.ops.len},
        ));
        if (Contract.outputs.len != 1) @compileError("stateful generated transform contract must expose one output");
        if (!std.mem.eql(u8, Contract.outputs[0].label, "counter")) @compileError("counter output label drifted");

        const read = contractOp(Contract, "counter", "read");
        if (read.mode != .transform) @compileError("counter.read contract mode drifted");
        if (!read.has_after) @compileError("counter.read must publish its after hook");

        const write = contractOp(Contract, "counter", "write");
        if (write.mode != .transform) @compileError("counter.write contract mode drifted");
        if (!write.has_after) @compileError("counter.write must publish its after hook");

        const select = contractOp(Contract, "approval", "select");
        if (select.mode != .choice) @compileError("approval.select contract mode drifted");
        if (!select.has_after) @compileError("approval.select must publish its after hook");

        const reject = contractOp(Contract, "guard", "reject");
        if (reject.mode != .abort) @compileError("guard.reject contract mode drifted");
        if (reject.has_after) @compileError("guard.reject must not publish an after hook");
    }

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try ContractProgram.run(&runtime, .{
        .counter = Counter.use(.{ .handler = CounterHandler{ .state = 5 } }),
        .approval = Approval.use(.{ .handler = ApprovalHandler{ .selected = 8 } }),
        .guard = Guard.use(.{ .handler = GuardHandler{} }),
    });
    try std.testing.expectEqual(@as(i32, 9), result.value);
    try std.testing.expectEqual(@as(i32, 9), result.outputs.counter);
}
