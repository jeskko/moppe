/*
 * The mainloop and its per-pass checks in C (Phase 4,
 * notes/hybrid-plan.md).  Replaces mainloop, gps_check (the NMEA and
 * Aisin Seiki gatherers), script_check, idlefn_check, bus_rf_relay,
 * dim_lights_if_idle, redrawcheck and ccircheck of r58.s (the assembler
 * originals are in git tag asm-final).  Fixed ROM.
 *
 * Stay assembler: cu_lights_off (single-bit writes to `indicators`,
 * which interrupts also write), ding, getchar (DI), send_packet_buffer
 * (through fsk_send).  The GPS processors are banked; gpsc_sentence and
 * gpsc_aisin call them with A through bank2_call.
 *
 * Everything here runs on every pass, so it stays small: the checks
 * return at once when there is nothing to do.  The routines called here
 * do not preserve IX, so no stack frames.
 */
#include "r58.h"

#define GPS_SENTENCE_SIZE	100	/* asserted in r58.s */
#define GPS_MIN_SENTENCE	10	/* shorter is junk */
#define GPS_AISIN_SEIKI	3		/* cfg_gps_config */
#define RELAY_BYTES	12
#define PKT_RELAY	0x50

extern uint8_t gps_hist_rp, gps_sentence_len, cfg_gps_config,
	cfg_onhook_script[SIZE_STR], cfg_offhook_script[SIZE_STR],
	cfg_idlefn, cfg_light_seconds, cfg_bus_rf_relay,
	cfg_spontaneous_mprs;
extern volatile uint8_t script_req, ding_req;

extern void gpsc_sentence(uint8_t len), gpsc_aisin(uint8_t idx);
extern void cu_lights_off(void);
/* the per-pass checks of other modules */
extern void fskcheck(void), far_repeater_run(void);

void gps_check(void), script_check(void), idlefn_check(void), bus_rf_relay(void),
	dim_lights_if_idle(void), redrawcheck(void), ccircheck(void);

void mainloop(void)
{
	for (;;) {
		redrawcheck();
		battcheck();
		pttcheck();
		aprs_ptt_check();
		keycheck();
		fskcheck();
		ccircheck();
		dim_lights_if_idle();
		idlefn_check();
		script_check();
		scanner_run();
		far_repeater_run();
		gps_check();
		if (cfg_bus_rf_relay)
			bus_rf_relay();		/* only if configured */
		if (cfg_spontaneous_mprs)
			spontaneous_mprs_check();
	}
}

/* ---- GPS: gather the bytes the SIO interrupt put in gps_history */

static uint8_t rp, len, c;		/* statics: no stack frame */
static uint8_t *dst;

/* Aisin Seiki: every 0x0D may end a CA CA block */
static void gps_check_aisin_seiki(void)
{
	do {
		c = gps_history[rp++];
		if (c == 0x0D)
			gpsc_aisin(rp);		/* just after the 0x0D */
	} while (gps_hist_idx != rp);
	gps_hist_rp = rp;
}

/* NMEA: '$' starts a sentence (not stored), LF ends it */
void gps_check(void)
{
	rp = gps_hist_rp;
	if (gps_hist_idx == rp)
		return;				/* empty */
	if (cfg_gps_config == GPS_AISIN_SEIKI) {
		gps_check_aisin_seiki();
		return;
	}
	len = gps_sentence_len;
	dst = gps_sentence + len;
	do {
		if (len >= GPS_SENTENCE_SIZE)
			goto rewind;		/* too long: not likely */
		c = gps_history[rp];
		if (c == '$')
			goto rewind;
		if (c == 0x0A) {		/* CR LF: process, then rewind */
			if (len >= GPS_MIN_SENTENCE)
				gpsc_sentence(len);
			goto rewind;
		}
		*dst++ = c;
		len++;
		goto next;
	rewind:
		len = 0;
		dst = gps_sentence;
	next:
		rp++;			/* stays in the page buffer */
	} while (gps_hist_idx != rp);
	gps_hist_rp = rp;
	gps_sentence_len = len;
}

/* ---- hook scripts: up to SIZE_STR keys typed on a hook change */

static const uint8_t *sp;
static uint8_t n;

void script_check(void)
{
	if (!script_req)
		return;
	open_selective();		/* before the script (it may mute) */
	c = script_req;
	script_req = 0;
	if (c == 1)
		sp = cfg_onhook_script;
	else if (c == 2)
		sp = cfg_offhook_script;
	else
		return;				/* not recognized */
	n = SIZE_STR;
	do {
		c = *sp++;
		if (c == EOS)
			return;
		key_time = 0;			/* only quick simple presses */
		keydown = 0;
		key = 0xFF;
		dokey_not_menu(c);
	} while (--n);
}

/* ---- the idle function, once the minute timer says so */

void idlefn_check(void)
{
	if (!idlefn_flag)
		return;
	idlefn_flag = 0;
	if (cfg_idlefn == 1)
		scanner_start();
	else if (cfg_idlefn == 2)
		def_memo(0);
}

/* ---- MBUS -> RF: every 12 bytes received go out as a relay packet */

void bus_rf_relay(void)
{
	if (mbusrx_cnt < RELAY_BYTES)
		return;
	outpacket[0] = PKT_RELAY;
	for (n = 1; n <= RELAY_BYTES; n++)
		outpacket[n] = getchar();
	append_long_packet_crc();
	fsk_send(LONG_PACLEN);
}

/* ---- small ones */

void dim_lights_if_idle(void)
{
	if (cfg_light_seconds < lights_timer)
		cu_lights_off();		/* idle longer than configured */
}

void redrawcheck(void)
{
	if (!redraw_req)
		return;
	redraw_req = 0;
	redraw();
}

void ccircheck(void)
{
	if (!ding_req)
		return;
	ding_req = 0;
	ding();
}
