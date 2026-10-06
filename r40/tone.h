/* CTCSS tones (experimental: the TX audio path for sub-audio is unknown). */
#ifndef TONE_H
#define TONE_H

#define NTONES 50
extern const unsigned tones[NTONES + 1];	/* 0.1 Hz; [0] = off */
extern volatile unsigned ctcss_inc, ctcss_phase;

void ctcss_on(int t);		/* tone index 1..NTONES */
void ctcss_off(void);

#endif
