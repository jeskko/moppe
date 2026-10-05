/* Settings menu. */
#ifndef MENU_H
#define MENU_H

extern unsigned char menu_active;
void menu_open(void);
void menu_key(int k);
void menu_draw(void);		/* rows 0 and 1 */

extern unsigned char sq_index;	/* 0 (open) - 9 */
extern unsigned char tot_index;
void settings_apply(void);	/* squelch level, time-out, DAC */

#endif
