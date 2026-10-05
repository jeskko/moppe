/* CU43 keypad, PWR key and hook switch. */
#ifndef KEYPAD_H
#define KEYPAD_H

/* key codes: the digits, '*' and '#' as characters, the rest below */
#define K_NONE  0
#define K_OK    0x80
#define K_CLR   0x81
#define K_FNC   0x82
#define K_RCL   0x83		/* RCL / STO */
#define K_UP    0x84
#define K_DOWN  0x85
#define K_PWR   0x86
#define K_X10   0x90		/* matrix positions with no known key yet: */
#define K_X04   0x91		/* (1,0), (0,4) and row 4 (+ column) */
#define K_X4    0x92

void keypad_init(void);
void keypad_poll(void);		/* call from the main loop */
int key_get(void);		/* next key press, or K_NONE */
extern unsigned char key_down;	/* the key held now, or K_NONE */
extern unsigned char offhook;	/* handset off the hook */
const char *key_name(int k);

#endif
