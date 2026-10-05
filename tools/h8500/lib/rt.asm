; Run-time helpers called by lcc-compiled H8/500 code (h8500.md).
; Register conventions are the back end's: each helper keeps every
; register its caller does not expect to change.
;@code

; signed 16-bit divide: r1 / r2 -> quotient r1, remainder r0
; (remainder has the dividend's sign, C semantics); keeps r2-r5
__divi2:
	stm	(r2,r3),@-sp
	clr.w	r3			; bit 0: negate quotient, bit 1: remainder
	tst.w	r1
	bpl	__divi2_a
	neg.w	r1
	xor.w	#3,r3
__divi2_a:
	tst.w	r2
	bpl	__divi2_b
	neg.w	r2
	xor.w	#1,r3
__divi2_b:
	clr.w	r0
	divxu.w	r2,r0
	btst.w	#0,r3
	beq	__divi2_c
	neg.w	r1
__divi2_c:
	btst.w	#1,r3
	beq	__divi2_d
	neg.w	r0
__divi2_d:
	ldm	@sp+,(r2,r3)
	rts

; block copy: r1 bytes from @r3 to @r2; uses r0-r3
__blkcpy:
	tst.w	r1
	beq	__blkcpy_x
	mov.b	@r3+,r0
	mov.b	r0,@r2+
	add.w	#-1,r1
	bra	__blkcpy
__blkcpy_x:
	rts

; 32-bit shifts of r0:r1 by r2 (r2 destroyed)
__shl4:	tst.w	r2
	beq	__shift_x
	shll.w	r1
	rotxl.w	r0
	add.w	#-1,r2
	bra	__shl4
__shr4:	tst.w	r2
	beq	__shift_x
	shlr.w	r0
	rotxr.w	r1
	add.w	#-1,r2
	bra	__shr4
__sar4:	tst.w	r2
	beq	__shift_x
	shar.w	r0
	rotxr.w	r1
	add.w	#-1,r2
	bra	__sar4
__shift_x:
	rts

; 32-bit multiply: r0:r1 * r2:r3 -> r0:r1 (low 32 bits); keeps r4, r5
__mul4:
	stm	(r4,r5),@-sp
	mov.w	r1,r4
	mulxu.w	r2,r4			; al * bh: low word in r5
	mov.w	r5,@-sp
	mov.w	r0,r4
	mulxu.w	r3,r4			; ah * bl
	add.w	@sp+,r5			; cross terms, low word
	mov.w	r1,r0
	mulxu.w	r3,r0			; al * bl, 32 bits
	add.w	r5,r0
	ldm	@sp+,(r4,r5)
	rts

; unsigned 32/32: r0:r1 / r2:r3 -> quotient r0:r1, remainder r4:r5
; (callers save r4, r5)
__udivmod4:
	clr.w	r4
	clr.w	r5
	mov.w	#32,@-sp
__udm_loop:
	shll.w	r1
	rotxl.w	r0
	rotxl.w	r5
	rotxl.w	r4
	cmp.w	r2,r4
	bcs	__udm_skip
	bne	__udm_sub
	cmp.w	r3,r5
	bcs	__udm_skip
__udm_sub:
	sub.w	r3,r5
	subx.w	r2,r4
	or.w	#1,r1
__udm_skip:
	add.w	#-1,@sp
	bne	__udm_loop
	add.w	#2,sp
	rts

__divu4:
	stm	(r4,r5),@-sp
	jsr	@__udivmod4
	ldm	@sp+,(r4,r5)
	rts

__modu4:
	stm	(r4,r5),@-sp
	jsr	@__udivmod4
	mov.w	r4,r0
	mov.w	r5,r1
	ldm	@sp+,(r4,r5)
	rts

; signed: divide the magnitudes; the quotient is negative if the signs
; differ, the remainder has the dividend's sign
__divi4:
	stm	(r4,r5),@-sp
	jsr	@__sdivmod4
	btst.w	#0,@sp			; sign bits left by __sdivmod4
	beq	__divi4_x
	jsr	@__neg01
__divi4_x:
	add.w	#2,sp
	ldm	@sp+,(r4,r5)
	rts

__modi4:
	stm	(r4,r5),@-sp
	jsr	@__sdivmod4
	mov.w	r4,r0
	mov.w	r5,r1
	btst.w	#1,@sp
	beq	__modi4_x
	jsr	@__neg01
__modi4_x:
	add.w	#2,sp
	ldm	@sp+,(r4,r5)
	rts

; magnitudes divided; returns with a word pushed under the return
; address: bit 0 negate the quotient, bit 1 the remainder
__sdivmod4:
	mov.w	@sp+,r4			; return address
	clr.w	r5
	tst.w	r0
	bpl	__sdm_a
	jsr	@__neg01
	xor.w	#3,r5
__sdm_a:
	tst.w	r2
	bpl	__sdm_b
	not.w	r2
	not.w	r3
	add.w	#1,r3
	addx.w	#0,r2
	xor.w	#1,r5
__sdm_b:
	mov.w	r5,@-sp
	mov.w	r4,@-sp
	jsr	@__udivmod4
	rts

; r0:r1 = -r0:r1
__neg01:
	not.w	r0
	not.w	r1
	add.w	#1,r1
	addx.w	#0,r0
	rts
