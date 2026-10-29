.data
.align 3
a:  .double 3.5
b:  .double 4.25
nl: .asciiz "\n"

.text

.globl main
main:
    l.d  $f0, a
    l.d  $f2, b
    add.d $f12, $f0, $f2
    li   $v0, 3
    syscall
    la   $a0, nl
    li   $v0, 4
    syscall
    li   $v0, 10
    syscall
