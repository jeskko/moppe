/*
 * Frequency, band and duplex logic in C (Phase 4,
 * notes/hybrid-plan.md).  Replaces changed_frequency and its chain,
 * locate_band, the duplex logic, the TX-legality check, channel
 * stepping, the QSY size check and the VCO band bits of r58.s (the
 * assembler originals are in git tag asm-final).
 *
 * Frequencies are 24-bit little-endian values in kHz; duplex shifts are
 * 24-bit two's complement, so sums wrap at 24 bits as in the assembler.
 * The arithmetic kernel stays in assembler (freq2div/div2freq and their
 * rounding quirks, via determine_rx_div, determine_tx_div_split and
 * set_channel_step), as do the helpers whose results asm callers take
 * from registers (locate_tx_band, channel_step_parms).
 *
 * The routines called here do not preserve IX, so no stack frames.
 * Mainline only.
 */
#include "r58.h"

#define BR_START	0
#define BR_END		3
#define BR_DUPLEX	6
#define BR_STEP		9
#define BR_SCTAIL	10
#define BR_SCLISTEN	11
#define BR_AUTOREJECT	12

#define MASK24		0xFFFFFFUL

extern uint8_t rx_freq_previous[3], last_qsy_kHz[3];
extern const uint8_t cfg_tx_band_end[3], cfg_tx_oob_0[3], cfg_tx_oob_1[3],
	cfg_tx_oob_2[3], cfg_tx_oob_3[3], cfg_tx_oob_4[3],
	cfg_scan_large_qsy[3];
extern uint8_t band, tx_is_legal, local_mode, synth_ctrl,
	cfg_scan_rate_kvik, cfg_scan_rate_slow;
extern uint16_t band_step_hz;

/* firmware routines (assembler) */
extern void lookup_rfc(void), determine_rx_div(void), load_rxsynth(void);
extern uint16_t channel_step_parms(uint8_t step);	/* user step, in DE */

/* ---- 24-bit values */

/* byte access through a static union: SDCC's 32-bit shifts are slow and
 * large, and a static avoids a stack frame */
static union {
	uint32_t l;
	uint8_t b[4];
} t24;

static uint32_t get24(const uint8_t *p)
{
	t24.b[0] = p[0];
	t24.b[1] = p[1];
	t24.b[2] = p[2];
	t24.b[3] = 0;
	return t24.l;
}

static void put24(uint8_t *p, uint32_t v)
{
	t24.l = v;
	p[0] = t24.b[0];
	p[1] = t24.b[1];
	p[2] = t24.b[2];
}

static uint32_t f, g;			/* static: no stack frame */
static const uint8_t *rec;
static uint8_t k;

/* ---- bands */

/* Band record of rx_freq (start <= rx < end) into band, band_step, ...;
 * outside the six bands: band 0, simplex, the "other" record. */
void locate_band(void)
{
	duplex_state = DPX_DUPLEX;		/* assume duplex */
	f = get24(rx_freq);
	rec = cfg_band1_start;
	for (k = 0; k < NUM_BANDRECS; k++, rec += SIZE_BANDREC)
		if (f >= get24(rec + BR_START) && f < get24(rec + BR_END))
			break;
	if (k == NUM_BANDRECS) {
		duplex_state = DPX_SIMPLEX;
		band = 0;
	} else
		band = k + 1;

	/* a band without its own shift is simplex with the "other" shift
	 * ("other" does not imply autoduplex) */
	put24(duplex_shift, get24(rec + BR_DUPLEX));
	if (!get24(duplex_shift)) {
		put24(duplex_shift, get24(cfg_other_duplex));
		duplex_state = DPX_SIMPLEX;
	}
	band_step = rec[BR_STEP];
	band_sctail = rec[BR_SCTAIL];
	band_sclisten = rec[BR_SCLISTEN];
	band_autoreject = rec[BR_AUTOREJECT];
}

static void parameters_from_band(void)
{
	locate_band();
	set_channel_step();
}

/* ---- duplex */

/* from a memory's rx/tx pair */
void set_duplex_from_tx_rx(void)
{
	f = get24(tx_freq);
	f = (f - get24(rx_freq)) & MASK24;
	if (f) {
		put24(duplex_shift, f);
		duplex_state = DPX_DUPLEX;
	} else {
		put24(duplex_shift, get24(cfg_other_duplex));
		duplex_state = DPX_SIMPLEX;
	}
}

/* duplex 0: tx = rx; 1: rx + shift; 2: rx - shift (shift has its sign);
 * 3 (split): tx_freq as it is.  Then the tx divisor and aligned tx_freq. */
static void determine_tx_div(void)
{
	f = get24(rx_freq);
	switch (duplex_state) {
	case DPX_DUPLEX:
		put24(tx_freq, f + get24(duplex_shift));
		break;
	case DPX_REVERSE:
		put24(tx_freq, f - get24(duplex_shift));
		break;
	case DPX_SPLIT:
		break;
	default:
		put24(tx_freq, f);
	}
	determine_tx_div_split();
}

/* TX allowed: start < tx < end, or one of the five out-of-band spots,
 * or anything while /LOCAL is grounded */
static void set_legal_tx_flag(void)
{
	f = get24(tx_freq);
	if ((get24(cfg_tx_band_start) < f && f < get24(cfg_tx_band_end)) ||
	    f == get24(cfg_tx_oob_0) || f == get24(cfg_tx_oob_1) ||
	    f == get24(cfg_tx_oob_2) || f == get24(cfg_tx_oob_3) ||
	    f == get24(cfg_tx_oob_4))
		tx_is_legal = 1;
	else
		tx_is_legal = local_mode;
}

/* ---- the frequency changed */

void update_rx_vco_band(void)
{
	f = get24(rx_freq);
	if (f < get24(cfg_rx_vco_center))
		synth_ctrl |= 0x01;		/* "1" = low band */
	else
		synth_ctrl &= ~0x01;
}

void update_tx_vco_band(void)
{
	f = get24(tx_freq);
	if (f < get24(cfg_tx_vco_center))
		synth_ctrl |= 0x02;
	else
		synth_ctrl &= ~0x02;
}

/* how far the last QSY went: sets the scanner's settling time */
static void determine_qsy_kHz(void)
{
	f = get24(rx_freq);
	g = get24(rx_freq_previous);
	g = f >= g ? f - g : g - f;
	put24(last_qsy_kHz, g);
	scan_settling_time = g < get24(cfg_scan_large_qsy) ?
		cfg_scan_rate_kvik : cfg_scan_rate_slow;
	put24(rx_freq_previous, f);
}

void temporary_change_rx_freq(void)
{
	close_squelch();
	lookup_rfc();
	update_rx_vco_band();
	update_tx_vco_band();
	determine_rx_div();
	load_rxsynth();
	determine_qsy_kHz();
}

void changed_frequency_duplex_okay(void)
{
	temporary_change_rx_freq();
	determine_tx_div();
	set_legal_tx_flag();
}

void changed_frequency(void)
{
	parameters_from_band();
	changed_frequency_duplex_okay();
}

/* simplex -> duplex -> reverse -> simplex; forgets split and temporary
 * shifts.  Every change except simplex -> duplex swaps rx and tx (split
 * -> simplex too, as v3_Z: the wrap-around out of DPX_SPLIT still takes
 * this "!= DPX_DUPLEX" branch). */
void step_duplex_state(void)
{
	if (++duplex_state >= DPX_SPLIT)
		duplex_state = DPX_SIMPLEX;
	if (duplex_state != DPX_DUPLEX) {
		f = get24(rx_freq);
		put24(rx_freq, get24(tx_freq));
		put24(tx_freq, f);
	}
	changed_frequency_duplex_okay();
}

/* ---- channel steps (rx_freq is aligned to the grid afterwards) */

void step_channel_up(void)
{
	/* one more, to land on the right slice when stepping to its end */
	f = get24(rx_freq);
	f += band_step_hz;
	f++;
	put24(rx_freq, f);
	changed_frequency();
}

void step_channel_down(void)
{
	/* step from 1 below, with the step of the slice we land in */
	f = get24(rx_freq) - 1;
	put24(rx_freq, f);
	locate_band();
	f = get24(rx_freq);
	f -= (uint16_t)(channel_step_parms(band_step) - 1);
	put24(rx_freq, f);
	changed_frequency();
}

/* ---- the RFC table: the receiver's tuning voltage per MHz (slot =
 * (RX kHz mod 100000) / 1000).  The lookup (get_rfc_hl, lookup_rfc,
 * save_rfc) stays assembler: it runs on every frequency change, and its
 * 24-bit subtraction loops cost ~0.1 ms where C's 32-bit ones cost more
 * than 1 ms per scanner step.  The fill runs from the menu only. */

static uint8_t hole;			/* rfctab index; not rx_freq */

/* one hole: rfctab[hole] set, rfctab[hole + 1] the first 0.  A line with
 * integer steps up to the next set value (dy is 8 bits: a lower one
 * wraps); leaves hole before that value.  A leaf (calls nothing), so
 * locals are fine. */
static void rfc_fill_one_hole(void)
{
	uint8_t x = hole, x2 = hole, y, dx, dy;
	uint16_t sum = 0;

	do
		x2++;
	while (!rfctab[x2]);			/* index 99 is never 0 */
	dy = rfctab[x2] - rfctab[x];
	dx = x2 - x;
	while (!rfctab[x + 1]) {
		y = rfctab[x];
		if (dx < dy) {			/* steep */
			do {
				y++;
				sum += dx;
			} while (sum < dy);
			sum -= dy;
		} else {			/* slow rise */
			sum += dy;
			if (sum >= dx) {
				sum -= dx;
				y++;
			}
		}
		rfctab[++x] = y;
	}
	hole = x;
}

/* dF:rFcFIL: interpolate every hole of 1...98; 0 is not a hole, 99 gets
 * a 255 barrier if 0 */
void rfc_fill_blanks(void)
{
	if (!rfctab[99])
		rfctab[99] = 0xFF;
	hole = 0;
	do {
		if (!rfctab[hole + 1])
			rfc_fill_one_hole();
		hole++;
	} while (hole < 98);
}
