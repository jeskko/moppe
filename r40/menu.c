/*
 * Settings menu (FNC, then OK): row 0 the item, row 1 its value.  UP /
 * DOWN change the value (at once, and saved), OK goes to the next item,
 * CLR or FNC leaves.
 *
 * Squelch 0-9: 0 never closes; level n opens below a noise reading of
 * 600 - 20 n (level 6 = 480, the old default).  The scale is a guess
 * until a real radio's noise readings are known.  TX power and RX tune
 * are the raw DAC values (TPC, RFC) until Nokia's calibration data in NV
 * is mapped (notes/r40.md gap 3).
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

#define M_SQUELCH 0
#define M_TOT     1
#define M_BEEP    2
#define M_TXPOWER 3
#define M_RXTUNE  4
#define NITEMS    5

static const char *const names[NITEMS] = {
	"Squelch", "Time-out", "Beep", "TX power", "RX tune"
};
static const unsigned tot_secs[] = { 0, 30, 60, 120, 180, 300, 600 };
#define NTOT (sizeof tot_secs / sizeof tot_secs[0])

unsigned char menu_active;
static unsigned char item;
unsigned char sq_index = 6;
unsigned char tot_index;

void settings_apply(void)
{
	if (sq_index > 9)
		sq_index = 6;
	if (tot_index >= NTOT)
		tot_index = 0;
	sq_level = sq_index ? 600 - 20 * sq_index : 1100;
	tot_limit = tot_secs[tot_index];
	rfc &= 0x3F;
	tpc &= 0x3F;
	dac_write(rfc, tpc, rfc, tpc);
}

void menu_open(void)
{
	menu_active = 1;
	item = 0;
}

static void change(int d)
{
	switch (item) {
	case M_SQUELCH:
		if (sq_index + d >= 0 && sq_index + d <= 9)
			sq_index += d;
		break;
	case M_TOT:
		if (tot_index + d >= 0 && tot_index + d < (int)NTOT)
			tot_index += d;
		break;
	case M_BEEP:
		beep_enabled = !beep_enabled;
		break;
	case M_TXPOWER:
		tpc = (tpc + d) & 0x3F;
		break;
	case M_RXTUNE:
		rfc = (rfc + d) & 0x3F;
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
		if (sq_index)
			utoa(sq_index, p, 1);
		else
			p = "open";
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
		utoa(tpc, p, 1);
		break;
	case M_RXTUNE:
		utoa(rfc, p, 1);
		break;
	}
	lcd_puts(1, 0, p);
}
