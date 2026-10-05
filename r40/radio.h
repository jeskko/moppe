/* Receiver and transmitter: tuning, squelch, signal strength, PTT. */
#ifndef RADIO_H
#define RADIO_H

extern unsigned long rx_hz, tx_hz;
extern unsigned char transmitting;
extern unsigned char rfc, tpc;
extern unsigned noise, rssi;	/* A/D, 0-1023 */
extern unsigned char sq_open;
extern unsigned sq_level;	/* opens below this noise reading */

void radio_init(void);
void radio_tune(unsigned long rx, unsigned long tx);
void radio_poll(void);		/* main loop: once per tick */

#endif
