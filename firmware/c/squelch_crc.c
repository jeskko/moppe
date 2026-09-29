/*
 * Squelch state machine and FSK packet CRCs in C (SDCC, --sdcccall 1).
 *
 * The first C module (the proof of concept of the hybrid build): replaces
 * `squelch` and the three `append_*_packet_crc` routines of r58.s (the
 * assembler originals are in git tag asm-final).  Firmware variables live
 * in r58.s and are declared extern here; the small helpers it calls stay
 * in assembler because other code uses them.
 */
#include <stdint.h>

/* firmware variables */
extern uint8_t squelch_open, squelch_delay, squelch_forced, squelch_muted,
	repeater_sitters_special, ad_rssi, last_sqtail;
extern uint16_t squelch_prev_ones;
extern uint8_t cfg_squelch_hyst, cfg_squelch_level, cfg_squelch_BIG,
	cfg_squelch_ctcss;
extern volatile uint8_t sir;
#define DPYSIR 1

/* firmware routines (assembler); byte results come back in A */
extern uint8_t read_squelcher_value(void);
extern uint8_t get_ctcss_rx_hz(void);
extern uint8_t read_ctcss_detect(void);
extern void squelch_is_closed(void);
extern void squelch_is_open(void);
extern void audioc_on(void);
extern void audioc_off(void);
extern void cu_serv_on(void);
extern void cu_serv_off(void);
extern void cu_lights_on_from_squelch(void);
extern void pull_down_EXIN1(void);
extern void release_EXIN1(void);
extern void serv_blip(void);
extern void start_repeater_sitters_special(void);

static uint8_t ctcss_blocks(void)
{
	return cfg_squelch_ctcss && get_ctcss_rx_hz() && !read_ctcss_detect();
}

/*
 * Called from systick at ~100 Hz (r58.asm L2638 in the assembler version).
 *
 * The assembler routines it calls do not preserve IX, which SDCC uses as
 * frame pointer; so this function must not have a stack frame: its locals
 * are static (placed in firmware RAM by the generated data include).
 */
static uint8_t rssi_20ms_ago, sql, half;

void squelch(void)
{
	rssi_20ms_ago = squelch_prev_ones & 0xff;
	squelch_prev_ones = (squelch_prev_ones >> 8) | ((uint16_t)ad_rssi << 8);
	sql = read_squelcher_value();
	half = cfg_squelch_hyst >> 1;

	if (!squelch_open) {
		if ((uint16_t)cfg_squelch_level + half >= sql) {
			squelch_is_closed();
			return;
		}
		if (squelch_delay && --squelch_delay)
			return;			/* opening delay still running */
		if (ctcss_blocks())
			return;			/* wait for the CTCSS tone too */
		cu_serv_on();
		cu_lights_on_from_squelch();
		pull_down_EXIN1();
		squelch_is_open();
		sir |= 1 << DPYSIR;
		start_repeater_sitters_special();
		if (!squelch_muted)
			audioc_on();
		return;
	}

	if (ctcss_blocks())
		sql = 0;			/* tone lost: close now */
	if (sql >= (cfg_squelch_level > half ? cfg_squelch_level - half : 0)) {
		squelch_is_open();
		return;
	}
	last_sqtail = 0;
	if (cfg_squelch_BIG >= rssi_20ms_ago) {
		last_sqtail = 1;		/* weak signal: closing has a tail */
		if (squelch_delay && --squelch_delay)
			return;
	}
	cu_serv_off();
	release_EXIN1();
	squelch_is_closed();
	sir |= 1 << DPYSIR;
	serv_blip();
	if (!squelch_forced)
		audioc_off();
}

/* ---- FSK packet CRC: reflected CCITT via the firmware's page tables,
 * init 0xFFFF, stored complemented, high byte first */
extern const uint8_t crctbl_hi[256], crctbl_lo[256];
extern uint8_t outpacket[16], cfg_remote_passwd[8];

static uint16_t crc_run(uint16_t crc, const uint8_t *p, uint8_t n)
{
	while (n--) {
		uint8_t i = (uint8_t)crc ^ *p++;
		crc = (crc >> 8) ^ ((uint16_t)crctbl_hi[i] << 8 | crctbl_lo[i]);
	}
	return crc;
}

static void put_crc(uint16_t crc, uint8_t at)
{
	outpacket[at] = ~(crc >> 8);
	outpacket[at + 1] = ~crc;
}

void append_short_packet_crc(void)
{
	put_crc(crc_run(0xffff, outpacket, 6), 6);
}

void append_long_packet_crc(void)
{
	put_crc(crc_run(0xffff, outpacket, 13), 13);
}

void append_secret_packet_crc(void)
{
	put_crc(crc_run(crc_run(0xffff, cfg_remote_passwd, 8), outpacket, 13), 13);
}
