/* Channels: the VFO, and memories 00-99 in NV RAM. */
#ifndef MEM_H
#define MEM_H

struct chan {
	unsigned long hz;	/* the frequency shown (RX unless reversed) */
	unsigned long shift;
	unsigned char duplex;	/* DUP_SIMPLEX, DUP_MINUS, DUP_PLUS (ui.h) */
	unsigned char reverse;
	unsigned char tone;	/* CTCSS on TX: index into tone.c, 0 = none */
};

#define NMEM 100

int mem_get(int n, struct chan *c);	/* 0 if channel n is stored */
void mem_put(int n, const struct chan *c);
void mem_clear(int n);
int mem_next(int n, int dir);		/* the next stored one, or -1 */

#endif
