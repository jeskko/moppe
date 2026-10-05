/* R40 ham firmware: main loop. */
#include "regs.h"
#include "hw.h"
#include "i2c.h"
#include "lcd.h"
#include "keypad.h"
#include "audio.h"
#include "radio.h"
#include "ui.h"
#include "nv.h"

/* power off; with the supply held on (ignition), wait for PWR */
static void off(void)
{
	power_off();
	lcd_clear();
	lcd_flush();
	while (key_down == K_PWR) {
		keypad_poll();
		wdog_kick();
	}
	while (key_get() != K_PWR) {
		keypad_poll();
		wdog_kick();
	}
	di();
	reset();
}

int main(void)
{
	int k;

	hw_init();
	i2c_init();
	lcd_init();
	nv_load();		/* the defaults stay if NV is not valid */
	audio_init();
	keypad_init();
	radio_init();
	ei();
	ui_init();		/* checks the settings, tunes, saves */
	for (;;) {
		wdog_kick();
		keypad_poll();
		radio_poll();
		audio_poll();
		ui_poll();
		k = key_get();
		if (k == K_PWR)
			off();
		else if (k != K_NONE) {
			audio_beep();
			ui_key(k);
		}
		ui_draw();
		lcd_update();
	}
}
