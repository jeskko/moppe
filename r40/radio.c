/*
 * Receiver and transmitter.  RX VCO at f + 45 MHz; the TX synthesizer
 * is parked 62.5 kHz (ten steps) above the TX frequency until PTT, as
 * the Nokia firmware does.
 *
 * PTT (P7.3 low, two ticks) in the Nokia firmware's order (emulator,
 * Cr 13.04 simplex): deviation bits, DAC (TPC), TX synthesizer to f,
 * TX ON (no lock wait: 0.6 ms later), microphone on.  Release: mic off,
 * TX OFF, synthesizer parked, receive state back.  The A/D
 * scans AN0 (RSSI) and AN1 (noise: high with no signal) continuously;
 * the squelch opens when the noise falls below sq_level and closes 16
 * counts above it, each after two ticks in a row.
 */
#include "regs.h"
#include "hw.h"
#include "pll.h"
#include "audio.h"
#include "serbus.h"
#include "radio.h"

#define TX_PARK 62500L
#define SQ_HYST 16

unsigned long rx_hz, tx_hz;
unsigned char transmitting;
unsigned char tx_locked;
unsigned char rfc, tpc;		/* DAC: RX tuning, TX power (uncalibrated) */
static unsigned char ptt_count;
unsigned noise, rssi;
unsigned char sq_open;
unsigned sq_level = 480;
static unsigned last_tick;
static unsigned char sq_count;

void radio_init(void)
{
	ADCSR = 0x31;		/* scan AN0-AN1, start */
	pll_init();
	audio_rx(0);
}

void radio_tune(unsigned long rx, unsigned long tx)
{
	rx_hz = rx;
	tx_hz = tx;
	if (transmitting)
		return;
	pll_vco(PLL_RX, rx + RX_IF);
	pll_vco(PLL_TX, tx + TX_PARK);
}

static void tx_on(void)
{
	transmitting = 1;
	audio_tx_prepare();
	dac_write(rfc, tpc, rfc, tpc);
	pll_vco(PLL_TX, tx_hz);
	out1(out1_shadow | OUT1_TXON);
	audio_mic(1);
}

static void tx_off(void)
{
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

	if (down && (tx_hz < TX_LO || tx_hz > TX_HI)) {
		tx_locked = 1;
		down = 0;
	} else if (!down)
		tx_locked = 0;
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

void radio_poll(void)
{
	int want;

	if (ticks == last_tick)
		return;
	last_tick = ticks;
	ptt_poll();
	if (transmitting)
		return;
	rssi = ADDRA >> 6;
	noise = ADDRB >> 6;
	if (sq_open)
		want = noise < sq_level + SQ_HYST;
	else
		want = noise < sq_level;
	if (want == sq_open) {
		sq_count = 0;
		return;
	}
	if (++sq_count < 2)
		return;
	sq_count = 0;
	sq_open = want;
	audio_rx(sq_open);
}
