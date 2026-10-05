/*
 * Two Fujitsu MB-series PLL chips on one data / clock pair (P7.1 SD,
 * P7.4 CLK, MSB first, taken on the rising clock), each latching on its
 * own strobe (P7.7 SRE: RX, P7.6 STE: TX).  The last bit is the control
 * bit: 1 for the reference word (SW, R13-R0), 0 for N10-N0 A6-A0.  As
 * the Nokia firmware: 128/129 prescaler (SW = 0), R = 1024 from 12.8 MHz,
 * and the chips count the VCO's second harmonic, so one step of
 * 128 N + A is 6.25 kHz of VCO (notes/r40.md "PLL").
 */
#include "regs.h"
#include "pll.h"

#define SD   0x02
#define CLK  0x10
#define STE  0x40
#define SRE  0x80

static void bits(unsigned long v, int n)
{
	unsigned long m = 1L << (n - 1);

	while (m) {
		if (v & m)
			PORT7 |= SD;
		else
			PORT7 &= ~SD;
		PORT7 |= CLK;
		PORT7 &= ~CLK;
		m >>= 1;
	}
	PORT7 &= ~SD;
}

static void strobe(unsigned char s)
{
	PORT7 |= s;
	PORT7 &= ~s;
}

/* the reference word, once into both chips */
void pll_init(void)
{
	bits(1024L << 1 | 1, 16);	/* SW = 0, R = 1024, C = 1 */
	strobe(SRE | STE);
}

void pll_vco(int which, unsigned long hz)
{
	unsigned long m = hz / PLL_STEP;
	unsigned n = (unsigned)(m >> 7), a = (unsigned)m & 0x7F;

	bits((unsigned long)n << 8 | a << 1, 19);
	strobe(which == PLL_RX ? SRE : STE);
}
