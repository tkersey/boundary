#ifdef __APPLE__
#define GSYM(x) _##x
#else
#define GSYM(x) x
#endif

.text
.globl GSYM(shift_swap_context)
.p2align 4, 0x90
GSYM(shift_swap_context):
    movq (%rsp), %rax
    movq %rax, 56(%rdi)
    leaq 8(%rsp), %rax
    movq %rax, 0(%rdi)
    movq %rbx, 8(%rdi)
    movq %rbp, 16(%rdi)
    movq %r12, 24(%rdi)
    movq %r13, 32(%rdi)
    movq %r14, 40(%rdi)
    movq %r15, 48(%rdi)

    movq 0(%rsi), %rsp
    movq 8(%rsi), %rbx
    movq 16(%rsi), %rbp
    movq 24(%rsi), %r12
    movq 32(%rsi), %r13
    movq 40(%rsi), %r14
    movq 48(%rsi), %r15
    movq 56(%rsi), %rax
    jmp *%rax
