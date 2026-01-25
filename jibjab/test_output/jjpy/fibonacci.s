// JibJab -> ARM64 Assembly (macOS)
.global _main
.align 4

_fib:
    stp x29, x30, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    stp x25, x26, [sp, #-16]!
    stp x27, x28, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #144
    stur w0, [x29, #-32]
    ldur w0, [x29, #-32]
    mov w9, w0
    mov w0, #2
    cmp w9, w0
    b.ge _else1
    ldur w0, [x29, #-32]
    b _fib_ret
_else1:
    ldur w0, [x29, #-32]
    str w0, [sp, #-16]!
    mov w0, #1
    mov w1, w0
    ldr w0, [sp], #16
    sub w0, w0, w1
    mov w20, w0
    mov w0, w20
    bl _fib
    str w0, [sp, #-16]!
    ldur w0, [x29, #-32]
    str w0, [sp, #-16]!
    mov w0, #2
    mov w1, w0
    ldr w0, [sp], #16
    sub w0, w0, w1
    mov w20, w0
    mov w0, w20
    bl _fib
    mov w1, w0
    ldr w0, [sp], #16
    add w0, w0, w1
    b _fib_ret
    mov w0, #0
_fib_ret:
    add sp, sp, #144
    ldp x27, x28, [sp], #16
    ldp x25, x26, [sp], #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

_main:
    stp x29, x30, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    stp x25, x26, [sp, #-16]!
    stp x27, x28, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #144
    mov w0, #0
    stur w0, [x29, #-32]
    mov w0, #15
    stur w0, [x29, #-40]
_loop3:
    ldur w0, [x29, #-32]
    ldur w1, [x29, #-40]
    cmp w0, w1
    b.ge _endloop4
    ldur w0, [x29, #-32]
    mov w20, w0
    mov w0, w20
    bl _fib
    sxtw x0, w0
    str x0, [sp]
    adrp x0, _fmt_int@PAGE
    add x0, x0, _fmt_int@PAGEOFF
    bl _printf
    ldur w0, [x29, #-32]
    add w0, w0, #1
    stur w0, [x29, #-32]
    b _loop3
_endloop4:
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
