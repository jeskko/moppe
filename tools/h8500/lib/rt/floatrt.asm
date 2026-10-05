; Float helpers called by lcc-compiled H8/500 code (h8500.md): operands
; in r0:r1 and r2:r3, result in r0:r1 (__cmpf: -1/0/1 in r0, __ftoi2:
; r1, __itof2 takes r1).  Every other register is kept: the back end
; only expects the result registers (and r0 for __cmpf and __ftoi2) to
; change, and an operand register may still hold a live value.  The work
; is done by float.c, which takes its arguments on the stack.
;@code

__addf:	stm	(r2,r3,r4),@-sp
	mov.w	#__fpadd,r4
	bra	__fcall2
__subf:	stm	(r2,r3,r4),@-sp
	mov.w	#__fpsub,r4
	bra	__fcall2
__mulf:	stm	(r2,r3,r4),@-sp
	mov.w	#__fpmul,r4
	bra	__fcall2
__divf:	stm	(r2,r3,r4),@-sp
	mov.w	#__fpdiv,r4
__fcall2:				; r4 holds the C function
	mov.w	r3,@-sp
	mov.w	r2,@-sp
	mov.w	r1,@-sp
	mov.w	r0,@-sp
	jsr	@r4
	add.w	#8,sp
	ldm	@sp+,(r2,r3,r4)
	rts

__cmpf:	stm	(r1,r2,r3),@-sp
	mov.w	r3,@-sp
	mov.w	r2,@-sp
	mov.w	r1,@-sp
	mov.w	r0,@-sp
	jsr	@__fpcmp
	add.w	#8,sp
	ldm	@sp+,(r1,r2,r3)
	rts

; __ftoi2: the low word of the 32-bit result is already in r1
__ftoi2:
__ftoi4:
	stm	(r2,r3),@-sp
	mov.w	r1,@-sp
	mov.w	r0,@-sp
	jsr	@__fptoi
	bra	__fcall1

__itof2:
	clr.w	r0
	tst.w	r1
	bpl	__itof4
	mov.w	#-1,r0
__itof4:
	stm	(r2,r3),@-sp
	mov.w	r1,@-sp
	mov.w	r0,@-sp
	jsr	@__itofp
__fcall1:
	add.w	#4,sp
	ldm	@sp+,(r2,r3)
	rts
