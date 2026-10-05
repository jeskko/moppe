/*
 * VFO screen.  Row 0: the frequency (the TX one while transmitting), or
 * the entry being typed, then the duplex sign ('-', '+', 'R' reversed)
 * and 'F' after FNC; row 1: volume and step; row 2: TX, LOCK (PTT
 * outside the TX band) or BUSY, and the RSSI reading (A/D / 4).
 *
 * Keys: digits then OK enter a frequency, MHz first ("4335" OK =
 * 433.500, "43350625" OK = 433.50625), rounded down to the 6.25 kHz
 * raster; CLR deletes the last digit.  UP / DOWN tune by one step.
 * FNC, then: UP / DOWN volume; 1 the next tuning step; # duplex
 * (simplex, -, +); 0 reverse; * a shift entry in kHz ("7600" OK).
 * FNC again or any other key cancels.  Every change is saved to NV.
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

static const unsigned long steps[] = {
	6250L, 12500L, 25000L, 100000L, 1000000L
};
#define NSTEPS (sizeof steps / sizeof steps[0])

unsigned long vfo_hz = 433500000L;
unsigned long shift_hz = 7600000L;
unsigned char duplex;		/* DUP_SIMPLEX, DUP_MINUS, DUP_PLUS */
unsigned char reverse;
unsigned char ui_step = 1;

static char entry[ENTRY_MAX + 1];
static int nentry;
static unsigned char shift_entry;	/* the entry is a shift in kHz */
static unsigned char fnc;
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

/* "433.50625"; returns the end */
static char *fmt_mhz(unsigned long hz, char *buf)
{
	buf = utoa(hz / 1000000L, buf, 1);
	*buf++ = '.';
	return utoa(hz % 1000000L / 10, buf, 5);
}

/* the radio's frequencies from the VFO */
static void apply(void)
{
	unsigned long other = vfo_hz;

	if (duplex == DUP_MINUS)
		other = vfo_hz - shift_hz;
	else if (duplex == DUP_PLUS)
		other = vfo_hz + shift_hz;
	if (reverse)
		radio_tune(other, vfo_hz);
	else
		radio_tune(vfo_hz, other);
	nv_save();
	redraw = 1;
}

static void tune(unsigned long hz)
{
	hz -= hz % PLL_STEP;
	if (hz < BAND_LO || hz > BAND_HI)
		return;
	vfo_hz = hz;
	apply();
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

/* the entry as kHz, in Hz */
static unsigned long entry_khz(void)
{
	unsigned long khz = 0;
	int i;

	for (i = 0; i < nentry; i++)
		khz = khz * 10 + (entry[i] - '0');
	return khz * 1000L;
}

void ui_init(void)
{
	if (ui_step >= NSTEPS)
		ui_step = 1;
	if (duplex > DUP_PLUS)
		duplex = DUP_SIMPLEX;
	if (vfo_hz < BAND_LO || vfo_hz > BAND_HI)
		vfo_hz = 433500000L;
	if (shift_hz % PLL_STEP || shift_hz > 50000000L)
		shift_hz = 7600000L;
	apply();
}

static void fnc_key(int k)
{
	switch (k) {
	case K_UP:
	case K_DOWN:
		audio_volume(volume + (k == K_UP ? 1 : -1));
		nv_save();
		break;
	case '1':
		ui_step = (ui_step + 1) % NSTEPS;
		nv_save();
		break;
	case '#':
		duplex = (duplex + 1) % 3;
		apply();
		break;
	case '0':
		reverse = !reverse;
		apply();
		break;
	case '*':
		nentry = 0;
		shift_entry = 1;
		break;
	}
}

void ui_key(int k)
{
	redraw = 1;
	if (fnc) {
		fnc = 0;
		fnc_key(k);
		return;
	}
	if (k >= '0' && k <= '9') {
		if (nentry < ENTRY_MAX)
			entry[nentry++] = k;
		return;
	}
	switch (k) {
	case K_OK:
		if (shift_entry) {
			unsigned long s = entry_khz();

			if (nentry && s % PLL_STEP == 0 && s <= 50000000L) {
				shift_hz = s;
				apply();
			}
		} else if (nentry)
			tune(entry_hz());
		nentry = 0;
		shift_entry = 0;
		break;
	case K_CLR:
		if (nentry)
			nentry--;
		else
			shift_entry = 0;
		break;
	case K_UP:
	case K_DOWN:
		nentry = 0;
		shift_entry = 0;
		if (k == K_UP)
			tune(vfo_hz + steps[ui_step]);
		else
			tune(vfo_hz - steps[ui_step]);
		break;
	case K_FNC:
		fnc = 1;
		break;
	}
}

static void draw_top(void)
{
	char buf[21], *p = buf;
	int i;

	if (shift_entry) {
		/* "Shift 7600_ kHz" */
		lcd_puts(0, 0, "Shift               ");
		for (i = 0; i < nentry; i++)
			buf[i] = entry[i];
		buf[i++] = '_';
		buf[i] = 0;
		lcd_puts(0, 6, buf);
		lcd_puts(0, 7 + i, "kHz");
		return;
	}
	for (i = 0; i < 20; i++)
		buf[i] = ' ';
	buf[20] = 0;
	if (nentry) {
		/* "433.5___" while typing */
		for (i = 0; i < ENTRY_MAX; i++) {
			if (i == 3)
				*p++ = '.';
			*p++ = i < nentry ? entry[i] : '_';
		}
	} else {
		p = fmt_mhz(transmitting ? tx_hz : rx_hz, buf);
		*p = ' ';
	}
	if (duplex)
		buf[10] = duplex == DUP_MINUS ? '-' : '+';
	if (reverse)
		buf[11] = 'R';
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

/* bottom row: TX, LOCK or BUSY, and the RSSI reading */
static void draw_rx(void)
{
	char buf[6];
	static unsigned char last_state = 0xFF;
	static unsigned last_rssi = 0xFFFF;
	unsigned char state = transmitting ? 2 : tx_locked ? 3 : sq_open;

	if (state != last_state) {
		if (state == 2 || last_state == 2)
			redraw = 1;	/* the top row shows the TX frequency */
		last_state = state;
		lcd_puts(2, 0, state == 2 ? "TX  " : state == 3 ? "LOCK" :
			 state ? "BUSY" : "    ");
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
	draw_rx();
	if (redraw) {
		redraw = 0;
		draw_top();
		draw_mid();
	}
}
