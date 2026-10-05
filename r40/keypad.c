/*
 * CU43 keypad: a 5 x 5 matrix between two PCF8574 (notes/r40.md
 * "Control head"): rows on IC200 (I2C 0x44) P0-P4, columns on IC190
 * (0x42) P0-P4.  At rest the rows drive low and the columns are inputs
 * (pulled up); a key pulls its column low, IC190 changes and its /INT
 * pulls P1.5 (IRQ0 pin, the interrupt itself left masked) low until
 * IC190 is read.  Then the columns drive low and the rows are read.
 * IC190 P6 is the PWR key (0 = pressed), P5 the hook (0 = on hook).
 * IC200 P7 / P5 are the display and key lights, P6 the head-type strap.
 */
#include "regs.h"
#include "hw.h"
#include "i2c.h"
#include "keypad.h"

#define IC190 0x42
#define IC200 0x44
#define LIGHTS 0xE0		/* IC200 P7-P5 high: lights on, P6 an input */

#define QLEN 8
static unsigned char q[QLEN];
static unsigned char qhead, qtail;
static unsigned last_scan;
unsigned char key_down;
unsigned char offhook;

/* [row][column], the emulator's map (emu/python/r40emu.py KEYS) */
static const unsigned char keymap[5][5] = {
	{ K_RCL, '3', '2', '1', K_X04 },
	{ K_X10, '6', '5', '4', K_OK },
	{ K_FNC, '9', '8', '7', K_UP },
	{ K_CLR, '#', '0', '*', K_DOWN },
	{ K_X4, K_X4 + 1, K_X4 + 2, K_X4 + 3, K_X4 + 4 },
};

static void wr(unsigned char addr, unsigned char v)
{
	i2c_write(addr, &v, 1, 0, 0);
}

static int rd(unsigned char addr)
{
	unsigned char v;

	if (i2c_read(addr, &v, 1))
		return -1;
	return v;
}

/* lowest clear bit of the five, or -1 */
static int line(int v)
{
	int i;

	for (i = 0; i < 5; i++)
		if (!(v & (1 << i)))
			return i;
	return -1;
}

static void push(int k)
{
	unsigned char n = (qhead + 1) % QLEN;

	if (n != qtail) {
		q[qhead] = k;
		qhead = n;
	}
}

static void scan(void);

/* a key held at power-on (PWR, usually) is down, not pressed */
void keypad_init(void)
{
	wr(IC200, LIGHTS);	/* rows low */
	wr(IC190, 0xFF);	/* columns, PWR, hook: inputs */
	scan();
	qhead = qtail = 0;
}

static void scan(void)
{
	int cols, rows, c, r, k = K_NONE;

	cols = rd(IC190);
	if (cols < 0)
		return;
	offhook = (cols & 0x20) != 0;
	c = line(cols);
	if (c >= 0) {
		wr(IC190, 0xE0);		/* columns low */
		wr(IC200, LIGHTS | 0x1F);	/* rows: inputs */
		rows = rd(IC200);
		wr(IC200, LIGHTS);
		wr(IC190, 0xFF);
		(void)rd(IC190);
		r = rows < 0 ? -1 : line(rows);
		if (r >= 0)
			k = keymap[r][c];
	} else if (!(cols & 0x40))
		k = K_PWR;
	if (k != key_down && k != K_NONE)
		push(k);
	key_down = k;
}

/* scan when IC190's /INT is low, and every 100 ms while a key is held
   (a release with /INT missed would leave it stuck) */
void keypad_poll(void)
{
	unsigned now = ticks;

	if (!(PORT1 & 0x20) || (key_down != K_NONE && now - last_scan >= 10)) {
		last_scan = now;
		scan();
	}
}

int key_get(void)
{
	int k;

	if (qhead == qtail)
		return K_NONE;
	k = q[qtail];
	qtail = (qtail + 1) % QLEN;
	return k;
}

const char *key_name(int k)
{
	static char s[2];

	switch (k) {
	case K_NONE: return "";
	case K_OK: return "OK";
	case K_CLR: return "CLR";
	case K_FNC: return "FNC";
	case K_RCL: return "RCL";
	case K_UP: return "UP";
	case K_DOWN: return "DOWN";
	case K_PWR: return "PWR";
	}
	if (k >= K_X10) {
		s[0] = 'a' + (k - K_X10);
		s[1] = 0;
		return s;
	}
	s[0] = k;
	s[1] = 0;
	return s;
}
