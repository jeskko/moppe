/* R40 board: devices outside page 8, the tick, the watchdog. */
#ifndef HW_H
#define HW_H

/* devices (page, address): 32 KB windows from 0xA0000 */
#define FX429_PAGE 0xA
#define FX429_ADDR 0x0000
#define OUT0_PAGE  0xA		/* OUT0 latch at 0xA8000 */
#define OUT0_ADDR  0x8000
#define OUT1_PAGE  0xB		/* OUT1 latch at 0xB0000 */
#define OUT1_ADDR  0x0000
#define I2C_PAGE   0xB		/* PCF8584 at 0xB8000 (S0) / 0xB8001 (S1) */
#define I2C_ADDR   0x8000

/* OUT1 bits */
#define OUT1_TXON  0x01

unsigned char xin(unsigned page, unsigned addr);	/* start.s */
void xout(unsigned page, unsigned addr, unsigned char v);

#define TICK_HZ 100
extern volatile unsigned ticks;		/* +1 every 10 ms */

void hw_init(void);
void ei(void);				/* start.s */
void di(void);
void reset(void);
void wdog_kick(void);
void delay_ticks(unsigned n);		/* kicks the watchdog meanwhile */
void out0(unsigned char v);
void out1(unsigned char v);
extern unsigned char out0_shadow, out1_shadow;	/* the latches are write-only */

#endif
