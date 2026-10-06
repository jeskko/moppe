/*
 * Audio paths as the Nokia firmware sets them (emulator, Cr 13.04):
 * receive with the squelch closed IC39 = 00001011, open 00001001;
 * transmit 00001010 then 00001000 (mic on), IC41 deviation bits 0111 in
 * receive, 0000 in transmit; IC40 volume in bits 6-4 with the amplifier
 * bit 3.  Power off: IC39 bit 2.
 *
 * Beeps as the Nokia firmware's key beep: the 8-bit timer on phi / 64,
 * cleared on compare A, TMO toggled on compares A and B (B = A / 2),
 * with IC41 SIGN LSP and IC40 PWRAMP on while it sounds.  Nokia's key
 * beep is compare A 89 for ~17 ms, then 51 for ~43 ms.
 */
#include "regs.h"
#include "hw.h"
#include "serbus.h"
#include "audio.h"

static unsigned char sw2, af, sw1;
static unsigned char rx_open;
static unsigned char beeping, beep_next;
static unsigned beep_end, beep_len2;
unsigned char volume = 3;
unsigned char beep_enabled = 1;

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
	rx_open = open;
	if (open) {
		sw2 &= ~SW2_AFMUTE;
		af |= AF_PWRAMP;
	} else {
		sw2 |= SW2_AFMUTE;
		if (!beeping)
			af &= ~AF_PWRAMP;
	}
	update();
}

static void tone(unsigned char a)
{
	T8_TCR = 0;
	T8_TCNT = 0;
	T8_TCORA = a;
	T8_TCORB = a / 2;
	T8_TCSR = 0x0F;		/* TMO toggles on compare A and B */
	T8_TCR = 0x0A;		/* cleared on compare A, phi / 64 */
}

/* Nokia's key beep: two tones, 60 ms */
void audio_beep(void)
{
	if (!beep_enabled)
		return;
	tone(89);
	beeping = 1;
	beep_next = 51;
	beep_len2 = 4;
	beep_end = ticks + 2;
	sw1 |= SW1_SIGNLSP;
	af |= AF_PWRAMP;
	sr_write(SR_SW1, sw1);
	sr_write(SR_AF, af);
}

/* main loop: ends the beep */
void audio_poll(void)
{
	if (!beeping || (int)(ticks - beep_end) < 0)
		return;
	if (beep_next) {
		tone(beep_next);
		beep_next = 0;
		beep_end = ticks + beep_len2;
		return;
	}
	T8_TCR = 0;
	beeping = 0;
	sw1 &= ~SW1_SIGNLSP;
	if (!rx_open)
		af &= ~AF_PWRAMP;
	sr_write(SR_SW1, sw1);
	sr_write(SR_AF, af);
}

/* before TX ON: the deviation bits; the receiver's audio off */
void audio_tx_prepare(void)
{
	if (beeping) {
		T8_TCR = 0;
		beeping = 0;
		sw1 &= ~SW1_SIGNLSP;
	}
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

/* the Fii switch: TMO (a CTCSS tone) into the TX audio */
void audio_fii(int on)
{
	if (on)
		sw1 |= SW1_FII;
	else
		sw1 &= ~SW1_FII;
	sr_write(SR_SW1, sw1);
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
