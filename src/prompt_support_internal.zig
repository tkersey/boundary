const frontend_mod = @import("frontend.zig");
const prompt_contract = @import("prompt_contract.zig");

/// Internal-only explicit program frontend support.
pub const frontend = frontend_mod;

/// Internal-only prompt mode enum.
pub const PromptMode = prompt_contract.PromptMode;

/// Internal-only prompt shell constructor.
pub const Prompt = prompt_contract.Prompt;

/// Internal-only zero-or-one-resume decision type.
pub const ResumeOrReturn = prompt_contract.ResumeOrReturn;

/// Internal-only explicit program shell.
pub const Program = frontend_mod.Program;

/// Internal-only explicit frontend operations.
/// Build one explicit pure program under the internal prompt protocol.
pub const pureProgram = frontend_mod.pureProgram;
/// Build one explicit transform program under the internal prompt protocol.
pub const transformProgram = frontend_mod.transformProgram;
/// Build one explicit choice program under the internal prompt protocol.
pub const choiceProgram = frontend_mod.choiceProgram;
/// Build one explicit abort program under the internal prompt protocol.
pub const abortProgram = frontend_mod.abortProgram;
/// Perform one internal prompt operation through the explicit frontend.
pub const perform = frontend_mod.perform;
/// Run one explicit frontend program under the internal prompt protocol.
pub const run = frontend_mod.run;
