/*
 * GPS sentence processing in C, in ROM bank 2 (Phase 4,
 * notes/hybrid-plan.md).  Built with `make C=1`; replaces the bank-1
 * assembler from gps_process_aisin_seiki to gps_information_has_been_updated
 * (see the C_MODULES blocks in r58.s) except the two APRS symbol tables in
 * it.  The byte gatherer gps_check stays fixed (it runs on every mainloop
 * pass); it calls these once per complete sentence through far_* stubs.
 *
 * Kept from the assembler on purpose (test_gps_diff.py pins them):
 * number fields only reject characters below '0' (a letter is stored as
 * its value minus '0'); a field that fails leaves the fields before it
 * updated; speed and course wrap at 16 bits.  Aisin Seiki blocks: the
 * course is heading * 45 / 256 plus 256 when bit 7 of the product is set
 * (not / 128), the centiminutes' ones byte is a remainder's low byte, and
 * no hemisphere letter is written (notes: open question to the user).
 *
 * The routines called here do not preserve IX: no stack frames, state is
 * static.  Mainline only.
 */
#pragma bank 2

#include <stdint.h>

#define EOS	0xFF

extern uint8_t gps_sentence[100], gps_history[256], gps_utc[8], gps_date[8],
	gps_status[8], cfg_gps_latitude[8], cfg_gps_longitude[8];
extern uint8_t gps_speed, gps_valid_seconds, menu_active;
extern uint16_t gps_knots, gps_course;

/* firmware routines (assembler) */
extern uint8_t knots_to_kmh(uint16_t knots);		/* HL -> A, max 255 */
extern uint8_t quarter_ms_to_kmh(uint16_t qms);	/* HL -> A, max 255 */
extern void redraw(void), far_gps_own_locator(void);
/* r58.s shim: aisin_seiki_parse_latlon (IY, IX) */
extern void gps_latlon(const uint8_t *from, uint8_t *to);

static const uint8_t str_gprmc[] = "GPRMC,";

static uint8_t i, a, b, c, d, e, l;
static uint16_t num;
static uint32_t acc;
static const uint8_t *p;
static uint8_t *dst;

static void gps_information_has_been_updated(void)
{
	far_gps_own_locator();		/* lat/lon into the Maidenhead locator */
	gps_valid_seconds = 5;
	if (menu_active)
		redraw();		/* in case a GPS value is shown */
}

/* ---- Aisin Seiki binary blocks */

/* packed BCD (or nibbles) at p into two bytes each at dst */
static void unpack(uint8_t n)
{
	while (n--) {
		*dst++ = *p >> 4;
		*dst++ = *p++ & 0x0F;
	}
}

static void gps_process_aisin_seiki_CACA(void)
{
	/* [0] validity: 3 2D fix, 4 3D fix (0x10: a change happened) */
	a = gps_sentence[0] & ~0x10;
	if (a < 3 || a >= 5)
		return;
	/* [1] latitude, [5] longitude: 1/256", MSByte first */
	gps_latlon(gps_sentence + 1, cfg_gps_latitude);
	gps_latlon(gps_sentence + 5, cfg_gps_longitude);
	/* [13] heading 360 / 1024 degrees */
	num = (uint16_t)(gps_sentence[13] << 8 | gps_sentence[14]) * 45u;
	gps_course = (num >> 8) | (num & 0x80 ? 0x100 : 0);
	/* [16] ground speed 1/4 m/s: knots = x * 31 / 64 */
	num = gps_sentence[16] << 8 | gps_sentence[17];
	acc = (uint32_t)num * 31;
	gps_knots = acc >> 6;
	gps_speed = quarter_ms_to_kmh(num);
	/* [22] YYMMDD HHMMSS packed BCD */
	p = gps_sentence + 22;
	dst = gps_date;
	unpack(3);
	dst = gps_utc;
	unpack(3);
	/* [31] satellites used: bytes 5..8 as hex digits */
	p = gps_sentence + 31 + 4;
	dst = gps_status;
	unpack(4);
	gps_information_has_been_updated();
}

/* e: index in gps_history after a 0x0D; the block CA CA [40] cksum 0D
 * ends there.  cksum: the complement of the 8-bit sum of CA CA and the
 * 40 bytes. */
void gps_process_aisin_seiki(uint8_t end)
{
	l = end - 44;
	if (gps_history[l++] != 0xCA || gps_history[l++] != 0xCA)
		return;
	c = 0xCA + 0xCA;
	for (i = 0; i < 40; i++) {
		a = gps_history[l++];
		gps_sentence[i] = a;
		c += a;
	}
	if ((uint8_t)(gps_history[l] + c) == 0)
		gps_process_aisin_seiki_CACA();
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
