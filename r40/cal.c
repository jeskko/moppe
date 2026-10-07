/*
 * Nokia's factory calibration, read once at start-up from the first
 * block (0x000-0x12A, checksum byte 0x12B) of its checksummed copies in
 * the P9.2 = 1 half of the NV RAM, the copy at 0x0000 or else the one at
 * 0x2000 (notes/r40.md "NV RAM"; mapped in the emulator from service
 * tests 20x, 21, 33, 34 and 36):
 *
 *   0x64  long  TX 0-channel in 6.25 kHz units (64000 = 400 MHz); the
 *               tables count from it (the RX 0-channel is 45 MHz up)
 *   0x6C        squelch "opening level" (test 33), 0x6D "closing level"
 *               (34): AN1 >> 2.  Nokia mutes above 0x6C and opens below
 *               0x6D (defaults 136 / 133)
 *   0x74        TX power (TPC), 3 levels x 10 bands of 7 MHz (test 20x;
 *               Nokia transmits on level 2 in simplex)
 *   0x92        deviation correction, the 4094 DEV bits, 71 x 1 MHz (21)
 *   0xD9        RX front-end tuning (RFC), 71 x 1 MHz (36)
 *
 * Without a valid copy (flat battery) the D-band defaults of Nokia's
 * test 190002 are used, with deviation 4 (the tuning instructions'
 * starting value; Nokia's defaults leave it 0).
 */
#include "regs.h"
#include "hw.h"
#include "cal.h"

#define BLOCK   0x12C		/* block 0 with its checksum byte */
#define TX0     0x64
#define SQ_O    0x6C
#define SQ_C    0x6D
#define TPC     0x74
#define DEV     0x92
#define RFC     0xD9
#define NBANDS  71
#define NV_SEL  0x04		/* P9.2 */

static unsigned char blk[BLOCK];
static unsigned long base_hz = 400000000L;
unsigned char cal_ok;

static const unsigned char def_tpc[30] = {
	0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D,
	0x1D, 0x1D, 0x1D, 0x1D, 0x1D, 0x1E, 0x1F, 0x20, 0x20, 0x20,
	0x29, 0x29, 0x29, 0x29, 0x29, 0x2A, 0x2A, 0x2A, 0x2A, 0x2A
};
static const unsigned char def_rfc[NBANDS] = {
	0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A,
	0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B,
	0x1C, 0x1C, 0x1C, 0x1C, 0x1C, 0x1C, 0x1C, 0x1C,
	0x1E, 0x1E, 0x1E, 0x1E, 0x1E, 0x1E, 0x1E, 0x1E, 0x1E, 0x1E, 0x1E, 0x1E,
	0x22, 0x22, 0x23, 0x24, 0x25, 0x25, 0x26, 0x28, 0x28, 0x29, 0x29, 0x29,
	0x2A, 0x2B,
	0x2C, 0x2C, 0x2C, 0x2C, 0x2C, 0x2C, 0x2C, 0x2C,
	0x2C, 0x2C, 0x2C, 0x2C, 0x2C, 0x2C, 0x2C, 0x2C
};

static int copy_ok(const unsigned char *p)
{
	unsigned char s = 0;
	int i;

	for (i = 0; i < BLOCK; i++)
		s += p[i];
	return s == 0xFF;	/* the checksum is NOT(sum of the rest) */
}

/* before interrupts are on: the other half hides our RAM's neighbours */
void cal_load(void)
{
	const unsigned char *p = 0;
	unsigned long ch;
	int i;

	PORT9 |= NV_SEL;
	if (!copy_ok(p))
		p = (const unsigned char *)0x2000;
	if (copy_ok(p)) {
		for (i = 0; i < BLOCK; i++)
			blk[i] = p[i];
		cal_ok = 1;
	}
	PORT9 &= ~NV_SEL;
	if (cal_ok) {
		ch = (unsigned long)blk[TX0] << 24 | (unsigned long)blk[TX0 + 1] << 16 |
		     (unsigned)blk[TX0 + 2] << 8 | blk[TX0 + 3];
		if (ch)
			base_hz = ch * 6250;
		return;
	}
	blk[SQ_O] = 0x88;
	blk[SQ_C] = 0x85;
	for (i = 0; i < 30; i++)
		blk[TPC + i] = def_tpc[i];
	for (i = 0; i < NBANDS; i++) {
		blk[DEV + i] = 4;
		blk[RFC + i] = def_rfc[i];
	}
}

/* whole MHz above the 0-channel, 0-70 */
static int mhz(unsigned long hz)
{
	unsigned long n;

	if (hz < base_hz)
		return 0;
	n = (hz - base_hz) / 1000000L;
	return n < NBANDS ? (int)n : NBANDS - 1;
}

unsigned char cal_rfc(unsigned long rx)
{
	return blk[RFC + mhz(rx)] & 0x3F;
}

unsigned char cal_dev(unsigned long tx)
{
	return blk[DEV + mhz(tx)] & 0x0F;
}

unsigned char cal_tpc(int level, unsigned long tx)
{
	int band = mhz(tx) / 7;

	return blk[TPC + 10 * level + (band < 10 ? band : 9)] & 0x3F;
}

/* 10-bit A/D units: open below the lower level, close above the
   higher (Nokia's defaults have 0x6C the higher; a real calibration
   may not, and the other order would oscillate between them) */
unsigned cal_sq_open(void)
{
	unsigned char a = blk[SQ_O], b = blk[SQ_C];

	return (unsigned)(a < b ? a : b) << 2;
}

unsigned cal_sq_close(void)
{
	unsigned char a = blk[SQ_O], b = blk[SQ_C];

	return (unsigned)(a > b ? a : b) << 2;
}
