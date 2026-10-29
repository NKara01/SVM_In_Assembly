# MIPS RBF SVM (MARS 4.5)
# Dataset format: first line "n d", then n lines "label x1 ... xd"
# Labels must be -1 or +1.  Lines beginning with # are comments.

.data

# Global scalars
n_samples:      .word 0
n_features:     .word 0
data_loaded:    .word 0
model_trained:  .word 0
n_sv:           .word 0
sweeps_used:    .word 0
max_sweeps:     .word 2000
best_j:         .word 0
best_yj:        .word 0
parse_ptr:      .word 0
in_fd:          .word 0
in_pos:         .word 0
in_len:         .word 0

# Floating-point constants
.align 3
d_zero:     .double 0.0
d_one:      .double 1.0
d_two:      .double 2.0
d_half:     .double 0.5
d_ten:      .double 10.0
d_tenth:    .double 0.1
d_hundred:  .double 100.0
d_neg700:   .double -700.0
d_log2e:    .double 1.4426950408889634
d_ln2:      .double 0.6931471805599453
d_c8:       .double 2.48015873015873e-5
d_c7:       .double 1.984126984126984e-4
d_c6:       .double 1.388888888888889e-3
d_c5:       .double 8.333333333333333e-3
d_c4:       .double 4.166666666666667e-2
d_c3:       .double 1.666666666666667e-1
d_c2:       .double 0.5

param_C:    .double 1.0
param_gamma:.double 0.5
param_tol:  .double 0.0001
eps_alpha:  .double 1.0e-12
eta_eps:    .double -1.0e-12
small_alpha:.double 1.0e-12

bias:          .double 0.0
best_aj:       .double 0.0
best_aj_new:   .double 0.0

# Arrays
.align 2
y_data:     .space 256
krow:       .space 1024
x_query:    .space 128
x_data:     .space 32768
kernel:     .space 131584

.align 3
alpha:      .space 2048
err_cache:  .space 2048

# Text buffers
pathbuf:    .space 512
linebuf:    .space 2048
filebuf:    .space 4096

# Strings
banner:     .asciiz "\n=== MIPS RBF SVM ===\n1 Load data file\n2 Set parameters\n3 Train\n4 Predict\n5 Evaluate training set\n6 Show model\n7 Exit\nChoice: "
load_prompt:.asciiz "Data file path: "
param_prompt:.asciiz "Enter: C gamma tol max_sweeps\n> "
query_prompt:.asciiz "Enter query features on one line:\n> "
nl:         .asciiz "\n"
msg_loaded: .asciiz "LOADED\n"
msg_n:      .asciiz "N "
msg_d:      .asciiz " D "
msg_trained:.asciiz "TRAINED\n"
msg_sweeps: .asciiz "SWEEPS "
msg_nsv:    .asciiz "N_SV "
msg_bias:   .asciiz "BIAS "
msg_decision:.asciiz "DECISION "
msg_class:  .asciiz "CLASS "
msg_accuracy:.asciiz "ACCURACY "
msg_accpct: .asciiz "ACC_PCT "
msg_eval:   .asciiz "EVAL "
msg_model:  .asciiz "MODEL\n"
msg_sv:     .asciiz "SV "
msg_alpha:  .asciiz " ALPHA "
msg_ay:     .asciiz " AY "
msg_y:      .asciiz " Y "
msg_params: .asciiz "PARAMS "
msg_space:  .asciiz " "
msg_slash:  .asciiz "/"

err_no_data:   .asciiz "ERROR no data loaded\n"
err_no_model:  .asciiz "ERROR model not trained\n"
err_open:      .asciiz "ERROR cannot open file\n"
err_format:    .asciiz "ERROR invalid data format\n"
err_labels:    .asciiz "ERROR labels must be -1 or +1\n"
err_classes:   .asciiz "ERROR need both classes in data\n"
err_limits:    .asciiz "ERROR too many samples or features\n"
err_params:    .asciiz "ERROR invalid parameters\n"
err_query:     .asciiz "ERROR not enough query features\n"
err_choice:    .asciiz "ERROR invalid choice\n"
err_read:      .asciiz "ERROR file read failed\n"

.text

# ===========================================================================
# main / menu
# ===========================================================================
.globl main
main:
    li   $t0, -8
    and  $sp, $sp, $t0

menu:
    la   $a0, banner
    li   $v0, 4
    syscall

    la   $a0, linebuf
    li   $a1, 256
    li   $v0, 8
    syscall

    la   $a0, linebuf
    jal  atoi
    move $t0, $v0

    li   $t1, 1
    beq  $t0, $t1, menu_load
    li   $t1, 2
    beq  $t0, $t1, menu_params
    li   $t1, 3
    beq  $t0, $t1, menu_train
    li   $t1, 4
    beq  $t0, $t1, menu_predict
    li   $t1, 5
    beq  $t0, $t1, menu_eval
    li   $t1, 6
    beq  $t0, $t1, menu_show
    li   $t1, 7
    beq  $t0, $t1, menu_exit

    la   $a0, err_choice
    li   $v0, 4
    syscall
    j    menu

menu_load:
    jal  load_data
    j    menu
menu_params:
    jal  set_params
    j    menu
menu_train:
    jal  train
    j    menu
menu_predict:
    jal  do_predict
    j    menu
menu_eval:
    jal  do_evaluate
    j    menu
menu_show:
    jal  show_model
    j    menu
menu_exit:
    li   $v0, 10
    syscall

# ===========================================================================
# strip_eol(char *s)
# ===========================================================================
strip_eol:
    move $t0, $a0
se_loop:
    lbu  $t1, 0($t0)
    beqz $t1, se_done
    li   $t2, 10
    beq  $t1, $t2, se_zero
    li   $t2, 13
    beq  $t1, $t2, se_zero
    addiu $t0, $t0, 1
    j    se_loop
se_zero:
    sb   $zero, 0($t0)
se_done:
    jr   $ra

# ===========================================================================
# next_token(): pointer to next token, or 0.  Uses/updates parse_ptr.
# ===========================================================================
next_token:
    la   $t0, parse_ptr
    lw   $t1, 0($t0)
nt_skip:
    lbu  $t2, 0($t1)
    beqz $t2, nt_eof
    li   $t3, 35
    beq  $t2, $t3, nt_comment
    li   $t3, 32
    bgt  $t2, $t3, nt_start
    addiu $t1, $t1, 1
    j    nt_skip
nt_comment:
    addiu $t1, $t1, 1
nt_cloop:
    lbu  $t2, 0($t1)
    beqz $t2, nt_eof
    li   $t3, 10
    beq  $t2, $t3, nt_after_nl
    addiu $t1, $t1, 1
    j    nt_cloop
nt_after_nl:
    addiu $t1, $t1, 1
    j    nt_skip
nt_start:
    move $v0, $t1
nt_tloop:
    lbu  $t2, 0($t1)
    beqz $t2, nt_tok_end_null
    li   $t3, 32
    ble  $t2, $t3, nt_tok_end_sep
    li   $t3, 35
    beq  $t2, $t3, nt_tok_end_hash
    addiu $t1, $t1, 1
    j    nt_tloop
nt_tok_end_sep:
    sb   $zero, 0($t1)
    addiu $t1, $t1, 1
    j    nt_store
nt_tok_end_hash:
    sb   $zero, 0($t1)
    addiu $t1, $t1, 1
nt_hash_scan:
    lbu  $t2, 0($t1)
    beqz $t2, nt_eof
    li   $t3, 10
    beq  $t2, $t3, nt_hash_nl
    addiu $t1, $t1, 1
    j    nt_hash_scan
nt_hash_nl:
    addiu $t1, $t1, 1
    j    nt_store
nt_tok_end_null:
nt_store:
    sw   $t1, 0($t0)
    jr   $ra
nt_eof:
    sw   $t1, 0($t0)
    li   $v0, 0
    jr   $ra

# ===========================================================================
# atoi(char *s) -> $v0
# ===========================================================================
atoi:
    move $t0, $a0
    li   $v0, 0
    li   $t1, 1
    lbu  $t2, 0($t0)
    li   $t3, 45
    bne  $t2, $t3, ai_plus
    li   $t1, -1
    addiu $t0, $t0, 1
    j    ai_loop
ai_plus:
    li   $t3, 43
    bne  $t2, $t3, ai_loop
    addiu $t0, $t0, 1
ai_loop:
    lbu  $t2, 0($t0)
    li   $t3, 48
    blt  $t2, $t3, ai_done
    li   $t3, 57
    bgt  $t2, $t3, ai_done
    addiu $t2, $t2, -48
    mul  $v0, $v0, 10
    addu $v0, $v0, $t2
    addiu $t0, $t0, 1
    j    ai_loop
ai_done:
    mul  $v0, $v0, $t1
    jr   $ra

# ===========================================================================
# atof(char *s) -> $f0
# ===========================================================================
atof:
    move $t0, $a0
    li   $t1, 1
    lbu  $t2, 0($t0)
    li   $t3, 45
    bne  $t2, $t3, af_plus
    li   $t1, -1
    addiu $t0, $t0, 1
    j    af_int_init
af_plus:
    li   $t3, 43
    bne  $t2, $t3, af_int_init
    addiu $t0, $t0, 1
af_int_init:
    l.d  $f0, d_zero
af_iloop:
    lbu  $t2, 0($t0)
    li   $t3, 48
    blt  $t2, $t3, af_after_int
    li   $t3, 57
    bgt  $t2, $t3, af_after_int
    addiu $t2, $t2, -48
    mtc1 $t2, $f2
    cvt.d.w $f2, $f2
    l.d  $f4, d_ten
    mul.d $f0, $f0, $f4
    add.d $f0, $f0, $f2
    addiu $t0, $t0, 1
    j    af_iloop
af_after_int:
    lbu  $t2, 0($t0)
    li   $t3, 46
    bne  $t2, $t3, af_exp_check
    addiu $t0, $t0, 1
    l.d  $f6, d_tenth
af_floop:
    lbu  $t2, 0($t0)
    li   $t3, 48
    blt  $t2, $t3, af_exp_check
    li   $t3, 57
    bgt  $t2, $t3, af_exp_check
    addiu $t2, $t2, -48
    mtc1 $t2, $f2
    cvt.d.w $f2, $f2
    mul.d $f2, $f2, $f6
    add.d $f0, $f0, $f2
    l.d  $f4, d_tenth
    mul.d $f6, $f6, $f4
    addiu $t0, $t0, 1
    j    af_floop
af_exp_check:
    lbu  $t2, 0($t0)
    li   $t3, 101
    beq  $t2, $t3, af_exp
    li   $t3, 69
    beq  $t2, $t3, af_exp
    j    af_apply_sign
af_exp:
    addiu $t0, $t0, 1
    li   $t4, 1
    lbu  $t2, 0($t0)
    li   $t3, 45
    bne  $t2, $t3, af_exp_plus
    li   $t4, -1
    addiu $t0, $t0, 1
    j    af_exp_digits
af_exp_plus:
    li   $t3, 43
    bne  $t2, $t3, af_exp_digits
    addiu $t0, $t0, 1
af_exp_digits:
    li   $t5, 0
af_eloop:
    lbu  $t2, 0($t0)
    li   $t3, 48
    blt  $t2, $t3, af_exp_apply
    li   $t3, 57
    bgt  $t2, $t3, af_exp_apply
    addiu $t2, $t2, -48
    mul  $t5, $t5, 10
    addu $t5, $t5, $t2
    addiu $t0, $t0, 1
    j    af_eloop
af_exp_apply:
    beqz $t5, af_apply_sign
    li   $t6, -1
    beq  $t4, $t6, af_ediv
af_emul:
    l.d  $f4, d_ten
    mul.d $f0, $f0, $f4
    addiu $t5, $t5, -1
    bgtz $t5, af_emul
    j    af_apply_sign
af_ediv:
    l.d  $f4, d_ten
    div.d $f0, $f0, $f4
    addiu $t5, $t5, -1
    bgtz $t5, af_ediv
af_apply_sign:
    bltz $t1, af_neg
    jr   $ra
af_neg:
    neg.d $f0, $f0
    jr   $ra

# ===========================================================================
# double dist2(float *a, float *b, int n) -> $f0
# ===========================================================================
dist2:
    l.d  $f0, d_zero
    li   $t0, 0
d2_loop:
    beq  $t0, $a2, d2_done
    sll  $t1, $t0, 2
    addu $t2, $a0, $t1
    addu $t3, $a1, $t1
    l.s  $f2, 0($t2)
    l.s  $f4, 0($t3)
    cvt.d.s $f2, $f2
    cvt.d.s $f4, $f4
    sub.d $f2, $f2, $f4
    mul.d $f2, $f2, $f2
    add.d $f0, $f0, $f2
    addiu $t0, $t0, 1
    j    d2_loop
d2_done:
    jr   $ra

# ===========================================================================
# double exp(double x) for x <= 0 -> $f0
# ===========================================================================
exp:
    l.d   $f2, d_neg700
    c.lt.d $f12, $f2
    bc1t  exp_zero

    l.d   $f4, d_log2e
    mul.d $f6, $f12, $f4
    round.w.d $f8, $f6
    mfc1  $t0, $f8

    mtc1  $t0, $f10
    cvt.d.w $f10, $f10
    l.d   $f14, d_ln2
    mul.d $f10, $f10, $f14
    sub.d $f12, $f12, $f10

    l.d   $f0, d_c8
    mul.d $f0, $f0, $f12
    l.d   $f2, d_c7
    add.d $f0, $f0, $f2
    mul.d $f0, $f0, $f12
    l.d   $f2, d_c6
    add.d $f0, $f0, $f2
    mul.d $f0, $f0, $f12
    l.d   $f2, d_c5
    add.d $f0, $f0, $f2
    mul.d $f0, $f0, $f12
    l.d   $f2, d_c4
    add.d $f0, $f0, $f2
    mul.d $f0, $f0, $f12
    l.d   $f2, d_c3
    add.d $f0, $f0, $f2
    mul.d $f0, $f0, $f12
    l.d   $f2, d_c2
    add.d $f0, $f0, $f2
    mul.d $f0, $f0, $f12
    l.d   $f2, d_one
    add.d $f0, $f0, $f2
    mul.d $f0, $f0, $f12
    l.d   $f2, d_one
    add.d $f0, $f0, $f2

    sra   $t3, $t0, 31
    xor   $t1, $t0, $t3
    subu  $t1, $t1, $t3
    l.d   $f16, d_two
    bgez  $t0, exp_scale_init
    l.d   $f16, d_half
exp_scale_init:
    l.d   $f18, d_one
exp_scale_loop:
    beqz  $t1, exp_scale_done
    andi  $t2, $t1, 1
    beqz  $t2, exp_no_mul
    mul.d $f18, $f18, $f16
exp_no_mul:
    mul.d $f16, $f16, $f16
    srl   $t1, $t1, 1
    j     exp_scale_loop
exp_scale_done:
    mul.d $f0, $f0, $f18
    jr    $ra

exp_zero:
    l.d   $f0, d_zero
    jr    $ra

# ===========================================================================
# build_krow(): krow[i] = i*(i+1)/2, row base of lower-triangular kernel
# ===========================================================================
build_krow:
    la   $t0, n_samples
    lw   $t1, 0($t0)
    la   $t2, krow
    sw   $zero, 0($t2)
    li   $t3, 1
    li   $t4, 0
bk_loop:
    bge  $t3, $t1, bk_done
    addu $t4, $t4, $t3
    sll  $t5, $t3, 2
    addu $t6, $t2, $t5
    sw   $t4, 0($t6)
    addiu $t3, $t3, 1
    j    bk_loop
bk_done:
    jr   $ra

# ===========================================================================
# kaddr(i, j): address of symmetric kernel element K(i,j)
#   a0=i, a1=j -> v0 = kernel + (krow[max(i,j)] + min(i,j))*4
# Uses only $k0/$k1 so caller temporaries survive.
# ===========================================================================
kaddr:
    move $k0, $a0
    move $k1, $a1
    bge  $k0, $k1, kaddr_ordered
    move $v0, $k0
    move $k0, $k1
    move $k1, $v0
kaddr_ordered:
    la   $v0, krow
    sll  $a0, $k0, 2
    addu $v0, $v0, $a0
    lw   $v0, 0($v0)
    addu $v0, $v0, $k1
    sll  $v0, $v0, 2
    la   $a0, kernel
    addu $v0, $a0, $v0
    jr   $ra

# ===========================================================================
# compute_kernel(): lower-triangular float kernel, K(i,j)=exp(-gamma*||xi-xj||^2)
# ===========================================================================
compute_kernel:
    subu $sp, $sp, 24
    sw   $ra, 20($sp)
    sw   $s0, 0($sp)
    sw   $s1, 4($sp)
    sw   $s2, 8($sp)
    sw   $s3, 12($sp)
    sw   $s4, 16($sp)

    la   $t0, n_samples
    lw   $s0, 0($t0)
    la   $t0, n_features
    lw   $s1, 0($t0)
    la   $s4, x_data
    li   $s2, 0

ck_i:
    bge  $s2, $s0, ck_done
    li   $s3, 0
ck_j:
    bgt  $s3, $s2, ck_inext

    mul  $t0, $s2, $s1
    sll  $t0, $t0, 2
    addu $a0, $s4, $t0
    mul  $t0, $s3, $s1
    sll  $t0, $t0, 2
    addu $a1, $s4, $t0
    move $a2, $s1
    jal  dist2

    l.d  $f2, param_gamma
    mul.d $f0, $f0, $f2
    neg.d $f12, $f0
    jal  exp

    cvt.s.d $f0, $f0
    move $a0, $s2
    move $a1, $s3
    jal  kaddr
    s.s  $f0, 0($v0)

    addiu $s3, $s3, 1
    j    ck_j
ck_inext:
    addiu $s2, $s2, 1
    j    ck_i
ck_done:
    lw   $ra, 20($sp)
    lw   $s0, 0($sp)
    lw   $s1, 4($sp)
    lw   $s2, 8($sp)
    lw   $s3, 12($sp)
    lw   $s4, 16($sp)
    addiu $sp, $sp, 24
    jr   $ra

# ===========================================================================
# train(): SMO training for RBF SVM
# ===========================================================================
train:
    subu $sp, $sp, 88
    sw   $ra, 80($sp)
    sw   $s0, 48($sp)
    sw   $s1, 52($sp)
    sw   $s2, 56($sp)
    sw   $s3, 60($sp)
    sw   $s4, 64($sp)
    sw   $s5, 68($sp)
    sw   $s6, 72($sp)
    sw   $s7, 76($sp)
    s.d  $f20, 0($sp)
    s.d  $f22, 8($sp)
    s.d  $f24, 16($sp)
    s.d  $f26, 24($sp)
    s.d  $f28, 32($sp)
    s.d  $f30, 40($sp)

    la   $t0, data_loaded
    lw   $t1, 0($t0)
    beqz $t1, tr_no_data

    la   $t0, n_samples
    lw   $s0, 0($t0)

    # require at least one example of each class
    li   $t0, 0
    li   $t1, 0
    li   $t2, 0
tr_bc_loop:
    bge  $t0, $s0, tr_bc_done
    la   $t4, y_data
    addu $t4, $t4, $t0
    lb   $t5, 0($t4)
    li   $t6, 1
    beq  $t5, $t6, tr_bc_pos
    addiu $t2, $t2, 1
    j    tr_bc_next
tr_bc_pos:
    addiu $t1, $t1, 1
tr_bc_next:
    addiu $t0, $t0, 1
    j    tr_bc_loop
tr_bc_done:
    beqz $t1, tr_no_classes
    beqz $t2, tr_no_classes

    # alpha = 0, E = -y, b = 0
    li   $t0, 0
tr_init_loop:
    bge  $t0, $s0, tr_init_done
    sll  $t1, $t0, 3
    la   $t2, alpha
    addu $t2, $t2, $t1
    l.d  $f0, d_zero
    s.d  $f0, 0($t2)

    la   $t2, y_data
    addu $t2, $t2, $t0
    lb   $t3, 0($t2)
    mtc1 $t3, $f0
    cvt.d.w $f0, $f0
    neg.d $f0, $f0
    la   $t2, err_cache
    addu $t2, $t2, $t1
    s.d  $f0, 0($t2)

    addiu $t0, $t0, 1
    j    tr_init_loop
tr_init_done:
    l.d  $f20, d_zero

    jal  build_krow
    jal  compute_kernel

    l.d  $f22, param_C
    l.d  $f24, param_tol
    l.d  $f26, eps_alpha
    l.d  $f28, eta_eps

    li   $s6, 0
tr_outer:
    la   $t0, max_sweeps
    lw   $t1, 0($t0)
    bge  $s6, $t1, tr_done
    addiu $s6, $s6, 1
    li   $s7, 0
    li   $s5, 0

tr_i_loop:
    bge  $s5, $s0, tr_end_i

    sll  $t0, $s5, 3
    la   $t1, alpha
    addu $t1, $t1, $t0
    l.d  $f18, 0($t1)                # ai
    la   $t1, err_cache
    addu $t1, $t1, $t0
    l.d  $f14, 0($t1)                # Ei

    la   $t1, y_data
    addu $t1, $t1, $s5
    lb   $t8, 0($t1)                 # yi
    mtc1 $t8, $f16
    cvt.d.w $f16, $f16

    mul.d $f2, $f16, $f14            # yi*Ei

    c.lt.d $f18, $f22
    bc1f tr_kkt_high
    neg.d $f6, $f24
    c.lt.d $f2, $f6
    bc1t tr_active
tr_kkt_high:
    l.d  $f6, d_zero
    c.le.d $f18, $f6
    bc1t tr_next_i
    c.le.d $f2, $f24
    bc1t tr_next_i

tr_active:
    l.d  $f30, d_zero
    li   $t4, 0

tr_j_loop:
    bge  $t4, $s0, tr_j_done
    beq  $t4, $s5, tr_j_next

    sll  $t0, $t4, 3
    la   $t1, alpha
    addu $t1, $t1, $t0
    l.d  $f2, 0($t1)                 # aj

    la   $t1, y_data
    addu $t1, $t1, $t4
    lb   $t6, 0($t1)                 # yj
    mtc1 $t6, $f0
    cvt.d.w $f0, $f0

    bne  $t6, $t8, tr_opposite

    # same class: L=max(0,ai+aj-C), H=min(C,ai+aj)
    add.d $f6, $f18, $f2
    sub.d $f8, $f6, $f22
    l.d  $f10, d_zero
    c.lt.d $f8, $f10
    bc1t tr_same_L
    mov.d $f10, $f8
tr_same_L:
    mov.d $f12, $f22
    c.lt.d $f6, $f12
    bc1f tr_have_bounds
    mov.d $f12, $f6
    j    tr_have_bounds

tr_opposite:
    # different class: L=max(0,aj-ai), H=min(C,C+aj-ai)
    sub.d $f8, $f2, $f18
    l.d  $f10, d_zero
    c.lt.d $f8, $f10
    bc1t tr_opp_L
    mov.d $f10, $f8
tr_opp_L:
    add.d $f6, $f22, $f8
    mov.d $f12, $f22
    c.lt.d $f6, $f12
    bc1f tr_have_bounds
    mov.d $f12, $f6

tr_have_bounds:
    c.le.d $f12, $f10
    bc1t tr_j_next

    # eta = 2*Kij - Kii - Kjj
    move $a0, $s5
    move $a1, $s5
    jal  kaddr
    l.s  $f6, 0($v0)                 # Kii
    cvt.d.s $f6, $f6

    move $a0, $s5
    move $a1, $t4
    jal  kaddr
    l.s  $f8, 0($v0)                 # Kij
    cvt.d.s $f8, $f8

    add.d $f8, $f8, $f8
    sub.d $f8, $f8, $f6

    move $a0, $t4
    move $a1, $t4
    jal  kaddr
    l.s  $f6, 0($v0)                 # Kjj
    cvt.d.s $f6, $f6
    sub.d $f8, $f8, $f6              # eta

    c.lt.d $f8, $f28
    bc1f tr_j_next

    sll  $t0, $t4, 3
    la   $t1, err_cache
    addu $t1, $t1, $t0
    l.d  $f6, 0($t1)                 # Ej
    sub.d $f6, $f14, $f6             # Ei-Ej
    mul.d $f6, $f6, $f0              # *yj
    div.d $f6, $f6, $f8              # /eta
    sub.d $f6, $f2, $f6              # aj_new

    c.lt.d $f6, $f10
    bc1t tr_clip_L
    c.lt.d $f12, $f6
    bc1t tr_clip_H
    j    tr_clipped
tr_clip_L:
    mov.d $f6, $f10
    j    tr_clipped
tr_clip_H:
    mov.d $f6, $f12

tr_clipped:
    sub.d $f8, $f6, $f2
    abs.d $f8, $f8
    c.lt.d $f30, $f8
    bc1f tr_j_next
    mov.d $f30, $f8
    s.d  $f6, best_aj_new
    s.d  $f2, best_aj
    sw   $t6, best_yj
    sw   $t4, best_j

tr_j_next:
    addiu $t4, $t4, 1
    j    tr_j_loop

tr_j_done:
    c.lt.d $f26, $f30
    bc1f tr_next_i

    lw   $t4, best_j
    l.d  $f2, best_aj
    l.d  $f6, best_aj_new
    lw   $t6, best_yj
    mtc1 $t6, $f0
    cvt.d.w $f0, $f0

    # ai_new = ai_old + yi*yj*(aj_old-aj_new)
    sub.d $f4, $f2, $f6
    mul.d $f4, $f4, $f16
    mul.d $f4, $f4, $f0
    add.d $f4, $f18, $f4

    # day_i = yi*(ai_new-ai_old), day_j = yj*(aj_new-aj_old)
    sub.d $f10, $f4, $f18
    mul.d $f10, $f10, $f16
    sub.d $f12, $f6, $f2
    mul.d $f12, $f12, $f0

    mov.d $f8, $f20                  # b_old

    # b1 = b - Ei - day_i*Kii - day_j*Kij, in f0
    mov.d $f0, $f20
    sub.d $f0, $f0, $f14
    move $a0, $s5
    move $a1, $s5
    jal  kaddr
    l.s  $f14, 0($v0)
    cvt.d.s $f14, $f14
    mul.d $f14, $f10, $f14
    sub.d $f0, $f0, $f14

    move $a0, $s5
    move $a1, $t4
    jal  kaddr
    l.s  $f14, 0($v0)
    cvt.d.s $f14, $f14
    mul.d $f14, $f12, $f14
    sub.d $f0, $f0, $f14             # b1

    # b2 = b - Ej - day_i*Kij - day_j*Kjj, in f2
    sll  $t0, $t4, 3
    la   $t1, err_cache
    addu $t1, $t1, $t0
    l.d  $f14, 0($t1)                # Ej
    mov.d $f2, $f20
    sub.d $f2, $f2, $f14

    move $a0, $s5
    move $a1, $t4
    jal  kaddr
    l.s  $f14, 0($v0)
    cvt.d.s $f14, $f14
    mul.d $f14, $f10, $f14
    sub.d $f2, $f2, $f14

    move $a0, $t4
    move $a1, $t4
    jal  kaddr
    l.s  $f14, 0($v0)
    cvt.d.s $f14, $f14
    mul.d $f14, $f12, $f14
    sub.d $f2, $f2, $f14             # b2

    l.d  $f14, d_zero
    c.le.d $f4, $f14
    bc1t tr_b_check_aj
    c.lt.d $f4, $f22
    bc1t tr_b_use_b1
tr_b_check_aj:
    c.le.d $f6, $f14
    bc1t tr_b_avg
    c.lt.d $f6, $f22
    bc1t tr_b_use_b2
tr_b_avg:
    add.d $f20, $f0, $f2
    l.d  $f14, d_half
    mul.d $f20, $f20, $f14
    j    tr_b_done
tr_b_use_b1:
    mov.d $f20, $f0
    j    tr_b_done
tr_b_use_b2:
    mov.d $f20, $f2

tr_b_done:
    sll  $t0, $s5, 3
    la   $t1, alpha
    addu $t1, $t1, $t0
    s.d  $f4, 0($t1)
    sll  $t0, $t4, 3
    la   $t1, alpha
    addu $t1, $t1, $t0
    s.d  $f6, 0($t1)

    sub.d $f8, $f20, $f8             # db

    li   $t0, 0
tr_k_loop:
    bge  $t0, $s0, tr_k_done

    sll  $t1, $t0, 3
    la   $t2, err_cache
    addu $t2, $t2, $t1
    l.d  $f2, 0($t2)                 # E[k]

    move $a0, $t0
    move $a1, $s5
    jal  kaddr
    l.s  $f4, 0($v0)
    cvt.d.s $f4, $f4
    mul.d $f4, $f4, $f10

    move $a0, $t0
    move $a1, $t4
    jal  kaddr
    l.s  $f6, 0($v0)
    cvt.d.s $f6, $f6
    mul.d $f6, $f6, $f12

    add.d $f4, $f4, $f6
    add.d $f4, $f4, $f8
    add.d $f2, $f2, $f4
    s.d  $f2, 0($t2)

    addiu $t0, $t0, 1
    j    tr_k_loop

tr_k_done:
    li   $s7, 1

tr_next_i:
    addiu $s5, $s5, 1
    j    tr_i_loop

tr_end_i:
    beqz $s7, tr_done
    j    tr_outer

tr_done:
    la   $t0, sweeps_used
    sw   $s6, 0($t0)
    la   $t0, bias
    s.d  $f20, 0($t0)

    # count support vectors
    li   $t0, 0
    li   $t1, 0
tr_sv_loop:
    bge  $t0, $s0, tr_sv_done
    sll  $t2, $t0, 3
    la   $t3, alpha
    addu $t3, $t3, $t2
    l.d  $f0, 0($t3)
    l.d  $f2, small_alpha
    c.lt.d $f2, $f0
    bc1f tr_sv_zero
    addiu $t1, $t1, 1
tr_sv_zero:
    addiu $t0, $t0, 1
    j    tr_sv_loop

tr_sv_done:
    la   $t0, n_sv
    sw   $t1, 0($t0)
    la   $t0, model_trained
    li   $t1, 1
    sw   $t1, 0($t0)

    la   $a0, msg_trained
    li   $v0, 4
    syscall

    la   $a0, msg_sweeps
    li   $v0, 4
    syscall
    la   $t0, sweeps_used
    lw   $a0, 0($t0)
    li   $v0, 1
    syscall
    la   $a0, nl
    li   $v0, 4
    syscall

    la   $a0, msg_nsv
    li   $v0, 4
    syscall
    la   $t0, n_sv
    lw   $a0, 0($t0)
    li   $v0, 1
    syscall
    la   $a0, nl
    li   $v0, 4
    syscall

    la   $a0, msg_bias
    li   $v0, 4
    syscall
    l.d  $f12, bias
    li   $v0, 3
    syscall
    la   $a0, nl
    li   $v0, 4
    syscall
    j    tr_restore

tr_no_data:
    la   $a0, err_no_data
    li   $v0, 4
    syscall
    j    tr_restore
tr_no_classes:
    la   $a0, err_classes
    li   $v0, 4
    syscall

tr_restore:
    lw   $ra, 80($sp)
    lw   $s0, 48($sp)
    lw   $s1, 52($sp)
    lw   $s2, 56($sp)
    lw   $s3, 60($sp)
    lw   $s4, 64($sp)
    lw   $s5, 68($sp)
    lw   $s6, 72($sp)
    lw   $s7, 76($sp)
    l.d  $f20, 0($sp)
    l.d  $f22, 8($sp)
    l.d  $f24, 16($sp)
    l.d  $f26, 24($sp)
    l.d  $f28, 32($sp)
    l.d  $f30, 40($sp)
    addiu $sp, $sp, 88
    jr   $ra

# ===========================================================================
# double predict_one(double *x) -> $f0
# ===========================================================================
predict_one:
    subu $sp, $sp, 40
    sw   $ra, 36($sp)
    sw   $s0, 8($sp)
    sw   $s1, 12($sp)
    sw   $s2, 16($sp)
    sw   $s3, 20($sp)
    sw   $s4, 24($sp)
    sw   $s5, 28($sp)
    sw   $s6, 32($sp)
    s.d  $f20, 0($sp)

    move $s0, $a0
    la   $t0, n_samples
    lw   $s3, 0($t0)
    la   $t0, n_features
    lw   $s1, 0($t0)
    la   $s4, x_data
    la   $s5, alpha
    l.d  $f20, bias
    li   $s2, 0

po_loop:
    bge  $s2, $s3, po_done

    mul  $t0, $s2, $s1
    sll  $t0, $t0, 3
    addu $a1, $s4, $t0
    move $a0, $s0
    move $a2, $s1
    jal  dist2

    l.d  $f2, param_gamma
    mul.d $f0, $f0, $f2
    neg.d $f12, $f0
    jal  exp

    # $f0 = K, multiply by alpha_i then y_i
    sll  $t0, $s2, 3
    addu $t1, $s5, $t0
    l.d  $f2, 0($t1)            # $f2 = alpha_i
    mul.d $f0, $f0, $f2         # $f0 = K * alpha_i

    la   $t1, y_data
    addu $t1, $t1, $s2
    lb   $t6, 0($t1)            # $t6 = y_i byte
    mtc1 $t6, $f4
    cvt.d.w $f4, $f4            # $f4 = y_i as double (±1.0)
    mul.d $f0, $f0, $f4         # $f0 = K * alpha_i * y_i
    add.d $f20, $f20, $f0

    addiu $s2, $s2, 1
    j    po_loop

po_done:
    mov.d $f0, $f20
    lw   $ra, 36($sp)
    lw   $s0, 8($sp)
    lw   $s1, 12($sp)
    lw   $s2, 16($sp)
    lw   $s3, 20($sp)
    lw   $s4, 24($sp)
    lw   $s5, 28($sp)
    lw   $s6, 32($sp)
    l.d  $f20, 0($sp)
    addiu $sp, $sp, 40
    jr   $ra

# ===========================================================================
# load_data()
# ===========================================================================
load_data:
    subu $sp, $sp, 32
    sw   $ra, 28($sp)
    sw   $s0, 0($sp)
    sw   $s1, 4($sp)
    sw   $s2, 8($sp)
    sw   $s3, 12($sp)
    sw   $s4, 16($sp)
    sw   $s5, 20($sp)
    sw   $s6, 24($sp)

    la   $a0, load_prompt
    li   $v0, 4
    syscall
    la   $a0, pathbuf
    li   $a1, 512
    li   $v0, 8
    syscall
    la   $a0, pathbuf
    jal  strip_eol

    la   $a0, pathbuf
    li   $a1, 0
    li   $a2, 0
    li   $v0, 13
    syscall
    bltz $v0, ld_open_err
    move $s0, $v0

    li   $s5, 0
ld_read_loop:
    li   $t0, 262000
    subu $t1, $t0, $s5
    blez $t1, ld_read_done
    la   $t2, filebuf
    addu $t2, $t2, $s5
    move $a0, $s0
    move $a1, $t2
    move $a2, $t1
    li   $v0, 14
    syscall
    bltz $v0, ld_read_err
    beqz $v0, ld_read_done
    addu $s5, $s5, $v0
    j    ld_read_loop

ld_read_done:
    move $a0, $s0
    li   $v0, 16
    syscall

    la   $t0, filebuf
    addu $t0, $t0, $s5
    sb   $zero, 0($t0)
    la   $t0, filebuf
    la   $t1, parse_ptr
    sw   $t0, 0($t1)

    jal  next_token
    beqz $v0, ld_format_err
    move $a0, $v0
    jal  atoi
    move $s1, $v0

    jal  next_token
    beqz $v0, ld_format_err
    move $a0, $v0
    jal  atoi
    move $s2, $v0

    li   $t0, 1
    blt  $s1, $t0, ld_format_err
    li   $t0, 256
    bgt  $s1, $t0, ld_limits_err
    li   $t0, 1
    blt  $s2, $t0, ld_format_err
    li   $t0, 32
    bgt  $s2, $t0, ld_limits_err

    li   $s3, 0
ld_i_loop:
    bge  $s3, $s1, ld_parsed

    jal  next_token
    beqz $v0, ld_format_err
    move $a0, $v0
    jal  atoi
    move $s6, $v0
    li   $t0, 1
    beq  $s6, $t0, ld_label_ok
    li   $t0, -1
    bne  $s6, $t0, ld_label_err
ld_label_ok:
    sll  $t0, $s3, 2
    la   $t1, y_data
    addu $t1, $t1, $t0
    sw   $s6, 0($t1)

    li   $s4, 0
ld_j_loop:
    bge  $s4, $s2, ld_i_next
    jal  next_token
    beqz $v0, ld_format_err
    move $a0, $v0
    jal  atof

    mul  $t0, $s3, $s2
    addu $t0, $t0, $s4
    sll  $t0, $t0, 3
    la   $t1, x_data
    addu $t1, $t1, $t0
    s.d  $f0, 0($t1)

    addiu $s4, $s4, 1
    j    ld_j_loop
ld_i_next:
    addiu $s3, $s3, 1
    j    ld_i_loop

ld_parsed:
    la   $t0, n_samples
    sw   $s1, 0($t0)
    la   $t0, n_features
    sw   $s2, 0($t0)
    la   $t0, data_loaded
    li   $t1, 1
    sw   $t1, 0($t0)
    la   $t0, model_trained
    sw   $zero, 0($t0)

    la   $a0, msg_loaded
    li   $v0, 4
    syscall
    la   $a0, msg_n
    li   $v0, 4
    syscall
    move $a0, $s1
    li   $v0, 1
    syscall
    la   $a0, msg_d
    li   $v0, 4
    syscall
    move $a0, $s2
    li   $v0, 1
    syscall
    la   $a0, nl
    li   $v0, 4
    syscall
    j    ld_restore

ld_open_err:
    la   $a0, err_open
    li   $v0, 4
    syscall
    j    ld_restore
ld_read_err:
    move $a0, $s0
    li   $v0, 16
    syscall
    la   $a0, err_read
    li   $v0, 4
    syscall
    j    ld_restore
ld_format_err:
    la   $a0, err_format
    li   $v0, 4
    syscall
    j    ld_restore
ld_label_err:
    la   $a0, err_labels
    li   $v0, 4
    syscall
    j    ld_restore
ld_limits_err:
    la   $a0, err_limits
    li   $v0, 4
    syscall

ld_restore:
    lw   $ra, 28($sp)
    lw   $s0, 0($sp)
    lw   $s1, 4($sp)
    lw   $s2, 8($sp)
    lw   $s3, 12($sp)
    lw   $s4, 16($sp)
    lw   $s5, 20($sp)
    lw   $s6, 24($sp)
    addiu $sp, $sp, 32
    jr   $ra

# ===========================================================================
# set_params()
# ===========================================================================
set_params:
    subu $sp, $sp, 16
    sw   $ra, 12($sp)
    sw   $s0, 8($sp)

    la   $a0, param_prompt
    li   $v0, 4
    syscall
    la   $a0, linebuf
    li   $a1, 512
    li   $v0, 8
    syscall
    la   $t0, linebuf
    la   $t1, parse_ptr
    sw   $t0, 0($t1)

    jal  next_token
    beqz $v0, sp_bad
    move $a0, $v0
    jal  atof
    l.d  $f2, d_zero
    c.le.d $f0, $f2
    bc1t sp_bad
    s.d  $f0, param_C

    jal  next_token
    beqz $v0, sp_bad
    move $a0, $v0
    jal  atof
    l.d  $f2, d_zero
    c.le.d $f0, $f2
    bc1t sp_bad
    s.d  $f0, param_gamma

    jal  next_token
    beqz $v0, sp_bad
    move $a0, $v0
    jal  atof
    l.d  $f2, d_zero
    c.le.d $f0, $f2
    bc1t sp_bad
    s.d  $f0, param_tol

    jal  next_token
    beqz $v0, sp_bad
    move $a0, $v0
    jal  atoi
    blez $v0, sp_bad
    la   $t0, max_sweeps
    sw   $v0, 0($t0)

    la   $a0, msg_params
    li   $v0, 4
    syscall
    l.d  $f12, param_C
    li   $v0, 3
    syscall
    la   $a0, msg_space
    li   $v0, 4
    syscall
    l.d  $f12, param_gamma
    li   $v0, 3
    syscall
    la   $a0, msg_space
    li   $v0, 4
    syscall
    l.d  $f12, param_tol
    li   $v0, 3
    syscall
    la   $a0, msg_space
    li   $v0, 4
    syscall
    la   $t0, max_sweeps
    lw   $a0, 0($t0)
    li   $v0, 1
    syscall
    la   $a0, nl
    li   $v0, 4
    syscall
    j    sp_restore

sp_bad:
    la   $a0, err_params
    li   $v0, 4
    syscall

sp_restore:
    lw   $ra, 12($sp)
    lw   $s0, 8($sp)
    addiu $sp, $sp, 16
    jr   $ra

# ===========================================================================
# do_predict()
# ===========================================================================
do_predict:
    subu $sp, $sp, 32
    sw   $ra, 24($sp)
    sw   $s0, 8($sp)
    sw   $s1, 12($sp)
    sw   $s2, 16($sp)
    sw   $s3, 20($sp)
    s.d  $f22, 0($sp)

    la   $t0, data_loaded
    lw   $t1, 0($t0)
    beqz $t1, dp_no_data
    la   $t0, model_trained
    lw   $t1, 0($t0)
    beqz $t1, dp_no_model

    la   $a0, query_prompt
    li   $v0, 4
    syscall
    la   $a0, linebuf
    li   $a1, 4096
    li   $v0, 8
    syscall
    la   $t0, linebuf
    la   $t1, parse_ptr
    sw   $t0, 0($t1)

    la   $t0, n_features
    lw   $s0, 0($t0)
    li   $s1, 0
dp_parse_loop:
    bge  $s1, $s0, dp_parsed
    jal  next_token
    beqz $v0, dp_bad_query
    move $a0, $v0
    jal  atof
    sll  $t0, $s1, 3
    la   $t1, x_query
    addu $t1, $t1, $t0
    s.d  $f0, 0($t1)
    addiu $s1, $s1, 1
    j    dp_parse_loop

dp_parsed:
    la   $a0, x_query
    jal  predict_one
    mov.d $f22, $f0

    la   $a0, msg_decision
    li   $v0, 4
    syscall
    mov.d $f12, $f22
    li   $v0, 3
    syscall
    la   $a0, nl
    li   $v0, 4
    syscall

    l.d  $f2, d_zero
    c.le.d $f22, $f2
    bc1t dp_class_neg
    la   $a0, msg_class
    li   $v0, 4
    syscall
    li   $a0, 1
    li   $v0, 1
    syscall
    la   $a0, nl
    li   $v0, 4
    syscall
    j    dp_restore

dp_class_neg:
    la   $a0, msg_class
    li   $v0, 4
    syscall
    li   $a0, -1
    li   $v0, 1
    syscall
    la   $a0, nl
    li   $v0, 4
    syscall
    j    dp_restore

dp_no_data:
    la   $a0, err_no_data
    li   $v0, 4
    syscall
    j    dp_restore
dp_no_model:
    la   $a0, err_no_model
    li   $v0, 4
    syscall
    j    dp_restore
dp_bad_query:
    la   $a0, err_query
    li   $v0, 4
    syscall

dp_restore:
    lw   $ra, 24($sp)
    lw   $s0, 8($sp)
    lw   $s1, 12($sp)
    lw   $s2, 16($sp)
    lw   $s3, 20($sp)
    l.d  $f22, 0($sp)
    addiu $sp, $sp, 32
    jr   $ra

# ===========================================================================
# do_evaluate()
# ===========================================================================
do_evaluate:
    subu $sp, $sp, 32
    sw   $ra, 24($sp)
    sw   $s0, 0($sp)
    sw   $s1, 4($sp)
    sw   $s2, 8($sp)
    sw   $s3, 12($sp)
    sw   $s4, 16($sp)
    sw   $s5, 20($sp)

    la   $t0, data_loaded
    lw   $t1, 0($t0)
    beqz $t1, de_no_data
    la   $t0, model_trained
    lw   $t1, 0($t0)
    beqz $t1, de_no_model

    la   $t0, n_samples
    lw   $s0, 0($t0)
    la   $t0, n_features
    lw   $s3, 0($t0)
    la   $s4, x_data
    la   $s5, y_data
    li   $s1, 0
    li   $s2, 0

de_loop:
    bge  $s1, $s0, de_done
    mul  $t0, $s1, $s3
    sll  $t0, $t0, 3
    addu $a0, $s4, $t0
    jal  predict_one

    sll  $t0, $s1, 2
    addu $t1, $s5, $t0
    lw   $t2, 0($t1)
    l.d  $f2, d_zero
    c.le.d $f0, $f2
    bc1t de_pred_neg
    li   $t3, 1
    j    de_pred_have
de_pred_neg:
    li   $t3, -1
de_pred_have:
    bne  $t2, $t3, de_next
    addiu $s2, $s2, 1
de_next:
    addiu $s1, $s1, 1
    j    de_loop

de_done:
    la   $a0, msg_eval
    li   $v0, 4
    syscall
    move $a0, $s2
    li   $v0, 1
    syscall
    la   $a0, msg_slash
    li   $v0, 4
    syscall
    move $a0, $s0
    li   $v0, 1
    syscall
    la   $a0, nl
    li   $v0, 4
    syscall

    mtc1 $s2, $f4
    cvt.d.w $f4, $f4
    mtc1 $s0, $f6
    cvt.d.w $f6, $f6
    div.d $f12, $f4, $f6
    la   $a0, msg_accuracy
    li   $v0, 4
    syscall
    li   $v0, 3
    syscall
    la   $a0, nl
    li   $v0, 4
    syscall

    div.d $f12, $f4, $f6
    l.d  $f2, d_hundred
    mul.d $f12, $f12, $f2
    la   $a0, msg_accpct
    li   $v0, 4
    syscall
    li   $v0, 3
    syscall
    la   $a0, nl
    li   $v0, 4
    syscall
    j    de_restore

de_no_data:
    la   $a0, err_no_data
    li   $v0, 4
    syscall
    j    de_restore
de_no_model:
    la   $a0, err_no_model
    li   $v0, 4
    syscall

de_restore:
    lw   $ra, 24($sp)
    lw   $s0, 0($sp)
    lw   $s1, 4($sp)
    lw   $s2, 8($sp)
    lw   $s3, 12($sp)
    lw   $s4, 16($sp)
    lw   $s5, 20($sp)
    addiu $sp, $sp, 32
    jr   $ra

# ===========================================================================
# show_model()
# ===========================================================================
show_model:
    subu $sp, $sp, 24
    sw   $ra, 20($sp)
    sw   $s0, 0($sp)
    sw   $s1, 4($sp)
    sw   $s2, 8($sp)

    la   $t0, data_loaded
    lw   $t1, 0($t0)
    beqz $t1, sm_no_data
    la   $t0, model_trained
    lw   $t1, 0($t0)
    beqz $t1, sm_no_model

    la   $a0, msg_model
    li   $v0, 4
    syscall

    la   $a0, msg_bias
    li   $v0, 4
    syscall
    l.d  $f12, bias
    li   $v0, 3
    syscall
    la   $a0, nl
    li   $v0, 4
    syscall

    la   $a0, msg_nsv
    li   $v0, 4
    syscall
    la   $t0, n_sv
    lw   $a0, 0($t0)
    li   $v0, 1
    syscall
    la   $a0, nl
    li   $v0, 4
    syscall

    la   $a0, msg_sweeps
    li   $v0, 4
    syscall
    la   $t0, sweeps_used
    lw   $a0, 0($t0)
    li   $v0, 1
    syscall
    la   $a0, nl
    li   $v0, 4
    syscall

    la   $t0, n_samples
    lw   $s1, 0($t0)
    li   $s0, 0
sm_loop:
    bge  $s0, $s1, sm_done

    sll  $t0, $s0, 3
    la   $t1, alpha
    addu $t1, $t1, $t0
    l.d  $f0, 0($t1)
    l.d  $f2, small_alpha
    c.lt.d $f2, $f0
    bc1f sm_next

    la   $a0, msg_sv
    li   $v0, 4
    syscall
    move $a0, $s0
    li   $v0, 1
    syscall

    la   $a0, msg_alpha
    li   $v0, 4
    syscall
    sll  $t0, $s0, 3
    la   $t1, alpha
    addu $t1, $t1, $t0
    l.d  $f12, 0($t1)
    li   $v0, 3
    syscall

    la   $t1, y_data
    addu $t1, $t1, $t0
    lb   $t6, 0($t1)
    move $v0, $t6
    li   $v0, 1
    syscall

    la   $a0, nl
    li   $v0, 4
    syscall

sm_next:
    addiu $s0, $s0, 1
    j    sm_loop

sm_done:
    j    sm_restore
sm_no_data:
    la   $a0, err_no_data
    li   $v0, 4
    syscall
    j    sm_restore
sm_no_model:
    la   $a0, err_no_model
    li   $v0, 4
    syscall

sm_restore:
    lw   $ra, 20($sp)
    lw   $s0, 0($sp)
    lw   $s1, 4($sp)
    lw   $s2, 8($sp)
    addiu $sp, $sp, 24
    jr   $ra


