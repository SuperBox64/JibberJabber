// JibJab -> ARM64 Assembly (macOS)
.global _main
.align 4

_main:
    stp x29, x30, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    stp x25, x26, [sp, #-16]!
    stp x27, x28, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #144
    mov w0, #10
    stur w0, [x29, #-32]
    mov w0, #5
    stur w0, [x29, #-40]
    adrp x0, _str1@PAGE
    add x0, x0, _str1@PAGEOFF
    bl _printf
    ldur w0, [x29, #-32]
    str w0, [sp, #-16]!
    ldur w0, [x29, #-40]
    mov w1, w0
    ldr w0, [sp], #16
    add w0, w0, w1
    sxtw x0, w0
    str x0, [sp]
    adrp x0, _fmt_int@PAGE
    add x0, x0, _fmt_int@PAGEOFF
    bl _printf
    ldur w0, [x29, #-32]
    str w0, [sp, #-16]!
    ldur w0, [x29, #-40]
    mov w1, w0
    ldr w0, [sp], #16
    sub w0, w0, w1
    sxtw x0, w0
    str x0, [sp]
    adrp x0, _fmt_int@PAGE
    add x0, x0, _fmt_int@PAGEOFF
    bl _printf
    ldur w0, [x29, #-32]
    str w0, [sp, #-16]!
    ldur w0, [x29, #-40]
    mov w1, w0
    ldr w0, [sp], #16
    mul w0, w0, w1
    sxtw x0, w0
    str x0, [sp]
    adrp x0, _fmt_int@PAGE
    add x0, x0, _fmt_int@PAGEOFF
    bl _printf
    ldur w0, [x29, #-32]
    str w0, [sp, #-16]!
    ldur w0, [x29, #-40]
    mov w1, w0
    ldr w0, [sp], #16
    sdiv w0, w0, w1
    sxtw x0, w0
    str x0, [sp]
    adrp x0, _fmt_int@PAGE
    add x0, x0, _fmt_int@PAGEOFF
    bl _printf
    ldur w0, [x29, #-32]
    str w0, [sp, #-16]!
    ldur w0, [x29, #-40]
    mov w1, w0
    ldr w0, [sp], #16
    sdiv w2, w0, w1
    msub w0, w2, w1, w0
    sxtw x0, w0
    str x0, [sp]
    adrp x0, _fmt_int@PAGE
    add x0, x0, _fmt_int@PAGEOFF
    bl _printf
    ldur w0, [x29, #-32]
    mov w9, w0
    ldur w0, [x29, #-40]
    cmp w9, w0
    b.le _else2
    adrp x0, _str4@PAGE
    add x0, x0, _str4@PAGEOFF
    bl _printf
_else2:
    mov w0, #0
    add sp, sp, #144
    ldp x27, x28, [sp], #16
    ldp x25, x26, [sp], #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

.data
_fmt_int:
    .asciz "%d\n"
_fmt_str:
    .asciz "%s\n"
_str1:
    .asciz "Math operations:\n"
_str4:
    .asciz "x is greater than y\n"
