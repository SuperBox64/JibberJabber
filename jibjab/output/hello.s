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
    adrp x0, _str1@PAGE
    add x0, x0, _str1@PAGEOFF
    bl _printf
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
    .asciz "Hello, JibJab World!\n"
