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
	lcd_update();
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
	rx_hz = tx_hz = 433500000L;	/* defaults, unless NV has better */
	if (nv_load() || rx_hz < BAND_LO || rx_hz > BAND_HI) {
		rx_hz = tx_hz = 433500000L;
		nv_save();
	}
	audio_init();
	keypad_init();
	radio_init();
	ei();
	radio_tune(rx_hz, tx_hz);
	ui_init();
	for (;;) {
		wdog_kick();
		keypad_poll();
		radio_poll();
		k = key_get();
		if (k == K_PWR)
			off();
		else if (k != K_NONE)
			ui_key(k);
		ui_draw();
		lcd_update();
	}
}
