!----------------------------------------------------------------------
!
!  Runtime helpers that SDCC-generated code calls (C_MODULES builds).
!
!  ___sdcc_enter_ix: set up an IX frame pointer (SDCC's crt helper).

___sdcc_enter_ix:
	pop hl			! return address
	push ix
	ld ix, 0
	add ix, sp
	jp [hl]
