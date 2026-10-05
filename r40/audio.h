/* Audio switching, volume, power-off: the 4094 states. */
#ifndef AUDIO_H
#define AUDIO_H

void audio_init(void);
void audio_rx(int open);	/* squelch open: speaker on */
void audio_tx(int on);		/* microphone to the transmitter */
void audio_volume(int v);	/* 0-7 */
extern unsigned char volume;
void power_off(void);

#endif
