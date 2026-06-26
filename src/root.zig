const shared = @import("boundary_shared");

/// Public effect namespace.
pub const effect = shared.effect;
/// Public ProgramPlan builder namespace.
pub const ir = shared.ir;
/// Canonical runtime handle for local program execution.
pub const Runtime = shared.Runtime;
/// Declare one reusable explicit effect program.
pub const program = shared.program;
/// Canonical v0 protocol manifest namespace.
pub const Protocol = shared.Protocol;
/// Boundary protocol manifest binary format version.
pub const boundary_protocol_manifest_format_version = shared.boundary_protocol_manifest_format_version;
/// Boundary protocol manifest fingerprint version.
pub const boundary_protocol_manifest_fingerprint_version = shared.boundary_protocol_manifest_fingerprint_version;

test {
    _ = Runtime;
    _ = program;
    _ = effect;
    _ = ir;
    _ = Protocol;
}
