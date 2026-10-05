/* I2C master on the PCF8584 (polled). */
#ifndef I2C_H
#define I2C_H

void i2c_init(void);
int i2c_write(unsigned char addr, const unsigned char *hdr, int nh,
	      const unsigned char *data, int nd);
int i2c_read(unsigned char addr, unsigned char *buf, int n);

#endif
