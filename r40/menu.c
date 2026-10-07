/*
 * Settings menu (FNC, then OK): row 0 the item, row 1 its value.  UP /
 * DOWN change the value (at once, and saved), OK goes to the next item,
 * CLR or FNC leaves.
 *
 * Tone: the CTCSS tone sent with the current channel (VFO or memory,
 * like duplex), off or 67.0-254.1 Hz; experimental (tone.c).
 *
 * Squelch: "cal" (the default) uses Nokia's calibrated levels (cal.c);
 * 0 never closes; level n opens below a noise reading of 600 - 20 n and
 * closes 16 above (the scale is a guess until a real radio's noise
 * readings are known).  TX power is Nokia's calibrated level 1-3 (low,
 * mid, high); RX tune a trim added to the calibrated RFC, shown with
 * the resulting DAC value.  RX self-cal: UP runs cal.c's sweep (any
 * key stops it), DOWN goes back to Nokia's table.  Band: auto (Nokia's
 * band byte), 2 m or 70 cm; a change restarts the firmware when the menu
 * is left.
 */
#include "hw.h"
#include "lcd.h"
#include "keypad.h"
#include "audio.h"
#include "radio.h"
#include "serbus.h"
#include "nv.h"
#include "ui.h"
#include "menu.h"
#include "tone.h"
#include "cal.h"
#include "band.h"

#define M_SQUELCH 0
#define M_TONE    1
#define M_TOT     2
#define M_BEEP    3
#define M_TXPOWER 4
#define M_RXTUNE  5
#define M_RXCAL   6
#define M_BAND    7
#define NITEMS    8

static const char *const names[NITEMS] = {
	"Squelch", "Tone (CTCSS)", "Time-out", "Beep", "TX power", "RX tune",
	"RX self-cal", "Band"
};
static const unsigned tot_secs[] = { 0, 30, 60, 120, 180, 300, 600 };
#define NTOT (sizeof tot_secs / sizeof tot_secs[0])

unsigned char menu_active;
static unsigned char item;
static unsigned char band_open;	/* band_choice when the menu opened */
unsigned char sq_index = SQ_CAL;
unsigned char tot_index;

/* copies s to p, returns the end */
static char *strcpy_end(char *p, const char *s)
{
	while ((*p = *s++) != 0)
		p++;
	return p;
}

void settings_apply(void)
{
	if (sq_index > SQ_CAL)
		sq_index = SQ_CAL;
	if (tot_index >= NTOT)
		tot_index = 0;
	if (tx_level > 2)
		tx_level = 1;
	if (rx_trim < -RX_TRIM || rx_trim > RX_TRIM)
		rx_trim = 0;
	if (sq_index == SQ_CAL) {
		sq_on = cal_sq_open();
		sq_off = cal_sq_close() + 4;	/* 8-bit: closes above it */
	} else if (sq_index) {
		sq_on = 600 - 20 * sq_index;
		sq_off = sq_on + 16;
	} else
		sq_on = sq_off = 1100;
	tot_limit = tot_secs[tot_index];
	radio_dac();
}

void menu_open(void)
{
	menu_active = 1;
	item = 0;
	band_open = band_choice;
}

static void change(int d)
{
	switch (item) {
	case M_SQUELCH:
		if (sq_index + d >= 0 && sq_index + d <= SQ_CAL)
			sq_index += d;
		break;
	case M_TONE:
		if (ui_tone() + d >= 0 && ui_tone() + d <= NTONES)
			ui_set_tone(ui_tone() + d);
		return;
	case M_TOT:
		if (tot_index + d >= 0 && tot_index + d < (int)NTOT)
			tot_index += d;
		break;
	case M_BEEP:
		beep_enabled = !beep_enabled;
		break;
	case M_TXPOWER:
		if (tx_level + d >= 0 && tx_level + d <= 2)
			tx_level += d;
		break;
	case M_RXTUNE:
		if (rx_trim + d >= -RX_TRIM && rx_trim + d <= RX_TRIM)
			rx_trim += d;
		break;
	case M_RXCAL:
		if (d > 0)
			cal_self();
		else
			cal_self_clear();
		break;
	case M_BAND:
		if (band_choice + d >= BAND_AUTO && band_choice + d <= BAND_70CM)
			band_choice += d;
		break;
	}
	settings_apply();
	nv_save();
}

void menu_key(int k)
{
	switch (k) {
	case K_UP:
		change(1);
		break;
	case K_DOWN:
		change(-1);
		break;
	case K_OK:
		item = (item + 1) % NITEMS;
		break;
	case K_CLR:
	case K_FNC:
		menu_active = 0;
		if (band_choice != band_open) {
			nv_save();
			di();
			reset();	/* the new band from the start */
		}
		break;
	}
}

void menu_draw(void)
{
	char buf[25], *p = buf;
	int i;

	for (i = 0; i < 24; i++)
		buf[i] = ' ';
	buf[24] = 0;
	lcd_puts(0, 0, buf);
	lcd_puts(1, 0, buf);
	lcd_puts(0, 0, names[item]);
	switch (item) {
	case M_SQUELCH:
		if (sq_index == SQ_CAL)
			p = "cal";
		else if (sq_index)
			utoa(sq_index, p, 1);
		else
			p = "open";
		break;
	case M_TONE:
		if (ui_tone()) {
			unsigned t = tones[ui_tone()];

			p = utoa(t / 10, buf, 1);
			*p++ = '.';
			*p++ = '0' + t % 10;
			*p++ = ' ';
			*p++ = 'H';
			*p++ = 'z';
			*p = 0;
			p = buf;
		} else
			p = "off";
		break;
	case M_TOT:
		if (tot_index == 0)
			p = "off";
		else if (tot_secs[tot_index] < 60) {
			lcd_puts(1, 3, "s");
			utoa(tot_secs[tot_index], p, 1);	/* "30 s" */
		} else {
			lcd_puts(1, 3, "min");
			utoa(tot_secs[tot_index] / 60, p, 1);	/* "5  min" */
		}
		break;
	case M_BEEP:
		p = beep_enabled ? "on" : "off";
		break;
	case M_TXPOWER:
		p = tx_level == 0 ? "low" : tx_level == 1 ? "mid" : "high";
		break;
	case M_RXTUNE:
		if (rx_trim < 0)
			*p++ = '-';
		else if (rx_trim > 0)
			*p++ = '+';
		p = utoa(rx_trim < 0 ? -rx_trim : rx_trim, p, 1);
		*p++ = ' ';
		*p++ = '(';
		p = utoa(rfc, p, 1);
		*p++ = ')';
		*p = 0;
		p = buf;
		break;
	case M_RXCAL:
		p = cal_self_valid() ? "own" : "Nokia";
		break;
	case M_BAND:
		if (band_choice == BAND_AUTO) {
			p = strcpy_end(buf, "auto (");
			p = strcpy_end(p, band->name);
			*p++ = ')';
			*p = 0;
			p = buf;
		} else
			p = band_choice == BAND_2M ? "2 m" : "70 cm";
		break;
	}
	lcd_puts(1, 0, p);
}
