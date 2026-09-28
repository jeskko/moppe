/*
 * MPRS receive and APRS sending in C, in ROM bank 2 (Phase 4,
 * notes/hybrid-plan.md).  Built with `make C=1`; replaces the bank-1
 * assembler from handle_mprs_packets to stuffed_8bits, the APRS symbol
 * tables and packet_callsign_unpack / mprs_degmin_pack (see the C_MODULES
 * blocks in r58.s).  Called directly by c/fsk.c (a 4x packet, the report
 * when cfg_report_type is set) and c/gps.c (gps_own_locator).
 *
 * Arithmetic follows the assembler exactly, test_aprs_diff.py compares
 * them: 24-bit values (AHL) wrap at 24 bits (mod24), digits are stored as
 * values 0..9 in distance_bearing, the out-of-range inputs of a packet go
 * through the same loops.  Deliberate difference: the metres-per-minute
 * table is indexed by the own latitude degrees; the assembler read past its
 * 90 entries for invalid latitudes (90 and up), C uses the 89 degree entry.
 *
 * Kept v3_Z behaviour: only 'W' makes the own position negative in
 * gps_own_locator (southern latitudes read as northern; the radios are
 * used in Finland); the logger output prints gps_utc up to EOS.
 *
 * The assembler routines called here do not preserve IX: no stack frame
 * in a function that calls them, state is static.  (centiminutes_to_meters
 * has one: SDCC spills a conversion there; it calls only C and the SDCC
 * library, which keep IX.)  Mainline only.
 */
#pragma bank 2

#include <stdint.h>

#define EOS		0xFF
#define SIZE_STR	8

extern uint8_t mprs_packed_packet[12], remote_display_buffer[16],
	locator_display_buffer[8], distance_bearing[8], mbus_mprs_buffer[64],
	my_coord_tmp_6bytes[6], gps_latlon_tmp[6], aprs_packet_out[124],
	aprs_bits_out[189], fsk_history[256], gps_utc[8], cfg_gps_latitude[8],
	cfg_gps_longitude[8], cfg_gps_locator[8], cfg_mprs_callsign[8],
	cfg_ax25_digi_other[8];
extern uint8_t mprs_qrb_dir_bits, packet_rssi, cfg_mbus_mprs, cfg_gps_upload,
	cfg_remote_dpy_secs, locator_dpyed, display_buffer_time, cfg_report_type,
	cfg_mprs_symbol, cfg_mprs_ssid, cfg_ax25_digi0, cfg_ax25_digi1,
	cfg_ax25_digi2, cfg_ax25_digi3, cfg_ax25_padbits, cfg_mic_e_message,
	cfg_mic_e_dest_ssid;
extern uint16_t gps_knots, gps_course;
extern const uint8_t tab_ax25_digi[];
extern const uint8_t AX25_DIGI_OTHER_IDX[];	/* an equate: its "address" */

/* firmware routines (assembler) */
extern void redraw(void), mute_fsk_at_mprs_end_maybe(void);
extern void emit_ax25_packet(const uint8_t *bits);	/* HL, fixed ROM */
/* r58.s shims */
extern void fsk_putchar(uint8_t c);			/* MBUS putchar (C) */
extern uint16_t aprs_crc(uint8_t len, const uint8_t *p);	/* calc_ax25_crc: A | C << 8 */
extern void gps_upload_start(const uint8_t *msg);	/* gps_upload_ptr, '$' out */

#define MOD24(x)	((x) & 0xFFFFFFUL)

/* primary symbols: 15 by MPRS symbol, then 16 by SSID (symbol 15) */
static const uint8_t symbols[31] = {
	'p', '>', 'v', 's', '-', '+', 'r', 'c', '0', '1', '2', '3', '4', '5', '6',
	'/', 'a', 'U', 'f', 'b', 'Y', 'X', 0x27, 's', '>', '<', 'O', 'j', 'R', 'k', 'v',
};
#define BY_SSID	15

static const uint8_t dst_aprs[SIZE_STR] = { 'A', 'P', 'R', 'S', EOS, EOS, EOS, EOS };
static const uint8_t dst_relay[SIZE_STR] = { 'R', 'E', 'L', 'A', 'Y', EOS, EOS, EOS };
static const uint8_t dst_wide[SIZE_STR] = { 'W', 'I', 'D', 'E', EOS, EOS, EOS, EOS };
static const uint8_t dst_mprs[SIZE_STR] = { 'M', 'P', 'R', 'S', EOS, EOS, EOS, EOS };

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

static uint8_t a, b, c, i, n, at, ones, last, h, l, rem;
static uint16_t w, q;
static uint32_t v, t, his, north, east;
static uint32_t *major, *minor;
static const uint8_t *s;
static uint8_t *d;

/* ---- small helpers */

/* a as two digits: tens (maybe above '9' when a >= 100), ones */
static void dekavalue_format(void)
{
	c = '0' - 1;
	do {
		c++;
		b = a < 10;
		a -= 10;
	} while (!b);
	*d++ = c;
	*d++ = a + 10 + '0';
}

/* ddmm.hh of a packed latitude at s (reserved and symbol bits masked) */
static void mprs_lat_format(void)
{
	a = s[0] & 0x7F;
	dekavalue_format();
	a = s[1] & 0x3F;
	dekavalue_format();
	*d++ = '.';
	a = s[2] & 0x7F;
	dekavalue_format();
}

/* dddmm.hh of a packed longitude at s */
static void mprs_lon_format(void)
{
	a = s[0];
	if (a >= 100) {
		a -= 100;
		*d++ = '1';
	} else {
		*d++ = '0';
	}
	dekavalue_format();
	a = s[1] & 0x3F;
	dekavalue_format();
	*d++ = '.';
	a = s[2] & 0x7F;
	dekavalue_format();
}

static void out_string(const uint8_t *p)
{
	while (*p != EOS)
		fsk_putchar(*p++);
}

static uint8_t ascify(uint8_t x)
{
	if (x >= 16)
		return x;
	return x < 10 ? x + '0' : x + 'A' - 10;
}

static void putchar_hex_nybble(uint8_t x)
{
	fsk_putchar(ascify(x & 0x0F));
}

static void crlf(void)
{
	fsk_putchar(0x0D);
	fsk_putchar(0x0A);
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
 * 3 bytes at d (only 'W' is negative) */
static void mprs_degmin_pack(void)
{
	d[0] = (s[0] ? 100 : 0) + s[1] * 10 + s[2];
	d[1] = s[3] * 10 + s[4];
	d[2] = s[5] * 10 + s[6];
	if (s[7] == 'W')
		d[2] |= 0x80;
}

/* the 8-character locator of the packed lat/lon at s into d */
static void packed_latlon_to_locator(void)
{
	/* latitude: field letter from 'J', square digit */
	a = s[0] & 0x7F;
	c = 'J' - 1;
	do {
		c++;
		b = a < 10;
		a -= 10;
	} while (!b);
	d[1] = c;
	d[3] = a + 10 + '0';
	/* subsquare: half minutes (one more above .50; the sign bit counts
	 * as above) */
	a = (s[1] << 1 | (50 < s[2])) & 0x7F;
	c = 'A' - 1;
	do {
		c++;
		b = a < 5;
		a -= 5;
	} while (!b);
	d[5] = c;
	c = (a + 5) << 1;
	a = s[2];
	if (a >= 50)
		a -= 50;
	if (a >= 25)
		c++;
	d[7] = c + '0';
	if (s[2] & 0x80) {			/* south */
		d[1] = 'I' - d[1] + 'J';
		d[3] = '9' - d[3] + '0';
		d[5] = 'L' - d[5] + 'M';
		d[7] = '9' - d[7] + '0';
	}
	/* longitude: 20 degrees per letter, 2 per digit */
	a = s[3];
	c = 'J' - 1;
	do {
		c++;
		b = a < 20;
		a -= 20;
	} while (!b);
	a += 20;
	b = a & 1;				/* odd degree */
	d[0] = c;
	d[2] = (a >> 1) + '0';
	a = s[4] & 0x3F;
	if (b)
		a += 60;
	c = 'A' - 1;
	do {
		c++;
		b = a < 5;
		a -= 5;
	} while (!b);
	d[4] = c;
	d[6] = ((uint8_t)((a + 5) << 1) | (50 < s[5])) + '0';
	if (s[5] & 0x80) {			/* west */
		d[0] = 'I' - d[0] + 'J';
		d[2] = '9' - d[2] + '0';
		d[4] = 'L' - d[4] + 'M';
		d[6] = '9' - d[6] + '0';
	}
}

/* the own locator from cfg_gps_latitude / longitude into cfg_gps_locator */
void gps_own_locator(void)
{
	s = cfg_gps_latitude;		/* longitude follows at +8 */
	d = gps_latlon_tmp;
	for (n = 0; n < 2; n++) {
		c = *s++ ? 100 : 0;
		for (i = 0; i < 3; i++, s += 2) {
			*d++ = s[0] * 10 + s[1] + c;
			c = 0;
		}
		if (*s++ == 'W')		/* (not 'S', v3_Z) */
			d[-1] |= 0x80;
	}
	s = gps_latlon_tmp;
	d = cfg_gps_locator;
	packed_latlon_to_locator();
}

/* ---- distance and bearing (flat model) */

/* s: degrees, minutes, hundredths (and sign, symbol bits) -> centiminutes */
static uint32_t degmin_to_centiminutes(void)
{
	w = (uint16_t)(s[0] & 0x7F) * 60 + (s[1] & 0x3F);
	v = w;
	v *= 100;
	return v + (s[2] & 0x7F);
}

static uint32_t from_south_pole(void)
{
	v = degmin_to_centiminutes();
	if (s[2] & 0x80)
		v = MOD24(-v);
	return MOD24(v + 90UL * 60 * 100);
}

static uint32_t from_meridian(void)
{
	v = degmin_to_centiminutes();
	if (s[2] & 0x80)
		v = MOD24(-v);
	return v;
}

/* the assembler's div248, bit for bit: v (AHL) / dv -> 16-bit quotient,
 * remainder in rem; a true division only while A < dv and dv < 128, which
 * the wrapped values of an out-of-range packet break */
static uint16_t quot;
static uint8_t k, cy;

static uint16_t div248_v(uint8_t dv)		/* v / dv */
{
	rem = v >> 16;
	quot = v;
	for (k = 0; k < 16; k++) {
		cy = quot >> 15;
		quot <<= 1;
		rem = rem << 1 | cy;		/* (the carry out of A is lost) */
		if (rem >= dv) {
			rem -= dv;
			quot |= 1;
		}
	}
	return quot;
}

/* 24-bit centiminutes of latitude (v) into metres */
static uint32_t centiminutes_to_1852_meters(void)
{
	q = div248_v(100);			/* full minutes */
	v = rem;				/* hundredths */
	v *= 1852;
	t = div248_v(100);			/* their metres */
	v = q;
	v *= 1852;
	return MOD24(v + t);
}

/* 24-bit centiminutes of longitude (v) into metres, w metres per minute
 * (v3_Z added hundredths * 655 m, and from 256 minutes on garbage) */
static uint32_t centiminutes_to_meters(void)
{
	q = div248_v(100);			/* full minutes */
	t = 0;
	if (rem) {				/* hundredths */
		v = rem;
		v *= w;
		t = div248_v(100);
	}
	v = q;
	v *= w;
	return MOD24(v + t);
}

/* into -180 .. +180 degrees */
static void delta_longitude_fixup(void)
{
	if (!(v & 0x800000)) {
		if (v >= 180UL * 60 * 100)
			v = MOD24(v - 2 * 180UL * 60 * 100);
	} else if (v + 180UL * 60 * 100 < 0x1000000) {	/* below -180 */
		v = MOD24(v + 2 * 180UL * 60 * 100);
	}
}

/* distance_bearing: 3 significant digits (values 0..9), '.', the unit
 * digit, ' ', N/S/E/W and EOS */
static void mprs_qrb_present(void)
{
	d = distance_bearing;
	b++;
	if (!--b)
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

/* 24 bits of t at d */
static void put24(void)
{
	d[0] = t;
	d[1] = t >> 8;
	d[2] = t >> 16;
}

/* major and minor axis of north and east (left in my_coord_tmp_6bytes, the
 * distance over the major one later, as the assembler did) */
static void pick_axes(void)
{
	t = north;
	d = my_coord_tmp_6bytes;
	put24();
	t = east;
	d = my_coord_tmp_6bytes + 3;
	put24();
	t = east;
	t -= north;				/* both below 2^24 */
	if (((uint8_t *)&t)[3]) {		/* borrow: east < north */
		major = &north;
		minor = &east;
	} else {
		major = &east;
		minor = &north;
		mprs_qrb_dir_bits |= 4;			/* the major axis is E/W */
	}
}

static void mprs_qrb(void)
{
	s = cfg_gps_latitude;
	d = my_coord_tmp_6bytes;
	mprs_degmin_pack();
	s = cfg_gps_longitude;
	d = my_coord_tmp_6bytes + 3;
	mprs_degmin_pack();
	mprs_qrb_dir_bits = 0;

	/* north-south */
	s = mprs_packed_packet + 6;
	his = from_south_pole();
	s = my_coord_tmp_6bytes;
	t = from_south_pole();			/* mine */
	if (t < his) {
		v = his - t;
		mprs_qrb_dir_bits |= 1;			/* he/she is north from me */
	} else {
		v = t - his;
	}
	north = centiminutes_to_1852_meters();

	/* east-west */
	s = mprs_packed_packet + 9;
	his = from_meridian();
	s = my_coord_tmp_6bytes + 3;
	v = MOD24(from_meridian() - his);
	delta_longitude_fixup();
	if (v & 0x800000) {
		v = MOD24(-v);
		mprs_qrb_dir_bits |= 2;			/* he/she is east from me */
	}
	w = minutes_to_meters[(my_coord_tmp_6bytes[0] & 0x7F) < 90 ? (my_coord_tmp_6bytes[0] & 0x7F) : 89];
	east = centiminutes_to_meters();

	/* distance = major + minor * 83 / 256 (< 5 % error, 7 % at 45 deg) */
	pick_axes();
	t = *minor;
	t *= 83;
	t >>= 8;
	v = MOD24(*major + t);
	t = v;
	d = major == &north ? my_coord_tmp_6bytes : my_coord_tmp_6bytes + 3;
	put24();

	/* 3 significant digits and b trailing zeroes (metres) */
	if (v < 1000) {
		b = 0;
		w = v;
	} else if (v < 10000) {
		b = 1;
		w = v / 10;
	} else if (v < 100000) {
		b = 2;
		w = v / 100;
	} else if (v < 1000000) {
		b = 3;
		w = (uint16_t)(v / 100) / 10;
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
		fsk_putchar(219);
		fsk_putchar(220);
	} else if (x == 219) {
		fsk_putchar(219);
		fsk_putchar(221);
	} else {
		fsk_putchar(x);
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

static void mbus_mprs_out_logger(void)
{
	/* 120000 6103.52N 02806.18E KP41BB 0 80 OH5NXO-15 */
	d = mbus_mprs_buffer;
	*d++ = ' ';
	s = mprs_packed_packet + 6;
	mprs_lat_format();
	*d++ = s[2] & 0x80 ? 'S' : 'N';
	*d++ = ' ';
	s = mprs_packed_packet + 9;
	mprs_lon_format();
	*d++ = s[2] & 0x80 ? 'W' : 'E';
	*d++ = ' ';
	*d = EOS;
	for (s = gps_utc; *s != EOS; s++)	/* (runs on without EOS, v3_Z) */
		fsk_putchar(ascify(*s));
	out_string(mbus_mprs_buffer);
	out_string(locator_display_buffer);
	fsk_putchar(' ');
	symbol_nibble();
	putchar_hex_nybble(a);
	fsk_putchar(' ');
	putchar_hex_nybble(packet_rssi >> 4);
	putchar_hex_nybble(packet_rssi);
	fsk_putchar(' ');
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
	s = mprs_packed_packet + 6;
	mprs_lat_format();
	*d++ = s[2] & 0x80 ? 'S' : 'N';
	*d++ = '/';				/* primary symbol table */
	s = mprs_packed_packet + 9;
	mprs_lon_format();
	*d++ = s[2] & 0x80 ? 'W' : 'E';
	symbol_nibble();
	*d++ = a == 15 ? symbols[BY_SSID + (mprs_packed_packet[4] >> 4)] : symbols[a];
	*d = EOS;

	switch (cfg_mbus_mprs) {
	case 1:					/* TNC emulation */
		out_string(remote_display_buffer);
		fsk_putchar('>');
		out_string(dst_aprs);
		fsk_putchar(',');
		out_string(dst_relay);
		fsk_putchar(',');
		out_string(dst_wide);
		fsk_putchar(':');
		out_string(mbus_mprs_buffer);
		crlf();
		break;
	case 2:					/* KISS */
		fsk_putchar(192);
		fsk_putchar(0x00);		/* data from TNC 0 */
		s = dst_aprs;
		last = 0;
		mbus_mprs_out_address_kiss();
		s = remote_display_buffer;
		last = 1;
		mbus_mprs_out_address_kiss();
		fsk_putchar(0x03);		/* control */
		fsk_putchar(0xF0);		/* PID */
		out_string(mbus_mprs_buffer);
		fsk_putchar(192);
		break;
	case 3:					/* third party, CONVERS */
		fsk_putchar('}');
		out_string(remote_display_buffer);
		fsk_putchar('>');
		out_string(dst_aprs);
		fsk_putchar(',');
		out_string(dst_mprs);
		fsk_putchar('*');
		fsk_putchar(':');
		out_string(mbus_mprs_buffer);
		fsk_putchar(0x0D);
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

/* at: packet_good, a 4x packet in fsk_history (nibbles) */
void handle_mprs_packets(uint8_t start)
{
	at = start + 2;				/* tag, minor digit ignored */
	for (i = 0; i < 12; i++) {
		a = fsk_history[at++] << 4;
		mprs_packed_packet[i] = a | fsk_history[at++];
	}
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

	if (!(mprs_packed_packet[6] & 0x80)) {	/* a position */
		s = mprs_packed_packet + 6;
		d = locator_display_buffer;
		packed_latlon_to_locator();
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

static void zero_bit(void)
{
	c = b & 1;
	b >>= 1;
	if (c)
		stuffed_8bits();
}

static void one_bit(void)
{
	c = b & 1;
	b = b >> 1 | 0x80;
	if (c)
		stuffed_8bits();
}

static void flag(void)
{
	for (a = 0x7E, i = 0; i < 8; i++, a >>= 1) {
		if (a & 1)
			one_bit();
		else
			zero_bit();
	}
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
		zero_bit();
	flag();
	/* the frame and its CRC, a zero after five ones */
	ones = 0;
	for (s = aprs_packet_out, n += 2; n; n--, s++) {
		for (h = *s, l = 0; l < 8; l++, h >>= 1) {
			if (h & 1) {
				one_bit();
				if (++ones < 5)
					continue;
			}
			ones = 0;
			zero_bit();
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
