/*
 * Receiver and transmitter.  RX VCO at f + 45 MHz; the TX synthesizer
 * is parked 62.5 kHz (ten steps) above the TX frequency until PTT, as
 * the Nokia firmware does.
 *
 * The DAC's RX tuning (RFC) and TX power (TPC) and the deviation bits
 * come from Nokia's calibration (cal.c) for the frequency: RFC per MHz
 * of the RX frequency plus the menu's trim, TPC for the TX frequency
 * at the menu's level (Nokia's levels 1-3; it uses 2 in simplex).
 *
 * PTT (P7.3 low, two ticks) in the Nokia firmware's order (emulator,
 * Cr 13.04 simplex): deviation bits, DAC (TPC), TX synthesizer to f,
 * TX ON (no lock wait: 0.6 ms later), microphone on, then the CTCSS
 * tone if the channel has one (tone.c).  Release: tone off, mic off,
 * TX OFF, synthesizer parked, receive state back.  The A/D
 * scans AN0 (RSSI) and AN1 (noise: high with no signal) continuously;
 * the squelch opens when the noise falls below sq_on and closes when it
 * reaches sq_off, each after two ticks in a row.  A retune closes it
 * and ignores the A/D for SETTLE ticks while the PLL locks (a guess:
 * the lock input is unknown, notes/r40.md gap 5).
 */
#include "regs.h"
#include "hw.h"
#include "pll.h"
#include "audio.h"
#include "serbus.h"
#include "menu.h"
#include "tone.h"
#include "cal.h"
#include "band.h"
#include "radio.h"

#define TX_PARK 62500L
#define SETTLE 3		/* ticks after a retune before the squelch looks */
#define SQ_TICKS 2

unsigned long rx_hz, tx_hz;
unsigned char transmitting;
unsigned char tx_locked;
unsigned tot_limit;
static unsigned tx_start;
unsigned char tx_level = 1;
signed char rx_trim;
unsigned char rfc, tpc;
unsigned char tx_tone;
static unsigned char ptt_count;
unsigned noise, rssi;
unsigned char sq_open;
unsigned sq_on = 480, sq_off = 496;
static unsigned last_tick;
static unsigned char sq_count;
static unsigned char settle;

void radio_init(void)
{
	ADCSR = 0x31;		/* scan AN0-AN1, start */
	pll_init();
	settings_apply();
	audio_rx(0);
}

void radio_tune(unsigned long rx, unsigned long tx)
{
	int moved = rx != rx_hz;

	rx_hz = rx;
	tx_hz = tx;
	if (transmitting)
		return;
	if (moved) {
		settle = SETTLE + SQ_TICKS;
		sq_count = 0;
		if (sq_open) {
			sq_open = 0;
			audio_rx(0);
		}
	}
	pll_vco(PLL_RX, rx + RX_IF);
	pll_vco(PLL_TX, tx + TX_PARK);
	radio_dac();
}

/* RFC and TPC for the current frequencies (not while transmitting) */
void radio_dac(void)
{
	int v = cal_rfc(rx_hz) + rx_trim;

	if (transmitting)
		return;
	rfc = v < 0 ? 0 : v > 63 ? 63 : v;
	tpc = cal_tpc(tx_level, tx_hz);
	dac_write(rfc, tpc, rfc, tpc);
}

static void tx_on(void)
{
	transmitting = 1;
	tx_start = ticks;
	audio_tx_prepare(cal_dev(tx_hz));
	dac_write(rfc, tpc, rfc, tpc);
	pll_vco(PLL_TX, tx_hz);
	out1(out1_shadow | OUT1_TXON);
	audio_mic(1);
	if (tx_tone) {
		ctcss_on(tx_tone);
		audio_fii(1);
	}
}

static void tx_off(void)
{
	if (tx_tone) {
		audio_fii(0);
		ctcss_off();
	}
	audio_mic(0);
	out1(out1_shadow & ~OUT1_TXON);
	transmitting = 0;
	radio_tune(rx_hz, tx_hz);	/* parks TX; RX if changed meanwhile */
	audio_tx_done();
	sq_open = 0;
	sq_count = 0;
	audio_rx(0);
}

static void ptt_poll(void)
{
	int down = !(PORT7 & 0x08);

	if (!down)
		tx_locked = 0;
	else if (tx_locked)
		down = 0;
	else if (tx_hz < band->tx_lo || tx_hz > band->tx_hi) {
		tx_locked = TXL_BAND;
		down = 0;
	} else if (transmitting && tot_limit &&
		   ticks - tx_start >= tot_limit * TICK_HZ) {
		tx_locked = TXL_TOT;	/* until PTT is let go */
		down = 0;
		ptt_count = 2;		/* off at once */
	}
	if (down == transmitting) {
		ptt_count = 0;
		return;
	}
	if (++ptt_count < 2)
		return;
	ptt_count = 0;
	if (down)
		tx_on();
	else
		tx_off();
}

/* the squelch has had its look at the channel since the last retune */
int radio_settled(void)
{
	return settle == 0;
}

void radio_poll(void)
{
	int want;

	if (ticks == last_tick)
		return;
	last_tick = ticks;
	ptt_poll();
	if (transmitting)
		return;
	if (settle)
		settle--;
	if (settle > SQ_TICKS)
		return;
	rssi = ADDRA >> 6;
	noise = ADDRB >> 6;
	if (sq_open)
		want = noise < sq_off;
	else
		want = noise < sq_on;
	if (want == sq_open) {
		sq_count = 0;
		return;
	}
	if (++sq_count < SQ_TICKS)
		return;
	sq_count = 0;
	sq_open = want;
	audio_rx(sq_open);
}
