const raw = @import("raw_core");

/// Legacy raw prompt-mode enum preserved for explicit compat consumers.
pub const PromptMode = raw.PromptMode;
/// Legacy stackful runtime preserved for explicit compat consumers.
pub const Runtime = raw.Runtime;
/// Legacy raw runtime error surface preserved for explicit compat consumers.
pub const Error = raw.Error;
/// Legacy raw setup failures preserved for explicit compat consumers.
pub const SetupError = raw.SetupError;
/// Legacy raw runtime error union preserved for explicit compat consumers.
pub const ControlError = raw.ControlError;
/// Legacy raw reset-time error union preserved for explicit compat consumers.
pub const ResetError = raw.ResetError;
/// Legacy raw optional-resumption decision type preserved for explicit compat consumers.
pub const ResumeOrReturn = raw.ResumeOrReturn;
/// Legacy raw prompt type preserved for explicit compat consumers.
pub const Prompt = raw.Prompt;
/// Legacy raw reset entrypoint preserved for explicit compat consumers.
pub const reset = raw.reset;
/// Legacy raw shift entrypoint preserved for explicit compat consumers.
pub const shift = raw.shift;
/// Legacy raw prompt-local identity shift helper preserved for compat consumers.
pub const shiftLocalIdentity = raw.shiftLocalIdentity;
