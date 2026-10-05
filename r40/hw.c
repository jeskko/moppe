/*
 * R40 board set-up: ports, the 100 Hz tick (FRT1 compare match A) and
 * the watchdogs.  Port directions and the latch defaults follow
 * OH5NXO's start.s; the watchdog kick is the Nokia firmware's
 * (watchdog_kick, 0x1CE91): P9.0 high for a few microseconds for the
 * external watchdog (IC57), then the on-chip WDT restarted in watchdog
 * mode (NMI after 4096 * 256 states, 130 ms).
 */
#include "regs.h"
#include "hw.h"

volatile unsigned ticks;
unsigned char out0_shadow, out1_shadow;

void out0(unsigned char v)
{
	out0_shadow = v;
	xout(OUT0_PAGE, OUT0_ADDR, v);
}

void out1(unsigned char v)
{
	out1_shadow = v;
	xout(OUT1_PAGE, OUT1_ADDR, v);
}

void wdog_kick(void)
{
	int i;

	PORT9 |= 0x01;
	for (i = 0; i < 2; i++)
		;
	PORT9 &= ~0x01;
	WDT_TCSR = 0xA57F;	/* watchdog mode, TME, clock / 4096 */
	WDT_TCSR = 0x5A00;	/* count from 0 */
}

void delay_ticks(unsigned n)
{
	unsigned t0 = ticks;

	while (ticks - t0 < n)
		wdog_kick();
}

void tick_isr(void)
{
	ticks++;
}

void hw_init(void)
{
	IPRA = IPRB = IPRC = IPRD = 0;
	DTEA = DTEB = DTEC = DTED = 0;

	P1CR = 0xF7;		/* IRQ0/1 pins, NMI rising edge, P1.2/P1.3 I/O */
	PORT1 = 0x00;
	P1DDR = 0x8D;		/* serial bus CLK/DATA out, TMO */
	PORT7 = 0x00;		/* PLL lines low */
	P7DDR = 0xD2;		/* SD, CLK, STE (P7.6), SRE (P7.7) */
	PORT9 = 0x20;		/* P9.2 = 0: lower half of the NV RAM */
	P9DDR = 0xA7;		/* watchdog kick P9.0, NV select, SCI */
	wdog_kick();

	out0(0x05);		/* DAC and FX803 chip selects inactive */
	out1(0x00);		/* TX off */

	/* tick: FRT1 at phi / 8 = 1.008 MHz, cleared on compare match A */
	T1_TCR = 0x01;		/* phi / 8 */
	T1_OCRA = 10080 - 1;
	T1_FRC = 0;
	T1_TCSR = FRT_CCLRA;
	T1_TCR = FRT_OCIEA | 0x01;
	IPRB = 0x10;		/* FRT1 level 1 */
}
