/*
 * Display composition in C (Phase 4, notes/hybrid-plan.md).  Replaces
 * draw_upper_row and draw_lower_row of r58.s and the routines only they
 * use (the assembler originals are in git tag asm-final).
 *
 * The assembler threads a display cursor through DE: on a CU53AN it walks
 * a ROM table of segment-bit positions, on a CU58AF a RAM character
 * buffer.  Here it lives in dpy_cursor, and small r58.s shims (dpy_*)
 * load DE, call the assembler primitive and store DE back.  The
 * primitives, the icon/LED bit setters (single set/res instructions,
 * some used by interrupts), redraw (sets DPYSIR atomically) and the
 * feedback texts stay in assembler.
 *
 * The routines called here do not preserve IX (the menu drawers use it),
 * so nothing here has a stack frame: loop state is static.  Mainline only.
 */
#include <stdint.h>

#define EOS		0xFF
#define MEM_VALID	0x01
#define MEM_HIDDEN	0x02
#define MEM_SCANNABLE	0x04

extern const uint8_t *dpy_cursor;
extern const uint8_t CU53AN_segs_u_digit_5[], CU58AF_segs_u_digit_7[],
	CU53AN_segs_bottom_row[], CU58AF_segs_bottom_row[];

extern uint8_t cu_is_alfa, menu_active, call_dpyed, locator_dpyed, volume,
	audio_dst, cfg_squelch_level, cfg_function, txon, srssi,
	call_timer_hour, call_timer_min, call_timer_sec, digidx,
	display_buffer_time, scan_on, scan_paused, squelch_forced, mem_flags,
	mem_idx, packet_good, yucko_alfa_draw_long_6_only;
extern uint8_t locator_display_buffer[], digbuf[], remote_display_buffer[],
	fsk_history[256], rx_freq[3], tx_freq[3];
extern const uint8_t *adj_feedback;
extern uint16_t scan_mask;

/* r58.s shims: the cursor in dpy_cursor */
extern void dpy_ch(uint8_t c);			/* dpydig */
extern void dpy_div9(uint8_t v);		/* 0..255 as 0..9 */
extern void dpy_div99(uint8_t v);		/* 0..255 as 0..99 */
extern void dpy_val99(uint8_t v);		/* 0..99, zero-blanked */
extern void dpy_freq(const uint8_t *f);		/* draw_long of a 24-bit value */
extern void dpy_menu_title(void);		/* bank 1 */
extern void dpy_menu_lower_row(void);		/* bank 1 */

/* firmware routines (assembler) */
extern uint8_t real_txpwr(void);		/* 0..255 */
extern void draw_upper_colons(void), clear_upper_colons(void),
	clear_lower_colon(void);
extern uint8_t get_ctcss_tx_hz(void), get_ctcss_rx_hz(void);	/* VFO or memory */

/* the indicators redraw sets: single segments (constants asserted in
 * r58.s).  Only mainline code writes `segments` (the display interrupt
 * reads it), so a read-modify-write is safe. */
extern uint8_t segments[], dpx_ind_flags;
extern volatile uint8_t squelch_muted, gps_valid_seconds;
#define CU53AN_SEG_V_U		0x43
#define CU53AN_SEG_PHONE	0x47
#define CU53AN_SEG_V_D		0x53
#define CU53AN_SEG_PHONE_NO	0x5B
#define CU53AN_SEG_MAST		0x5F
#define CU53AN_SEG_STAR		0x6B
#define CU53AN_SEG_KEY		0x73
#define CU53AN_SEG_BOOK		0x77
#define CU58AF_SEG_ARROW0	(24 + 4)
#define CU58AF_SEG_ARROW1	(24 + 5)
#define SEG(s, on) do { \
		if (on) \
			segments[(s) >> 3] |= 1 << ((s) & 7); \
		else \
			segments[(s) >> 3] &= ~(1 << ((s) & 7)); \
	} while (0)
void draw_squelch_ind(void), set_dpx_ind_from_rx_tx_freq(void);

static uint8_t n, i, c;
static const uint8_t *p;
static uint16_t m;

static void dpy_str(const char *s)
{
	while (*s)
		dpy_ch(*s++);
}

static void two_spaces_if_alfa(void)
{
	if (cu_is_alfa) {
		dpy_ch(' ');
		dpy_ch(' ');
	}
}

/* ---- upper row */

static void draw_call_timer(void)
{
	if (call_timer_sec & 1)
		draw_upper_colons();
	else
		clear_upper_colons();
	two_spaces_if_alfa();
	dpy_val99(call_timer_hour);
	dpy_val99(call_timer_min);
	dpy_val99(call_timer_sec);
}

static void draw_locator_in_upper_row(void)
{
	clear_upper_colons();
	two_spaces_if_alfa();
	for (i = 0; i < 6; i++)
		dpy_ch(locator_display_buffer[i]);
}

void draw_upper_row(void)
{
	dpy_cursor = cu_is_alfa ? CU58AF_segs_u_digit_7 : CU53AN_segs_u_digit_5;

	if (menu_active) {
		dpy_menu_title();
		return;
	}
	if (call_dpyed) {
		draw_call_timer();
		return;
	}
	if (locator_dpyed) {
		draw_locator_in_upper_row();
		return;
	}

	/* txpwr volume squelch rssi */
	draw_upper_colons();
	dpy_div9(real_txpwr());
	dpy_ch(volume);
	if (cu_is_alfa)				/* where the audio goes */
		dpy_ch(audio_dst == 1 ? '>' : audio_dst == 2 ? '<' : ' ');
	dpy_div99(cfg_squelch_level);
	draw_squelch_ind();
	/* TX power while transmitting (not as a repeater), else RSSI */
	dpy_div99(cfg_function != 1 && txon ? real_txpwr() : srssi);
}

/* ---- lower row: 2 digits lower left, 8 lower right */

static void draw_adjust_feedback(const uint8_t *s)
{
	p = s;
	for (n = cu_is_alfa ? 9 : 10; n; n--) {
		c = *p++;
		dpy_ch(c == EOS ? ' ' : c);
	}
}

static void draw_call_notice(void)
{
	dpy_str("CALL");
	if (!cu_is_alfa)
		dpy_str(" ");
	if (call_dpyed == 1) {			/* FSK call: caller id */
		c = packet_good + 1;		/* wraps in the page */
		for (i = 0; i < 5; i++)
			dpy_ch(fsk_history[c++]);
	} else if (call_dpyed == 2)
		dpy_str(" CCIr");
	else
		dpy_str("  ???");
}

/* scan mask: ABC DEF 0 123 456 789 (bits 0..15), padded with '-' */
static void draw_scan_mask(void)
{
	n = cu_is_alfa ? 9 : 10;
	m = scan_mask;
	c = 0xA;
	do {
		i = m & 1;
		m >>= 1;
		if (i) {
			dpy_ch(c);
			if (!--n)
				return;			/* screen full */
		}
		if (++c == 0x10)
			c = 0;
	} while (m);
	while (n--)
		dpy_ch('-');
}

static void draw_digit_buffer(void)
{
	n = digidx < 10 ? digidx : 10;		/* shown */
	for (i = 0; i < n; i++)
		dpy_ch(digbuf[i]);
	n = 10 - n;				/* blanks */
	if (!n)
		return;
	dpy_ch('_');
	while (--n)
		dpy_ch(' ');
}

static void draw_memory_info(void)
{
	if (cfg_function == 1) {
		dpy_str("rP ");
		return;
	}
	if (!(mem_flags & MEM_VALID)) {
		dpy_str("   ");
		return;
	}
	dpy_val99(mem_idx);
	dpy_ch(mem_flags & MEM_HIDDEN ? '=' :
	       !(mem_flags & MEM_SCANNABLE) ? '-' : ' ');
}

void draw_lower_row(void)
{
	dpy_cursor = cu_is_alfa ? CU58AF_segs_bottom_row : CU53AN_segs_bottom_row;

	/* clear the lower colon unless the menu row is next, which lights it
	 * (v3_Z cleared it first, so a frame sent mid-redraw lost it) */
	if (call_dpyed || adj_feedback || digidx || !menu_active)
		clear_lower_colon();

	if (call_dpyed) {
		draw_call_notice();
		return;
	}
	if (adj_feedback) {
		draw_adjust_feedback(adj_feedback);
		return;
	}
	if (digidx) {
		draw_digit_buffer();
		return;
	}
	if (menu_active) {
		dpy_menu_lower_row();
		return;
	}
	if (display_buffer_time) {
		draw_adjust_feedback(remote_display_buffer);
		return;
	}
	if (scan_on && !scan_paused && !squelch_forced) {
		draw_scan_mask();
		return;
	}

	draw_memory_info();
	set_dpx_ind_from_rx_tx_freq();
	yucko_alfa_draw_long_6_only = cu_is_alfa;
	dpy_freq(txon ? tx_freq : rx_freq);
}

/* ---- indicators */

/* forced squelch: an icon on the CU53AN, '*' at the cursor on the CU58AF */
void draw_squelch_ind(void)
{
	if (cu_is_alfa)
		dpy_ch(squelch_forced ? '*' : ' ');
	else
		SEG(CU53AN_SEG_STAR, squelch_forced);
}

/* the duplex arrows: 1 = TX below RX, 2 = TX above; unchanged if equal */
void set_dpx_ind_from_rx_tx_freq(void)
{
	for (i = 3; i--; ) {
		if (tx_freq[i] != rx_freq[i]) {
			dpx_ind_flags = tx_freq[i] < rx_freq[i] ? 1 : 2;
			return;
		}
	}
}

void draw_dpx_ind(void)
{
	c = dpx_ind_flags;
	if (cu_is_alfa) {
		SEG(CU58AF_SEG_ARROW0, c & 1);
		SEG(CU58AF_SEG_ARROW1, c & 2);
		return;
	}
	SEG(CU53AN_SEG_V_D, c & 1);
	SEG(CU53AN_SEG_V_U, c & 2);
	SEG(CU53AN_SEG_PHONE, display_buffer_time);	/* remote display */
}

/* CTCSS TX/RX, selective mute, GPS fix: CU53AN only */
void draw_ctcss_and_mute_and_gps_ind(void)
{
	if (cu_is_alfa)
		return;
	SEG(CU53AN_SEG_MAST, get_ctcss_tx_hz());
	SEG(CU53AN_SEG_PHONE_NO, get_ctcss_rx_hz());
	SEG(CU53AN_SEG_KEY, squelch_muted & 2);
	SEG(CU53AN_SEG_BOOK, gps_valid_seconds);
}
