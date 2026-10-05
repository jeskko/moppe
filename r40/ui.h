/* User interface: VFO screen and keys. */
#ifndef UI_H
#define UI_H

#define BAND_LO 400000000L	/* tuning limits (the VCO's range is unknown) */
#define BAND_HI 470000000L

#define DUP_SIMPLEX 0
#define DUP_MINUS   1
#define DUP_PLUS    2

#include "mem.h"

extern struct chan vfo;
extern unsigned char mem_mode, mem_ch;
extern unsigned char ui_step;	/* index of the tuning step */
void ui_init(void);
void ui_key(int k);
void ui_draw(void);
void ui_poll(void);		/* main loop: the scan */
extern unsigned char scanning;		/* main loop: refreshes what changed */
char *utoa(unsigned long v, char *buf, int digits);

#endif
