! Console and exit for programs run by h8run (tools/h8500/h8run.c):
! writes to 8FFF0 print a character, to 8FFF1 end the run with a status.
	.text
	.global	_putchar
	.global	_exit
	.global	_getchar

! void putchar(int c): the argument word is at @(2,sp), its byte at 3
_putchar:
	mov.b	@(3,sp),r0
	mov.b	r0,@0xfff0:16
	rts

! void exit(int status)
_exit:
	mov.b	@(3,sp),r0
	mov.b	r0,@0xfff1:16
__exit_halt:
	bra	__exit_halt

! int getchar(void): the next byte of h8run's stdin, -1 at its end
_getchar:
	mov.w	@0xfff2:16,r0
	rts
