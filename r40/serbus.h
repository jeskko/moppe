/* Serial bus (P1.2 clock, P1.3 data): 4094 shift registers, DAC. */
#ifndef SERBUS_H
#define SERBUS_H

/* IC39 (SWITCH2), IC40 (AFCONT), IC41 (DEV / SWITCH1): the board
   description's bit names, checked against the Nokia firmware's writes */
#define SR_SW2   0
#define SR_AF    1
#define SR_SW1   2

#define SW2_MICMUTE  0x01	/* 1: microphone muted */
#define SW2_AFMUTE   0x02	/* 1: receiver audio muted */
#define SW2_OFF      0x04	/* 1: power off */
#define SW2_CHSPA    0x08	/* receiver audio gain for the channel spacing */
#define SW2_CRMC     0x10	/* car radio mute */
#define SW2_ALARM    0x20	/* external alarm */

#define AF_PWRAMP    0x08	/* 1: loudspeaker amplifier on */
#define AF_VOL_SHIFT 4		/* bits 6-4: volume 0-7 */
#define AF_VOL_MASK  0x70

#define SW1_DEV_MASK 0x0F	/* deviation attenuation */
#define SW1_PEAKDEV  0x10
#define SW1_FII      0x20	/* Fii tone (TMO) to the transmitter */
#define SW1_SIGNLSP  0x80	/* confidence tones (TMO) to the loudspeaker */

void sr_write(int n, unsigned char v);
void dac_write(unsigned char tpc, unsigned char rfc, unsigned char c,
	       unsigned char d);

#endif
