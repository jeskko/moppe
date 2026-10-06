/*
 * CTCSS encoder, experimental.  The only tone source into the TX audio
 * is TMO (P1.7) through IC41's Fii switch (bit 5), and whether sub-audio
 * gets past the TX path's high-pass and the PLL loop to the carrier is
 * not known (notes/r40.md gap 1): check with a deviation meter before
 * relying on it.  TMO carries the timer's frequency directly: the Nokia
 * firmware's CCIR tones (table at 8:2051, routine 0x1D2AB) come out
 * right with no divider.
 *
 * The 8-bit timer runs from phi / 8 (1.008 MHz) and clears at compare A
 * = 125: an 8 kHz interrupt (start.s `ctcss`) adds ctcss_inc to a 16-bit
 * phase and sets TMO's next level from its top bit.  inc = f * 65536 /
 * 8000, rounded; the edges jitter by one 125 us step, the frequency is
 * within 0.06 Hz on average.
 */
#include "regs.h"
#include "tone.h"

#define RATE10 80000L		/* the interrupt rate, 0.1 Hz units */

const unsigned tones[NTONES + 1] = {
	0,
	670, 693, 719, 744, 770, 797, 825, 854, 885, 915,
	948, 974, 1000, 1035, 1072, 1109, 1148, 1188, 1230, 1273,
	1318, 1365, 1413, 1462, 1514, 1567, 1598, 1622, 1655, 1679,
	1713, 1738, 1773, 1799, 1835, 1862, 1899, 1928, 1966, 1995,
	2035, 2065, 2107, 2181, 2257, 2291, 2336, 2418, 2503, 2541
};

volatile unsigned ctcss_inc, ctcss_phase;
unsigned char tcsr_seen;	/* lcc drops a bare volatile read: store it */

void ctcss_on(int t)
{
	if (t < 1 || t > NTONES)
		return;
	ctcss_inc = (unsigned)(((unsigned long)tones[t] * 65536L + RATE10 / 2) / RATE10);
	ctcss_phase = 0;
	T8_TCR = 0;
	T8_TCNT = 0;
	T8_TCORA = 125;		/* 126 counts: 8000 Hz */
	T8_TCORB = 0xFF;
	tcsr_seen = T8_TCSR;
	T8_TCSR = 0x01;		/* TMO low at the next compare */
	IPRC = (IPRC & 0xF0) | 0x03;	/* 8-bit timer: level 3 */
	T8_TCR = 0x49;		/* CMIEA, cleared on compare A, phi / 8 */
}

void ctcss_off(void)
{
	T8_TCR = 0;
	tcsr_seen = T8_TCSR;
	T8_TCSR = 0x00;		/* TMO back to a port pin */
}
