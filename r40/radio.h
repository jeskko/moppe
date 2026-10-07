/* Receiver and transmitter: tuning, squelch, signal strength, PTT. */
#ifndef RADIO_H
#define RADIO_H

extern unsigned long rx_hz, tx_hz;
extern unsigned char transmitting;
extern unsigned char tx_locked;	/* why PTT is not transmitting: */
#define TXL_BAND 1			/* outside the TX band */
#define TXL_TOT  2			/* the time-out ran out */
extern unsigned tot_limit;		/* seconds, 0 = none */

#define TX_LO 430000000L		/* transmit only in the 70 cm band */
#define TX_HI 440000000L
extern unsigned char tx_level;	/* TX power: Nokia's level 1-3 as 0-2 */
extern signed char rx_trim;	/* added to the calibrated RFC */
extern unsigned char rfc, tpc;	/* the DAC values in use */
extern unsigned char tx_tone;	/* CTCSS index, 0 = none */
extern unsigned noise, rssi;	/* A/D, 0-1023 */
extern unsigned char sq_open;
extern unsigned sq_on, sq_off;	/* opens below sq_on, closes at sq_off */

void radio_init(void);
void radio_tune(unsigned long rx, unsigned long tx);
void radio_poll(void);
void radio_dac(void);		/* after a level or trim change */
int radio_settled(void);		/* main loop: once per tick */

#endif
