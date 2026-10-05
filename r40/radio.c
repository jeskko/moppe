/*
 * Receiver.  RX VCO at f + 45 MHz; the TX synthesizer is parked 62.5 kHz
 * (ten steps) above f until PTT, as the Nokia firmware does.  The A/D
 * scans AN0 (RSSI) and AN1 (noise: high with no signal) continuously;
 * the squelch opens when the noise falls below sq_level and closes 16
 * counts above it, each after two ticks in a row.
 */
#include "regs.h"
#include "hw.h"
#include "pll.h"
#include "audio.h"
#include "radio.h"

#define TX_PARK 62500L
#define SQ_HYST 16

unsigned long rx_hz;
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

void radio_tune(unsigned long hz)
{
	rx_hz = hz;
	pll_vco(PLL_RX, hz + RX_IF);
	pll_vco(PLL_TX, hz + TX_PARK);
}

void radio_poll(void)
{
	int want;

	if (ticks == last_tick)
		return;
	last_tick = ticks;
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
