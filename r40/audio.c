/*
 * Audio paths as the Nokia firmware sets them (emulator, Cr 13.04):
 * receive with the squelch closed IC39 = 00001011, open 00001001;
 * transmit 00001010 then 00001000 (mic on), IC41 deviation bits 0111 in
 * receive, 0000 in transmit; IC40 volume in bits 6-4 with the amplifier
 * bit 3.  Power off: IC39 bit 2.
 */
#include "hw.h"
#include "serbus.h"
#include "audio.h"

static unsigned char sw2, af, sw1;
unsigned char volume = 3;

static void update(void)
{
	sr_write(SR_SW2, sw2);
	sr_write(SR_AF, af);
	sr_write(SR_SW1, sw1);
}

void audio_init(void)
{
	sw2 = SW2_MICMUTE | SW2_AFMUTE | SW2_CHSPA;
	af = volume << AF_VOL_SHIFT;
	sw1 = 0x07;
	update();
}

void audio_rx(int open)
{
	if (open) {
		sw2 &= ~SW2_AFMUTE;
		af |= AF_PWRAMP;
	} else {
		sw2 |= SW2_AFMUTE;
		af &= ~AF_PWRAMP;
	}
	update();
}

/* before TX ON: the deviation bits; the receiver's audio off */
void audio_tx_prepare(void)
{
	sw1 &= ~SW1_DEV_MASK;
	sr_write(SR_SW1, sw1);
	sw2 |= SW2_AFMUTE;
	af &= ~AF_PWRAMP;
	sr_write(SR_AF, af);
}

/* after TX ON: microphone on; off again before TX OFF */
void audio_mic(int on)
{
	if (on)
		sw2 &= ~SW2_MICMUTE;
	else
		sw2 |= SW2_MICMUTE;
	sr_write(SR_SW2, sw2);
}

/* after TX OFF: receive deviation bits (the squelch sets the rest) */
void audio_tx_done(void)
{
	sw1 = (sw1 & ~SW1_DEV_MASK) | 0x07;
	sr_write(SR_SW1, sw1);
}

void audio_volume(int v)
{
	if (v < 0)
		v = 0;
	if (v > 7)
		v = 7;
	volume = v;
	af = (af & ~AF_VOL_MASK) | (v << AF_VOL_SHIFT);
	sr_write(SR_AF, af);
}

void power_off(void)
{
	sw2 |= SW2_MICMUTE | SW2_AFMUTE | SW2_OFF;
	af &= ~AF_PWRAMP;
	update();
}
