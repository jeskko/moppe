/*
 * Setup menu engine in C, in ROM bank 1 (Phase 4,
 * notes/hybrid-plan.md).  Replaces the bank-1 assembler from init_menu
 * to the RST routines (set_defaults_band ... do_reboot); the assembler
 * originals are in git tag asm-final.  The 285 REC records, the TAB/STR
 * tables, the band defaults and menu_quickspots stay assembler data in
 * bank 1 next to this code; the DYN and RST records point at the
 * routines here.
 *
 * Fixed code enters through the far_* stubs (bank1_call): init_menu,
 * update_gpio12_foo, the key handlers, decoder_hist_rewind, leaved_setup,
 * remote_config_execute (pointer in HL, data in DE here), menu_value_ptr
 * (load_menu_ptr of menu_ptr, for c/fsk.c) and the two drawers, which
 * keep the display cursor in dpy_cursor as c/display.c does.  Register
 * interfaces go through r58.s shims (dpy_*, menu_a2i*).
 *
 * The routines called here do not preserve IX, so nothing has a stack
 * frame: state is static.  Mainline only (never from interrupts).
 */
#pragma bank 1

#include "r58.h"

#define S8C		1
#define S8B		2

/* record types (r58.s CFG_*) */
#define CFG_BYTE	1
#define CFG_WORD	2
#define CFG_FREQ	3
#define CFG_TAB		4
#define CFG_DYN		5
#define CFG_RST		6
#define CFG_STR		7
#define CFG_DPX		8
#define CFG_cSEC	9
#define CFG_EXE		10

/* REC() in r58.s; the offsets are asserted there */
struct rec {
	uint8_t tag[2];
	uint8_t title[6];
	uint8_t *ptr;		/* the variable; DYN: change routine, RST: routine */
	const uint8_t *arg;	/* TAB: the table; DYN: draw routine */
	uint16_t def;
	uint8_t type;
	uint8_t z;
};

typedef void (*step_fn)(uint8_t d);
typedef void (*void_fn)(void);

__sfr __at(0x30) da_rfc;			/* DA_RFC (DA0) */

/* bank 1 data (r58.s) */
extern const struct rec start_menu[], end_menu[], menu_rec_sql[], menu_rec_sqB[];
extern const struct rec *const menu_quickspots[10];
extern const uint8_t defaults_70cm[], defaults_2m[], defaults_6m[];
extern const uint8_t banner[];

extern uint8_t cfg_enter_time, cfg_synth_card, cfg_ctcss_tx_hz,
	cfg_ctcss_rx_hz, cfg_other_step, ccir_hist_idx, dtmf_hist_idx,
	fsk_hist_idx, ccir_hist_finger, dtmf_hist_finger, fsk_hist_finger,
	gps_hist_finger;
extern uint8_t cfg_external_serial_A[2], cfg_external_serial_B[2],
	cfg_if_freq[3], cfg_band2_start[3], ccir_history[256],
	dtmf_history[256], nvstart[], nvend[], end_memories[], end_rfctab[],
	cfg_image_buffer[];

/* firmware routines (assembler) */
extern void draw_lower_colon(void), ctcss_dec_startstop(void),
	feedback_hold(void), feedback_let_go_the_darn_button(void),
	feedback_ready(void), feedback_loading(void), feedback_error(void),
	update_gpio12(void), shift_external_serial_A(void),
	shift_external_serial_B(void), save_rfc(void);

/* r58.s shims */
extern void dpy_val255(uint8_t v);		/* dpyval255 */
extern void dpy_word(uint16_t v);		/* draw_word */
extern void dpy_freq_signed(const uint8_t *f);	/* draw_long_signed */
extern void dpy_str_rj(const uint8_t *s);	/* draw_string_rightjust */
extern void dpy_str_rj_scores(const uint8_t *s);	/* ..._scores */
extern void dpy_history(const uint8_t *at);	/* draw_decoder_history */
extern uint32_t menu_a2i(void);			/* a2i: AHL */
extern uint16_t menu_a2i_word(void);		/* a2i_word: HL */

static const struct rec *r, *rr;
static uint8_t *p, *q;
static const uint8_t *s;
static uint8_t i, n, v, c, t0, t1, sum, card, type, dir;
static uint16_t w, size;
static uint32_t l;

static const uint8_t question_marks[] = { '?', '?', '?', EOS };

static void dpy_str(const char *str)
{
	while (*str)
		dpy_ch(*str++);
}

/* 24-bit values wrap at 24 bits */
static uint32_t get24(const uint8_t *a)
{
	return a[0] | (uint16_t)a[1] << 8 | (uint32_t)a[2] << 16;
}

static void put24(uint8_t *a, uint32_t x)
{
	a[0] = x;
	a[1] = x >> 8;
	a[2] = x >> 16;
}

static void copy3(uint8_t *dst, const uint8_t *src)
{
	dst[0] = src[0];
	dst[1] = src[1];
	dst[2] = src[2];
}

/* ---- the value a record shows and edits (load_menu_ptr) */

static uint8_t *value_ptr(const struct rec *x)
{
	uint8_t *a;

	if (display_buffer_time)
		return remote_display_buffer;	/* a remote config reply */
	a = x->ptr;
	/* on a memory, the CTCSS records edit the memory's copy (CtCSSt is
	 * a TAB record, CtCSSr a BYTE; v3_Z only swapped BYTE records) */
	if (!(mem_flags & MEM_VALID) || (x->type != CFG_BYTE && x->type != CFG_TAB))
		return a;
	if (a == &cfg_ctcss_tx_hz)
		return &mem_ctcss_tx_hz;
	if (a == &cfg_ctcss_rx_hz)
		return &mem_ctcss_rx_hz;
	return a;
}

uint8_t *menu_value_ptr(void)
{
	return value_ptr(menu_ptr);
}

void init_menu(void)
{
	menu_ptr = start_menu;
}

void leaved_setup(void)
{
	if (mem_flags & MEM_VALID)
		save_memory_ctcss();
	ctcss_dec_startstop();
	save_nvdata();
}

void update_gpio12_foo(void)
{
	__asm__("di");
	update_gpio12();
	__asm__("ei");
}

/* ---- drawing */

/* 6 characters of title, two more blanks on an alpha handset */
void draw_menu_title(void)
{
	clear_upper_colons();
	r = menu_ptr;
	for (i = 0; i < 6; i++)
		dpy_ch(r->title[i]);
	if (cu_is_alfa) {
		dpy_ch(' ');
		dpy_ch(' ');
	}
}

/* TT:b1234567, where :b is not on a CU58AF */
void draw_menu_lower_row(void)
{
	r = menu_ptr;
	dpy_ch(r->tag[0]);
	dpy_ch(r->tag[1]);
	if (!cu_is_alfa) {
		draw_lower_colon();
		dpy_ch(' ');
	}
	switch (r->type) {
	case CFG_BYTE:
		dpy_str("    ");			/* 3 zero-blanked digits */
		dpy_val255(*value_ptr(r));
		break;
	case CFG_WORD:
		dpy_str("  ");				/* 5 zero-blanked digits */
		p = value_ptr(r);
		dpy_word(p[0] | p[1] << 8);
		break;
	case CFG_FREQ:
		dpy_freq(value_ptr(r));
		break;
	case CFG_TAB:
		v = *value_ptr(r);
		s = r->arg;
		if (v < s[0])
			dpy_str_rj(s + 1 + (uint16_t)v * 8);
		else
			dpy_str_rj(question_marks);
		break;
	case CFG_DYN:
		((void_fn)r->arg)();
		break;
	case CFG_RST:
		dpy_str("  666 ?");
		break;
	case CFG_STR:
		dpy_str_rj_scores(value_ptr(r));
		break;
	case CFG_DPX:
		p = value_ptr(r);
		if (p[0] | p[1] | p[2])
			dpy_freq_signed(p);
		else
			dpy_str("    oFF");
		break;
	case CFG_cSEC:
		dpy_str("   ");			/* NNN0 ms */
		v = *value_ptr(r);
		if (v) {
			dpy_val255(v);
			dpy_ch('0');
		} else
			dpy_str("   0");
		break;
	default:
		dpy_str("???????");
	}
}

/* ---- DYN records: change routine (d = +1, -1, or 0 for the typed
 * number) and draw routine */

static void draw_remote_dyn_dpy(void)
{
	dpy_val255(remote_display_buffer[0]);
	dpy_ch(' ');
	dpy_val255(remote_display_buffer[1]);
}

void draw_rfc_dpy(void)
{
	if (display_buffer_time) {
		draw_remote_dyn_dpy();
		return;
	}
	dpy_val255(rfc);
	dpy_ch(' ');
	dpy_val255(ad_rssi);
}

void menu_rfc_change(uint8_t d)
{
	if (d != 0xFF && d != 1) {
		rfc = a2i_byte();
		d = 0;
	}
	rfc += d;
	da_rfc = rfc;
	save_rfc();
}

void draw_sql_dpy(void)
{
	if (display_buffer_time) {
		draw_remote_dyn_dpy();
		return;
	}
	dpy_val255(cfg_squelch_level);
	dpy_ch(' ');
	dpy_val255(read_squelcher_value());
}

void draw_sqB_dpy(void)
{
	if (display_buffer_time) {
		draw_remote_dyn_dpy();
		return;
	}
	dpy_val255(cfg_squelch_BIG);
	dpy_ch(' ');
	dpy_val255(ad_rssi);		/* with RSSI, not read_squelcher_value */
}

void menu_sql_change(uint8_t d)
{
	if (d)
		cfg_squelch_level += d;
	else
		cfg_squelch_level = a2i_byte();
}

void menu_sqB_change(uint8_t d)
{
	if (d)
		cfg_squelch_BIG += d;
	else
		cfg_squelch_BIG = a2i_byte();
}

void decoder_hist_rewind(void)
{
	ccir_hist_finger = ccir_hist_idx - 1;	/* usually past the last blank */
	dtmf_hist_finger = dtmf_hist_idx - 1;
	fsk_hist_finger = fsk_hist_idx - 1;
	gps_hist_finger = gps_hist_idx - 1;
}

void ccir_hist_walk(uint8_t d) { ccir_hist_finger += d; }
void dtmf_hist_walk(uint8_t d) { dtmf_hist_finger += d; }
void fsk_hist_walk(uint8_t d) { fsk_hist_finger += d; }
void gps_hist_walk(uint8_t d) { gps_hist_finger += d; }

/* the finger is an offset in the history's page */
#define PAGE(h, off)	((const uint8_t *)(((uint16_t)(h) & 0xFF00) | (off)))

void draw_ccir_hist(void) { dpy_history(PAGE(ccir_history, ccir_hist_finger)); }
void draw_dtmf_hist(void) { dpy_history(PAGE(dtmf_history, dtmf_hist_finger)); }
void draw_fsk_hist(void) { dpy_history(PAGE(fsk_history, fsk_hist_finger)); }
void draw_gps_hist(void) { dpy_history(PAGE(gps_history, gps_hist_finger)); }

/* ---- ENT: toggle the menu, or go to group/record by digits */

/* the ENT safety delay: 1 if held long enough */
static uint8_t enter_safety_delay(void)
{
	feedback_hold();
	redraw();
	for (;;) {
		v = key_time;
		c = cfg_enter_time;
		if (c >= 10)
			c = 10;			/* the limit is clamped at 10 */
		if (c < v)
			break;			/* long enough */
		if (!is_key_down()) {
			clear_buffer();
			clear_key();
			no_feedback();
			redraw();
			return 0;
		}
	}
	feedback_let_go_the_darn_button();
	redraw();
	waitkey();
	clear_key();
	no_feedback();
	return 1;
}

void toggle_or_position_menu(void)
{
	if (!menu_active && cfg_enter_time && !enter_safety_delay())
		return;				/* too short a press */

	n = digidx;
	if (!n) {				/* just ENT: toggle setup */
		menu_active ^= 1;
		if (!menu_active)
			leaved_setup();
		return;
	}
	/* group t0, record t1 */
	if (n == 1) {
		t0 = digbuf[0];
		t1 = 0;
	} else if (n == 2) {
		t0 = digbuf[0];
		t1 = digbuf[1];
	} else {
		l = menu_a2i();
		t0 = l / 100;			/* the low byte of the quotient */
		t1 = l % 100;
	}
	if (t0 >= 10)
		t0 = 9;				/* someone might alpha-input these */
	/* the records end in 255 * 16 bytes of address space (asserted) */
	r = (const struct rec *)((uint16_t)menu_quickspots[t0] + (uint16_t)t1 * sizeof(struct rec));
	if (r >= end_menu)
		r = end_menu - 1;		/* stick at the last */
	menu_ptr = r;
	menu_active = 1;
	digidx = 0;
}

/* ---- walking */

static void menu_next(void)
{
	r = menu_ptr + 1;
	if (r == end_menu)
		r = start_menu;
	if (r == start_menu - 1)
		r = end_menu - 1;
	menu_ptr = r;
}

void menu_prev(void)
{
	r = menu_ptr - 1;
	if (r == end_menu)
		r = start_menu;
	if (r == start_menu - 1)
		r = end_menu - 1;
	menu_ptr = r;
}

void menu_next_group(void)
{
	t0 = menu_ptr->tag[0];
	t1 = menu_ptr->tag[1];
	do
		menu_next();
	while (menu_ptr->tag[0] == t0 && menu_ptr->tag[1] == t1);
}

/* ---- changing values */

static void word_value_changed(void)
{
	if (p == cfg_external_serial_A)
		shift_external_serial_A();
	else if (p == cfg_external_serial_B)
		shift_external_serial_B();
}

static void tab_value_changed(void)
{
	if (p == &cfg_gpio1_state || p == &cfg_gpio2_state)
		update_gpio12_foo();
}

/* a DYN record's change routine; the pointer is value_ptr's, i.e. the
 * remote display buffer while a remote config reply is shown */
static void dyn_step(uint8_t d)
{
	if (p)				/* 0: not editable */
		((step_fn)p)(d);
}

/* the typed digits (digbuf, digidx) into the current record */
static void menu_new_value(void)
{
	r = menu_ptr;
	p = value_ptr(r);
	type = r->type;			/* if chains: a switch table spills */
	if (type == CFG_BYTE) {
		v = a2i_byte();		/* not *p = : p would be kept across the call */
		*p = v;
	} else if (type == CFG_WORD) {
		w = menu_a2i_word();
		p[0] = w;
		p[1] = w >> 8;
		word_value_changed();
	} else if (type == CFG_FREQ) {
		put24(p, menu_a2i());
	} else if (type == CFG_TAB) {
		c = *r->arg;			/* count of selections */
		v = a2i_byte();
		if (v >= c)
			v = c - 1;
		*p = v;
		tab_value_changed();
	} else if (type == CFG_DYN) {
		dyn_step(0);
	} else if (type == CFG_RST) {
		((void_fn)p)();
	} else if (type == CFG_STR) {
		for (i = 0; i < SIZE_STR; i++)
			p[i] = EOS;
		n = digidx;
		if (!n)
			return;
		if (n >= SIZE_STR)
			n = SIZE_STR;		/* then no EOS */
		for (i = 0; i < n; i++)
			p[i] = digbuf[i];
	} else if (type == CFG_DPX) {
		l = menu_a2i();
		if (p[2] & 0x80)
			l = -l;			/* keeps the previous sign */
		put24(p, l);
	} else if (type == CFG_cSEC) {
		/* 10 ms digits typed, 1 cs stored: drops the last digit
		 * (notes/open-bugs.md) */
		digidx--;
		v = a2i_byte();
		*p = v;
	}
}

void menu_enter_or_walk(void)
{
	if (!digidx) {
		menu_next();
		return;
	}
	menu_new_value();
	digidx = 0;
}

/* dir: +1 or -1 (0xFF) */
static void menu_step_value(void)
{
	r = menu_ptr;
	p = value_ptr(r);
	type = r->type;
	if (type == CFG_DYN) {
		dyn_step(dir);
	} else if (type == CFG_BYTE || type == CFG_cSEC) {
		*p += dir;
	} else if (type == CFG_TAB) {
		v = *p + dir;
		c = *r->arg;
		if (v == 0xFF)
			v = c - 1;		/* down from 0 */
		if (v >= c)
			v = 0;			/* up from the last */
		*p = v;
		tab_value_changed();
	} else if (type == CFG_WORD) {
		w = (p[0] | p[1] << 8) + (dir == 1 ? 1 : -1);
		p[0] = w;
		p[1] = w >> 8;
		word_value_changed();
	} else if (type == CFG_FREQ) {
		/* get_probable_chstep_de */
		w = cfg_synth_card == S8B ? 20 : 25;
		l = get24(p);
		put24(p, dir == 1 ? l + w : l - w);
	} else if (type == CFG_DPX) {
		put24(p, -get24(p));		/* flip the sign */
	}
}

void menu_up_value(void)
{
	dir = 1;
	menu_step_value();
}

void menu_dn_value(void)
{
	dir = 0xFF;
	menu_step_value();
}

/* ---- defaults */

static void reset_menurec(const struct rec *x)
{
	switch (x->type) {
	case CFG_BYTE:
	case CFG_TAB:
	case CFG_cSEC:
		*value_ptr(x) = x->def;
		break;
	case CFG_WORD:
		q = value_ptr(x);
		q[0] = x->def;
		q[1] = x->def >> 8;
		break;
	case CFG_STR:
		*value_ptr(x) = EOS;
		break;
	}
}

void menu_defval_or_exec(void)
{
	r = menu_ptr;
	p = value_ptr(r);
	switch (r->type) {
	case CFG_DPX:
		copy3(p, cfg_other_duplex);
		break;
	case CFG_FREQ:
		copy3(p, rx_freq);		/* from the VFO */
		break;
	case CFG_EXE:
		((void_fn)p)();
		break;
	default:
		reset_menurec(r);
	}
}

/* ---- remote configuration: digits for the record of a variable */

/* ptr: a variable's address, or 0..3 = VERSION, RFC, SQL, SQL BI; data:
 * nibble pairs (wrapping in its page) up to EOS */
void remote_config_execute(uint16_t ptr, const uint8_t *data)
{
	w = ptr;
	s = data;
	if (!(w >> 8)) {
		if ((uint8_t)w == 2)
			r = menu_rec_sql;
		else if ((uint8_t)w == 3)
			r = menu_rec_sqB;
		else
			return;
	} else {
		/* the search looks at the record at end_menu too (TAB data) */
		for (r = start_menu; (uint16_t)r->ptr != w; r++)
			if (r == end_menu)
				return;		/* no such record */
	}
	menu_ptr = r;

	/* act as remote data in digbuf */
	i = (uint8_t)(uint16_t)s;
	for (n = 0; n < SIZE_STR; n++) {
		v = *PAGE(s, i) << 4;
		i++;
		v |= *PAGE(s, i);
		i++;
		if (v == EOS)
			break;
		digbuf[n] = v;
	}
	digidx = n;
	menu_new_value();
	digidx = 0;
}

/* ---- RST records (confirmed with 666) */

/* fill [a, b) with 0 (a leaf: the pointers stay in registers) */
static void zero(uint8_t *a, const uint8_t *b)
{
	do
		*a++ = 0;
	while (a != b);
}

/* the received image to NV (a leaf) */
static void image_to_nv(const uint8_t *src)
{
	uint8_t *a = nvstart;

	do
		*a++ = *src++;
	while (a != nvend);
}

static uint8_t is_666(void)
{
	return menu_a2i() == 666;
}

static void reset_menurecords(void)
{
	for (rr = start_menu; rr != end_menu; rr++)
		reset_menurec(rr);
}

static void copy_default(uint8_t *dst, uint8_t len)
{
	while (len--)
		*dst++ = *s++;
}

static void set_defaults_band(void)
{
	card = cfg_synth_card;
	reset_menurecords();			/* keep the radio type */
	cfg_synth_card = card;
	if (card == S8B)
		s = defaults_6m;
	else if (card == S8C)
		s = defaults_2m;
	else
		s = defaults_70cm;
	copy_default(cfg_implied, 6);
	copy_default(cfg_if_freq, 3);
	copy_default(cfg_rx_vco_center, 3);
	copy_default(cfg_tx_vco_center, 3);
	copy_default(cfg_tx_band_start, 6);	/* and end */
	copy_default(cfg_band1_start, 10);	/* and end, duplex, step */
	copy_default(cfg_band2_start, 10);
	copy_default(cfg_other_duplex, 3);
	copy_default(&cfg_other_step, 1);
	save_nvdata();
	powerdown_now();
}

void sane_defaults(void)
{
	if (is_666())
		set_defaults_band();
}

void disaster(void)
{
	if (!is_666())
		return;
	card = cfg_synth_card;
	zero(nvstart, nvend);
	cfg_synth_card = card;
	set_defaults_band();
}

void all_config_send(void)
{
	if (!is_666())
		return;
	for (s = banner; *s != EOS; s++)
		fsk_putchar(*s);		/* banner line */
	size = nvend - nvstart;
	fsk_putchar(size);
	fsk_putchar(size >> 8);			/* length, a binary word */
	sum = 0;
	for (q = nvstart; q != nvend; q++) {
		v = *q;
		sum += v;
		fsk_putchar(v);
	}
	fsk_putchar(-sum);			/* data + checksum == 0 */
}

void all_config_get(void)
{
	if (!is_666())
		return;
	while (mbusrx_cnt)
		getchar();			/* purge old */
	feedback_ready();
	force_redraw();
	v = getchar();				/* first character of the banner */
	feedback_loading();
	force_redraw();
	while (v != 0x0A)			/* end of the banner */
		v = getchar();

	size = nvend - nvstart;
	if (getchar() != (uint8_t)size || getchar() != (uint8_t)(size >> 8))
		goto failed;
	sum = 0;
	for (q = cfg_image_buffer; q != cfg_image_buffer + size; q++) {
		v = getchar();
		*q = v;
		sum += v;
	}
	if ((uint8_t)(getchar() + sum))
		goto failed;
	image_to_nv(cfg_image_buffer);
	no_feedback();
	redraw();
	return;
failed:
	feedback_error();
	redraw();
}

void wipe_memories(void)
{
	if (!is_666())
		return;
	zero(memories, end_memories);
}

void wipe_rfctab(void)
{
	if (!is_666())
		return;
	zero(rfctab, end_rfctab);
}

void do_reboot(void)
{
	if (!is_666())
		return;
	__asm__("di");
	for (;;)
		;				/* the watchdog restarts */
}
