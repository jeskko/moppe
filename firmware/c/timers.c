/*
 * systick timers and the battery check in C (Phase 4, notes/hybrid-plan.md).
 * Built with `make C=1`; replaces once_per_second, once_per_minute,
 * once_per_hour and battcheck of r58.s (see the C_MODULES blocks there).
 * Behaviour pinned by emu/tests/test_timers.py and test_menu_power.py.
 *
 * once_per_* run from systick, in interrupt context: the PIO ISR saves
 * only AF, BC, DE, HL, so these must not touch IX or IY.  IY is reserved
 * (--reserve-regs-iy); IX would only be used as a frame pointer, so these
 * functions have no stack locals or parameters.  Nothing here owns RAM.
 */
#include <stdint.h>

/* firmware variables (r58.s) */
extern volatile uint8_t seconds, ad_batt;
extern uint8_t gps_valid_seconds, gps_speed, txon, pioa_data,
	repeater_sitters_special, alert_timer, scan_on, scan_patience, keydown,
	lights_timer, dtmf_idletime, cfg_dtmf_holdtime, cfg_function,
	display_buffer_time, locator_dpyed, redraw_req, call_dpyed,
	call_timer_sec, call_timer_min, call_timer_hour, cfg_tx_tot_minutes,
	tx_tot_timer, squelch_open, key, digidx, menu_active, idle_timer,
	cfg_idlefn_delay, idlefn_flag, cfg_ign_apo_hours, ign_apo_timer,
	txtail_timer;
extern uint16_t mprs_report_timer, transmitter_hours_second_counter;
extern uint8_t transmitter_hours[3];

/* firmware routines (assembler) */
extern void powerdown_now(void);		/* does not return */
extern void audioc_off(void);
extern void dtmf_decoder_timeout(void);
extern void repeater_step_1sec(void);
extern uint8_t is_ptt_pressed(void);		/* A != 0: pressed */
extern void unreject_timer(void);
extern void re_enable_modem(void);
extern void feedback_lobatt(void);
extern void force_redraw(void);
extern void clear_clock_icon(void);
extern void draw_clock_icon(void);
extern void no_feedback(void);
extern void redraw(void);
extern void alert_tone_1s(void);		/* 300 Hz for 1 s (r58.s shim) */

#define PA_HOOK		0x02
#define PB_EXIN2	0x04			/* aka /IGN */
__sfr __at(0x01) pio_bdata;			/* PIO + BDATA */

void once_per_second(void)
{
	if (gps_valid_seconds)
		gps_valid_seconds--;

	/* MPRS report timer, faster when moving: + speed/4 + 1, saturating */
	if (mprs_report_timer > 0xFFFF - 1 - ((gps_speed >> 2) & 0x3F))
		mprs_report_timer = 0xFFFF;
	else
		mprs_report_timer += ((gps_speed >> 2) & 0x3F) + 1;

	if (txon && ++transmitter_hours_second_counter == 3600) {
		transmitter_hours_second_counter = 0;
		if (!++transmitter_hours[0] && !++transmitter_hours[1])
			++transmitter_hours[2];
	}

	/* repeater sitting: counts up from -N while on the cradle */
	if ((pioa_data & PA_HOOK) && repeater_sitters_special &&
	    !++repeater_sitters_special)
		audioc_off();

	if (alert_timer)
		alert_timer--;

	if (scan_on && scan_patience)
		scan_patience--;

	if (!keydown && lights_timer != 255)
		lights_timer++;			/* seconds since handset use */

	if (dtmf_idletime) {
		if ((uint8_t)(dtmf_idletime + 1) >= cfg_dtmf_holdtime) {
			dtmf_decoder_timeout();
			dtmf_idletime = 0;
		} else
			dtmf_idletime++;
	}

	if (cfg_function == 1)
		repeater_step_1sec();

	if (display_buffer_time && !--display_buffer_time) {
		locator_dpyed = 0;
		redraw_req = 1;
	}

	if (call_dpyed && ++call_timer_sec >= 60) {
		call_timer_sec = 0;
		if (++call_timer_min >= 60) {
			call_timer_min = 0;
			if (++call_timer_hour >= 99)
				call_timer_hour = 99;
		}
	}
}

void once_per_minute(void)
{
	/* TOT: tx_tot_timer counts minute boundaries since TX on, so TX lasts
	 * N..N+1 minutes before a TOT of N powers down; 255 = no limit */
	if (txon && cfg_tx_tot_minutes != 255 &&
	    cfg_tx_tot_minutes < ++tx_tot_timer) {
		powerdown_now();
		return;
	}

	/* idle function (autoscan, default memory) after cfg_idlefn_delay
	 * minutes without squelch, keys, digits, menu or PTT */
	if (!scan_on && !squelch_open && key == 0xFF && !digidx &&
	    !menu_active && !is_ptt_pressed() && idle_timer != 255) {
		idle_timer++;
		if (cfg_idlefn_delay && cfg_idlefn_delay == idle_timer)
			idlefn_flag = 1;
	}

	unreject_timer();		/* decay temporary rejects */
}

void once_per_hour(void)
{
	/* ignition auto power-off: /IGN open for more than the configured
	 * hours (255 = never) */
	if (pio_bdata & PB_EXIN2) {
		if (cfg_ign_apo_hours < ign_apo_timer) {
			powerdown_now();
			return;
		}
		ign_apo_timer++;
	}

	re_enable_modem();
}

/* ---- battery (mainline, from mainloop and the TX paths) */

#define VOLTS(v)	((v) * 10 * 256 / 156)	/* AD_BATT reading: 8 V = 131 */

/* Dangerously low: warn, then power off within about 5 s unless the
 * voltage comes back. */
static void battcheck_lobatt(void)
{
	static uint8_t until;

	feedback_lobatt();
	force_redraw();

	until = seconds + 5;
	if (until >= 60)
		until -= 60;
	for (;;) {
		if (seconds == until)
			powerdown_now();
		if (ad_batt >= VOLTS(10))
			break;
	}

	clear_clock_icon();		/* battery reanimation */
	no_feedback();
	redraw();
}

/* The routines called here do not preserve IX, so no stack locals. */
static uint8_t low, warn, v;

void battcheck(void)
{
	/* after a transmission the voltage sags, so lower thresholds */
	if (txtail_timer) {
		low = VOLTS(8);
		warn = VOLTS(9);
	} else {
		low = VOLTS(9);
		warn = VOLTS(10);
	}
	v = ad_batt;			/* one reading for both thresholds */
	if (v < low) {
		battcheck_lobatt();
		return;
	}
	if (v >= warn) {
		clear_clock_icon();
		return;
	}
	draw_clock_icon();
	if (alert_timer)
		return;
	alert_timer = 60;		/* 1 s tone every 60 s */
	alert_tone_1s();
}
