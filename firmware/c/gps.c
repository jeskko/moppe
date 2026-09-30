/*
 * GPS sentence processing in C, in ROM bank 2 (Phase 4,
 * notes/hybrid-plan.md).  Replaces the bank-1 assembler from
 * gps_process_aisin_seiki to gps_information_has_been_updated (the
 * assembler originals are in git tag asm-final; the Aisin Seiki binary
 * path, cfg_gps_config 3, was dropped 2026-10-01: broken since v3_Z and
 * not known to be in use); the two APRS symbol
 * tables that used to sit in that range are c/aprs.c's symbols[] now.
 * The byte gatherer gps_check stays fixed (it runs on every mainloop
 * pass); it calls these once per complete sentence through far_* stubs.
 *
 * Kept from the assembler on purpose (test_gps_diff.py pins them):
 * number fields only reject characters below '0' (a letter is stored as
 * its value minus '0'); a field that fails leaves the fields before it
 * updated; speed and course wrap at 16 bits.
 *
 * The routines called here do not preserve IX: no stack frames, state is
 * static.  Mainline only.
 */
#pragma bank 2

#include "r58.h"

extern uint8_t gps_date[8];

/* firmware routines (assembler) */
extern uint8_t knots_to_kmh(uint16_t knots);		/* HL -> A, max 255 */

static const uint8_t str_gprmc[] = "GPRMC,";

static uint8_t i, a, b, c, d, e;
static uint16_t num;
static const uint8_t *p;
static uint8_t *dst;

static void gps_information_has_been_updated(void)
{
	gps_own_locator();		/* lat/lon into the Maidenhead locator */
	gps_valid_seconds = 5;
	if (menu_active)
		redraw();		/* in case a GPS value is shown */
}

/* ---- NMEA */

/* 0..15, or 0xFF */
static uint8_t hexchr_to_bin(uint8_t ch)
{
	if (ch >= '0' && ch <= '9')
		return ch - '0';
	if (ch >= 'A' && ch <= 'F')
		return ch - 'A' + 10;
	if (ch >= 'a' && ch <= 'f')
		return ch - 'a' + 10;
	return 0xFF;
}

/* XOR of the characters before '*' against the two hex digits after it;
 * len counts the stored characters ($ is not stored) */
static uint8_t gps_checksum_ok(uint8_t len)
{
	p = gps_sentence;
	b = len;
	e = 0;
	while ((a = *p++) != '*') {
		e ^= a;
		if (!--b)
			return 0;		/* too short */
	}
	if (b < 2)
		return 0;
	if ((d = hexchr_to_bin(*p++)) == 0xFF || (a = hexchr_to_bin(*p++)) == 0xFF)
		return 0;
	return (d << 4 | a) == e;
}

/* DDDMM.mm[m..],H into dst[0..7]; 0 on a bad character.  Digits before the
 * point go through a shift register b c d e (and dst[0]), so only the last
 * five count and short fields are zero-filled on the left. */
static uint8_t latlon_field(void)
{
	b = c = d = e = 0;
	while ((a = *p++) != '.') {
		if (a < '0')
			return 0;
		dst[0] = b;
		b = c;
		c = d;
		d = e;
		e = a - '0';
	}
	dst[1] = b;
	dst[2] = c;
	dst[3] = d;
	dst[4] = e;
	/* two decimals of minutes, the rest ignored */
	d = e = 0;
	if ((a = *p++) != ',') {
		if (a < '0')
			return 0;
		d = a - '0';
		if ((a = *p++) != ',') {
			if (a < '0')
				return 0;
			e = a - '0';
			while ((a = *p++) != ',')
				if (a < '0')
					return 0;
		}
	}
	dst[5] = d;
	dst[6] = e;
	dst[7] = *p++;			/* N/S, E/W */
	return *p++ == ',';
}

/* a number up to ',' into num, rounded at the first decimal (16 bits,
 * overflow not checked); 0 on a bad character */
static uint8_t number_field(void)
{
	num = 0;
	for (;;) {
		a = *p++;
		if (a == ',')
			return 1;
		if (a == '.')
			break;
		if (a < '0')
			return 0;
		num = num * 10 + (uint8_t)(a - '0');
	}
	a = *p++;
	if (a == ',')
		return 1;
	if (a >= '5')
		num++;			/* round up */
	while ((a = *p++) != ',')
		if (a < '0')
			return 0;
	return 1;
}

/* two characters at p as digits into dst[at], dst[at + 1]; 0 on a bad one */
static uint8_t digits(uint8_t at)
{
	for (i = 0; i < 2; i++) {
		a = *p++;
		if (a < '0')
			return 0;
		dst[at + i] = a - '0';
	}
	return 1;
}

/* GPRMC,212909.00,A,4915.607,N,12310.537,W,000.0,360.0,111198,020.3,E*68 */
static void gps_process_gprmc(void)
{
	p = gps_sentence + 6;		/* after "GPRMC," */

	/* HHMMSS time of fix, maybe .NN decimals */
	dst = gps_utc;
	if (!digits(0) || !digits(2) || !digits(4))
		return;
	gps_utc[6] = EOS;
	gps_utc[7] = EOS;
	while ((a = *p++) != ',')
		if (a != '.' && (a < '0' || a > '9'))
			return;

	/* A = OK, V = receiver warning */
	if (*p++ != 'A' || *p++ != ',')
		return;

	dst = cfg_gps_latitude;
	if (!latlon_field())
		return;
	dst = cfg_gps_longitude;
	if (!latlon_field())
		return;

	/* speed over ground, knots */
	if (!number_field())
		return;
	gps_knots = num;
	gps_speed = knots_to_kmh(num);	/* max 255 km/h */

	/* course made good, true */
	if (!number_field())
		return;
	gps_course = num;

	/* DDMMYY date of fix into YYMMDD */
	dst = gps_date;
	if (!digits(4) || !digits(2) || !digits(0))
		return;
	gps_date[6] = EOS;
	gps_date[7] = EOS;
	if (*p++ != ',')
		return;
	/* (magnetic variation not used) */
	gps_information_has_been_updated();
}

/* len characters in gps_sentence (without the '$') */
void gps_process_sentence(uint8_t len)
{
	b = len;
	for (i = 0; str_gprmc[i]; i++) {
		if (gps_sentence[i] != str_gprmc[i])
			return;			/* not GPRMC */
		if (!--b)
			return;
	}
	if (gps_checksum_ok(len))
		gps_process_gprmc();
}
