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
 * code between them is the same straight line: every mainloop pass does
 * what the assembler did in that pass.  scanner_start, toggle_scan_mask
 * and add_reject restart it at S_STEP (scan_do_step).
 *
 * Mainline only; the scan timers it waits on are counted in interrupts.
 * The routines called here do not preserve IX: no stack frames.
 */
#include <stdint.h>

#define MEM_SIZE	12		/* asserted in r58.s */
#define MEM_FLAGS	6
#define MEM_VALID	0x01
#define MEM_SCANNABLE	0x04
#define NUM_BANDRECS	6
#define SIZE_BANDREC	14
#define NUM_TMP_REJECTS	20
#define MDM_DCD		0x04

/* resume points of the assembler coroutine */
#define S_STEP		0		/* scan_do_step */
#define S_FIRST_FREQ	1		/* scan_first_frequency */
#define S_FIRST_MEM	2		/* scan_first_memory */
#define S_WAIT		3		/* the settling wait */
#define S_LISTEN	4		/* on a channel: patience, signal */
#define S_TAIL		5		/* the tail after the signal */

__sfr __at(0xA3) mdm_ctrl;			/* MDM + MDMCTRL */

extern uint8_t scan_on, scan_paused, scan_slicecnt, mem_flags, mem_idx, digidx,
	cfg_unreject_mins, cfg_scan_skip_fsk_channels, cfg_squelch_level,
	band_autoreject, band_sctail, band_sclisten, scan_settling_time, vip_idx,
	reject_idx;
extern volatile uint8_t scan_timer, scan_timer_secs, scan_patience, squelch_open,
	squelch_forced;
extern uint16_t scan_mask, scanner_state;
extern uint8_t scan_slices[NUM_BANDRECS * 6], digbuf[16], rx_freq[3], vip_freq[3],
	tmp_rejects[NUM_TMP_REJECTS * 4], memories[];
extern const uint8_t cfg_band1_start[], cfg_reject_0[30], cfg_reject_10[30];

/* firmware routines (assembler, c/freq.c) */
extern void unforce_squelch(void), draw_scanner_icon(void), clear_scanner_icon(void),
	clear_buffer(void), redraw(void), mute_squelch_scanner(void),
	restore_squelch_scanner(void), leave_memories(void), changed_frequency(void),
	step_channel_up(void), go_mem_a(uint8_t m), remember_vip(void), next_vip(void);
extern uint8_t read_squelcher_value(void), load_num_tmp_rejects(void);

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

static void copy3(uint8_t *dst, const uint8_t *src)
{
	dst[0] = src[0];
	dst[1] = src[1];
	dst[2] = src[2];
}

/* ---- rejects */

/* these run for every channel: loops without calls */
static uint8_t is_freq_rejected_temp(void)
{
	n = load_num_tmp_rejects();
	for (q = tmp_rejects; n; n--, q += 4)
		if (q[3] && q[0] == rx_freq[0] && q[1] == rx_freq[1] && q[2] == rx_freq[2])
			return 1;		/* timer 0: stale */
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
	for (mnext = 10, mbit = 0x40; mk >= mnext && mnext < 100; mnext += 10)
		mbit <<= 1;			/* k's block */
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

/* the scanned bands, sorted by start frequency (they may overlap) */
static void build_scan_slicetab(void)
{
	n = 0;
	sl = scan_slices;
	s = cfg_band1_start;
	for (c = 1, i = 0; i < NUM_BANDRECS; i++, s += SIZE_BANDREC, c <<= 1) {
		if (!((uint8_t)scan_mask & c))
			continue;
		if (!(s[0] | s[1] | s[2]))
			continue;		/* empty band */
		for (j = 0; j < 6; j++)
			sl[j] = s[j];		/* start, end */
		sl += 6;
		n++;
	}
	scan_slicecnt = n;
	if (n < 2)
		return;
	for (i = n - 1; i; i--)			/* bubble sort */
		for (j = 0, sl = scan_slices; j < i; j++, sl += 6)
			if (lt24(sl + 6, sl))
				for (m = 0; m < 6; m++) {
					v = sl[m];
					sl[m] = sl[m + 6];
					sl[m + 6] = v;
				}
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

#define YIELD(st)	do { scanner_state = (st); return; } while (0)

void scanner_run(void)
{
	if (!scan_on)
		return;
	switch ((uint8_t)scanner_state) {
	case S_FIRST_FREQ:	goto first_frequency_on;
	case S_FIRST_MEM:	goto first_memory_on;
	case S_WAIT:		goto wait_on;
	case S_LISTEN:		goto listen_on;
	case S_TAIL:		goto tail_on;
	}

step:						/* scan_do_step */
	scan_paused = 0;
	redraw();
	mute_squelch_scanner();
	if (mem_flags)
		goto next_memory;

	/* scan_next_frequency: the slice we are in, then one channel up */
	if (!scan_slicecnt)
		goto first_memory;
	for (n = scan_slicecnt, sl = scan_slices; !lt24(rx_freq, sl + 3); sl += 6)
		if (!--n)
			goto first_memory;	/* past all slices */
	if (lt24(rx_freq, sl)) {
		copy3(rx_freq, sl);		/* below it: to its start */
		changed_frequency();
		goto did_step_freq;
	}
	step_channel_up();
	if (lt24(rx_freq, sl + 3))
		goto did_step_freq;		/* still in the slice */
	if (n == 1)
		goto first_memory;		/* no slice left */
	sl += 6;
	copy3(rx_freq, sl);
	changed_frequency();
	goto did_step_freq;

first_frequency:				/* scan_first_frequency */
	YIELD(S_FIRST_FREQ);			/* a way out for the keys */
first_frequency_on:
	leave_memories();
	if (!scan_slicecnt)
		goto first_memory;
	copy3(rx_freq, scan_slices);
	changed_frequency();
	goto did_step_freq;

first_memory:					/* scan_first_memory */
	YIELD(S_FIRST_MEM);
first_memory_on:
	if (!(scan_mask & 0xFFC0))
		goto first_frequency;		/* no memory blocks scanned */
	m = memory_from(0);
	goto memory_found;
next_memory:
	m = mem_idx;
	if (m >= 130)
		m = 99;				/* point_ix_memory_a */
	m = memory_from(m + 1);
memory_found:
	if (m >= 100)
		goto first_frequency;		/* past memory 99: the bands */
	go_mem_a(m);
	goto did_step;

did_step_freq:
	if (is_freq_rejected_perm())
		goto step_again;
did_step:
	if (is_freq_rejected_temp())
		goto step_again;
	v = scan_settling_time;
	if (squelch_open)			/* busy: twice as long */
		v = v >= 128 ? 255 : v + v;
	__asm__("di");
	scan_timer = v;				/* 10 ms ticks */
	scan_timer_secs = 0;
	__asm__("ei");
wait:
	YIELD(S_WAIT);
wait_on:
	if (scan_timer)
		goto wait;

	/* after the settling wait, look around */
	if (squelch_forced)
		goto signal;			/* forced open: as if a signal */
	if (!is_sql_over_level())
		goto step;			/* no signal: next */
	scan_paused = 1;			/* normal display */
signal:
	redraw();
	if (band_sclisten != 255)
		scan_patience = band_sclisten;	/* N seconds, signal or not */
	if (cfg_scan_skip_fsk_channels && (mdm_ctrl & MDM_DCD))
		goto step;
listen:
	YIELD(S_LISTEN);
listen_on:
	if (band_sclisten != 255 && !scan_patience)
		goto maybe_reject;		/* lost patience: next */
	restore_squelch_scanner();		/* audio on */
	if (squelch_forced)
		goto signal;			/* forced: for ever, and then some */
	if (!squelch_open)
		goto tail;
	remember_vip();
	goto listen;				/* a signal: stay */

tail:						/* N seconds without a signal */
	if (band_sctail != 255) {		/* 255: listen for ever */
		v = band_sctail;
		__asm__("di");
		scan_timer_secs = v;
		scan_timer = v ? 100 : 0;	/* seconds of 100 ticks */
		__asm__("ei");
	}
tail_wait:
	YIELD(S_TAIL);
tail_on:
	if (squelch_open)
		goto listen;			/* a signal again */
	if (scan_timer_secs)
		goto tail_wait;
	goto step;

maybe_reject:
	if (band_autoreject)
		add_reject();
	goto step;

step_again:
	YIELD(S_STEP);				/* the next step on the next pass */
}
