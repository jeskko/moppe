! R40 ham firmware: vectors, reset, interrupt entry, page-crossing I/O.
!
! Small model (notes/r40-firmware.md "Decisions"): code and the ROM
! image of the initialized data in page 0, data, bss and stack in page
! 8 (SRAM 0x88000-0x8FFFF).  The linker script (h8cc.py) puts this
! file's .text first, at address 0, and defines __data_rom,
! __data_start/__data_end, __bss_start/__bss_end and __stack.
!
! Page registers while C runs: DP = EP = TP = 8, BR = 0xFF (@aa:8 is
! the register field).  Only the helpers here change EP, and the
! interrupt entry sets it back to 8 for the C handler.

	.text

! vectors: 4 bytes each in maximum mode, CP word + PC word
	.macro	vec h
	.word	0, \h
	.endm

	vec	reset		! 00 reset
	vec	fault		! 04
	vec	fault		! 08 invalid instruction
	vec	fault		! 0C zero divide
	vec	fault		! 10 TRAP/VS
	vec	fault		! 14
	vec	fault		! 18
	vec	fault		! 1C
	vec	fault		! 20 address error
	vec	fault		! 24 trace
	vec	fault		! 28
	vec	nmi		! 2C NMI (and the WDT in watchdog mode)
	vec	fault		! 30
	vec	fault		! 34
	vec	fault		! 38
	vec	fault		! 3C
	.rept	16
	vec	fault		! 40-7C TRAPA #0-15
	.endr
	vec	fault		! 80 IRQ0
	vec	fault		! 84 IRQ1
	vec	fault		! 88
	vec	fault		! 8C
	vec	fault		! 90 FRT1 ICI
	vec	tick		! 94 FRT1 OCIA: the 100 Hz tick
	.rept	26
	vec	fault		! 98-FC
	.endr
	.org	0x180		! 100-17F: DTC vectors (DTC unused)

	.global	reset, _reset
reset:
_reset:
	ldc.w	#0x0700,sr	! also after a jump here, not only a reset
	ldc.b	#8,tp
	mov.w	#__stack,sp	! (16-bit relocations keep the low word)
	ldc.b	#8,dp
	ldc.b	#0xff,br
	mov.b	#0x7f,@0xfff9:8	! RAMCR: on-chip RAM off, ROM to 0xFF7F
	mov.b	#0xf0,@0xfff8:8	! WCR: no wait states
	ldc.b	#0,ep		! r4 points into the ROM for the copy
	mov.w	#__data_rom,r4
	mov.w	#__data_start,r0
copy:	cmp.w	#__data_end,r0
	beq	copied
	mov.b	@r4+,r1
	mov.b	r1,@r0+
	bra	copy
copied:
	ldc.b	#8,ep
	mov.w	#__bss_start,r0
clear:	cmp.w	#__bss_end,r0
	beq	cleared
	clr.b	@r0+
	bra	clear
cleared:
	clr.w	r6
	jsr	@_main
	bra	reset

! an unexpected exception or interrupt, NMI (power failure or the
! watchdog): start again
	.align	1
fault:
nmi:
	bra	reset

! FRT1 compare match A: tick_isr() in C
	.align	1
tick:
	stm	(r0,r1,r2,r3),@-sp
	stc.b	ep,@-sp		! saves the EP:DP pair as a word
	ldc.b	#8,ep
	bclr.b	#5,@0xff91:8	! clear OCFA (bclr reads it as 1 first)
	jsr	@_tick_isr
	ldc.b	@sp+,ep
	ldm	@sp+,(r0,r1,r2,r3)
	rte

! unsigned char xin(unsigned page, unsigned addr): a byte from another
! page (devices at 0xA0000-0xBFFFF)
	.align	1
	.global	_xin
_xin:
	stm	(r4),@-sp
	mov.w	@(4,r7),r0	! page
	mov.w	@(6,r7),r4	! address
	ldc.b	r0,ep
	mov.b	@r4,r0
	ldc.b	#8,ep
	extu.b	r0
	ldm	@sp+,(r4)
	rts

! void xout(unsigned page, unsigned addr, unsigned char v)
	.align	1
	.global	_xout
_xout:
	stm	(r4),@-sp
	mov.w	@(4,r7),r0	! page
	mov.w	@(6,r7),r4	! address
	mov.w	@(8,r7),r1	! value (low byte)
	ldc.b	r0,ep
	mov.b	r1,@r4
	ldc.b	#8,ep
	ldm	@sp+,(r4)
	rts

! interrupts on (mask 0) / off (mask 7)
	.align	1
	.global	_ei
_ei:	andc.w	#0xf8ff,sr
	rts
	.global	_di
_di:	orc.w	#0x0700,sr
	rts
