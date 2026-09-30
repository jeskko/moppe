/*
 * Repeater state machine, CW and note sequences in C, in ROM bank 2
 * (Phase 4, notes/hybrid-plan.md).  Replaces the bank-1 assembler from
 * repeater_halt to cw_tab (the assembler originals are in git tag
 * asm-final).  What interrupts reach stays in fixed-ROM assembler: the
 * DTMF/CCIR command parsers that set repeater_req, the 1 s / 10 ms
 * timer steps, the suspend toggle; so do cw_calc_delays / cw_calc_blip
 * (div248_full) and the waits, which run in bank 0 (b0_*).
 *
 * States.  The assembler kept a code address in repeater_state
 * (`call repeater_setstate` stored its return address and jumped there).
 * Here the low byte of repeater_state is a state number; repeater_init
 * (fixed ROM) stores ST_BOOT_NEW, i.e. boot not entered yet.  Entering a
 * state runs its entry actions and then its poll at once, as the
 * assembler did; a poll returns the state to enter next, or STAY.  go()
 * loops instead of nesting calls, as the assembler's jumps did.
 *
 * CW pre-emption.  The assembler saved SP in send_cw / send_notes and a
 * pre-empted tone did `ld sp, (repeater_cw_jmpbuf) / ret`, returning
 * from the send_cw, send_cw_chr or send_notes in progress without its
 * closing silence_timer1.  Here the tone routines return 1 when
 * pre-empted and every level passes it up.
 *
 * The routines called here do not preserve IX: no stack frames, state is
 * static.  Mainline only.
 */
#pragma bank 2

#include "r58.h"

#define PA_CCIR		0xF0
#define DTMF_STAR	(0x80 | 0xB << 3)	/* StD and '*' as the decoder latches it */
#define SILENCE		4		/* timer 1 count for the gaps (~1 MHz) */

enum { ST_BOOT_NEW, ST_BOOT, ST_IDLE, ST_OPENING, ST_BEEP_TOO_LONG, ST_OPEN,
	ST_ACTIVE, ST_CLOSING, ST_REOPENING, ST_LOCKOUT, STAY = 0xFF };

/* written by interrupts (squelch, decoders, timers) or by the menu */
extern volatile uint8_t dtmf_prevdata, ccir_tonetime, repeater_req,
	repeater_timer_BLIP_state, ad_tp4, ad_rpm, cfg_repeater_suspended;
extern uint8_t repeater_state, repeater_timer_BLIP, repeater_cw_sendit_all,
	repeater_is_suspended, repeater_sig, sio_bctrl_local,
	squelch_tightening, txpwr_increment, ctcss_is_on, ctcss_custom_flag,
	nosir, cw_slot_ticks, cfg_repeater_cmd_9_hidden,
	cfg_ctcss_output_when, cfg_cw_pitch_blip, cfg_cw_pitch_blip_link,
	cfg_cw_pitch_blip_gpio, cfg_rssi_S1, cfg_rssi_S9,
	cfg_temperature_limit_hot, cfg_temperature_limit_cold,
	cfg_rpm_limit, repeater_cfg_sqincr, repeater_cfg_txincr,
	repeater_cfg_rssi_bongos, repeater_cfg_access_method,
	repeater_cfg_afsrc, repeater_cfg_musical_blips,
	repeater_cfg_mprs_id, repeater_cfg_TBLIP, repeater_cfg_rssi_A,
	repeater_cfg_rssi_B, repeater_cfg_rssi_C;
extern uint16_t cw_pitch_cnt, repeater_cfg_TOPEN, repeater_cfg_TID,
	repeater_cfg_THOG, repeater_cfg_TCLS, repeater_cfg_TDEAD,
	repeater_cfg_TBEEPMAX;
extern uint8_t repeater_cfg_open_counter[3];
extern const uint8_t repeater_cfg_id_greet1[], repeater_cfg_id_greet2[],
	repeater_cfg_id_greet3[], repeater_cfg_id_during1[], repeater_cfg_id_during2[],
	repeater_cfg_id_during3[], repeater_cfg_id_bye1[], repeater_cfg_id_bye2[],
	repeater_cfg_id_bye3[], repeater_cfg_msg_hog[], repeater_cfg_msg_hot_alert[],
	repeater_cfg_msg_cold_alert[], repeater_cfg_msg_ant_bad[], repeater_cfg_blip[],
	repeater_cfg_blip_link[], repeater_cfg_blip_gpio_001[],
	repeater_cfg_blip_rssi_A[], repeater_cfg_blip_rssi_B[],
	repeater_cfg_blip_rssi_C[];

/* firmware routines (assembler) */
extern void repeater_init(void), tx_on(void), ctcss_off_nohang(void),
	silence_timer1(void), update_txpwr_if_tx(void),
	cw_calc_delays(void);
extern uint8_t b0_cw_wait_tone(void);		/* A != 0: pre-empted */
extern void b0_ccir_tx_timer_wait(uint8_t ticks);
/* r58.s shims */
extern void rptr_tone(uint8_t ticks, uint16_t count);	/* start_marker_tone */
extern void rptr_calc_blip(uint8_t pitch);		/* cw_calc_blip (C) */
/* the second timers, which repeater_step_1sec (interrupt) counts down:
 * one-instruction 16-bit accesses, as the assembler did */
extern uint8_t rptr_other_running(void), rptr_id_running(void);
extern void rptr_set_other(uint16_t v), rptr_set_id(uint16_t v);

/* 1 = dit, 0 = dash, left aligned, terminated by 10*; 0x00 plays '?'.
 * From 0x60 on (and the gaps) 0xFF, what the assembler's table read. */
static const uint8_t cw_tab[0x60] = {
	0x04, 0x84, 0xC4, 0xE4, 0xF4, 0xFC, 0x7C, 0x3C,
	0x1C, 0x0C, 0xA0, 0x78, 0x58, 0x70, 0xC0, 0xD8,
	0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
	0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
	0x80, 0xFF, 0xB6, 0xEA, 0xBC, 0xFF, 0xFF, 0x86,
	0x4A, 0x4A, 0xFF, 0xFF, 0x32, 0x7A, 0xAA, 0x6C,
	0x04, 0x84, 0xC4, 0xE4, 0xF4, 0xFC, 0x7C, 0x3C,
	0x1C, 0x0C, 0x1E, 0xFF, 0xFF, 0xFF, 0xFF, 0xCE,
	0xFF, 0xA0, 0x78, 0x58, 0x70, 0xC0, 0xD8, 0x30,
	0xF8, 0xE0, 0x88, 0x50, 0xB8, 0x20, 0x60, 0x10,
	0x98, 0x28, 0xB0, 0xF0, 0x40, 0xD0, 0xE8, 0x90,
	0x68, 0x48, 0x38, 0xA8, 0xA6, 0x18, 0xFF, 0xFF,
};

#define MT_CALCHZ(f)	(4032000UL / (f))
static const uint16_t note_pitch[26] = {
	MT_CALCHZ(500), MT_CALCHZ(600), MT_CALCHZ(700), MT_CALCHZ(800), MT_CALCHZ(900),
	MT_CALCHZ(1000), MT_CALCHZ(1100), MT_CALCHZ(1200), MT_CALCHZ(1300), MT_CALCHZ(1400),
	MT_CALCHZ(1500), MT_CALCHZ(1600), MT_CALCHZ(1700), MT_CALCHZ(1800), MT_CALCHZ(1900),
	MT_CALCHZ(2000), MT_CALCHZ(2100), MT_CALCHZ(2200), MT_CALCHZ(2300), MT_CALCHZ(2400),
	MT_CALCHZ(2500), MT_CALCHZ(2600), MT_CALCHZ(2700), MT_CALCHZ(2800), MT_CALCHZ(2900),
	SILENCE,
};

/* send_cw/send_cw_chr stop at EOS, so these need no padding to SIZE_STR
 * (unlike the repeater_cfg_* strings, which are fixed-size NV fields) */
static const uint8_t cw_msg_roger[] = { 'R', EOS };
static const uint8_t cw_msg_u_are[] = { 'U', 'R', ' ', EOS };
static const uint8_t cw_msg_qrt[] = { 'Q', 'R', 'T', EOS };

static uint8_t pat, ch, sval, delta, pitch, gpio, was_tx, next, mprs_bit;
static uint16_t acc;
static const uint8_t *msg, *mp, *mend;
static const uint8_t *const *ids;

/* ---- transmitter and audio */

static void repeater_txon(void)
{
	if (cfg_ctcss_output_when == 1)		/* CTCSS WHEN = TRANSMITTER */
		ctcss_maybe();
	tx_on();
	force_redraw();
}

static void repeater_txoff(void)
{
	if (cfg_ctcss_output_when == 1)
		ctcss_off();
	tx_off();
	force_redraw();
}

static uint8_t ctcss_signal_or_custom(void)
{
	return cfg_ctcss_output_when == 2 || cfg_ctcss_output_when == 4;
}

static void repeater_aon(void)
{
	if (ctcss_signal_or_custom())
		ctcss_maybe();
	/* which way /MIC affects AF relaying */
	if (repeater_cfg_afsrc == 2) {		/* bypassed: MIC just for the handset */
		if (is_ptt_pressed())
			mic_on();
		else
			mic_off();
	} else if (repeater_cfg_afsrc == 0) {	/* reversed MIC control */
		mic_off();
	} else {
		mic_on();
	}
}

static void repeater_aoff(void)
{
	if (ctcss_signal_or_custom())
		ctcss_off_nohang();
	if (repeater_cfg_afsrc == 0)
		mic_on();
	else
		mic_off();
}

/* ---- CW: 1 = pre-empted (a carrier while repeater_cw_sendit_all is 0) */

static uint8_t cw_slots(uint8_t ticks, uint16_t count)
{
	rptr_tone(ticks, count);
	if (b0_cw_wait_tone())
		return 1;
	/* tone or silence ends: open or close relay audio */
	if (squelch_open)
		repeater_aon();
	else
		repeater_aoff();
	return 0;
}

/* one character: its elements, each followed by one slot of silence */
static uint8_t cw_chr_1(void)
{
	pat = ch < sizeof cw_tab ? cw_tab[ch] : 0xFF;
	if (!pat)
		pat = 0xCE;			/* ? */
	while (pat != 0x80) {
		if (cw_slots((pat & 0x80) ? cw_slot_ticks : (uint8_t)(cw_slot_ticks * 3), cw_pitch_cnt))
			return 1;
		pat <<= 1;
		if (cw_slots(cw_slot_ticks, SILENCE))
			return 1;
	}
	return 0;
}

/* a character and 2 more slots of silence */
static uint8_t cw_chr(void)
{
	if (cw_chr_1())
		return 1;
	return cw_slots(cw_slot_ticks * 2, SILENCE);
}

static void send_cw(const uint8_t *s)
{
	mend = s + SIZE_STR;
	for (mp = s; mp != mend && *mp != EOS; mp++) {
		ch = *mp;
		if (cw_chr())
			return;
	}
	silence_timer1();
}

static void send_cw_chr(uint8_t c)
{
	ch = c;
	if (cw_chr())
		return;
	silence_timer1();
}

/* 0..9, A..O: 500..2900 Hz in 100 Hz steps, 100 ms each; above, a pause */
static void send_notes(const uint8_t *s)
{
	mend = s + SIZE_STR;
	for (mp = s; mp != mend && *mp != EOS; mp++) {
		ch = *mp < 25 ? *mp : 25;
		rptr_tone(10, note_pitch[ch]);
		if (b0_cw_wait_tone())
			return;
	}
	silence_timer1();
}

static void send_cw_prolog(void)
{
	/* CUSTOM: CTCSS during the message, stopped by the epilog if turned
	 * on here */
	ctcss_custom_flag = 0;
	if (cfg_ctcss_output_when == 4 && !ctcss_is_on) {
		ctcss_maybe();
		if (ctcss_is_on)
			ctcss_custom_flag = 1;
	}
	cw_calc_delays();
	nosir = 1;
	repeater_cw_sendit_all = 1;
	ccir_on();
	silence_timer1();
	b0_ccir_tx_timer_wait(20);
}

static void send_cw_epilog(void)
{
	if (ctcss_custom_flag)
		ctcss_off();
	ccir_off();
	silence_timer1();
	nosir = 0;
	b0_ccir_tx_timer_wait(20);
}

static void send_message(const uint8_t *s)
{
	send_cw_prolog();
	send_cw(s);
	send_cw_epilog();
}

/* ---- messages */

static void repeater_append_any_alerts(void)
{
	/* NTC to ground: the A/D value goes down as the temperature rises */
	if (ad_tp4 < cfg_temperature_limit_hot)
		send_cw(repeater_cfg_msg_hot_alert);
	if (cfg_temperature_limit_cold < ad_tp4)
		send_cw(repeater_cfg_msg_cold_alert);
	if (cfg_rpm_limit < ad_rpm)			/* high SWR */
		send_cw(repeater_cfg_msg_ant_bad);
}

static const uint8_t *const id_greet[3] = {
	repeater_cfg_id_greet1, repeater_cfg_id_greet2, repeater_cfg_id_greet3 };
static const uint8_t *const id_during[3] = {
	repeater_cfg_id_during1, repeater_cfg_id_during2, repeater_cfg_id_during3 };
static const uint8_t *const id_bye[3] = {
	repeater_cfg_id_bye1, repeater_cfg_id_bye2, repeater_cfg_id_bye3 };

/* the three parts of the ID in ids, alerts; an MPRS report if mprs is in
 * repeater_cfg_mprs_id */
static void send_id(void)
{
	send_cw_prolog();
	send_cw(ids[0]);
	send_cw(ids[1]);
	send_cw(ids[2]);
	repeater_append_any_alerts();
	send_cw_epilog();
	if (repeater_cfg_mprs_id & mprs_bit)
		send_mprs_report_packet_1();
}

static void repeater_send_id_greet(void)
{
	ids = id_greet;
	mprs_bit = 0x01;
	send_id();
}

static void repeater_send_id_during(void)
{
	ids = id_during;
	mprs_bit = 0x02;
	send_id();
}

static void repeater_send_id_bye(void)
{
	ids = id_bye;
	mprs_bit = 0x04;
	send_id();
}

/* nonzero if there is a bye message */
static uint8_t repeater_id_bye_length(void)
{
	return repeater_cfg_id_bye1[0] != EOS || repeater_cfg_id_bye2[0] != EOS ||
		repeater_cfg_id_bye3[0] != EOS || (repeater_cfg_mprs_id & 0x04);
}

/* msg and pitch of the blip to send */
static void repeater_select_which_blip(void)
{
	if (repeater_ptt_seen) {		/* PTT bongo */
		repeater_ptt_seen = 0;
		msg = repeater_cfg_blip_link;
		pitch = cfg_cw_pitch_blip_link;
		return;
	}
	gpio = (cfg_gpio2_state & 3) << 1 | (cfg_gpio1_state & 1);
	if (gpio) {				/* GPIO bongo, if not empty */
		msg = repeater_cfg_blip_gpio_001 + (uint8_t)((gpio - 1) * SIZE_STR);
		if (*msg != EOS) {
			pitch = cfg_cw_pitch_blip_gpio;
			return;
		}
	}
	msg = repeater_cfg_blip;		/* default */
	if (repeater_cfg_rssi_bongos) {
		/* the limit nearest below the peak RSSI of the last over */
		delta = 255;
		if (repeater_sig >= repeater_cfg_rssi_A) {
			delta = repeater_sig - repeater_cfg_rssi_A;
			msg = repeater_cfg_blip_rssi_A;
		}
		if (repeater_sig >= repeater_cfg_rssi_B &&
		    (uint8_t)(repeater_sig - repeater_cfg_rssi_B) < delta) {
			delta = repeater_sig - repeater_cfg_rssi_B;
			msg = repeater_cfg_blip_rssi_B;
		}
		if (repeater_sig >= repeater_cfg_rssi_C &&
		    (uint8_t)(repeater_sig - repeater_cfg_rssi_C) < delta)
			msg = repeater_cfg_blip_rssi_C;
		if (*msg == EOS)
			msg = repeater_cfg_blip;
	}
	pitch = cfg_cw_pitch_blip;
}

static void repeater_send_blip(void)
{
	send_cw_prolog();
	repeater_cw_sendit_all = 0;		/* a blip is pre-empted by carrier */
	repeater_select_which_blip();
	if (repeater_cfg_musical_blips) {
		send_notes(msg);
	} else {
		rptr_calc_blip(pitch);
		send_cw(msg);
	}
	send_cw_epilog();
}

/* "#": UR 5x, the S-report of the last over */
static void repeater_check_report_req(void)
{
	if (repeater_req != '#')
		return;
	repeater_req = 0;
	send_cw_prolog();
	send_cw(cw_msg_u_are);
	send_cw_chr(5 - last_sqtail);		/* 5 with tail, 4 tailless */
	if (repeater_sig >= cfg_rssi_S9) {
		sval = 9;
	} else if (repeater_sig < cfg_rssi_S1) {
		sval = 1;
	} else {
		/* S = 7 * fraction / fullscale + 2 */
		delta = cfg_rssi_S9 - cfg_rssi_S1;	/* fullscale, > 0 here */
		acc = (uint16_t)(uint8_t)(repeater_sig - cfg_rssi_S1) * 7;
		sval = (uint8_t)(acc / delta) + 2;
	}
	send_cw_chr(sval);
	send_cw_epilog();
	if (repeater_cfg_mprs_id & 0x08)
		send_mprs_report_packet_1();
}

/* ---- inputs and timers */

static uint8_t repeater_check_carrier_access(void)
{
	if (!squelch_open)
		return 0;			/* no signal */
	/* access 1 = carrier (and 3+); 0 = beeps, 2 = none */
	return repeater_cfg_access_method != 0 && repeater_cfg_access_method != 2;
}

static uint8_t repeater_recheck_beep_quickly(void)
{
	if ((pioa_data & PA_CCIR) == 0x80)	/* 1750 Hz */
		return 1;
	return dtmf_prevdata == DTMF_STAR;
}

static uint8_t repeater_check_beep(void)
{
	if (is_ptt_pressed())
		return 1;			/* as if an access tone */
	if (repeater_cfg_access_method == 2 || repeater_cfg_access_method == 3)
		return 0;			/* none, CTCSS */
	if (!squelch_open)
		return 0;
	if ((pioa_data & PA_CCIR) == 0x80 && ccir_tonetime >= 25)
		return 1;			/* 1750 Hz, 250 ms */
	return dtmf_prevdata == DTMF_STAR;
}

/* the blip timer counted down (then idle again) */
static uint8_t repeater_check_timer_BLIP(void)
{
	if (repeater_timer_BLIP_state != 2)
		return 0;
	repeater_timer_BLIP_state = 0;
	return 1;
}

static void start_timer_BLIP(void)
{
	repeater_timer_BLIP_state = 0;		/* stop */
	repeater_timer_BLIP = repeater_cfg_TBLIP;
	repeater_timer_BLIP_state = 1;		/* start, 2 when done */
}

static void start_timer_ID(void)
{
	rptr_set_id(repeater_cfg_TID);
}

static void repeater_bump_open_counter(void)
{
	if (++repeater_cfg_open_counter[0] == 0 && ++repeater_cfg_open_counter[1] == 0)
		++repeater_cfg_open_counter[2];
}

/* ---- states */

static uint8_t to_active(void)
{
	repeater_aon();
	rptr_set_other(repeater_cfg_THOG);
	return ST_ACTIVE;
}

static uint8_t txon_to_active(void)
{
	repeater_txon();
	return to_active();
}

/* back to open with a fresh TOPEN, blip timer running (active -> open,
 * reopening -> open) */
static uint8_t to_open(void)
{
	start_timer_BLIP();
	rptr_set_other(repeater_cfg_TOPEN);
	return ST_OPEN;
}

/* open with a fresh TOPEN and the ID timer running (a greeting ID follows,
 * or is already under way) */
static uint8_t open_at_TOPEN(void)
{
	start_timer_ID();
	rptr_set_other(repeater_cfg_TOPEN);
	return ST_OPEN;
}

/* from opening, /LOCAL and the end of a suspension */
static uint8_t open_by_reset(void)
{
	repeater_txon();
	repeater_send_id_greet();
	return open_at_TOPEN();
}

/* closing time over: the bye message, if any, on its own */
static uint8_t bye_to_idle(void)
{
	if (repeater_id_bye_length()) {
		repeater_txon();
		repeater_send_id_bye();
		repeater_txoff();
	}
	return ST_IDLE;
}

static void entry(uint8_t s)
{
	switch (s) {
	case ST_BOOT:		/* stick here for a minute (std function restorable) */
		rptr_set_other(60);
		break;
	case ST_IDLE:
		squelch_tightening = 0;
		txpwr_increment = 0;
		break;
	case ST_OPENING:
		repeater_bump_open_counter();
		rptr_set_other(repeater_cfg_TBEEPMAX);	/* tone length */
		break;
	case ST_ACTIVE:
		repeater_sig = 0;	/* peak RSSI during an over */
		break;
	}
}

static uint8_t poll(uint8_t s)
{
	switch (s) {
	case ST_BOOT:
		if (!rptr_other_running())
			return ST_IDLE;
		break;

	case ST_IDLE:		/* beep, or carrier with carrier access: opening */
		if (repeater_check_beep() || repeater_check_carrier_access())
			return ST_OPENING;
		break;

	case ST_OPENING:	/* tone too long: back; carrier gone: open */
		if (!rptr_other_running())
			return ST_BEEP_TOO_LONG;
		if (!squelch_open)
			return open_by_reset();
		break;

	case ST_BEEP_TOO_LONG:
		if (squelch_open || repeater_recheck_beep_quickly())
			break;
		return ST_IDLE;

	case ST_OPEN:		/* TX on, audio muted */
		repeater_check_report_req();
		if (repeater_check_timer_BLIP())
			repeater_send_blip();
		if ((squelch_open && !repeater_recheck_beep_quickly()) || is_ptt_pressed())
			return to_active();
		if (!rptr_id_running()) {
			repeater_send_id_during();
			start_timer_ID();
		}
		if (!rptr_other_running()) {
			/* end of open time: the closing state, or fully close */
			if (repeater_cfg_TCLS) {
				repeater_txoff();	/* quiet time */
				rptr_set_other(repeater_cfg_TCLS);
				return ST_CLOSING;
			}
			repeater_send_id_bye();
			repeater_txoff();
			return ST_IDLE;
		}
		break;

	case ST_ACTIVE:		/* TX and audio on (or forced with PTT) */
		if (!squelch_open && !is_ptt_pressed()) {
			repeater_aoff();
			return to_open();
		}
		/* (no ID here: it would let noise through at the end of an
		 * over, oh5rab) */
		if (!rptr_other_running()) {
			repeater_aoff();
			send_message(repeater_cfg_msg_hog);
			repeater_txoff();
			rptr_set_other(repeater_cfg_TDEAD);
			return ST_LOCKOUT;
		}
		break;

	case ST_CLOSING:	/* no emission */
		if (squelch_open) {
			if (repeater_recheck_beep_quickly())
				return ST_REOPENING;
			return txon_to_active();
		}
		if (is_ptt_pressed())
			return txon_to_active();
		if (!rptr_other_running())
			return bye_to_idle();
		break;

	case ST_REOPENING:	/* no emission */
		if (!repeater_recheck_beep_quickly()) {
			if (squelch_open)
				return txon_to_active();
			repeater_txon();
			return to_open();
		}
		if (is_ptt_pressed())
			return txon_to_active();
		if (!rptr_other_running())
			return bye_to_idle();
		break;

	case ST_LOCKOUT:
		if (!rptr_other_running()) {
			repeater_txon();
			repeater_send_id_bye();
			repeater_txoff();
			return ST_IDLE;
		}
		break;
	}
	return STAY;
}

static void go(uint8_t s)
{
	do {
		entry(s);
		repeater_state = s;
		s = poll(s);
	} while (s != STAY);
}

static void repeater_halt(void)
{
	repeater_aoff();
	repeater_txoff();
	repeater_init();		/* ST_BOOT_NEW */
}

void repeater_run(void)
{
	if (cfg_function != 1) {
		repeater_init();	/* not repeater, init in case later turned on */
		return;
	}

	if (cfg_repeater_suspended) {
		if (repeater_is_suspended)
			return;		/* normal path during suspension */
		repeater_is_suspended = 1;
		if (!txon)
			repeater_txon();
		send_message(cw_msg_qrt);
		repeater_halt();
		return;
	}
	if (repeater_is_suspended) {
		repeater_is_suspended = 0;	/* back in business immediately */
		go(open_by_reset());
		return;
	}

	/* /LOCAL rising resets the repeater into the open state */
	if (!(sio_bctrl_local & SB_LOCAL) && (sio_bctrl_mirror & SB_LOCAL)) {
		sio_bctrl_local = SB_LOCAL;
		go(open_by_reset());
		return;
	}

	/* #x DTMF (and CCIR) commands */
	switch (repeater_req) {
	case 9:				/* #9: close now */
		repeater_req = 0;
		if (cfg_repeater_cmd_9_hidden)
			break;
		repeater_aoff();
		send_message(cw_msg_roger);
		repeater_txoff();
		go(ST_IDLE);
		return;
	case 0xFF:			/* #0: restore squelch and power */
		repeater_req = 0;
		squelch_tightening = 0;
		txpwr_increment = 0;
		update_txpwr_if_tx();
		send_message(cw_msg_roger);
		break;
	case 1:				/* #1: tighten squelch */
		repeater_req = 0;
		squelch_tightening = repeater_cfg_sqincr;
		send_message(cw_msg_roger);
		break;
	case 3:				/* #3: raise TX power */
		repeater_req = 0;
		txpwr_increment = repeater_cfg_txincr;
		update_txpwr_if_tx();
		send_message(cw_msg_roger);
		break;
	case 5:				/* #5: toggle the RSSI bongos */
		repeater_req = 0;
		repeater_cfg_rssi_bongos ^= 1;
		send_message(cw_msg_roger);
		break;
	case 0xFE:			/* internal: just roger */
		repeater_req = 0;
		was_tx = txon;
		if (!was_tx)
			repeater_txon();
		send_message(cw_msg_roger);
		if (!was_tx)
			repeater_txoff();
		break;
	}

	if (repeater_state == ST_BOOT_NEW) {
		go(ST_BOOT);
		return;
	}
	next = poll(repeater_state);
	if (next != STAY)
		go(next);
}

/* no ID sent here, an operator announcement assumed */
void repeater_operator_ptt(void)
{
	if (cfg_function != 1)
		return;
	repeater_txon();
	repeater_aoff();
	repeater_send_blip();
	go(open_at_TOPEN());
}
