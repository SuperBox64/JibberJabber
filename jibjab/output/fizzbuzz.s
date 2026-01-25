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
    mov w0, #1
    stur w0, [x29, #-32]
    mov w0, #101
    stur w0, [x29, #-40]
_loop1:
    ldur w0, [x29, #-32]
    ldur w1, [x29, #-40]
    cmp w0, w1
    b.ge _endloop2
    ldur w0, [x29, #-32]
    str w0, [sp, #-16]!
    mov w0, #15
    mov w1, w0
    ldr w0, [sp], #16
    sdiv w2, w0, w1
    msub w0, w2, w1, w0
    mov w9, w0
    mov w0, #0
    cmp w9, w0
    b.ne _else3
    adrp x0, _str5@PAGE
    add x0, x0, _str5@PAGEOFF
    bl _printf
    b _endif4
_else3:
    ldur w0, [x29, #-32]
    str w0, [sp, #-16]!
    mov w0, #3
    mov w1, w0
    ldr w0, [sp], #16
    sdiv w2, w0, w1
    msub w0, w2, w1, w0
    mov w9, w0
    mov w0, #0
    cmp w9, w0
    b.ne _else6
    adrp x0, _str8@PAGE
    add x0, x0, _str8@PAGEOFF
    bl _printf
    b _endif7
_else6:
    ldur w0, [x29, #-32]
    str w0, [sp, #-16]!
    mov w0, #5
    mov w1, w0
    ldr w0, [sp], #16
    sdiv w2, w0, w1
    msub w0, w2, w1, w0
    mov w9, w0
    mov w0, #0
    cmp w9, w0
    b.ne _else9
    adrp x0, _str11@PAGE
    add x0, x0, _str11@PAGEOFF
    bl _printf
    b _endif10
_else9:
    ldur w0, [x29, #-32]
    sxtw x0, w0
    str x0, [sp]
    adrp x0, _fmt_int@PAGE
    add x0, x0, _fmt_int@PAGEOFF
    bl _printf
_endif10:
_endif7:
_endif4:
    ldur w0, [x29, #-32]
    add w0, w0, #1
    stur w0, [x29, #-32]
    b _loop1
_endloop2:
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
_str5:
    .asciz "FizzBuzz\n"
_str8:
    .asciz "Fizz\n"
_str11:
    .asciz "Buzz\n"
