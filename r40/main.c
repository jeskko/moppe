/* R40 ham firmware: main loop. */
#include "regs.h"
#include "hw.h"
#include "i2c.h"
#include "lcd.h"
#include "keypad.h"
#include "audio.h"

static void utoa(unsigned v, char *buf)
{
	char t[6];
	int n = 0;

	do
		t[n++] = '0' + v % 10;
	while ((v /= 10) != 0);
	while (n > 0)
		*buf++ = t[--n];
	*buf = 0;
}

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
	unsigned last = 0xFFFF;
	char buf[8];
	int k;

	hw_init();
	i2c_init();
	lcd_init();
	audio_init();
	keypad_init();
	ei();
	lcd_puts(0, 0, "R40 ham");
	lcd_puts(1, 0, "Hello, world");
	for (;;) {
		unsigned s = ticks / TICK_HZ;

		wdog_kick();
		if (s != last) {
			last = s;
			utoa(s, buf);
			lcd_puts(2, 0, buf);
		}
		keypad_poll();
		k = key_get();
		if (k == K_PWR)
			off();
		if (k == K_UP || k == K_DOWN) {
			audio_volume(volume + (k == K_UP ? 1 : -1));
			buf[0] = '0' + volume;
			buf[1] = 0;
			lcd_puts(1, 14, "Vol ");
			lcd_puts(1, 18, buf);
		}
		if (k != K_NONE) {
			lcd_puts(2, 8, "Key      ");
			lcd_puts(2, 12, key_name(k));
		}
		lcd_update();
	}
}
