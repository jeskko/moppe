/*
 * Helper macros for the cpp + asmpp.py + sdasz80 pipeline
 * (notes/toolchain.md).  Macro bodies separate statements with '@';
 * tools/r58/asmpp.py splits them into lines after cpp.
 */

/* as80 HI()/LO(): HI is not masked (x >> 8 of a 24-bit value keeps 16 bits) */
#define HI(x)	((x) >> 8)
#define LO(x)	((x) & 0xFF)

/* n bytes of value v */
#define FILL(n, v)	.rept n @ .db v @ .endm

/* pad with v up to a multiple of 2^bits (as80 .align bits, v) */
#define ALIGN(bits, v)	.rept (0 - .) & ((1 << (bits)) - 1) @ .db v @ .endm

/* a fixed-ROM stub that runs fn in another bank (bank1_call, bank2_call)
 * or with bank 0 selected (bank0_call); registers pass both ways */
#define FAR(name, bankcall, fn) \
name: @ call bankcall @ .dw fn

/* build-time checks */
#define ASSERT_NZ(x)	.iif eq, x, .error 1
#define ASSERT_EQ(a, b)	.iif ne, (a) - (b), .error 1
#define ASSERT_LT(a, b)	.iif ge, (a) - (b), .error 1
#define ASSERT_LE(a, b)	.iif gt, (a) - (b), .error 1
#define ASSERT_GT(a, b)	.iif le, (a) - (b), .error 1
#define ASSERT_GE(a, b)	.iif lt, (a) - (b), .error 1
