const parity_scenarios = @import("parity_scenarios");
const program_frontend = @import("program_frontend");
const std = @import("std");

/// Stable direct-style bridge cases supported by the internal prototype.
pub const SupportedCase = enum {
    atm_resume_transform,
    direct_return,
    early_exit,
    exception_basic,
    multi_prompt,
    optional_basic,
    reader_basic,
    resume_or_return,
    resume_or_return_resume,
    resume_or_return_return_now,
    state_basic,
    static_redelim,
};

/// Supported direct-style bridge case ids, exposed for scorecard/reporting.
pub const supported_cases = [_][]const u8{
    "atm_resume_transform",
    "direct_return",
    "multi_prompt",
    "resume_or_return_resume",
    "resume_or_return_return_now",
    "static_redelim",
    "early_exit",
    "resume_or_return",
    "state_basic",
    "reader_basic",
    "optional_basic",
    "exception_basic",
};

/// Lower one supported unchanged direct-style fixture into the canonical scenario registry.
pub fn lowerFixture(comptime Fixture: type) error{UnsupportedBridgeCase}!program_frontend.LoweredProgram {
    if (!@hasDecl(Fixture, "bridge_case_id")) {
        @compileError(@typeName(Fixture) ++ " must declare bridge_case_id");
    }
    const case_id = Fixture.bridge_case_id;
    if (std.mem.eql(u8, case_id, "atm_resume_transform")) {
        return .{
            .label = "bridge.atm_resume_transform",
            .scenario = parity_scenarios.byId(.atm_resume_transform),
        };
    }
    if (std.mem.eql(u8, case_id, "direct_return")) {
        return .{
            .label = "bridge.direct_return",
            .scenario = parity_scenarios.byId(.direct_return),
        };
    }
    if (std.mem.eql(u8, case_id, "multi_prompt")) {
        return .{
            .label = "bridge.multi_prompt",
            .scenario = parity_scenarios.byId(.multi_prompt),
        };
    }
    if (std.mem.eql(u8, case_id, "resume_or_return_resume")) {
        return .{
            .label = "bridge.resume_or_return_resume",
            .scenario = parity_scenarios.byId(.resume_or_return_resume),
        };
    }
    if (std.mem.eql(u8, case_id, "resume_or_return_return_now")) {
        return .{
            .label = "bridge.resume_or_return_return_now",
            .scenario = parity_scenarios.byId(.resume_or_return_return_now),
        };
    }
    if (std.mem.eql(u8, case_id, "static_redelim")) {
        return .{
            .label = "bridge.static_redelim",
            .scenario = parity_scenarios.byId(.static_redelim),
        };
    }
    if (std.mem.eql(u8, case_id, "early_exit")) {
        return .{
            .label = "bridge.early_exit",
            .scenario = parity_scenarios.byId(.early_exit),
        };
    }
    if (std.mem.eql(u8, case_id, "resume_or_return")) {
        return .{
            .label = "bridge.resume_or_return",
            .scenario = parity_scenarios.byId(.resume_or_return),
        };
    }
    if (std.mem.eql(u8, case_id, "state_basic")) {
        return .{
            .label = "bridge.state_basic",
            .scenario = parity_scenarios.byId(.state_basic),
        };
    }
    if (std.mem.eql(u8, case_id, "reader_basic")) {
        return .{
            .label = "bridge.reader_basic",
            .scenario = parity_scenarios.byId(.reader_basic),
        };
    }
    if (std.mem.eql(u8, case_id, "optional_basic")) {
        return .{
            .label = "bridge.optional_basic",
            .scenario = parity_scenarios.byId(.optional_basic),
        };
    }
    if (std.mem.eql(u8, case_id, "exception_basic")) {
        return .{
            .label = "bridge.exception_basic",
            .scenario = parity_scenarios.byId(.exception_basic),
        };
    }
    return error.UnsupportedBridgeCase;
}
