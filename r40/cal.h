/* Nokia's factory calibration from NV (or its D-band defaults). */
#ifndef CAL_H
#define CAL_H

extern unsigned char cal_ok;	/* 1: read from Nokia's NV copies */

void cal_load(void);
unsigned char cal_rfc(unsigned long rx);	/* RX front-end DAC */
unsigned char cal_dev(unsigned long tx);	/* 4094 DEV bits */
unsigned char cal_tpc(int level, unsigned long tx);	/* level 0-2 */
unsigned cal_sq_open(void);	/* noise (10-bit A/D) to open below */
unsigned cal_sq_close(void);	/* and to close above */

#define SC_N 6				/* self-cal points: 430, 432 ... 440 */
extern unsigned char rx_selfcal[SC_N];	/* RFC there; 0xFF: none */
int cal_self_valid(void);
int cal_self(void);			/* sweeps; -1 if a key stopped it */
void cal_self_clear(void);

#endif
