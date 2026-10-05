/*
 * VFO screen.  Row 0: the frequency, or the entry being typed; row 1:
 * volume and step; row 2: BUSY and the RSSI reading (A/D / 4).
 *
 * Keys: digits then OK enter a frequency, MHz first ("4335" OK =
 * 433.500, "43350625" OK = 433.50625), rounded down to the 6.25 kHz
 * raster; CLR deletes the last digit.  UP / DOWN tune by one step.
 * FNC, then UP / DOWN: volume; FNC, then 1: the next tuning step (FNC
 * again or any other key cancels).  Every change is saved to NV.
 */
#include "hw.h"
#include "lcd.h"
#include "keypad.h"
#include "audio.h"
#include "pll.h"
#include "radio.h"
#include "nv.h"
#include "ui.h"

#define ENTRY_MAX 8

static char entry[ENTRY_MAX + 1];
static int nentry;
static unsigned char fnc;
static const unsigned long steps[] = {
	6250L, 12500L, 25000L, 100000L, 1000000L
};
#define NSTEPS (sizeof steps / sizeof steps[0])
unsigned char ui_step = 1;
static unsigned char redraw;	/* rows 0 and 1 */

/* v as decimal, at least `digits` digits; returns the end */
char *utoa(unsigned long v, char *buf, int digits)
{
	char t[11];
	int n = 0;

	do
		t[n++] = '0' + (int)(v % 10);
	while ((v /= 10) != 0 || n < digits);
	while (n > 0)
		*buf++ = t[--n];
	*buf = 0;
	return buf;
}

/* "433.50625" */
static void fmt_mhz(unsigned long hz, char *buf)
{
	buf = utoa(hz / 1000000L, buf, 1);
	*buf++ = '.';
	utoa(hz % 1000000L / 10, buf, 5);
}

static void tune(unsigned long hz)
{
	hz -= hz % PLL_STEP;
	if (hz < BAND_LO || hz > BAND_HI)
		return;
	radio_tune(hz, hz);
	nv_save();
	redraw = 1;
}

/* the entry as Hz: three digits of MHz, then fractions */
static unsigned long entry_hz(void)
{
	unsigned long hz = 0, unit = 100000000L;
	int i;

	for (i = 0; i < nentry; i++) {
		hz += (entry[i] - '0') * unit;
		unit /= 10;
	}
	return hz;
}

void ui_init(void)
{
	if (ui_step >= NSTEPS)
		ui_step = 1;
	redraw = 1;
}

void ui_key(int k)
{
	if (fnc) {
		fnc = 0;
		redraw = 1;
		if (k == K_UP || k == K_DOWN) {
			audio_volume(volume + (k == K_UP ? 1 : -1));
			nv_save();
			return;
		}
		if (k == '1') {
			ui_step = (ui_step + 1) % NSTEPS;
			nv_save();
			return;
		}
		if (k == K_FNC)
			return;
	}
	if (k >= '0' && k <= '9') {
		if (nentry < ENTRY_MAX)
			entry[nentry++] = k;
		redraw = 1;
		return;
	}
	switch (k) {
	case K_OK:
		if (nentry) {
			tune(entry_hz());
			nentry = 0;
			redraw = 1;
		}
		break;
	case K_CLR:
		if (nentry)
			nentry--;
		redraw = 1;
		break;
	case K_UP:
		nentry = 0;
		tune(rx_hz + steps[ui_step]);
		break;
	case K_DOWN:
		nentry = 0;
		tune(rx_hz - steps[ui_step]);
		break;
	case K_FNC:
		fnc = 1;
		redraw = 1;
		break;
	}
}

static void draw_top(void)
{
	char buf[21];
	int i, j = 0;

	for (i = 0; i < 20; i++)
		buf[i] = ' ';
	buf[20] = 0;
	if (nentry) {
		/* "433.5___" while typing */
		for (i = 0; i < ENTRY_MAX; i++) {
			if (i == 3)
				buf[j++] = '.';
			buf[j++] = i < nentry ? entry[i] : '_';
		}
	} else
		fmt_mhz(rx_hz, buf);
	for (i = 0; buf[i]; i++)
		;
	if (i < 20)
		buf[i] = ' ';
	if (fnc)
		buf[19] = 'F';
	lcd_puts(0, 0, buf);
}

static void draw_mid(void)
{
	char buf[25], *p;

	p = buf;
	*p++ = 'V';
	*p++ = 'o';
	*p++ = 'l';
	*p++ = ' ';
	*p++ = '0' + volume;
	while (p < buf + 14)
		*p++ = ' ';
	p = utoa(steps[ui_step] / 10, p, 1);	/* "1250" -> "12.50k" */
	p[1] = p[0];
	p[0] = p[-1];
	p[-1] = p[-2];
	p[-2] = '.';
	p += 1;
	*p++ = 'k';
	while (p < buf + 24)
		*p++ = ' ';
	*p = 0;
	lcd_puts(1, 0, buf);
}

/* bottom row: "TX" or "BUSY", and the RSSI reading */
static void draw_rx(void)
{
	char buf[6];
	static unsigned char last_state = 0xFF;
	static unsigned last_rssi = 0xFFFF;
	unsigned char state = transmitting ? 2 : sq_open;

	if (state != last_state) {
		last_state = state;
		lcd_puts(2, 0, state == 2 ? "TX  " : state ? "BUSY" : "    ");
	}
	if (!transmitting && rssi / 4 != last_rssi) {
		last_rssi = rssi / 4;
		lcd_puts(2, 18, "      ");
		utoa(last_rssi, buf, 1);
		lcd_puts(2, 21, buf);
	}
}

void ui_draw(void)
{
	if (redraw) {
		redraw = 0;
		draw_top();
		draw_mid();
	}
	draw_rx();
}
