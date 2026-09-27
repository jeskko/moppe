/*
 * Idiomatic C versions of a sample of R58 firmware routines, to measure
 * SDCC code density against the hand-written Z80 assembler.
 * See notes/rewrite-evaluation.md.
 */
#include <stdint.h>

/* ---- hardware and RAM the routines touch (addresses irrelevant here) */
__sfr __at 0x60 OUT0;
#define O0_AUDIOC 0x10

extern uint8_t output_0, squelch_open, squelch_delay, squelch_forced,
	squelch_muted, squelch_tightening, repeater_sitters_special,
	idle_timer, ad_rssi, ad_sql, last_sqtail;
extern uint16_t squelch_prev_ones;
extern uint8_t cfg_squelch_source, cfg_squelch_hyst, cfg_squelch_level,
	cfg_squelch_head, cfg_squelch_tail, cfg_squelch_BIG, cfg_squelch_ctcss,
	cfg_repeater_sitters_special;
extern volatile uint8_t sir;
#define DPYSIR 1

uint8_t get_ctcss_rx_hz(void);
uint8_t read_ctcss_detect(void);
void cu_serv_on(void);
void cu_serv_off(void);
void cu_lights_on_from_squelch(void);
void pull_down_EXIN1(void);
void release_EXIN1(void);
void serv_blip(void);

/* ---- squelch (r58.asm L2606-2800) */

void audioc_on(void)  { OUT0 = output_0 |= O0_AUDIOC; }
void audioc_off(void) { OUT0 = output_0 &= ~O0_AUDIOC; }

static void squelch_is_closed(void)
{
	squelch_open = 0;
	repeater_sitters_special = 0;
	squelch_delay = cfg_squelch_head;
}

static void squelch_is_open(void)
{
	squelch_open = 1;
	squelch_delay = cfg_squelch_tail;
	idle_timer = 0;
}

static uint8_t sat_sub(uint8_t a, uint8_t b) { return a > b ? a - b : 0; }

static uint8_t read_squelcher_value(void)
{
	switch (cfg_squelch_source) {
	case 0:  return sat_sub(ad_sql, squelch_tightening);
	case 1:  return sat_sub((uint8_t)~ad_sql, squelch_tightening);
	default: return sat_sub(ad_rssi, squelch_tightening);
	}
}

static uint8_t ctcss_gate(void)
{
	return cfg_squelch_ctcss && get_ctcss_rx_hz();
}

void squelch(void)
{
	uint8_t rssi_20ms_ago = squelch_prev_ones & 0xff;
	squelch_prev_ones = (squelch_prev_ones >> 8) | ((uint16_t)ad_rssi << 8);
	uint8_t sql = read_squelcher_value();
	uint8_t half = cfg_squelch_hyst >> 1;

	if (!squelch_open) {
		uint16_t lim = cfg_squelch_level + half;
		if (lim > 255)
			lim = 255;
		if (lim >= sql) {
			squelch_is_closed();
			return;
		}
		if (squelch_delay && --squelch_delay)
			return;
		if (ctcss_gate() && !read_ctcss_detect())
			return;
		cu_serv_on();
		cu_lights_on_from_squelch();
		pull_down_EXIN1();
		squelch_is_open();
		sir |= 1 << DPYSIR;
		repeater_sitters_special = -cfg_repeater_sitters_special;
		if (!squelch_muted)
			audioc_on();
		return;
	}
	if (ctcss_gate() && !read_ctcss_detect())
		sql = 0;
	if (sql >= sat_sub(cfg_squelch_level, half)) {
		squelch_is_open();
		return;
	}
	uint8_t tail = 0;
	if (cfg_squelch_BIG >= rssi_20ms_ago) {
		tail = 1;
		if (squelch_delay && --squelch_delay)
			return;
	}
	last_sqtail = tail;
	cu_serv_off();
	release_EXIN1();
	squelch_is_closed();
	sir |= 1 << DPYSIR;
	serv_blip();
	if (!squelch_forced)
		audioc_off();
}

/* ---- a2i (L14064): digit buffer to 24-bit value */
extern uint8_t digidx, digbuf[16];

uint32_t a2i(void)
{
	uint32_t v = 0;
	uint8_t n = digidx, *p = digbuf;
	digidx = 0;
	while (n--)
		v = v * 10 + *p++;
	return v;
}

/* ---- bin_bcd (L16642): 24-bit binary to 8 packed BCD digits */
uint32_t bin_bcd(uint32_t bin)
{
	uint32_t bcd = 0;
	for (uint8_t i = 0; i < 24; i++) {
		for (uint8_t k = 0; k < 32; k += 4)
			if (((bcd >> k) & 15) >= 5)
				bcd += (uint32_t)3 << k;
		bcd = (bcd << 1) | ((bin >> 23) & 1);
		bin <<= 1;
	}
	return bcd;
}

/* ---- FSK packet CRC (L9099-9160) */
extern const uint8_t crctbl_hi[256], crctbl_lo[256];
extern uint8_t outpacket[16], cfg_remote_passwd[8];

static uint16_t crc_run(uint16_t crc, const uint8_t *p, uint8_t n)
{
	while (n--) {
		uint8_t i = (crc & 0xff) ^ *p++;
		crc = (crc >> 8) ^ (crctbl_hi[i] << 8 | crctbl_lo[i]);
	}
	return crc;
}

static void put_crc(uint16_t crc, uint8_t at)
{
	outpacket[at] = ~(crc >> 8);
	outpacket[at + 1] = ~crc;
}

void append_short_packet_crc(void)  { put_crc(crc_run(0xffff, outpacket, 6), 6); }
void append_long_packet_crc(void)   { put_crc(crc_run(0xffff, outpacket, 13), 13); }
void append_secret_packet_crc(void)
{
	put_crc(crc_run(crc_run(0xffff, cfg_remote_passwd, 8), outpacket, 13), 13);
}
