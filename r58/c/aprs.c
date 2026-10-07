/*
 * MPRS receive and APRS sending in C, in ROM bank 2 (Phase 4,
 * notes/hybrid-plan.md).  Replaces the bank-1 assembler from
 * handle_mprs_packets to stuffed_8bits, the APRS symbol tables and
 * packet_callsign_unpack / mprs_degmin_pack (the assembler originals
 * are in git tag asm-final).  Called directly by c/fsk.c (a 4x packet,
 * the report when cfg_report_type is set) and c/gps.c
 * (gps_own_locator).
 *
 * Positions are signed hundredths of a minute, the locator and the
 * distance plain integer arithmetic (since 2026-10-01; before, the C
 * followed the assembler's 24-bit arithmetic bit for bit, garbage of an
 * out-of-range packet included).  A packet with an out-of-range position
 * is taken as one without a position.  distance_bearing holds digits as
 * values 0..9, as the display code expects.
 *
 * The assembler routines called here do not preserve IX: no stack frame
 * in a function that calls them, state is static.  mprs_degmin_pack,
 * position_from_packed and mprs_qrb call no firmware assembler (C and the
 * SDCC library only) and may have one: SDCC keeps parameters and 32-bit
 * temporaries there.  Mainline only.
 */
#pragma bank 2

#include "r58.h"

extern uint8_t mprs_packed_packet[12], distance_bearing[8],
	mbus_mprs_buffer[64], my_coord_tmp_6bytes[6], gps_latlon_tmp[6],
	aprs_packet_out[124], aprs_bits_out[189], cfg_gps_locator[8],
	cfg_ax25_digi_other[8];
extern uint8_t mprs_qrb_dir_bits, packet_rssi, cfg_mbus_mprs,
	cfg_gps_upload, cfg_remote_dpy_secs, cfg_ax25_digi0, cfg_ax25_digi1,
	cfg_ax25_digi2, cfg_ax25_digi3, cfg_ax25_padbits, cfg_mic_e_message,
	cfg_mic_e_dest_ssid;
extern const uint8_t tab_ax25_digi[];
extern const uint8_t AX25_DIGI_OTHER_IDX[];	/* an equate: its "address" */

/* firmware routines (assembler) */
extern void mute_fsk_at_mprs_end_maybe(void);
extern void emit_ax25_packet(const uint8_t *bits);	/* HL, fixed ROM */
/* r58.s shims */
extern uint16_t aprs_crc(uint8_t len, const uint8_t *p);	/* calc_ax25_crc: A | C << 8 */
extern void gps_upload_start(const uint8_t *msg);	/* gps_upload_ptr, '$' out */

/* primary symbols: 15 by MPRS symbol, then 16 by SSID (symbol 15) */
static const uint8_t symbols[31] = {
	'p', '>', 'v', 's', '-', '+', 'r', 'c', '0', '1', '2', '3', '4', '5', '6',
	'/', 'a', 'U', 'f', 'b', 'Y', 'X', 0x27, 's', '>', '<', 'O', 'j', 'R', 'k', 'v',
};
#define BY_SSID	15

/* every reader (out_string, mbus_mprs_out_address_kiss,
 * pack_aprs_report_packet_call) stops at the first EOS, so one is enough */
static const uint8_t dst_aprs[] = { 'A', 'P', 'R', 'S', EOS };
static const uint8_t dst_relay[] = { 'R', 'E', 'L', 'A', 'Y', EOS };
static const uint8_t dst_wide[] = { 'W', 'I', 'D', 'E', EOS };
static const uint8_t dst_mprs[] = { 'M', 'P', 'R', 'S', EOS };

/* metres per minute of longitude by latitude degree */
static const uint16_t minutes_to_meters[90] = {
	1852, 1852, 1851, 1849, 1847, 1845, 1842, 1838, 1834, 1829,
	1824, 1818, 1812, 1805, 1797, 1789, 1780, 1771, 1761, 1751,
	1740, 1729, 1717, 1705, 1692, 1678, 1665, 1650, 1635, 1620,
	1604, 1587, 1571, 1553, 1535, 1517, 1498, 1479, 1459, 1439,
	1419, 1398, 1376, 1354, 1332, 1310, 1287, 1263, 1239, 1215,
	1190, 1166, 1140, 1115, 1089, 1062, 1036, 1009, 981, 954,
	926, 898, 869, 841, 812, 783, 753, 724, 694, 664,
	633, 603, 572, 541, 510, 479, 448, 417, 385, 353,
	322, 290, 258, 226, 194, 161, 129, 97, 65, 32,
};

static const uint8_t mic_e_DC_tab[10] = { ' ', '*', '4', '>', 'H', 'R', 0x5C, 'f', 'p', 'z' };

static uint8_t a, b, c, i, n, ones, last, h, l;
static uint16_t w;
static const uint8_t *s;
static uint8_t *d;

/* ---- small helpers */

/* x (below 100) as two digits at d */
static void two_digits(uint8_t x)
{
	*d++ = '0' + x / 10;
	*d++ = '0' + x % 10;
}

/* ddmm.hh of a packed latitude at s (flag and symbol bits masked) */
static void mprs_lat_format(void)
{
	two_digits(s[0] & 0x7F);
	two_digits(s[1] & 0x3F);
	*d++ = '.';
	two_digits(s[2] & 0x7F);
}

/* dddmm.hh of a packed longitude at s */
static void mprs_lon_format(void)
{
	*d++ = s[0] >= 100 ? '1' : '0';
	two_digits(s[0] % 100);
	two_digits(s[1] & 0x3F);
	*d++ = '.';
	two_digits(s[2] & 0x7F);
}

static void out_string(const uint8_t *p)
{
	while (*p != EOS)
		mbus_putchar(*p++);
}

static uint8_t ascify(uint8_t x)
{
	if (x >= 16)
		return x;
	return x < 10 ? x + '0' : x + 'A' - 10;
}

static void putchar_hex_nybble(uint8_t x)
{
	mbus_putchar(ascify(x & 0x0F));
}

static void crlf(void)
{
	mbus_putchar(0x0D);
	mbus_putchar(0x0A);
}

/* ---- callsigns and positions of the packet */

/* 6 bytes of packed callsign at mprs_packed_packet into 8 characters */
static void packet_callsign_unpack(void)
{
	s = mprs_packed_packet;
	d = remote_display_buffer;
	for (i = 0; i < 2; i++, s += 3) {
		*d++ = (s[0] & 0x3F) + ' ';
		*d++ = ((s[0] >> 6 | s[1] << 2) & 0x3F) + ' ';
		*d++ = (((s[1] & 0xF0) | (s[2] & 0x03)) >> 4 | (s[2] & 0x03) << 4) + ' ';
		*d++ = (s[2] >> 2 & 0x3F) + ' ';
	}
}

/* deg[3] min[2] decimal_min[2] unpacked BCD and the hemisphere at s into
 * 3 bytes at d, bit 7 of the last for 'S' or 'W' (v3_Z only 'W', so
 * southern latitudes went out as northern); shared with c/fsk.c and
 * gps_own_locator (C-only leaf, calls no asm: SDCC gives it a small frame
 * to spill s/d, but that is harmless since it never calls into asm) */
void mprs_degmin_pack(const uint8_t *s, uint8_t *d)
{
	d[0] = (s[0] ? 100 : 0) + s[1] * 10 + s[2];
	d[1] = s[3] * 10 + s[4];
	d[2] = s[5] * 10 + s[6];
	if (s[7] == 'S' || s[7] == 'W')
		d[2] |= 0x80;
}

/* A packed position (3 bytes latitude, 3 longitude: degrees, minutes,
 * hundredths | 0x80 for S or W; the bits above are flags and symbol bits)
 * at s into lat, lon: signed hundredths of a minute.  0 when out of range
 * (latitude 90 degrees or more, longitude 180 or more, minutes 60 or
 * more, hundredths 100 or more): such a packet has no usable position. */
static int32_t lat, lon;

static uint8_t position_from_packed(void)
{
	a = s[0] & 0x7F;
	b = s[1] & 0x3F;
	c = s[2] & 0x7F;
	if (a >= 90 || b >= 60 || c >= 100)
		return 0;
	lat = (int32_t)((uint16_t)a * 60 + b) * 100 + c;
	if (s[2] & 0x80)
		lat = -lat;
	a = s[3];
	b = s[4] & 0x3F;
	c = s[5] & 0x7F;
	if (a >= 180 || b >= 60 || c >= 100)
		return 0;
	lon = (int32_t)((uint16_t)a * 60 + b) * 100 + c;
	if (s[5] & 0x80)
		lon = -lon;
	return 1;
}

/* the 8-character Maidenhead locator of lat, lon at d: fields of 20 x 10
 * degrees, squares of 2 x 1, subsquares of 5' x 2.5', and their tenths
 * (30" x 15"); counted from 180 W, 90 S, so a point on an edge is in the
 * upper cell (the v3_Z code mirrored the northern/eastern locator for
 * S/W, one low on an edge: fixed 2026-09-30/10-01) */
static uint32_t ul;
static uint16_t uw, deg;

static void locator_of_position(void)
{
	ul = lon + 180L * 6000;			/* 0 .. 2159999 */
	deg = ul / 6000;			/* 0 .. 359 */
	uw = (uint16_t)ul - deg * 6000;		/* hundredths of a minute */
	d[0] = 'A' + deg / 20;
	d[2] = '0' + deg % 20 / 2;
	if (deg & 1)
		uw += 6000;			/* the odd degree of a square */
	d[4] = 'A' + uw / 500;
	d[6] = '0' + uw % 500 / 50;
	ul = lat + 90L * 6000;			/* 0 .. 1079999 */
	deg = ul / 6000;			/* 0 .. 179 */
	uw = (uint16_t)ul - deg * 6000;
	d[1] = 'A' + deg / 10;
	d[3] = '0' + deg % 10;
	d[5] = 'A' + uw / 250;
	d[7] = '0' + uw % 250 / 25;
}

/* the own position (cfg_gps_latitude / longitude digits) into lat, lon;
 * 0 if out of range */
static uint8_t own_position(void)
{
	mprs_degmin_pack(cfg_gps_latitude, gps_latlon_tmp);
	mprs_degmin_pack(cfg_gps_longitude, gps_latlon_tmp + 3);
	s = gps_latlon_tmp;
	return position_from_packed();
}

/* the own locator into cfg_gps_locator (left as it was when the GPS
 * position is out of range) */
void gps_own_locator(void)
{
	if (!own_position())
		return;
	d = cfg_gps_locator;
	locator_of_position();
}

/* ---- distance and bearing (flat model) */

/* distance_bearing: 3 significant digits (values 0..9), '.', the unit
 * digit, ' ', N/S/E/W and EOS; w the digits, b the trailing zeroes */
static void mprs_qrb_present(void)
{
	d = distance_bearing;
	if (!b)
		*d++ = '.';			/* .999 km */
	a = w / 100;
	w %= 100;
	*d++ = a;
	if (!--b)
		*d++ = '.';			/* 9.99 */
	*d++ = (uint8_t)w / 10;
	a = (uint8_t)w % 10;
	if (!--b)
		*d++ = '.';			/* 99.9 */
	*d++ = a;
	*d++ = --b ? 0 : '.';			/* 999. or 9990 */
	*d++ = ' ';
	if (mprs_qrb_dir_bits & 4)
		d[0] = mprs_qrb_dir_bits & 2 ? 'E' : 'W';
	else
		d[0] = mprs_qrb_dir_bits & 1 ? 'N' : 'S';
	d[1] = EOS;
}

/* Distance and main direction from the own position to his_lat, his_lon:
 * north-south 1852 m a minute, east-west by the own latitude's metres per
 * minute, distance = major + minor * 83 / 256 (< 5 % error, 7 % at 45
 * degrees); nothing beyond 999 km, or without an own position. */
static int32_t his_lat, his_lon, dl;
static uint32_t north, east;

static void mprs_qrb(void)
{
	if (!own_position())
		return;
	mprs_qrb_dir_bits = 0;

	dl = his_lat - lat;
	if (dl > 0)
		mprs_qrb_dir_bits |= 1;		/* he/she is north from me */
	else
		dl = -dl;
	north = (uint32_t)dl * 1852 / 100;

	dl = his_lon - lon;			/* into -180 .. +180 degrees */
	if (dl > 180L * 6000)
		dl -= 360L * 6000;
	else if (dl <= -180L * 6000)
		dl += 360L * 6000;
	if (dl > 0)
		mprs_qrb_dir_bits |= 2;		/* he/she is east from me */
	else
		dl = -dl;
	a = (lat < 0 ? -lat : lat) / 6000;	/* own latitude degrees */
	east = (uint32_t)dl * minutes_to_meters[a] / 100;

	if (east < north) {
		ul = north;
		dl = east;
	} else {
		ul = east;
		dl = north;
		mprs_qrb_dir_bits |= 4;		/* the major axis is E/W */
	}
	if (ul >= 1000000)
		return;				/* too far */
	ul += (uint32_t)dl * 83 >> 8;

	/* 3 significant digits and b trailing zeroes (metres) */
	if (ul < 1000) {
		b = 0;
		w = ul;
	} else if (ul < 10000) {
		b = 1;
		w = ul / 10;
	} else if (ul < 100000) {
		b = 2;
		w = ul / 100;
	} else if (ul < 1000000) {
		b = 3;
		w = ul / 1000;
	} else {
		return;				/* too far */
	}
	mprs_qrb_present();
}

/* ---- MBUS output of a received position */

static void symbol_nibble(void)
{
	a = (mprs_packed_packet[7] & 0xC0) >> 4 | (mprs_packed_packet[10] & 0xC0) >> 6;
}

/* the address of s: 6 characters shifted up and the SSID byte, last-bit
 * at, KISS-escaped */
static void putchar_slipped(uint8_t x)
{
	if (x == 192) {
		mbus_putchar(219);
		mbus_putchar(220);
	} else if (x == 219) {
		mbus_putchar(219);
		mbus_putchar(221);
	} else {
		mbus_putchar(x);
	}
}

static void mbus_mprs_out_address_kiss(void)
{
	for (i = 0; i < 6; i++) {
		c = ' ';
		if (*s != EOS && *s != '-')
			c = *s++;
		putchar_slipped(c << 1);
	}
	c = 0;
	if (s[0] == '-') {
		c = s[1] - '0';
		if (s[2] != EOS)
			c = s[2] - ('0' - 10);
	}
	putchar_slipped(((c << 1) & 0x1E) | 0x60 | last);
}

/* lat, N/S, sep, lon, E/W of mprs_packed_packet at d (which it advances) */
static void latlon_text(uint8_t sep)
{
	s = mprs_packed_packet + 6;
	mprs_lat_format();
	*d++ = s[2] & 0x80 ? 'S' : 'N';
	*d++ = sep;
	s = mprs_packed_packet + 9;
	mprs_lon_format();
	*d++ = s[2] & 0x80 ? 'W' : 'E';
}

static void mbus_mprs_out_logger(void)
{
	/* 120000 6103.52N 02806.18E KP41BB 0 80 OH5NXO-15 */
	d = mbus_mprs_buffer;
	*d++ = ' ';
	latlon_text(' ');
	*d++ = ' ';
	*d = EOS;
	/* six digits: 000000 before the first fix (bss); v3_Z printed up to
	 * EOS, and before a fix went on through the RAM after it (user,
	 * 2026-10-01) */
	for (i = 0; i < 6; i++)
		mbus_putchar(ascify(gps_utc[i]));
	out_string(mbus_mprs_buffer);
	out_string(locator_display_buffer);
	mbus_putchar(' ');
	symbol_nibble();
	putchar_hex_nybble(a);
	mbus_putchar(' ');
	putchar_hex_nybble(packet_rssi >> 4);
	putchar_hex_nybble(packet_rssi);
	mbus_putchar(' ');
	out_string(remote_display_buffer);
	crlf();
}

/* OH5NXO-1>APRS,RELAY,WIDE:!6103.52N/02806.18E> and the others */
static void mbus_mprs_call_latlon(void)
{
	if (cfg_mbus_mprs == 4) {
		mbus_mprs_out_logger();
		return;
	}
	d = mbus_mprs_buffer;
	*d++ = '!';
	latlon_text('/');			/* primary symbol table */
	symbol_nibble();
	*d++ = a == 15 ? symbols[BY_SSID + (mprs_packed_packet[4] >> 4)] : symbols[a];
	*d = EOS;

	switch (cfg_mbus_mprs) {
	case 1:					/* TNC emulation */
		out_string(remote_display_buffer);
		mbus_putchar('>');
		out_string(dst_aprs);
		mbus_putchar(',');
		out_string(dst_relay);
		mbus_putchar(',');
		out_string(dst_wide);
		mbus_putchar(':');
		out_string(mbus_mprs_buffer);
		crlf();
		break;
	case 2:					/* KISS */
		mbus_putchar(192);
		mbus_putchar(0x00);		/* data from TNC 0 */
		s = dst_aprs;
		last = 0;
		mbus_mprs_out_address_kiss();
		s = remote_display_buffer;
		last = 1;
		mbus_mprs_out_address_kiss();
		mbus_putchar(0x03);		/* control */
		mbus_putchar(0xF0);		/* PID */
		out_string(mbus_mprs_buffer);
		mbus_putchar(192);
		break;
	case 3:					/* third party, CONVERS */
		mbus_putchar('}');
		out_string(remote_display_buffer);
		mbus_putchar('>');
		out_string(dst_aprs);
		mbus_putchar(',');
		out_string(dst_mprs);
		mbus_putchar('*');
		mbus_putchar(':');
		out_string(mbus_mprs_buffer);
		mbus_putchar(0x0D);
		break;
	}
}

/* $GPWPL,6103.52,N,02806.18,E,OH5NXO-15*XX or $PMGNWPL,...,,,call*XX to
 * the GPS (the waypoint name is not tidied) */
static const uint8_t str_gpwpl[] = "GPWPL,";
static const uint8_t str_pmgnwpl[] = "PMGNWPL,";

static void gps_mprs_call_latlon(void)
{
	d = mbus_mprs_buffer;
	for (s = cfg_gps_upload == 2 ? str_pmgnwpl : str_gpwpl; (*d++ = *s++) != ','; )
		;
	s = mprs_packed_packet + 6;
	mprs_lat_format();
	*d++ = ',';
	*d++ = s[2] & 0x80 ? 'S' : 'N';
	*d++ = ',';
	s = mprs_packed_packet + 9;
	mprs_lon_format();
	*d++ = ',';
	*d++ = s[2] & 0x80 ? 'W' : 'E';
	*d++ = ',';
	if (cfg_gps_upload == 2) {
		*d++ = ',';			/* altitude and its unit */
		*d++ = ',';
	}
	for (s = remote_display_buffer; (*d = *s++) != EOS; d++)
		;
	*d++ = '*';
	c = 0;
	for (s = mbus_mprs_buffer; *s != '*'; s++)
		c ^= *s;
	*d++ = ascify(c >> 4);
	*d++ = ascify(c & 0x0F);
	*d++ = 0x0D;
	*d++ = 0x0A;
	*d = 0x00;
	gps_upload_start(mbus_mprs_buffer);
}

/* ---- receive */

/* start: packet_good, a 4x packet in fsk_history (nibbles) */
void handle_mprs_packets(uint8_t start)
{
	fsk_at = start + 2;				/* tag, minor digit ignored */
	for (i = 0; i < 12; i++)
		mprs_packed_packet[i] = nibbles();
	mute_fsk_at_mprs_end_maybe();

	packet_callsign_unpack();
	for (i = 6; i <= 10; i++)
		remote_display_buffer[i] = EOS;	/* 6 valid, 10 shown, barrier */
	/* the call ends at the first blank */
	for (d = remote_display_buffer; *d != EOS; d++)
		if (*d == ' ') {
			*d = EOS;
			break;
		}
	a = mprs_packed_packet[4] >> 4;		/* -SSID */
	if (a) {
		*d++ = '-';
		if (a >= 10) {
			*d++ = '1';
			a -= 10;
		}
		*d++ = a + '0';
		*d = EOS;
	}

	s = mprs_packed_packet + 6;
	if (!(mprs_packed_packet[6] & 0x80) && position_from_packed()) {	/* a position */
		his_lat = lat;
		his_lon = lon;
		d = locator_display_buffer;
		locator_of_position();
		locator_display_buffer[6] = EOS;
		locator_display_buffer[7] = EOS;
		if (cfg_mbus_mprs)
			mbus_mprs_call_latlon();
		if (cfg_gps_upload)
			gps_mprs_call_latlon();
		locator_dpyed = cfg_remote_dpy_secs;
		mprs_qrb();
	}
	display_buffer_time = cfg_remote_dpy_secs;
	if (display_buffer_time)
		redraw();
}

/* ---- send */

/* an address from s: 6 characters (to upper case) shifted up, -SSID */
static void pack_aprs_report_packet_call(void)
{
	for (i = 0; i < 6; i++) {
		c = ' ';
		if (*s != EOS && *s != '-') {
			c = ascify(*s++);
			if (c >= 'a')
				c &= ~0x20;
		}
		*d++ = c << 1;
	}
	c = 0;
	if (*s == '-') {
		a = *++s;
		c = a >= '0' ? a - '0' : a;	/* digits or values */
		if (c == 1 && (a = *++s) != EOS)
			c = (a >= '0' ? a - '0' : a) + 10;
	}
	*d++ = ((c << 1) & 0x1E) | 0x60;
}

static void pack_aprs_report_packet_mycall(void)
{
	s = cfg_mprs_callsign;
	for (i = 0; i < 6; i++) {
		c = ' ';
		if (*s != EOS)
			c = ascify(*s++);
		*d++ = c << 1;
	}
	*d++ = ((cfg_mprs_ssid << 1) & 0x1E) | 0x60;
}

static void pack_aprs_report_digi_maybe(uint8_t digi)
{
	if (!digi)
		return;
	if (digi >= (uint8_t)(uint16_t)AX25_DIGI_OTHER_IDX)
		s = cfg_ax25_digi_other;
	else
		s = tab_ax25_digi + 1 + (uint8_t)(digi * 8);
	pack_aprs_report_packet_call();
}

static uint16_t gps_course_1_to_360_degrees(void)
{
	return gps_course ? gps_course : 360;
}

/* w as three digits at d, 999 at most */
static void HL_to_3_ascii(void)
{
	if (w >= 1000) {
		*d++ = '9';
		*d++ = '9';
		*d++ = '9';
		return;
	}
	*d++ = '0' + w / 100;
	a = w % 100;
	*d++ = '0' + a / 10;
	*d++ = '0' + a % 10;
}

/* !6103.52N/02806.18E> [ccc/sss] */
static void encode_aprs_report_packet_normal(void)
{
	s = dst_aprs;
	pack_aprs_report_packet_call();
	pack_aprs_report_packet_mycall();
	pack_aprs_report_digi_maybe(cfg_ax25_digi0);
	pack_aprs_report_digi_maybe(cfg_ax25_digi1);
	pack_aprs_report_digi_maybe(cfg_ax25_digi2);
	pack_aprs_report_digi_maybe(cfg_ax25_digi3);
	d[-1] |= 1;				/* last address */
	*d++ = 0x03;				/* control */
	*d++ = 0xF0;				/* PID */
	*d++ = '!';
	s = cfg_gps_latitude;
	for (i = 1; i <= 6; i++) {
		if (i == 5)
			*d++ = '.';
		*d++ = s[i] + '0';
	}
	*d++ = s[7] == 'S' ? 'S' : 'N';
	*d++ = '/';
	s = cfg_gps_longitude;
	for (i = 0; i <= 6; i++) {
		if (i == 5)
			*d++ = '.';
		*d++ = s[i] + '0';
	}
	*d++ = s[7] == 'W' ? 'W' : 'E';
	*d++ = cfg_mprs_symbol == 15 ? symbols[BY_SSID + cfg_mprs_ssid] : symbols[cfg_mprs_symbol];
	if (gps_knots >= 2) {			/* course/speed when moving */
		w = gps_course_1_to_360_degrees();
		HL_to_3_ascii();
		*d++ = '/';
		w = gps_knots;
		HL_to_3_ascii();
	}
}

/* tens and ones digits at s as a value, 99 at most */
static uint8_t mic_e_binary_dmh(void)
{
	a = s[0] * 10 + s[1];
	s += 2;
	return a < 100 ? a : 99;
}

static void encode_aprs_report_packet_mic_e(void)
{
	/* message, N, +100 and W bits, left aligned in c */
	h = cfg_mic_e_message < 8 ? 'P' : 'A';	/* standard or custom message */
	l = 3;					/* custom characters in 3 slots */
	c = ((cfg_mic_e_message & 7) ^ 7) << 5;
	if (cfg_gps_latitude[7] != 'S')
		c |= 0x10;			/* north */
	if (cfg_gps_longitude[7] == 'W')
		c |= 0x04;			/* west */
	if (cfg_gps_longitude[0] || !cfg_gps_longitude[1])
		c |= 0x08;			/* 100 or more, or below 10 degrees */

	/* destination: latitude digits with those bits */
	s = cfg_gps_latitude + 1;
	for (i = 0; i < 6; i++) {
		a = c & 0x80 ? h : '0';
		c <<= 1;
		*d++ = (a + *s++) << 1;
		if (!--l)
			h = 'P';
	}
	*d++ = ((cfg_mic_e_dest_ssid << 1) & 0x1E) | 0x60;
	pack_aprs_report_packet_mycall();
	d[-1] |= 1;				/* last address, no digipeaters */
	*d++ = 0x03;
	*d++ = 0xF0;
	*d++ = 0x60;				/* MIC-E, valid GPS data */

	/* longitude degrees */
	b = cfg_gps_longitude[0];
	s = cfg_gps_longitude + 1;
	a = mic_e_binary_dmh();
	if (b == 1)
		a += 100;
	if (a < 10)
		a += 190;
	else if (a >= 100 && a < 110)
		a += 80;
	if (a >= 100)
		a -= 100;
	*d++ = a + 28;
	/* minutes */
	a = mic_e_binary_dmh();
	if (a < 10)
		a += 60;
	*d++ = a + 28;
	/* hundredths */
	*d++ = mic_e_binary_dmh() + 28;

	/* speed: hundreds and tens of knots */
	w = gps_knots;
	a = 'l';				/* 0-99: 'l' ... 'u' */
	if (w >= 100) {
		w -= 100;
		a = 'v';			/* 100-199: 'v' ... DEL */
		if (w >= 100) {
			w -= 100;
			a = '0';		/* 200-299: '0' ... '9' */
			if (w >= 100)
				a = ':', w = 0;	/* clamp at 300 */
		}
	}
	*d++ = a + (uint8_t)w / 10;
	ones = (uint8_t)w % 10;
	/* ones of knots and hundreds of degrees; tens and ones of degrees */
	w = gps_knots ? gps_course_1_to_360_degrees() : 0;
	a = mic_e_DC_tab[ones];
	a += w / 100;
	*d++ = a;
	*d++ = (uint8_t)(w % 100) + 28;

	*d++ = cfg_mprs_symbol < 15 ? symbols[cfg_mprs_symbol] : symbols[BY_SSID + (cfg_mprs_ssid & 0x0F)];
	*d++ = '/';				/* symbol table */
}

/* aprs_bits_out: bits LSB first into bytes, 0x80 marks the empty byte */
static void stuffed_8bits(void)
{
	*d++ = b;
	b = 0x80;
}

/* shift a 0 or 1 (top, 0x00 or 0x80) into b, LSB first, stuffing on a 1 */
static void put_bit(uint8_t top)
{
	c = b & 1;
	b = b >> 1 | top;
	if (c)
		stuffed_8bits();
}

static void flag(void)
{
	for (a = 0x7E, i = 0; i < 8; i++, a >>= 1)
		put_bit(a & 1 ? 0x80 : 0);
}

void send_aprs_report_packet(void)
{
	d = aprs_packet_out;
	if (cfg_report_type == 2)
		encode_aprs_report_packet_mic_e();
	else
		encode_aprs_report_packet_normal();
	n = d - aprs_packet_out;
	w = aprs_crc(n, aprs_packet_out);
	d[0] = ~(uint8_t)w;			/* note the byte order */
	d[1] = ~(uint8_t)(w >> 8);

	d = aprs_bits_out;
	b = 0x80;
	/* preamble: zero bits (36 = 30 ms by default), the flag */
	for (a = cfg_ax25_padbits ? cfg_ax25_padbits : 36; a; a--)
		put_bit(0);
	flag();
	/* the frame and its CRC, a zero after five ones */
	ones = 0;
	for (s = aprs_packet_out, n += 2; n; n--, s++) {
		for (h = *s, l = 0; l < 8; l++, h >>= 1) {
			if (h & 1) {
				put_bit(0x80);
				if (++ones < 5)
					continue;
			}
			ones = 0;
			put_bit(0);
		}
	}
	flag();
	/* the rest of the last byte, the end marker */
	do {
		c = b & 1;
		b >>= 1;
	} while (!c);
	stuffed_8bits();
	*d = 0x7F;
	emit_ax25_packet(aprs_bits_out);
}
