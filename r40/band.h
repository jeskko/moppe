/* The radio's band: 70 cm on an RD40 (Nokia's D band), 2 m on an RC40
   (C band). */
#ifndef BAND_H
#define BAND_H

struct band {
	const char *name;
	unsigned long lo, hi;		/* tuning (the VCO's range is unknown) */
	unsigned long tx_lo, tx_hi;	/* transmit and scan */
	unsigned long boot, shift;	/* first VFO frequency, default shift */
	unsigned long base;		/* 0-channel if Nokia's NV has none */
	unsigned char sw;		/* PLL prescaler: 0 = 128/129, 1 = 64/65 */
};

#define BAND_AUTO 0			/* band_choice: from Nokia's NV */
#define BAND_2M   1
#define BAND_70CM 2
extern unsigned char band_choice;	/* menu, kept in our NV */
extern unsigned char band_id;		/* the one in use: BAND_2M / BAND_70CM */
extern const struct band *band;

void band_select(void);		/* after cal_load() and nv_load() */

#endif
