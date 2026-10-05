/* User interface: VFO screen and keys. */
#ifndef UI_H
#define UI_H

#define BAND_LO 400000000L	/* tuning limits (the VCO's range is unknown) */
#define BAND_HI 470000000L

extern unsigned char ui_step;	/* index of the tuning step */
void ui_init(void);
void ui_key(int k);
void ui_draw(void);		/* main loop: refreshes what changed */
char *utoa(unsigned long v, char *buf, int digits);

#endif
