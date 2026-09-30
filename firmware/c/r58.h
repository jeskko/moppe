/*
 * Declarations shared by the C modules.  A symbol that one module alone
 * uses is declared in that module; when a second one needs it, it moves
 * here.
 *
 * Firmware variables live in r58.s.  `volatile` marks those an interrupt
 * writes: mainline code reads such a variable once into a static
 * (notes/hybrid-plan.md, "C coding rules").  The layout constants are
 * asserted in r58.s.
 */
#ifndef R58_H
#define R58_H

#include <stdint.h>

#define EOS		0xFF		/* string end */
#define SIZE_STR	8		/* STRING: 8 bytes */

#define NUM_MEMORIES	130
#define MEM_SIZE	12		/* a memory record */
#define MEM_FLAGS	6
#define MEM_VALID	0x01
#define MEM_HIDDEN	0x02
#define MEM_SCANNABLE	0x04

#define NUM_BANDRECS	6
#define SIZE_BANDREC	14

#define DPX_SIMPLEX	0		/* duplex_state */
#define DPX_DUPLEX	1
#define DPX_REVERSE	2
#define DPX_SPLIT	3

#define DIGBUF_SIZE	16
#define LONG_PACLEN	15		/* long FSK packet incl. CRC */
#define SB_LOCAL	0x10		/* sio_bctrl_mirror: /LOCAL */

/* ---- firmware variables (r58.s) */

extern uint8_t band_autoreject, band_sclisten, band_sctail, band_step,
	call_dpyed, call_timer_hour, call_timer_min, call_timer_sec,
	cfg_function, cfg_gpio1_state, cfg_gpio2_state, cfg_idlefn_delay,
	cfg_mprs_ssid, cfg_mprs_symbol, cfg_report_type, cfg_squelch_BIG,
	cfg_squelch_level, cu_is_alfa, digidx, display_buffer_time,
	duplex_state, gps_speed, last_sqtail, locator_dpyed, mem_ctcss_rx_hz,
	mem_ctcss_tx_hz, mem_flags, mem_idx, menu_active, packet_good,
	repeater_ptt_seen, rfc, scan_on, scan_paused, scan_settling_time, txon,
	vip_idx, volume;
extern volatile uint8_t ad_batt, ad_rssi, gps_hist_idx, gps_valid_seconds,
	idle_timer, idlefn_flag, key, key_time, keydown, lights_timer,
	mbusrx_cnt, pioa_data, redraw_req, scan_patience, sio_bctrl_mirror,
	squelch_forced, squelch_muted, squelch_open;
extern uint16_t gps_course, gps_knots, mprs_report_timer, scan_mask;

/* 24-bit frequencies (kHz) and shifts */
extern uint8_t rx_freq[3], tx_freq[3], vip_freq[3], duplex_shift[3],
	cfg_other_duplex[3], cfg_rx_vco_center[3], cfg_tx_vco_center[3],
	cfg_tx_band_start[3];
extern uint8_t cfg_band1_start[NUM_BANDRECS * SIZE_BANDREC];	/* the records */
extern uint8_t memories[NUM_MEMORIES * MEM_SIZE], rfctab[100];

/* strings and buffers */
extern uint8_t cfg_gps_latitude[SIZE_STR], cfg_gps_longitude[SIZE_STR],
	cfg_implied[SIZE_STR], cfg_mprs_callsign[SIZE_STR],
	cfg_remote_passwd[SIZE_STR], gps_utc[SIZE_STR],
	locator_display_buffer[SIZE_STR], digbuf[DIGBUF_SIZE],
	remote_display_buffer[16], outpacket[16], gps_sentence[100],
	fsk_history[256], gps_history[256];

struct rec;					/* a menu record, c/menu.c */
extern const struct rec *menu_ptr;

/* ---- assembler routines and shims (r58.s) */

extern uint8_t a2i_byte(void);		/* digits -> A (0xFF if > 255) */
extern uint8_t fsk_mprs_not_yet(void);	/* check_for_mprs_timer: carry */
extern uint8_t fsk_tx_on_failed(void);	/* tx_on: carry */
extern uint8_t get_ctcss_rx_hz(void);	/* VFO or memory */
extern uint8_t getchar(void);
extern uint8_t is_key_down(void);	/* A = keydown; clears key when up */
extern uint8_t is_ptt_pressed(void);	/* A != 0: pressed */
extern uint8_t read_squelcher_value(void);
extern void dpy_ch(uint8_t c);		/* dpydig */
extern void dpy_freq(const uint8_t *f);	/* draw_long of a 24-bit value */
extern void fsk_putchar(uint8_t c);	/* MBUS putchar (C) */
extern void fsk_send(uint8_t len);	/* send_packet_buffer (B) */
extern void clear_key(void);		/* preserves A */
extern void marker_300hz_1s(void);	/* 300 Hz marker, 1 s */
extern void powerdown_now(void);	/* does not return */
extern void audioc_off(void), ccir_off(void), ccir_on(void),
	clear_buffer(void), clear_upper_colons(void), close_squelch(void),
	ctcss_maybe(void), ctcss_off(void), determine_tx_div_split(void),
	ding(void), force_redraw(void), mic_off(void), mic_off_ccir_off(void),
	mic_on(void), no_feedback(void), open_selective(void), redraw(void),
	save_nvdata(void), set_channel_step(void), tx_off(void),
	unforce_squelch(void), waitkey(void);

/* ---- C functions other modules call */

/* c/aprs.c (bank 2) */
extern void gps_own_locator(void), send_aprs_report_packet(void);
extern void handle_mprs_packets(uint8_t start);

/* c/freq.c */
extern void changed_frequency(void), changed_frequency_duplex_okay(void),
	locate_band(void), set_duplex_from_tx_rx(void), step_channel_down(void),
	step_channel_up(void), step_duplex_state(void),
	temporary_change_rx_freq(void), update_tx_vco_band(void);

/* c/fsk.c (bank 2) */
extern void send_mprs_report_packet_1(void);

/* c/keys.c */
extern void keycheck(void), leave_memories(void), next_vip(void),
	remember_vip(void), save_memory_ctcss(void);
extern void def_memo(uint8_t k), dokey_not_menu(uint8_t k),
	go_mem_a(uint8_t m), handle_key_during_tx(uint8_t k);

/* c/menu.c (bank 1): fsk.c compares their addresses */
extern void menu_rfc_change(uint8_t d), menu_sql_change(uint8_t d),
	menu_sqB_change(uint8_t d);

/* c/ptt.c */
extern void aprs_ptt_check(void), beep1750(void), pttcheck(void),
	spontaneous_mprs_check(void), tx_error(void);

/* c/scan.c */
extern void add_reject(void), clear_rejects(void), scanner_run(void),
	scanner_start(void), scanner_stop(void);
extern void toggle_scan_mask(uint8_t k);

/* c/squelch_crc.c */
extern void append_short_packet_crc(void), append_long_packet_crc(void),
	append_secret_packet_crc(void);

/* c/timers.c */
extern void battcheck(void);

#endif
