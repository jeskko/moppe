/*
 * The band.  Nokia's service mode stores it at NV 0x63 (test 15x: 0x40
 * C band 138-174 MHz, 0x80 D band 400-470 MHz) with the 0-channels
 * (test 18: C 138 / 183 MHz, D 400 / 445 MHz); cal.c reads them.  The
 * synthesizers differ only in the prescaler: with the same R = 1024 and
 * 6.25 kHz raster, Nokia loads SW = 1 (64/65) on C and SW = 0 (128/129)
 * on D (emulator, Cr 13.04: 145 MHz RX 475/0, TX parked 362/42).
 *
 * The menu's band choice overrides Nokia's byte, for a radio whose NV
 * lost it.  The 2 m transmit range is the Finnish/IARU region 1 band.
 */
#include "cal.h"
#include "band.h"

static const struct band bands[] = {
	{ "", 0, 0, 0, 0, 0, 0, 0, 0 },
	{ "2 m", 138000000L, 174000000L, 144000000L, 146000000L,
	  145500000L, 600000L, 138000000L, 1 },
	{ "70 cm", 400000000L, 470000000L, 430000000L, 440000000L,
	  433500000L, 7600000L, 400000000L, 0 },
};

unsigned char band_choice;
unsigned char band_id = BAND_70CM;
const struct band *band = &bands[BAND_70CM];

void band_select(void)
{
	int b = band_choice;

	if (b != BAND_2M && b != BAND_70CM) {
		band_choice = BAND_AUTO;
		b = cal_nokia_band() == 0x40 ? BAND_2M : BAND_70CM;
	}
	band_id = b;
	band = &bands[b];
	cal_band();
}
