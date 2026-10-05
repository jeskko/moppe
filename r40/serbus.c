/*
 * The logic board's serial bus: P1.2 clock, P1.3 data, MSB first, data
 * taken on the rising clock.  A 4094 copies its eight bits to the
 * outputs on a pulse of its strobe (OUT1 bits 1-3); the MC144111 DAC
 * (4 x 6 bits) takes 24 bits while its select (OUT0 bit 0) is low and
 * loads them as it goes high.  Main loop only: the bit-banging owns
 * PORT1 and the latch shadows.
 */
#include "regs.h"
#include "hw.h"
#include "serbus.h"

#define CLK  0x04
#define DATA 0x08

static void shift(unsigned v, int n)
{
	unsigned m = 1 << (n - 1);

	while (m) {
		if (v & m)
			PORT1 |= DATA;
		else
			PORT1 &= ~DATA;
		PORT1 |= CLK;
		PORT1 &= ~CLK;
		m >>= 1;
	}
	PORT1 &= ~DATA;
}

void sr_write(int n, unsigned char v)
{
	unsigned char strobe = 0x02 << n;

	shift(v, 8);
	out1(out1_shadow | strobe);
	out1(out1_shadow & ~strobe);
}

/* channels 1-4 in the order shifted.  1 is RFC (RX front-end tuning:
   service test 36 moves it); the Nokia firmware shifts only two values
   per select, so 3 = 1 and 4 = 2, 2 presumably TPC (TX power) */
void dac_write(unsigned char a, unsigned char b, unsigned char c,
	       unsigned char d)
{
	out0(out0_shadow & ~0x01);
	shift(a, 6);
	shift(b, 6);
	shift(c, 6);
	shift(d, 6);
	out0(out0_shadow | 0x01);
}
