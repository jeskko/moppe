/*
 * FSK packet layer in C, in ROM bank 2 (Phase 4, notes/hybrid-plan.md).
 * Replaces the bank-1 assembler from packet_callsign_pack to
 * send_mprs_report_packet_1 and from map_special_ptrs to
 * build_call_packet_buffer (the assembler originals are in git tag
 * asm-final).  packet_callsign_unpack and mprs_degmin_pack are in
 * c/aprs.c.
 *
 * Fixed code enters through the far_* stubs (bank2_call): receive
 * dispatch packet_for_whom, send_remote_config_packets,
 * send_mprs_report_packet{_maybe,,_1} and send_call_packet.  Bank-1
 * routines (the menu's) are called through their own far_* stubs, which
 * return to bank 2; MPRS receive and APRS sending are c/aprs.c.  Register
 * interfaces go through r58.s shims (fsk_*).
 *
 * Received packets are one nibble per byte in the page-aligned ring
 * fsk_history, starting at packet_good; the index wraps at 256 as the
 * assembler's `inc l` did.  The routines called here do not preserve IX,
 * so nothing has a stack frame: state is static.  Mainline only.
 */
#pragma bank 2

#include "r58.h"

#define SHORT_PACLEN	8

extern uint8_t cfg_keyup_mprs, gps_reported_speed;
extern uint8_t cfg_mycall_1[5];
extern uint16_t cfg_remote_id;
extern const uint8_t version[8];

/* firmware routines (assembler) */
extern void cu_lights_on(void), cu_call_on(void), mdm_delay(void),
	start_call_timer(uint8_t on), far_leaved_setup(void);

/* r58.s shims */
extern uint16_t fsk_menu_ptr(void);		/* menu_value_ptr (bank 1): DE */
extern void fsk_remote_config_execute(uint16_t ptr, const uint8_t *data);

static const uint8_t onesies[8] = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };

uint8_t fsk_at;			/* shared with c/aprs.c: nibbles() */
static uint8_t i, n, b, c;
static uint16_t ptr;
static uint8_t *d;
static const uint8_t *s, *from;

/* the byte from the nibbles at fsk_history[fsk_at], [fsk_at + 1] */
uint8_t nibbles(void)
{
	uint8_t v = fsk_history[fsk_at++] << 4;
	return v | fsk_history[fsk_at++];
}

/* ---- receive */

static void handle_relay_packets(void)
{
	/* the 12 nibbles from the tag on, wraps in the ring; v3_Z did not */
	fsk_at = packet_good;
	for (i = 0; i < 12; i++)
		mbus_putchar(fsk_history[fsk_at++]);
}

static void send_display_config_packet(void);

static void handle_config_packets(void)
{
	/* c still holds the tag ('A' ask / 'E' enter) from packet_for_whom */
	fsk_at = packet_good + 1;
	if (fsk_history[fsk_at++] != 0xC)	/* AC/EC ii DD ptr PTR possible data */
		return;
	if (!cfg_remote_id)		/* remote id zero equals not used */
		return;
	if (nibbles() != (uint8_t)cfg_remote_id)
		return;
	if (nibbles() != cfg_remote_id >> 8)
		return;
	ptr = nibbles();
	ptr |= nibbles() << 8;
	/* refuse to reveal/modify the password */
	if (ptr <= (uint16_t)(cfg_remote_passwd + SIZE_STR - 1)
	    && ptr > (uint16_t)(cfg_remote_passwd - SIZE_STR))
		return;
	if (c == 0xE) {
		fsk_remote_config_execute(ptr, &fsk_history[fsk_at]);
		far_leaved_setup();
	}
	send_display_config_packet();	/* FSK reply in either case */
}

static void display_packet(void)
{
	fsk_at = packet_good + 2;
	for (i = 0; i < 8; i++)
		remote_display_buffer[i] = nibbles();
	remote_display_buffer[8] = EOS;
	remote_display_buffer[9] = EOS;	/* all 10 characters */
	display_buffer_time = 5;
}

static void handle_display_packets(void)
{
	c = fsk_history[(uint8_t)(packet_good + 1)];
	if (c == 0xD) {
		display_packet();
	} else if (c == 0xC) {
		if (!cfg_remote_id)
			return;
		display_packet();
		digidx = 0;		/* as an ack */
	} else {
		return;
	}
	redraw();
}

static void handle_call_packet(void)
{
	fsk_at = packet_good + 6;		/* destination address */
	for (i = 0; i < 5; i++)
		if (fsk_history[fsk_at++] != cfg_mycall_1[i])
			return;
	start_call_timer(1);
	cu_lights_on();
	cu_call_on();
	redraw();
	ding();
}

void packet_for_whom(void)
{
	c = fsk_history[packet_good];
	if (c == 0xC)
		handle_call_packet();
	else if (c == 0xA || c == 0xE)	/* ask, enter */
		handle_config_packets();
	else if (c == 0xD)
		handle_display_packets();
	else if (c == 0x4)
		handle_mprs_packets(packet_good);
	else if (c == 0x5)
		handle_relay_packets();
}

/* ---- config packets */

/* a variable pointer, or the page-0 pseudo pointer of a special one */
static void map_special_ptrs(void)
{
	if (ptr == (uint16_t)version)
		ptr = 0;			/* VERSION = 0 */
	else if (ptr == (uint16_t)menu_rfc_change)
		ptr = 1;			/* RFC = 1 */
	else if (ptr == (uint16_t)menu_sql_change)
		ptr = 2;			/* SQL = 2 */
	else if (ptr == (uint16_t)menu_sqB_change)
		ptr = 3;			/* SQL BI = 3 */
}

/* n bytes from `from` to d */
static void copy(void)
{
	while (n--)
		*d++ = *from++;
}

#define COPY(f, len)	(from = (f), n = (len), copy())

/* the menu's variable pointer at outpacket[3] */
static void fill_ptr(void)
{
	ptr = fsk_menu_ptr();
	map_special_ptrs();
	outpacket[3] = ptr;
	outpacket[4] = ptr >> 8;
	d = &outpacket[5];
}

static void fill_enter_config_packet(void)
{
	fill_ptr();
	c = digidx;			/* depending on number of characters: */
	if (c <= 8) {
		COPY(digbuf, c);	/* up to 8, padded (COPY(onesies, 0) at 8) */
		COPY(onesies, 8 - c);
	} else {
		COPY(onesies, 8);	/* 9 or more -> 0 characters (silly) */
	}
}

static void remote_config_header(uint8_t tag)
{
	outpacket[0] = tag;
	outpacket[1] = cfg_remote_id;	/* with this remote config identifier */
	outpacket[2] = cfg_remote_id >> 8;
}

/* PTT in menu, send query or config packet */
void send_remote_config_packets(void)
{
	if (!cfg_remote_id)		/* dont bother when remote id zeroed */
		return;
	mic_off_ccir_off();
	if (digidx) {
		remote_config_header(0xEC);	/* "Enter Config" */
		fill_enter_config_packet();
		append_secret_packet_crc();
		fsk_send(LONG_PACLEN);
	} else {
		remote_config_header(0xAC);	/* "Ask Config" */
		fill_ptr();
		COPY(onesies, 3);
		append_short_packet_crc();
		fsk_send(SHORT_PACLEN);
	}
}

/* ptr: variable pointer or special 0..3 */
static void fill_display_config_packet(void)
{
	d = &outpacket[1];
	if (ptr >> 8) {
		COPY((const uint8_t *)ptr, 8);
		return;
	}
	switch ((uint8_t)ptr) {
	case 0:				/* VERSION */
		COPY(version, 8);
		return;
	case 1:				/* RFC */
		*d++ = rfc;
		*d++ = ad_rssi;
		break;
	case 2:				/* SQL */
		*d++ = cfg_squelch_level;
		*d++ = read_squelcher_value();
		break;
	case 3:				/* SQL BI, with RSSI */
		*d++ = cfg_squelch_BIG;
		*d++ = ad_rssi;
		break;
	default:
		COPY(onesies, 8);
		return;
	}
	COPY(onesies, 6);
}

static void send_display_config_packet(void)
{
	b = txon;			/* in case tx already on, repeater ? */
	if (!b && tx_on_failed()) {
		tx_error();
		return;
	}
	mic_off_ccir_off();
	outpacket[0] = 0xDC;
	fill_display_config_packet();
	append_long_packet_crc();
	fsk_send(LONG_PACLEN);
	mdm_delay();
	fsk_send(LONG_PACLEN);
	if (!b)
		tx_off();		/* turned on, so turn off also */
}

/* ---- MPRS report */

/* the next character of a callsign as 6 bits (get_next_cfg_6bits) */
static uint8_t next_6bits(void)
{
	uint8_t a = *s++;
	if (a == EOS)
		a = ' ';		/* pad short strings with blanks */
	else if (a < 10)
		a += '0';
	else if (a < 16)
		a += 'A' - 10;
	return (a - ' ') & 0x3F;
}

/* 8 characters at s into 6 bytes at d */
static void packet_callsign_pack(void)
{
	for (i = 0; i < 2; i++) {
		b = next_6bits();
		c = next_6bits();
		*d++ = (c & 3) << 6 | b;
		b = c >> 2;
		c = next_6bits();
		*d++ = c << 4 | b;
		b = c >> 4;
		c = next_6bits();
		*d++ = c << 2 | b;
	}
}

void send_mprs_report_packet_1(void)
{
	gps_reported_speed = gps_speed;	/* the speed during report */
	if (cfg_report_type) {
		send_aprs_report_packet();
		return;
	}
	/* 40 cc cc cc cc cs xx la la la lo lo lo */
	outpacket[0] = 0x40;		/* "MPRS #0" */
	s = cfg_mprs_callsign;
	d = &outpacket[1];
	packet_callsign_pack();
	/* SSID in the top nibble after the 6 packed characters */
	outpacket[5] = (outpacket[5] & 0x0F) | cfg_mprs_ssid << 4;
	outpacket[6] = 0;		/* routing/digipeating reserved */
	mprs_degmin_pack(cfg_gps_latitude, &outpacket[7]);
	mprs_degmin_pack(cfg_gps_longitude, &outpacket[10]);
	outpacket[8] |= (cfg_mprs_symbol << 4) & 0xC0;	/* hibits of symbol */
	outpacket[11] |= cfg_mprs_symbol << 6;		/* lobits */
	append_long_packet_crc();
	fsk_send(LONG_PACLEN);		/* once */
}

void send_mprs_report_packet(void)
{
	mprs_report_timer = 0;
	mic_off_ccir_off();
	send_mprs_report_packet_1();
}

void send_mprs_report_packet_maybe(void)
{
	if (!cfg_keyup_mprs)		/* oFF */
		return;
	if (cfg_keyup_mprs != 1 && mprs_timer_not_yet())	/* on demand */
		return;
	send_mprs_report_packet();	/* 1: ALL */
}

/* ---- call packet */

static void build_call_packet_buffer(void)
{
	b = digidx;
	if (b == 1 && digbuf[0] == 0)
		return;			/* 0* = send it again */
	outpacket[0] = 0xC0 | cfg_mycall_1[0];
	outpacket[1] = cfg_mycall_1[1] << 4 | cfg_mycall_1[2];
	outpacket[2] = cfg_mycall_1[3] << 4 | cfg_mycall_1[4];
	/* digits two per byte, a lone one padded with 0xF, into
	 * outpacket[3..5]; unused bytes 0xFF.  (digidx == 0 wraps b past 0,
	 * so this always runs all 3 iterations; v3_Z did too.) */
	s = digbuf;
	d = &outpacket[3];
	for (;;) {
		i = *s++ << 4 | 0x0F;
		*d++ = i;
		if (!--b)
			break;
		d[-1] = (i & 0xF0) | *s++;
		if (!--b || d == &outpacket[6])
			break;
	}
	while (d != &outpacket[6])
		*d++ = 0xFF;
}

void send_call_packet(void)
{
	if (tx_on_failed()) {
		tx_error();
		return;
	}
	mic_off_ccir_off();
	waitkey();
	build_call_packet_buffer();
	append_short_packet_crc();
	fsk_send(SHORT_PACLEN);
	mdm_delay();
	fsk_send(SHORT_PACLEN);
	mdm_delay();
	fsk_send(SHORT_PACLEN);
	tx_off();
	clear_buffer();
}
