/*
 * The scanner in C (Phase 4, notes/hybrid-plan.md), fixed ROM.
 * Replaces is_freq_rejected_temp ... the scan tail wait of r58.s (the
 * reject lists, scan masks, the slice table and the scan state machine;
 * the assembler original is in git tag asm-final).
 * load_num_tmp_rejects and unreject_timer stay assembler (the minute
 * timer calls them).
 *
 * The assembler scanner was a coroutine: scanner_run jumped to the
 * address in scanner_state, and each `call scanner_ret` stored its return
 * address there and returned to the mainloop.  Here scanner_state holds a
 * state number (its low byte) for each of those resume points, and the
 * code between the labels is split into block functions (scanner_run's
 * table) that return the next block or a yield: every mainloop pass does
 * what the assembler did in that pass.  scanner_start, toggle_scan_mask
 * and add_reject restart it at S_STEP (scan_do_step).
 *
 * Mainline only; the scan timers it waits on are counted in interrupts.
 * The routines called here do not preserve IX: no stack frames.
 */
#include "r58.h"

#define NUM_TMP_REJECTS	20
#define MDM_DCD		0x04

/* a scan slice: two 24-bit frequencies, start and end (asm: 2 * SIZE_FREQ,
 * SIZE_FREQ) */
#define SLICE		6
#define SL_END		3

/* resume points of the assembler coroutine */
#define S_STEP		0		/* scan_do_step */
#define S_FIRST_FREQ	1		/* scan_first_frequency */
#define S_FIRST_MEM	2		/* scan_first_memory */
#define S_WAIT		3		/* the settling wait */
#define S_LISTEN	4		/* on a channel: patience, signal */
#define S_TAIL		5		/* the tail after the signal */

__sfr __at(0xA3) mdm_ctrl;			/* MDM + MDMCTRL */

extern uint8_t scan_slicecnt, cfg_unreject_mins, cfg_scan_skip_fsk_channels,
	reject_idx;
extern volatile uint8_t scan_timer, scan_timer_secs;
extern uint16_t scanner_state;
extern uint8_t scan_slices[NUM_BANDRECS * SLICE],
	tmp_rejects[NUM_TMP_REJECTS * 4];
extern const uint8_t cfg_reject_0[30], cfg_reject_10[30];

/* firmware routines (assembler) */
extern void draw_scanner_icon(void), clear_scanner_icon(void),
	mute_squelch_scanner(void), restore_squelch_scanner(void);
extern uint8_t load_num_tmp_rejects(void);

static uint8_t *sl, *p, *q;
static const uint8_t *s;
static uint8_t n, m, v, c, i, j;
static uint16_t w;

/* a < b, 24 bits; bytewise (this runs for every channel) */
static uint8_t lt24(const uint8_t *a, const uint8_t *b)
{
	if (a[2] != b[2])
		return a[2] < b[2];
	if (a[1] != b[1])
		return a[1] < b[1];
	return a[0] < b[0];
}

/* ---- rejects */

/* these run for every channel: loops without calls */
static uint8_t is_freq_rejected_temp(void)
{
	n = load_num_tmp_rejects();
	for (q = tmp_rejects; n; n--, q += 4)
		if (q[3] /* timer 0: stale */ && q[0] == rx_freq[0] &&
		    q[1] == rx_freq[1] && q[2] == rx_freq[2])
			return 1;
	return 0;
}

static uint8_t ten_rejects(const uint8_t *a)
{
	for (n = 10; n; n--, a += 3)
		if (a[0] == rx_freq[0] && a[1] == rx_freq[1] && a[2] == rx_freq[2])
			return 1;
	return 0;
}

static uint8_t is_freq_rejected_perm(void)
{
	return ten_rejects(cfg_reject_0) || ten_rejects(cfg_reject_10);	/* 10 + 10 */
}

void clear_rejects(void)
{
	for (q = tmp_rejects; q != tmp_rejects + NUM_TMP_REJECTS * 4; q++)
		*q = 0;
}

/* the current frequency (the VIP one while scanning) into tmp_rejects:
 * its own slot if listed, else the oldest, else the next round robin */
void add_reject(void)
{
	s = scan_on ? vip_freq : rx_freq;
	n = load_num_tmp_rejects();
	c = 255;				/* 255 does not crawl down */
	for (p = tmp_rejects, i = n; i; i--, p += 4) {
		if (p[0] == s[0] && p[1] == s[1] && p[2] == s[2])
			goto out;		/* found: the same slot */
		v = p[3];
		if (v < c) {
			q = p;			/* an older one */
			c = v;
		}
	}
	if (c != 255) {
		p = q;
	} else {
		v = reject_idx + 1;
		if (v >= n)
			v = 0;
		reject_idx = v;
		p = tmp_rejects + v * 4;
	}
out:
	copy3(p, s);
	v = cfg_unreject_mins;
	p[3] = v ? v : 255;			/* 0 behaves as 255 */
	scanner_state = S_STEP;
}

/* ---- scan masks: bits 0..5 bands 1..6, 6..15 memory blocks 0x..9x */

/* digits typed before S */
static uint16_t digit_to_scan_mask(uint8_t d)
{
	if (d >= 1 && d <= 6)
		return 1 << (d - 1);
	if (d >= 7 && d <= 9)
		return 0x2000 << (d - 7);
	return 0x1FC0;				/* 0 (and letters): blocks 0x..6x */
}

/* a digit while scanning toggles memory block dx */
void toggle_scan_mask(uint8_t d)
{
	if (d <= 9)
		scan_mask ^= 0x40 << d;
	scanner_state = S_STEP;
}

/* the first scanned memory from k on, 100 if none: valid and scannable,
 * its block (0x..9x = scan_mask bits 6..15; 9x takes 90..99) in the mask.
 * The assembler tested the block bit of every memory; this skips a whole
 * block when its bit is clear (same result, less work: up to 100
 * memories a step) */
static const uint8_t *mf;
static uint8_t mk, mnext;
static uint16_t mbit;

static uint8_t memory_from(uint8_t k)
{
	mk = k;
	mf = memories + MEM_FLAGS + k * MEM_SIZE;
	/* k's block; k >= 100 shifts mbit off the top (unused: mk < 100
	 * below is false already, so mnext/mbit's end value never matters) */
	for (mnext = 10, mbit = 0x40; mk >= mnext; mnext += 10)
		mbit <<= 1;
	while (mk < 100) {
		if (scan_mask & mbit) {
			for (; mk < mnext; mk++, mf += MEM_SIZE)
				if ((*mf & (MEM_VALID | MEM_SCANNABLE)) == (MEM_VALID | MEM_SCANNABLE))
					return mk;
		} else {
			for (; mk < mnext; mk++)
				mf += MEM_SIZE;
		}
		mnext += 10;
		mbit <<= 1;
	}
	return 100;
}

/* the scanned bands, sorted by start frequency, overlapping ones merged
 * into one slice: v3_Z kept them apart, and stepping out of a slice's
 * end to the next one's start, which lay inside it, looped between the
 * two for ever (user, 2026-10-01).  A merged slice is stepped with the
 * band of each frequency (locate_band: the lowest-numbered one), so the
 * scanner visits every frequency of the bands once per round. */
static void build_scan_slicetab(void)
{
	/* c: the bands left out (not in the mask, or empty: start 0) */
	c = 0;
	for (i = 0, v = 1, s = cfg_band1_start; i < NUM_BANDRECS; i++, v <<= 1, s += SIZE_BANDREC)
		if (!((uint8_t)scan_mask & v) || !(s[0] | s[1] | s[2]))
			c |= v;
	/* the lowest start left next (of equal starts the lower band); it
	 * extends the last slice when it starts inside it */
	n = 0;
	for (;;) {
		q = 0;
		for (i = 0, v = 1, p = cfg_band1_start; i < NUM_BANDRECS; i++, v <<= 1, p += SIZE_BANDREC)
			if (!(c & v) && (!q || lt24(p, q))) {
				q = p;
				m = v;
			}
		if (!q)
			break;
		c |= m;
		if (n && lt24(q, sl + SL_END)) {
			if (lt24(sl + SL_END, q + SL_END))
				copy3(sl + SL_END, q + SL_END);
			continue;
		}
		sl = n ? sl + SLICE : scan_slices;
		for (j = 0; j < SLICE; j++)
			sl[j] = q[j];		/* start, end */
		n++;
	}
	scan_slicecnt = n;
}

void scanner_start(void)
{
	unforce_squelch();
	draw_scanner_icon();
	scanner_state = S_STEP;
	w = scan_mask;				/* a lone S: the previous mask */
	if (digidx) {
		w = 0;
		for (i = 0; i < digidx; i++)
			w |= digit_to_scan_mask(digbuf[i]);
	}
	if (!w)
		w = 0x0003;			/* none given and no previous */
	scan_mask = w;
	clear_buffer();
	build_scan_slicetab();
	scan_on = 1;
}

void scanner_stop(void)
{
	if (!scan_on)
		return;
	scan_on = 0;
	vip_idx = 0;				/* next_vip: the most recent */
	restore_squelch_scanner();
	clear_scanner_icon();
	next_vip();
}

/* ---- the scan, once per mainloop pass */

/* like squelch_open, but without the hysteresis and slowness */
static uint8_t is_sql_over_level(void)
{
	return read_squelcher_value() > cfg_squelch_level;
}

/* The scan as the blocks between the assembler coroutine's labels: each
 * does what that block did and returns the next block, or YIELD(state):
 * store the state, back to the mainloop.  The resume blocks are numbered
 * as the states.  (As one function with gotos and a switch into its
 * middle, SDCC's register allocator searched for minutes: 2026-10-01.) */
#define YIELD(st)	(0x80 | (st))
#define B_STEP		S_STEP		/* the resume points ... */
#define B_FIRST_FREQ_ON	S_FIRST_FREQ
#define B_FIRST_MEM_ON	S_FIRST_MEM
#define B_WAIT_ON	S_WAIT
#define B_LISTEN_ON	S_LISTEN
#define B_TAIL_ON	S_TAIL
#define B_NEXT_MEMORY	6		/* ... and the blocks between */
#define B_MEMORY_FOUND	7
#define B_DID_STEP_FREQ	8
#define B_DID_STEP	9
#define B_SIGNAL	10
#define B_TAIL		11
#define B_MAYBE_REJECT	12

#define FIRST_FREQUENCY	YIELD(S_FIRST_FREQ)	/* scan_first_frequency: */
#define FIRST_MEMORY	YIELD(S_FIRST_MEM)	/* a way out for the keys */

/* scan_do_step, scan_next_frequency: the slice we are in, then one
 * channel up */
static uint8_t b_step(void)
{
	scan_paused = 0;
	redraw();
	mute_squelch_scanner();
	if (mem_flags)
		return B_NEXT_MEMORY;
	if (!scan_slicecnt)
		return FIRST_MEMORY;
	for (n = scan_slicecnt, sl = scan_slices; !lt24(rx_freq, sl + SL_END); sl += SLICE)
		if (!--n)
			return FIRST_MEMORY;	/* past all slices */
	if (lt24(rx_freq, sl)) {
		copy3(rx_freq, sl);		/* below it: to its start */
		changed_frequency();
		return B_DID_STEP_FREQ;
	}
	step_channel_up();
	if (lt24(rx_freq, sl + SL_END))
		return B_DID_STEP_FREQ;		/* still in the slice */
	if (n == 1)
		return FIRST_MEMORY;		/* no slice left */
	sl += SLICE;
	copy3(rx_freq, sl);
	changed_frequency();
	return B_DID_STEP_FREQ;
}

static uint8_t b_first_freq_on(void)
{
	leave_memories();
	if (!scan_slicecnt)
		return FIRST_MEMORY;
	copy3(rx_freq, scan_slices);
	changed_frequency();
	return B_DID_STEP_FREQ;
}

static uint8_t b_first_mem_on(void)
{
	if (!(scan_mask & 0xFFC0))
		return FIRST_FREQUENCY;		/* no memory blocks scanned */
	m = memory_from(0);
	return B_MEMORY_FOUND;
}

static uint8_t b_next_memory(void)
{
	m = mem_idx;
	if (m >= 130)
		m = 99;				/* point_ix_memory_a */
	m = memory_from(m + 1);
	return B_MEMORY_FOUND;
}

static uint8_t b_memory_found(void)
{
	if (m >= 100)
		return FIRST_FREQUENCY;		/* past memory 99: the bands */
	go_mem_a(m);
	return B_DID_STEP;
}

static uint8_t b_did_step(void)
{
	if (is_freq_rejected_temp())
		return YIELD(S_STEP);		/* the next step on the next pass */
	v = scan_settling_time;
	if (squelch_open)			/* busy: twice as long */
		v = v >= 128 ? 255 : v + v;
	__asm__("di");
	scan_timer = v;				/* 10 ms ticks */
	scan_timer_secs = 0;
	__asm__("ei");
	return YIELD(S_WAIT);
}

/* after the settling wait, look around */
static uint8_t b_wait_on(void)
{
	if (scan_timer)
		return YIELD(S_WAIT);
	if (squelch_forced)
		return B_SIGNAL;		/* forced open: as if a signal */
	if (!is_sql_over_level())
		return B_STEP;			/* no signal: next */
	scan_paused = 1;			/* normal display */
	return B_SIGNAL;
}

static uint8_t b_signal(void)
{
	redraw();
	if (band_sclisten != 255)
		scan_patience = band_sclisten;	/* N seconds, signal or not */
	if (cfg_scan_skip_fsk_channels && (mdm_ctrl & MDM_DCD))
		return B_STEP;
	return YIELD(S_LISTEN);
}

static uint8_t b_listen_on(void)
{
	if (band_sclisten != 255 && !scan_patience)
		return B_MAYBE_REJECT;		/* lost patience: next */
	restore_squelch_scanner();		/* audio on */
	if (squelch_forced)
		return B_SIGNAL;		/* forced: for ever, and then some */
	if (!squelch_open)
		return B_TAIL;
	remember_vip();
	return YIELD(S_LISTEN);			/* a signal: stay */
}

/* N seconds without a signal */
static uint8_t b_tail(void)
{
	if (band_sctail != 255) {		/* 255: listen for ever */
		v = band_sctail;
		__asm__("di");
		scan_timer_secs = v;
		scan_timer = v ? 100 : 0;	/* seconds of 100 ticks */
		__asm__("ei");
	}
	return YIELD(S_TAIL);
}

static uint8_t b_tail_on(void)
{
	if (squelch_open)
		return YIELD(S_LISTEN);		/* a signal again */
	if (scan_timer_secs || band_sctail == 255)
		return YIELD(S_TAIL);		/* (v3_Z: 255 stepped on at once) */
	return B_STEP;
}

static uint8_t b_did_step_freq(void)
{
	if (is_freq_rejected_perm())
		return YIELD(S_STEP);		/* the next step on the next pass */
	return B_DID_STEP;
}

static uint8_t b_maybe_reject(void)
{
	if (band_autoreject)
		add_reject();
	return B_STEP;
}

/* by block number */
static uint8_t (*const blocks[])(void) = {
	b_step, b_first_freq_on, b_first_mem_on, b_wait_on, b_listen_on,
	b_tail_on, b_next_memory, b_memory_found, b_did_step_freq,
	b_did_step, b_signal, b_tail, b_maybe_reject,
};

static uint8_t blk;			/* the next block */

void scanner_run(void)
{
	if (!scan_on)
		return;
	blk = (uint8_t)scanner_state;		/* a resume block */
	if (blk > B_MAYBE_REJECT)
		blk = B_STEP;			/* (any other state: a step) */
	do
		blk = blocks[blk]();
	while (!(blk & 0x80));
	scanner_state = blk & 0x7F;
}
