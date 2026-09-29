/*
 * PTT and TX flow in C (Phase 4, notes/hybrid-plan.md).  Replaces
 * pttcheck, tx_error, beep1750, tx_tune_tone_maybe, aprs_ptt_check and
 * spontaneous_mprs_check of r58.s (the assembler originals are in git
 * tag asm-final).  Fixed ROM, mainline only.
 *
 * Stay assembler: tx_on/tx_off/tx_on_legal_or_not (the keying sequence:
 * OUT1, TX power, synth load, the PLL delay in halts; the result in carry
 * for their asm callers), ptt_ccir_xmit and the CCIR/marker tone routines
 * (OUT0 and 8254 writes with interrupts off), check_for_mprs_timer (carry),
 * locate_tx_band (IX).  Shims in r58.s: marker_300hz_1s, ptt_tone_count,
 * ptt_1750_tone, ptt_tx_band_step; fsk_tx_on_failed/fsk_mprs_not_yet turn
 * carry into A.
 *
 * The routines called here do not preserve IX, so no stack frames.
 */
#include <stdint.h>

#define SB_LOCAL	0x10		/* sio_bctrl_mirror; asserted in r58.s */

extern uint8_t repeater_ptt_seen, cfg_function, menu_active, digidx,
	cfg_aprs_tx, cfg_idlefn_delay, cfg_aprs_tx_freq[3], tx_freq[3],
	tx_divisor[3], txon, squelch_open;
extern uint16_t cfg_txtune_hz, tx_refdiv, tx_bstep_cfg;
extern uint8_t *menu_ptr;
extern uint8_t tune_tone_position[];		/* bank 1: compared only */
extern volatile uint8_t ad_batt, idle_timer, sio_bctrl_mirror, key;

extern uint8_t is_ptt_pressed(void);		/* A != 0: pressed */
extern uint8_t is_key_down(void);		/* A = keydown */
extern uint8_t fsk_tx_on_failed(void);		/* tx_on: carry -> 0xFF */
extern uint8_t fsk_mprs_not_yet(void);		/* check_for_mprs_timer */
extern void open_selective(void), cu_manipulated(void), ctcss_maybe(void),
	ptt_ccir_xmit(void), mic_on(void), mic_off(void), battcheck(void),
	redraw(void), stop_dtmf_tone(void), ctcss_off(void),
	change_to_signalling_deviation(void), far_send_remote_config_packets(void),
	far_send_mprs_report_packet_maybe(void), far_send_mprs_report_packet(void),
	tx_off(void), remember_vip(void), far_repeater_operator_ptt(void),
	waitkey(void), mic_off_ccir_off(void), ccir_on(void), ccir_off(void),
	update_tx_vco_band(void), determine_tx_div_split(void),
	close_squelch(void), tx_on_legal_or_not(void);
extern void handle_key_during_tx(uint8_t k);
extern void marker_300hz_1s(void);		/* 300 Hz marker, 1 s */
extern void ptt_tone_count(uint16_t count);	/* 8254 counter 1 */
extern void ptt_1750_tone(void);
extern void ptt_tx_band_step(void);		/* tx_refdiv, tx_bstep_cfg */

void tx_error(void), tx_tune_tone_maybe(void);

static uint8_t batt, k;			/* statics: no stack frame */

void pttcheck(void)
{
	if (!is_ptt_pressed())
		return;
	open_selective();
	repeater_ptt_seen = 1;
	if (cfg_function == 1)
		return;				/* repeater mode: not here */

	/* PTT is down, normal or slave mode */
	cu_manipulated();
	if (fsk_tx_on_failed()) {
		tx_error();			/* illegal: bail out */
		return;
	}
	ctcss_maybe();
	if (!menu_active && digidx)
		ptt_ccir_xmit();		/* pending digits: CCIR */
	mic_on();
	tx_tune_tone_maybe();

	/* then watch PTT; redraw when the battery reading moves by more
	 * than one step */
	battcheck();
	redraw();
	batt = ad_batt;
	do {
		switch ((uint8_t)(ad_batt - batt)) {
		case 0:
		case 1:
		case 0xFF:
			break;
		default:
			battcheck();
			redraw();
			batt = ad_batt;
		}
		if (menu_active)
			redraw();		/* status displays */
		k = key;			/* read once */
		if (k != 0xFF)
			handle_key_during_tx(k);
		if (!is_key_down())
			stop_dtmf_tone();
	} while (is_ptt_pressed());

	/* trailing end of PTT */
	ctcss_off();		/* no tone under e.g. APRS - OH1E */
	change_to_signalling_deviation();
	if (menu_active)
		far_send_remote_config_packets();	/* query/command */
	far_send_mprs_report_packet_maybe();
	tx_off();
	stop_dtmf_tone();
	redraw();
	remember_vip();
	far_repeater_operator_ptt();
}

/* TX refused: a 300 Hz marker, then wait for PTT to go up */
void tx_error(void)
{
	marker_300hz_1s();
	do
		waitkey();
	while (is_ptt_pressed());
}

/* '*' without digits: the repeater's 1750 Hz tone while the key is held */
void beep1750(void)
{
	if (fsk_tx_on_failed()) {
		tx_error();
		return;
	}
	battcheck();
	mic_off_ccir_off();
	change_to_signalling_deviation();
	ptt_1750_tone();
	ccir_on();
	waitkey();
	ccir_off();
	tx_off();
}

/* in the menu at "t tunE": a tuning tone of cfg_txtune_hz (0 = none) */
void tx_tune_tone_maybe(void)
{
	if (!menu_active || menu_ptr != tune_tone_position || !cfg_txtune_hz)
		return;
	/* the asm counted subtractions: 4032000 / Hz, 16 bits kept */
	ptt_tone_count((uint16_t)(4032000UL / cfg_txtune_hz));
	mic_off();
	ccir_on();
}

/* ---- transmitting on the APRS frequency: /LOCAL (real APRS mode) and
 * the spontaneous MPRS report.  The TX frequency and synth set-up are
 * saved around it. */

static uint8_t save_freq[3], save_div[3];
static uint16_t save_refdiv, save_bstep;

static uint8_t aprs_freq_set(void)
{
	return cfg_aprs_tx_freq[0] | cfg_aprs_tx_freq[1] | cfg_aprs_tx_freq[2];
}

static void copy3(uint8_t *d, const uint8_t *s)
{
	d[0] = s[0];
	d[1] = s[1];
	d[2] = s[2];
}

static void to_aprs_freq(void)
{
	copy3(save_freq, tx_freq);
	copy3(save_div, tx_divisor);
	save_refdiv = tx_refdiv;
	save_bstep = tx_bstep_cfg;
	copy3(tx_freq, cfg_aprs_tx_freq);
	update_tx_vco_band();

	ptt_tx_band_step();
	determine_tx_div_split();
	close_squelch();
	tx_on_legal_or_not();			/* error ignored */
	redraw();
}

static void back_from_aprs_freq(void)
{
	tx_off();
	redraw();
	tx_bstep_cfg = save_bstep;
	tx_refdiv = save_refdiv;
	copy3(tx_divisor, save_div);
	copy3(tx_freq, save_freq);
	update_tx_vco_band();
}

void spontaneous_mprs_check(void)
{
	if (txon)
		return;				/* TX on: wait */
	if (idle_timer < cfg_idlefn_delay)
		return;				/* not idle enough */
	if (fsk_mprs_not_yet())
		return;
	if (squelch_open)
		return;			/* no traffic, wait - OH1E */
	if (!aprs_freq_set())
		return;				/* not configured */
	to_aprs_freq();
	far_send_mprs_report_packet();
	back_from_aprs_freq();
}

void aprs_ptt_check(void)
{
	if (!cfg_aprs_tx)
		return;				/* not configured */
	if (!(sio_bctrl_mirror & SB_LOCAL))
		return;			/* /LOCAL not pulled (inverted) */
	if (idle_timer < cfg_idlefn_delay)
		return;				/* not idle enough */
	if (!aprs_freq_set())
		return;
	to_aprs_freq();
	mic_on();
	while (sio_bctrl_mirror & SB_LOCAL)
		;				/* watch /LOCAL */
	back_from_aprs_freq();
}
