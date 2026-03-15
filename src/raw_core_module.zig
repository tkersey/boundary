const raw = @import("raw.zig");

/// Internal shim prompt-mode enum for standalone compat consumers.
pub const PromptMode = raw.PromptMode;
/// Internal shim runtime for standalone compat consumers.
pub const Runtime = raw.Runtime;
/// Internal shim raw runtime error surface for standalone compat consumers.
pub const Error = raw.Error;
/// Internal shim setup error surface for standalone compat consumers.
pub const SetupError = raw.SetupError;
/// Internal shim raw control error union for standalone compat consumers.
pub const ControlError = raw.ControlError;
/// Internal shim raw reset error union for standalone compat consumers.
pub const ResetError = raw.ResetError;
/// Internal shim optional-resumption decision type for standalone compat consumers.
pub const ResumeOrReturn = raw.ResumeOrReturn;
/// Internal shim prompt type for standalone compat consumers.
pub const Prompt = raw.Prompt;
/// Internal shim raw reset entrypoint for standalone compat consumers.
pub const reset = raw.reset;
/// Internal shim raw shift entrypoint for standalone compat consumers.
pub const shift = raw.shift;
/// Internal shim prompt-local identity shift helper for standalone compat consumers.
pub const shiftLocalIdentity = raw.shiftLocalIdentity;
