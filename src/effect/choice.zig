const prompt_contract = @import("prompt_contract_support");

/// Public lexical choice-decision type used by optional handlers and generated choice families.
pub fn Decision(
    comptime Resume: type,
    comptime Answer: type,
) type {
    return prompt_contract.ResumeOrReturn(Resume, Answer);
}
