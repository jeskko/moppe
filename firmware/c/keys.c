/*
 * Key dispatch and key handlers in C (Phase 4, notes/hybrid-plan.md).
 * Built with `make C=1`; replaces keycheck, dokey, dokey_not_menu,
 * menu_input, handle_key_during_tx, the handlers they call (execute,
 * monitor, the long-digit functions, volume, digit entry and backspace,
 * duplex/scanner/star keys) and the memories and VIP list (store/recall,
 * go_mem_a, remember_vip/next_vip) of r58.s (see the C_MODULES blocks
 * there).  Stay assembler: the volume/OUT0 writer set_vola_a, the
 * squelch forcing (DI), is_key_down/waitkey, the feedback text stubs,
 * clear_buffer/clear_key (asm callers keep A), point_ix_memory (IX) and
 * compare_tx_rx_freq (flags) for their asm callers, beep1750 and
 * set_tx_freq/set_duplex_shift_* (with the PTT/TX flow and the frequency
 * kernel).
 *
 * Every handler takes the key code in A, which is where --sdcccall 1
 * passes a uint8_t argument (checked: none reads B or C before writing
 * them).  The handlers do not preserve IX, so no function here has a
 * stack frame.  Mainline only.
 *
 * Key codes: 0-9 digits, '#', '*', 'C', 'E', 'B', 'S', 'R', 'K', 'T',
 * '+', '-'; 0x0B/0x0C/0x0E are B/C/E from the CU53AN; 0x80-0x89 long
 * presses of 0-9.
 */
#include <stdint.h>

#define NUM_MEMORIES	130
#define MEM_DEFAULT	99		/* point_ix_memory: out of range -> 99 */
#define MEM_SIZE	12		/* record layout asserted in r58.s */
#define MEM_FLAGS	6
#define MEM_CTCSST	7
#define MEM_BAND	8
#define MEM_CTCSSR	9
#define MEM_FOO2	10
#define MEM_FOO3	11
#define MEM_VALID	0x01
#define MEM_HIDDEN	0x02
#define MEM_SCANNABLE	0x04
#define VIP_COUNT	10
#define DIGBUF_SIZE	16
#define KEYDOWN_LONG	20		/* 10 ms ticks: 200 ms */

extern uint8_t key, menu_active, cu_is_alfa, scan_on, digidx, digbuf[DIGBUF_SIZE],
	vip_idx, vip_list[3 * VIP_COUNT], vip_freq[3], mem_idx, mem_flags,
	memories[NUM_MEMORIES * MEM_SIZE], rx_freq[3], tx_freq[3], volume,
	cfg_def_volume, cfg_def_memory, cfg_def_frequency[3], cfg_squelch_level,
	cfg_def_squelch, squelch_forced, band_step, mem_ctcss_tx_hz,
	mem_ctcss_rx_hz, cfg_implied[3];
extern volatile uint8_t key_time, keydown;	/* keypad interrupt */

extern void clear_key(void);			/* preserves A */
extern void no_feedback(void);
extern void open_selective(void);
extern void redraw(void);
extern uint8_t is_key_down(void);		/* A = keydown; clears key when up */
extern void waitkey(void);
extern void feedback_default(void), feedback_stored(void), feedback_reject(void),
	feedback_cleared(void), feedback_shift_neg(void), feedback_shift_pos(void),
	feedback_split(void);
extern void save_nvdata(void), force_squelch(void), unforce_squelch(void),
	far_decoder_hist_rewind(void), far_send_call_packet(void), beep1750(void),
	set_duplex_shift_neg(void), set_duplex_shift_pos(void), set_tx_freq(void),
	set_channel_step(void);
extern void set_vola_a(uint8_t v);		/* clamps to 0..9, drives OUT0 */
extern uint8_t a2i_byte(void);			/* digits -> A (0xFF if > 255) */
extern void keys_a2i(uint8_t *p);		/* digits -> 24 bits at p */
/* c/freq.c, c/scan.c */
extern void changed_frequency(void), changed_frequency_duplex_okay(void),
	temporary_change_rx_freq(void), locate_band(void),
	set_duplex_from_tx_rx(void), step_duplex_state(void),
	step_channel_up(void), step_channel_down(void), scanner_start(void),
	scanner_stop(void), add_reject(void), clear_rejects(void),
	toggle_scan_mask(uint8_t k);

extern void mute_squelch_selective(uint8_t), far_toggle_or_position_menu(uint8_t),
	step_audio_dst(uint8_t),
	far_menu_enter_or_walk(uint8_t), far_menu_defval_or_exec(uint8_t),
	far_menu_up_value(uint8_t), far_menu_dn_value(uint8_t),
	far_menu_next_group(uint8_t), far_menu_prev(uint8_t),
	step_txpwr_up(uint8_t), step_txpwr_down(uint8_t),
	dtmf_cu58af(uint8_t), dtmf_bang_tone(uint8_t);

void execute(uint8_t k), monitor_audio(uint8_t k), up_freq(uint8_t k),
	dn_freq(uint8_t k), def_sqlv(uint8_t k), up_sqlv(uint8_t k),
	dn_sqlv(uint8_t k), up_vola(uint8_t k), dn_vola(uint8_t k),
	insdig_or_scan_toggle(uint8_t k), insdig(uint8_t k), backspace(uint8_t k),
	insdig_punct(uint8_t k), insdig_alpha(uint8_t k), duplex_key(uint8_t k),
	beep_or_fsk_send(uint8_t k), scanner_key(uint8_t k), def_vola(uint8_t k),
	def_memo(uint8_t k), def_freq(uint8_t k), up_memo(uint8_t k),
	dn_memo(uint8_t k);
void go_mem_a(uint8_t m), remember_vip(void), next_vip(void),
	leave_memories(void), fill_implied(void);
static void save_memory(void), go_mem(void);

void dokey_not_menu(uint8_t k)
{
	if (k < 10) {
		insdig_or_scan_toggle(k);
		return;
	}
	switch (k) {
	case 'T':	mute_squelch_selective(k); break;
	case '#':	execute(k); break;
	case 'C':
	case 0x0C:	backspace(k); break;
	case 'E':
	case 0x0E:	far_toggle_or_position_menu(k); break;
	case '*':	beep_or_fsk_send(k); break;
	case '+':	up_vola(k); break;
	case '-':	dn_vola(k); break;
	case 'B':
	case 0x0B:	monitor_audio(k); break;
	case 0x81:	up_sqlv(k); break;
	case 0x84:	dn_sqlv(k); break;
	case 0x87:	def_sqlv(k); break;
	case 0x82:	up_memo(k); break;
	case 0x85:	dn_memo(k); break;
	case 0x88:	def_memo(k); break;
	case 0x83:	up_freq(k); break;
	case 0x86:	dn_freq(k); break;
	case 0x89:	def_freq(k); break;
	case 0x80:	def_vola(k); break;
	case 'S':	scanner_key(k); break;
	case 'R':	duplex_key(k); break;
	case 'K':	step_audio_dst(k); break;
	}
}

static void menu_input(uint8_t k)
{
	if (k < 10) {
		insdig(k);
		return;
	}
	if (k >= 0x81 && k <= 0x89) {		/* long digit: letters */
		insdig_alpha(k);
		return;
	}
	switch (k) {
	case 'C':
	case 0x0C:	backspace(k); break;
	case 'E':
	case 0x0E:	far_toggle_or_position_menu(k); break;
	case '#':	far_menu_enter_or_walk(k); break;
	case '*':	far_menu_defval_or_exec(k); break;
	case '+':	far_menu_up_value(k); break;
	case '-':	far_menu_dn_value(k); break;
	case 'B':
	case 0x0B:	monitor_audio(k); break;
	case 0x80:	insdig_punct(k); break;	/* long 0: punctuation */
	case 'S':	far_menu_next_group(k); break;
	case 'R':	far_menu_prev(k); break;
	case 'K':	step_audio_dst(k); break;
	}
}

static void dokey(uint8_t k)
{
	if (menu_active)
		menu_input(k);
	else
		dokey_not_menu(k);
}

/* mainloop: one pending key */
static uint8_t pending;			/* static: no stack frame */

void keycheck(void)
{
	if (key == 0xFF)
		return;
	pending = key;
	clear_key();
	dokey(pending);
	no_feedback();
	open_selective();
	redraw();
}

/* from pttcheck while transmitting: +/- step the TX power, others send
 * DTMF */
void handle_key_during_tx(uint8_t k)
{
	clear_key();
	if (k == '+')
		step_txpwr_up(k);
	else if (k == '-')
		step_txpwr_down(k);
	else if (cu_is_alfa)
		dtmf_cu58af(k);
	else
		dtmf_bang_tone(k);
}

/* ---- helpers (statics throughout: the asm callees may clobber IX) */

static uint8_t *mp;			/* the memory record at hand */
static uint8_t t, n, e;

static uint8_t *memory_rec(uint8_t m)	/* point_ix_memory_a */
{
	if (m >= NUM_MEMORIES)
		m = MEM_DEFAULT;
	return memories + m * MEM_SIZE;
}

static void copy3(uint8_t *d, const uint8_t *s)
{
	d[0] = s[0];
	d[1] = s[1];
	d[2] = s[2];
}

/* redraw while the key is held; 1 once key_time reaches `until`, 0 if
 * the key went up first (the limit in a static: no frame) */
static uint8_t until;

static uint8_t held_until(uint8_t u)
{
	until = u;
	do {
		redraw();
		if (key_time >= until)
			return 1;
	} while (is_key_down());
	return 0;
}

/* ---- '#': frequency/memory entry, VIP walk, memory store */

static void execute_1(void)
{
	do {
		if (key_time) {
			save_memory();		/* long press starting */
			return;
		}
	} while (is_key_down());

	n = digidx;
	if (n == 0) {
		next_vip();			/* just #, no digits */
		return;
	}
	if (n < 3) {
		go_mem();			/* 1...2 digits */
		return;
	}
	if (n < 5)
		fill_implied();			/* 3 or 4 digits, fix to abs. */
	keys_a2i(rx_freq);
	leave_memories();
	remember_vip();
	changed_frequency();
}

void execute(uint8_t k)
{
	(void)k;
	if (scan_on) {
		scanner_stop();			/* just stop it, nothing else */
		return;
	}
	execute_1();
	save_nvdata();
}

/* 3 or 4 digits: the implied beginning of the frequency in front */
void fill_implied(void)
{
	n = digidx == 3 ? 3 : 4;
	t = n;
	do {
		t--;
		digbuf[t + 6 - n] = digbuf[t];
	} while (t);
	t = 6 - n;
	do {
		t--;
		digbuf[t] = cfg_implied[t];
	} while (t);
	digidx = 6;
}

/* ---- 'B': monitor */

static uint8_t mon_rx[3], mon_shifted, mon_forced, mon_long;

void monitor_audio(uint8_t k)
{
	(void)k;
	if (scan_on) {
		scanner_stop();			/* just stops the scanner */
		return;
	}
	/* possibly listen on the repeater input */
	copy3(mon_rx, rx_freq);
	mon_shifted = tx_freq[0] != rx_freq[0] || tx_freq[1] != rx_freq[1] ||
		tx_freq[2] != rx_freq[2];
	if (mon_shifted) {
		copy3(rx_freq, tx_freq);
		temporary_change_rx_freq();
	}
	mon_forced = squelch_forced;		/* which way it was */
	force_squelch();			/* open while the key is down */

	/* wait for the release, "long" after 200 ms */
	mon_long = 0;
	do {
		redraw();
		if (keydown >= KEYDOWN_LONG)
			mon_long = 1;
	} while (is_key_down());

	/* opened above: close if long or already forced, else stay open */
	if (mon_long | mon_forced)
		unforce_squelch();

	if (mon_shifted) {
		copy3(rx_freq, mon_rx);
		temporary_change_rx_freq();
	}
}

/* ---- long digits */

void up_freq(uint8_t k)
{
	(void)k;
	leave_memories();
	digidx = 0;
	scanner_stop();
	step_channel_up();
}

void dn_freq(uint8_t k)
{
	(void)k;
	leave_memories();
	digidx = 0;
	scanner_stop();
	step_channel_down();
}

void def_sqlv(uint8_t k)
{
	(void)k;
	digidx = 0;
	feedback_default();
	redraw();
	do {
		if (key_time >= 2) {		/* held: store as default */
			cfg_def_squelch = cfg_squelch_level;
			feedback_stored();
			waitkey();
			return;
		}
	} while (is_key_down());
	cfg_squelch_level = cfg_def_squelch;
	unforce_squelch();		/* adjusting removes a hard open */
}

void up_sqlv(uint8_t k)
{
	(void)k;
	digidx = 0;
	if (cfg_squelch_level != 255)
		cfg_squelch_level++;
	unforce_squelch();
}

void dn_sqlv(uint8_t k)
{
	(void)k;
	digidx = 0;
	if (cfg_squelch_level)
		cfg_squelch_level--;
	unforce_squelch();
}

void up_vola(uint8_t k)
{
	(void)k;
	set_vola_a(volume + 1);
}

void dn_vola(uint8_t k)
{
	(void)k;
	set_vola_a(volume - 1);
}

void def_vola(uint8_t k)
{
	(void)k;
	digidx = 0;
	feedback_default();
	waitkey();
	set_vola_a(cfg_def_volume);
}

void def_memo(uint8_t k)
{
	(void)k;
	digidx = 0;
	scanner_stop();
	feedback_default();
	waitkey();
	go_mem_a(cfg_def_memory);
}

void def_freq(uint8_t k)
{
	(void)k;
	digidx = 0;
	scanner_stop();
	feedback_default();
	waitkey();
	leave_memories();
	copy3(rx_freq, cfg_def_frequency);
	changed_frequency();
}

/* ---- digit entry */

void insdig_or_scan_toggle(uint8_t k)
{
	if (scan_on)
		toggle_scan_mask(k);
	else
		insdig(k);
}

void insdig(uint8_t k)
{
	if (digidx < DIGBUF_SIZE)
		digbuf[digidx++] = k;
	scanner_stop();
}

void backspace(uint8_t k)
{
	(void)k;
	far_decoder_hist_rewind();
	vip_idx = 0;
	scanner_stop();
	if (keydown >= KEYDOWN_LONG)
		digidx = 0;			/* repeating: clear all */
	else if (digidx)
		digidx--;			/* first press: erase one */
}

static const uint8_t alpha_punct[8] = { '/', '-', '?', '#', '$', '=', '.', 0 };
static const uint8_t alpha_tab[9 * 4] = {
	0xA, 0xB, 0xC, 1,
	0xD, 0xE, 0xF, 2,
	'G', 'H', 'I', 3,
	'J', 'K', 'L', 4,
	'M', 'N', 'O', 5,
	'P', 'Q', 'R', 6,
	'S', 'T', 'U', 7,
	'V', 'W', 'X', 8,
	' ', 'Y', 'Z', 9,
};

/* a held key steps through its characters: the first one is appended
 * (key_time 1), the later ones replace it */
static void insert_alpha(void)
{
	n = digidx;
	if (n >= DIGBUF_SIZE)
		return;				/* buffer full */
	if (n == 0 || key_time == 1) {
		digbuf[n] = e;
		digidx = n + 1;
	} else {
		digbuf[n - 1] = e;
	}
}

void insdig_punct(uint8_t k)			/* long 0 */
{
	(void)k;
	e = alpha_punct[(uint8_t)(key_time - 1) & 7];
	insert_alpha();
}

void insdig_alpha(uint8_t k)			/* long 1-9 */
{
	e = alpha_tab[(uint8_t)(((k & 0xF) - 1) * 4) + ((uint8_t)(key_time - 1) & 3)];
	insert_alpha();
}

/* ---- 'R', '*', 'S' */

void duplex_key(uint8_t k)
{
	(void)k;
	if (digidx < 2 || !held_until(1)) {
		step_duplex_state();		/* simplex/duplex/reverse */
		return;
	}
	feedback_shift_neg();
	if (!held_until(2)) {
		set_duplex_shift_neg();		/* temporary shift override */
		return;
	}
	feedback_shift_pos();
	if (!held_until(3)) {
		set_duplex_shift_pos();
		return;
	}
	feedback_split();
	waitkey();
	set_tx_freq();				/* temporary TX frequency */
}

void beep_or_fsk_send(uint8_t k)
{
	(void)k;
	if (digidx)
		far_send_call_packet();
	else
		beep1750();			/* no digits: repeater beep */
}

void scanner_key(uint8_t k)
{
	(void)k;
	if (!held_until(1)) {
		scanner_start();
		return;
	}
	feedback_reject();
	if (!held_until(2)) {
		add_reject();
		return;
	}
	feedback_cleared();
	waitkey();
	clear_rejects();
}

/* ---- VIP list: the last VIP_COUNT channels, newest first; a memory is
 * stored as (index, 0, 0), a frequency as its 24 bits */

static uint8_t vn[3], vo[3];
static uint8_t *vp;

/* push the current memory/frequency; a duplicate moves to the head */
void remember_vip(void)
{
	copy3(vip_freq, rx_freq);
	if (mem_flags & MEM_VALID) {
		vn[0] = mem_idx;
		vn[1] = 0;
		vn[2] = 0;
	} else {
		copy3(vn, rx_freq);
	}
	vp = vip_list;
	t = VIP_COUNT;
	do {
		copy3(vo, vp);
		copy3(vp, vn);
		copy3(vn, vo);
		if (vn[0] == vip_list[0] && vn[1] == vip_list[1] && vn[2] == vip_list[2])
			return;			/* overwrote the duplicate */
		vp += 3;
	} while (--t);
}

void next_vip(void)
{
	t = vip_idx;
	vip_idx = t + 1 < VIP_COUNT ? t + 1 : 0;
	vp = vip_list + t * 3;
	if (!(vp[2] | vp[1])) {
		go_mem_a(vp[0]);		/* up to 255: a memory */
		return;
	}
	copy3(rx_freq, vp);
	leave_memories();
	changed_frequency();
}

/* ---- memories */

/* '#' held: store into the typed memory (or the current one); held
 * longer: 2 s not scannable, 3 s hidden */
static void save_memory(void)
{
	t = digidx ? a2i_byte() : mem_idx;
	if (t >= NUM_MEMORIES)
		t = MEM_DEFAULT;
	mem_idx = t;

	mem_flags = MEM_VALID | MEM_SCANNABLE;
	redraw();
	do {
		t = mem_flags;
		if (key_time >= 2)
			t = MEM_VALID;
		if (key_time >= 3)
			t = MEM_VALID | MEM_HIDDEN;
		if (mem_flags != t) {
			mem_flags = t;
			redraw();
		}
	} while (is_key_down());

	mp = memory_rec(mem_idx);
	copy3(mp, rx_freq);
	copy3(mp + 3, tx_freq);
	mp[MEM_FLAGS] = mem_flags;
	/* CTCSS is not stored here; the band step is, but not recalled */
	mp[MEM_BAND] = band_step;
	mp[MEM_FOO2] = 0;
	mp[MEM_FOO3] = 0;
	save_nvdata();
}

static uint8_t recallable(uint8_t m)
{
	return (memory_rec(m)[MEM_FLAGS] & (MEM_VALID | MEM_HIDDEN)) == MEM_VALID;
}

/* long 2 / long 5: from the VFO back to the last memory if it can be
 * recalled, else to the next/previous one that can; none: the VFO */
static void step_memory(uint8_t up)
{
	digidx = 0;
	scanner_stop();
	if (!mem_flags && recallable(mem_idx)) {
		go_mem_a(mem_idx);
		return;
	}
	e = (uint8_t)(NUM_MEMORIES + 1);	/* tries */
	do {
		if (up) {
			t = mem_idx + 1;
			if (t >= NUM_MEMORIES)
				t = 0;
		} else {
			t = mem_idx - 1;
			if (t >= NUM_MEMORIES)
				t = (uint8_t)(NUM_MEMORIES - 1);
		}
		mem_idx = t;
		if (recallable(t)) {
			go_mem_a(mem_idx);
			return;
		}
	} while (--e);
	mem_flags = 0;
}

void up_memo(uint8_t k)
{
	(void)k;
	step_memory(1);
}

void dn_memo(uint8_t k)
{
	(void)k;
	step_memory(0);
}

static void go_mem(void)
{
	go_mem_a(a2i_byte());
	remember_vip();
}

void save_memory_ctcss(void)
{
	mp = memory_rec(mem_idx);
	mp[MEM_CTCSST] = mem_ctcss_tx_hz;
	mp[MEM_CTCSSR] = mem_ctcss_rx_hz;
}

void go_mem_a(uint8_t m)
{
	if (m >= NUM_MEMORIES)
		m = MEM_DEFAULT;
	mem_idx = m;
	mp = memory_rec(m);
	copy3(rx_freq, mp);
	copy3(tx_freq, mp + 3);
	locate_band();			/* band presets, overridden below */
	mem_flags = mp[MEM_FLAGS] | MEM_VALID;	/* valid even if cleared */
	mem_ctcss_tx_hz = mp[MEM_CTCSST];
	mem_ctcss_rx_hz = mp[MEM_CTCSSR];	/* not (yet) used */
	set_duplex_from_tx_rx();
	set_channel_step();
	changed_frequency_duplex_okay();	/* keeps the memory's duplex */
}

void leave_memories(void)
{
	mem_flags = 0;
}
