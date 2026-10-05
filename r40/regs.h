/*
 * H8/532 on-chip registers (H8/532 Hardware Manual; the field FF80-FFFF
 * of page 0).  The compiler reaches a constant address in FF80-FFFF as
 * @aa:8 through BR = FF, so these are plain C lvalues.
 */
#ifndef REGS_H
#define REGS_H

#define REG8(a)  (*(volatile unsigned char *)(a))
#define REG16(a) (*(volatile unsigned *)(a))

#define P1DDR   REG8(0xFF80)
#define PORT1   REG8(0xFF82)
#define P7DDR   REG8(0xFF8C)
#define PORT7   REG8(0xFF8E)
#define PORT8   REG8(0xFF8F)

/* free-running timers 1-3 (base FF90, FFA0, FFB0) */
#define T1_TCR  REG8(0xFF90)
#define T1_TCSR REG8(0xFF91)
#define T1_FRC  REG16(0xFF92)
#define T1_OCRA REG16(0xFF94)
#define T1_OCRB REG16(0xFF96)
#define T1_ICR  REG16(0xFF98)
#define FRT_ICIE  0x80
#define FRT_OCIEB 0x40
#define FRT_OCIEA 0x20
#define FRT_OVIE  0x10
#define FRT_ICF   0x80
#define FRT_OCFB  0x40
#define FRT_OCFA  0x20
#define FRT_OVF   0x10
#define FRT_CCLRA 0x01

/* 8-bit timer */
#define T8_TCR   REG8(0xFFD0)
#define T8_TCSR  REG8(0xFFD1)
#define T8_TCORA REG8(0xFFD2)
#define T8_TCORB REG8(0xFFD3)
#define T8_TCNT  REG8(0xFFD4)

#define ADDRA   REG16(0xFFE0)	/* left justified: value << 6 */
#define ADDRB   REG16(0xFFE2)
#define ADDRC   REG16(0xFFE4)
#define ADDRD   REG16(0xFFE6)
#define ADCSR   REG8(0xFFE8)

#define WDT_TCSR REG16(0xFFEC)	/* written as a word: A5xx TCSR, 5Axx TCNT */

#define IPRA    REG8(0xFFF0)	/* IRQ0, IRQ1 */
#define IPRB    REG8(0xFFF1)	/* FRT1, FRT2 */
#define IPRC    REG8(0xFFF2)	/* FRT3, 8-bit timer */
#define IPRD    REG8(0xFFF3)	/* SCI, A/D */
#define DTEA    REG8(0xFFF4)
#define DTEB    REG8(0xFFF5)
#define DTEC    REG8(0xFFF6)
#define DTED    REG8(0xFFF7)
#define WCR     REG8(0xFFF8)
#define RAMCR   REG8(0xFFF9)
#define P1CR    REG8(0xFFFC)
#define P9DDR   REG8(0xFFFE)
#define PORT9   REG8(0xFFFF)

#endif
