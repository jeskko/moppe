/*
 * I2C master on the PCF8584 at 0xB8000 (S0 data, S1 control/status),
 * polled: the controller's INT (FTI2) is not used.  Clock as the Nokia
 * firmware's (45 kHz SCL, the 4.43 MHz setting for the 4.032 MHz
 * fclk).  A transfer that hangs is abandoned with a STOP after
 * I2C_SPIN polls.
 */
#include "hw.h"
#include "i2c.h"

#define S0 I2C_ADDR
#define S1 (I2C_ADDR + 1)

/* S1 control bits */
#define PIN 0x80
#define ESO 0x40
#define ES1 0x20
#define ES2 0x10
#define ENI 0x08
#define STA 0x04
#define STO 0x02
#define ACK 0x01
/* S1 status bits */
#define LRB 0x08
#define BB  0x01		/* 1 = bus free */

#define I2C_SPIN 2000

static void ctl(unsigned char v)
{
	xout(I2C_PAGE, S1, v);
}

static void put(unsigned char v)
{
	xout(I2C_PAGE, S0, v);
}

/* wait for the byte in progress; 0 when done, -1 on a time-out */
static int wait_pin(void)
{
	int n;

	for (n = 0; n < I2C_SPIN; n++)
		if (!(xin(I2C_PAGE, S1) & PIN))
			return 0;
	return -1;
}

static int wait_free(void)
{
	int n;

	for (n = 0; n < I2C_SPIN; n++)
		if (xin(I2C_PAGE, S1) & BB)
			return 0;
	return -1;
}

static void stop(void)
{
	ctl(PIN | ESO | STO | ACK);
}

void i2c_init(void)
{
	ctl(PIN);			/* serial interface off: S0' */
	put(0xE0 >> 1);			/* own address (unused as a slave) */
	ctl(PIN | ES1);			/* S2 */
	put(0x11);			/* fclk 4.43 MHz setting, SCL 45 kHz */
	ctl(PIN | ESO | ACK);		/* on, idle */
}

/* START, the address byte, and wait for it; 0 if the slave acked */
static int start(unsigned char addr)
{
	if (wait_free())
		return -1;
	put(addr);
	ctl(PIN | ESO | STA | ACK);
	if (wait_pin() || (xin(I2C_PAGE, S1) & LRB)) {
		stop();
		return -1;
	}
	return 0;
}

static int send(const unsigned char *p, int n)
{
	while (n-- > 0) {
		put(*p++);
		if (wait_pin() || (xin(I2C_PAGE, S1) & LRB))
			return -1;
	}
	return 0;
}

/* hdr[0..nh) then data[0..nd) to the slave at addr (write address,
   bit 0 clear); 0 on success */
int i2c_write(unsigned char addr, const unsigned char *hdr, int nh,
	      const unsigned char *data, int nd)
{
	int r;

	if (start(addr))
		return -1;
	r = send(hdr, nh);
	if (!r)
		r = send(data, nd);
	stop();
	return r;
}

/* n bytes (n >= 1) from the slave at addr (write address) */
int i2c_read(unsigned char addr, unsigned char *buf, int n)
{
	int i;

	if (start(addr | 1))
		return -1;
	if (n == 1)
		ctl(ESO);		/* no acknowledge after the last byte */
	(void)xin(I2C_PAGE, S0);	/* dummy read: starts the first byte */
	for (i = 0; i < n - 1; i++) {
		if (wait_pin())
			goto fail;
		if (i == n - 2)
			ctl(ESO);
		buf[i] = xin(I2C_PAGE, S0);
	}
	if (wait_pin())
		goto fail;
	stop();
	buf[n - 1] = xin(I2C_PAGE, S0);
	return 0;
fail:
	stop();
	return -1;
}
