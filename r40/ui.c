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
 * (simplex, -, +); 0 reverse; * a shift entry in kHz ("7600" OK); RCL
 * (= STO) store what is on now: two digits name the memory (the mode
 * stays); 9 scan; OK the settings menu (menu.c).  FNC again or any
 * other key cancels.
 *
 * Scan: the VFO steps up through 430-440 MHz, the memories through the
 * stored ones; it stops while the squelch is open and goes on 2 s after
 * it closes.  Any key (taken by the scan, not acted on) or PTT ends it.
 *
 * RCL switches between the VFO and the memories ("M05" on row 0; the
 * last channel used, or the next stored one).  In memory mode two
 * digits choose a channel and UP / DOWN step through the stored ones;
 * duplex, shift and reverse change the channel until the next recall
 * (STO keeps them).  The VFO and settings are saved to NV on every
 * change.
 */
#include "hw.h"
#include "lcd.h"
#include "keypad.h"
#include "audio.h"
#include "pll.h"
#include "radio.h"
#include "nv.h"
#include "mem.h"
#include "menu.h"
#include "tone.h"
#include "ui.h"

#define ENTRY_MAX 8

static const unsigned long steps[] = {
	6250L, 12500L, 25000L, 100000L, 1000000L
};
#define NSTEPS (sizeof steps / sizeof steps[0])

struct chan vfo = { 433500000L, 7600000L, DUP_SIMPLEX, 0 };
static struct chan cur;		/* what the radio is on */
unsigned char mem_mode;
unsigned char mem_ch;
unsigned char ui_step = 1;

static char entry[ENTRY_MAX + 1];
static int nentry;
#define E_FREQ  0
#define E_SHIFT 1		/* a shift in kHz */
#define E_STORE 2		/* a memory number to store to */
#define E_RCL   3		/* a memory number to recall */
static unsigned char etype;
static unsigned char fnc;
static unsigned char redraw;	/* rows 0 and 1 */
unsigned char scanning;
static unsigned scan_resume;	/* ticks: when to leave a busy channel */
static unsigned char scan_held;

#define SCAN_LO 430000000L
#define SCAN_HI 440000000L
#define SCAN_HOLD 200		/* ticks after the signal goes */

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

/* the radio's frequencies from cur; in VFO mode cur is the VFO */
static void apply(void)
{
	unsigned long other = cur.hz;

	if (cur.duplex == DUP_MINUS)
		other = cur.hz - cur.shift;
	else if (cur.duplex == DUP_PLUS)
		other = cur.hz + cur.shift;
	tx_tone = cur.tone <= NTONES ? cur.tone : 0;
	if (cur.reverse)
		radio_tune(other, cur.hz);
	else
		radio_tune(cur.hz, other);
	if (!mem_mode)
		vfo = cur;
	nv_save();
	redraw = 1;
}

static void to_vfo(void)
{
	mem_mode = 0;
	cur = vfo;
	apply();
}

/* memory n, if stored */
static void recall(int n)
{
	if (mem_get(n, &cur))
		return;
	mem_mode = 1;
	mem_ch = n;
	apply();
}

static void tune(unsigned long hz)
{
	hz -= hz % PLL_STEP;
	if (hz < BAND_LO || hz > BAND_HI)
		return;
	if (mem_mode) {
		mem_mode = 0;
		cur = vfo;
	}
	cur.hz = hz;
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

static int entry_num(void)
{
	return (entry[0] - '0') * 10 + entry[1] - '0';
}

/* the menu's Tone item: the channel on now (as duplex: a memory keeps
   it only when stored again) */
int ui_tone(void)
{
	return cur.tone;
}

void ui_set_tone(int t)
{
	cur.tone = t;
	apply();
}

void ui_init(void)
{
	if (ui_step >= NSTEPS)
		ui_step = 1;
	if (vfo.duplex > DUP_PLUS)
		vfo.duplex = DUP_SIMPLEX;
	if (vfo.hz < BAND_LO || vfo.hz > BAND_HI || vfo.hz % PLL_STEP)
		vfo.hz = 433500000L;
	if (vfo.shift % PLL_STEP || vfo.shift > 50000000L)
		vfo.shift = 7600000L;
	vfo.reverse = vfo.reverse != 0;
	if (vfo.tone > NTONES)
		vfo.tone = 0;
	if (mem_mode && mem_get(mem_ch, &cur) == 0)
		apply();
	else
		to_vfo();
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
		cur.duplex = (cur.duplex + 1) % 3;
		apply();
		break;
	case '0':
		cur.reverse = !cur.reverse;
		apply();
		break;
	case '*':
		nentry = 0;
		etype = E_SHIFT;
		break;
	case K_RCL:
		nentry = 0;
		etype = E_STORE;
		break;
	case K_OK:
		menu_open();
		break;
	case '9':
		if (!mem_mode || mem_next(mem_ch, 1) >= 0) {
			scanning = 1;
			scan_held = 0;
		}
		break;
	}
}

static void scan_step(void)
{
	unsigned long hz;
	int n;

	if (mem_mode) {
		n = mem_next(mem_ch, 1);
		if (n >= 0)
			recall(n);
		return;
	}
	hz = cur.hz + steps[ui_step];
	if (hz < SCAN_LO || hz > SCAN_HI)
		hz = SCAN_LO;
	tune(hz);
}

/* main loop: the scan */
void ui_poll(void)
{
	if (!scanning)
		return;
	if (transmitting) {
		scanning = 0;
		return;
	}
	if (!radio_settled())
		return;
	if (sq_open) {
		scan_held = 1;
		scan_resume = ticks + SCAN_HOLD;
		return;
	}
	if (scan_held && (int)(ticks - scan_resume) < 0)
		return;
	scan_held = 0;
	scan_step();
}

/* OK, or the second digit of a memory number */
static void enter(void)
{
	unsigned long s;

	switch (etype) {
	case E_FREQ:
		if (nentry)
			tune(entry_hz());
		break;
	case E_SHIFT:
		s = entry_khz();
		if (nentry && s % PLL_STEP == 0 && s <= 50000000L) {
			cur.shift = s;
			apply();
		}
		break;
	case E_STORE:
		if (nentry == 2) {
			mem_put(entry_num(), &cur);
			if (mem_mode)
				recall(entry_num());
		}
		break;
	case E_RCL:
		if (nentry == 2)
			recall(entry_num());
		break;
	}
	nentry = 0;
	etype = E_FREQ;
}

void ui_key(int k)
{
	redraw = 1;
	if (scanning) {
		scanning = 0;
		return;
	}
	if (menu_active) {
		menu_key(k);
		return;
	}
	if (fnc) {
		fnc = 0;
		fnc_key(k);
		return;
	}
	if (k >= '0' && k <= '9') {
		if (mem_mode && etype == E_FREQ && nentry == 0)
			etype = E_RCL;
		if (nentry < ENTRY_MAX)
			entry[nentry++] = k;
		if ((etype == E_STORE || etype == E_RCL) && nentry == 2)
			enter();
		return;
	}
	switch (k) {
	case K_OK:
		enter();
		break;
	case K_CLR:
		if (nentry)
			nentry--;
		else
			etype = E_FREQ;
		break;
	case K_UP:
	case K_DOWN:
		nentry = 0;
		etype = E_FREQ;
		if (mem_mode) {
			int n = mem_next(mem_ch, k == K_UP ? 1 : -1);

			if (n >= 0)
				recall(n);
		} else if (k == K_UP)
			tune(cur.hz + steps[ui_step]);
		else
			tune(cur.hz - steps[ui_step]);
		break;
	case K_RCL:
		nentry = 0;
		etype = E_FREQ;
		if (mem_mode)
			to_vfo();
		else if (mem_get(mem_ch, 0) == 0)
			recall(mem_ch);
		else if (mem_next(mem_ch, 1) >= 0)
			recall(mem_next(mem_ch, 1));
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

	if (etype == E_SHIFT || etype == E_STORE) {
		/* "Shift 7600_ kHz", "Store 0_" */
		lcd_puts(0, 0, etype == E_SHIFT ? "Shift               " :
			 "Store               ");
		for (i = 0; i < nentry; i++)
			buf[i] = entry[i];
		buf[i++] = '_';
		buf[i] = 0;
		lcd_puts(0, 6, buf);
		if (etype == E_SHIFT)
			lcd_puts(0, 7 + i, "kHz");
		return;
	}
	for (i = 0; i < 20; i++)
		buf[i] = ' ';
	buf[20] = 0;
	if (etype == E_RCL) {
		/* "M0_" while choosing a memory */
		*p++ = 'M';
		*p++ = entry[0];
		*p++ = '_';
	} else if (nentry) {
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
	if (cur.duplex && !nentry)
		buf[10] = cur.duplex == DUP_MINUS ? '-' : '+';
	if (cur.reverse && !nentry)
		buf[11] = 'R';
	if (cur.tone && !nentry)
		buf[12] = 'T';
	if (mem_mode && !nentry) {
		buf[14] = 'M';
		buf[15] = '0' + mem_ch / 10;
		buf[16] = '0' + mem_ch % 10;
	}
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
	unsigned char state = transmitting ? 2 : tx_locked == TXL_BAND ? 3 :
		tx_locked == TXL_TOT ? 5 : sq_open ? 1 : scanning ? 4 : 0;

	if (state != last_state) {
		if (state == 2 || last_state == 2)
			redraw = 1;	/* the top row shows the TX frequency */
		last_state = state;
		lcd_puts(2, 0, state == 2 ? "TX  " : state == 3 ? "LOCK" :
			 state == 4 ? "SCAN" : state == 5 ? "TOT " :
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
		if (menu_active) {
			menu_draw();
			return;
		}
		draw_top();
		draw_mid();
	}
}
