; Start-up code for lcc-compiled H8/500 programs (tools/h8500), small
; model: code in page 0, data in page 8.  h8link.py places this first,
; at address 0, and defines __data_rom (the ROM copy of the initialized
; data), __data_start/__data_end and __bss_start/__bss_end (page 8), and
; __stack (initial SP, page 8).
;
; The R40 firmware supplies its own vector table and start-up through
; the same symbols; this file is the bare one used by h8run tests.
;@code
	org	0
	dc.w	0,__start		; reset: CP 0, PC
	org	$100

__start:
	ldc.b	#8,tp			; stack, data and EP pages: 8
	mov.w	#(__stack&$FFFF),sp
	ldc.b	#8,dp
	ldc.b	#$FF,br			; @aa:8 reaches the registers FF80-FFFF
	ldc.b	#0,ep			; r4/r5 point into the ROM for the copy
	mov.w	#__data_rom,r4
	mov.w	#(__data_start&$FFFF),r0
__copy:	cmp.w	#(__data_end&$FFFF),r0
	beq	__copied
	mov.b	@r4+,r1
	mov.b	r1,@r0+
	bra	__copy
__copied:
	ldc.b	#8,ep
	mov.w	#(__bss_start&$FFFF),r0
__clear:
	cmp.w	#(__bss_end&$FFFF),r0
	beq	__cleared
	clr.b	@r0+
	bra	__clear
__cleared:
	clr.w	r0			; main(0, argv) with argv[0] == NULL
	mov.w	r0,@-sp
	mov.w	sp,r1
	mov.w	r1,@-sp
	mov.w	r0,@-sp
	jsr	@_main
	mov.w	r0,@-sp
	jsr	@_exit
__halt:	bra	__halt
