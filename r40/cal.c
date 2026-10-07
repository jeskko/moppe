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
 *   0x63        the band (test 15x): 0x40 C (2 m), 0x80 D (70 cm); band.c
 *
 * Without a valid copy (flat battery) the band comes from the menu
 * (band.c), the 0-channel from its table, and the defaults are the D
 * band's of Nokia's test 190002 (Cr 13.04 has no others: 171 loads the
 * same tables) with deviation 7, Nokia's own cold-start value; on 2 m
 * RFC is a flat 32, a placeholder for the self-calibration.
 *
 * Self-calibration of RFC (cal_self): with no signal, the receiver's
 * own noise is strongest where the front end is tuned, so at the centre
 * of every other MHz of the band's transmit range (430.5 ... 440.5,
 * 144.5 and 146.5 MHz) RFC is swept 0-63 and the RSSI peak kept
 * (1-2-1 smoothing, the middle of a flat top).  The results (kept
 * in our NV with their band) replace Nokia's table there, the odd MHz
 * interpolated; Nokia's table still serves outside it.  Untried on
 * hardware: whether the peak is clear, and how long RFC takes to settle
 * (one tick here).
 */
#include "regs.h"
#include "hw.h"
#include "lcd.h"
#include "keypad.h"
#include "radio.h"
#include "serbus.h"
#include "ui.h"
#include "band.h"
#include "cal.h"

#define BLOCK   0x12C		/* block 0 with its checksum byte */
#define BANDB   0x63
#define TX0     0x64
#define SQ_O    0x6C
#define SQ_C    0x6D
#define TPC     0x74
#define DEV     0x92
#define RFC     0xD9
#define NBANDS  71
#define NV_SEL  0x04		/* P9.2 */

#define SETTLE  3		/* ticks after a retune */

static unsigned char blk[BLOCK];
unsigned char rx_selfcal[SC_N] = { 0xFF };
unsigned char rx_selfcal_band;	/* band_id the results are for */
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
	}
}

/* Nokia's band byte, -1 without a valid copy */
int cal_nokia_band(void)
{
	return cal_ok ? blk[BANDB] : -1;
}

/* band.c, once the band is known: the defaults if Nokia's copy is bad */
void cal_band(void)
{
	int i;

	if (cal_ok)
		return;
	base_hz = band->base;
	blk[SQ_O] = 0x88;
	blk[SQ_C] = 0x85;
	for (i = 0; i < 30; i++)
		blk[TPC + i] = def_tpc[i];
	for (i = 0; i < NBANDS; i++) {
		blk[DEV + i] = 7;
		blk[RFC + i] = band_id == BAND_70CM ? def_rfc[i] : 32;
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

/* self-cal points: every other MHz of the transmit range, at most SC_N */
static int npoints(void)
{
	int n = (int)((band->tx_hi - band->tx_lo) / 2000000L) + 1;

	return n < SC_N ? n : SC_N;
}

int cal_self_valid(void)
{
	int i;

	if (rx_selfcal_band != band_id)
		return 0;
	for (i = 0; i < npoints(); i++)
		if (rx_selfcal[i] > 63)
			return 0;
	return 1;
}

unsigned char cal_rfc(unsigned long rx)
{
	int i = mhz(rx) - mhz(band->tx_lo), j = i / 2;

	if (i < 0 || i > 2 * (npoints() - 1) || !cal_self_valid())
		return blk[RFC + mhz(rx)] & 0x3F;
	if (i & 1)
		return (rx_selfcal[j] + rx_selfcal[j + 1] + 1) / 2;
	return rx_selfcal[j];
}

static unsigned rssi_sum(void)
{
	unsigned s;

	delay_ticks(1);		/* RFC settles */
	s = ADDRA >> 6;
	delay_ticks(1);
	return s + (ADDRA >> 6);
}

static void show(unsigned long f, int rfc)
{
	char buf[8], *p;

	p = utoa(f / 1000000L, buf, 1);
	*p++ = '.';
	*p++ = '5';
	*p = 0;
	lcd_puts(1, 0, buf);
	lcd_puts(1, 6, "MHz  RFC");
	utoa(rfc, buf, 2);
	lcd_puts(1, 15, buf);
	lcd_flush();
}

/* the RFC with the most noise at f; -1 if a key was pressed */
static int sweep(unsigned long f)
{
	static unsigned s[64];
	unsigned best = 0, v;
	int r, a = 0, b = 0;

	for (r = 0; r < 64; r++) {
		dac_write(r, tpc, r, tpc);
		s[r] = rssi_sum();
		keypad_poll();
		if (key_get() != K_NONE)
			return -1;
	}
	for (r = 0; r < 64; r++) {
		/* 1-2-1, the centre standing in for a missing neighbour (with
		   1-1-1 a peak at 1 tied with 0 and came out as 0) */
		v = 2 * s[r] + s[r > 0 ? r - 1 : r] + s[r < 63 ? r + 1 : r];
		if (v > best) {
			best = v;
			a = b = r;
		} else if (v == best && b == r - 1)
			b = r;
	}
	show(f, (a + b) / 2);
	return (a + b) / 2;
}

int cal_self(void)
{
	unsigned long rx = rx_hz, tx = tx_hz, f;
	unsigned char got[SC_N];
	int i, r = 0;

	lcd_clear();
	lcd_puts(0, 0, "RX self-cal");
	for (i = 0; i < npoints() && r >= 0; i++) {
		f = band->tx_lo + 2000000L * i + 500000L;
		radio_tune(f, tx);
		show(f, 0);
		delay_ticks(SETTLE);
		r = sweep(f);
		got[i] = r;
	}
	if (r >= 0) {
		for (i = 0; i < SC_N; i++)
			rx_selfcal[i] = i < npoints() ? got[i] : 0xFF;
		rx_selfcal_band = band_id;
	}
	radio_tune(rx, tx);
	radio_dac();
	lcd_clear();
	return r < 0 ? -1 : 0;
}

void cal_self_clear(void)
{
	int i;

	for (i = 0; i < SC_N; i++)
		rx_selfcal[i] = 0xFF;
	radio_dac();
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
