/*
 * CU43 LCD: a PCF8578 (I2C 0x78, subaddress 0, columns at X 24-39) and
 * three PCF8579 (40 columns each) give 120 columns x 3 text banks plus
 * an icon bank (notes/r40.md "Control head").  No character generator:
 * each character is five column bytes from font.c, 24 cells per row.
 * The top row's glass has 20 characters: cells 2, 9, 14 and 21 are
 * gaps, so text column c of row 0 goes to cell top_cell[c].
 */
#include "hw.h"
#include "i2c.h"
#include "lcd.h"

#define LCD_I2C 0x78

static char text[LCD_ROWS][LCD_COLS];
static unsigned char dirty;		/* bit per row */
static unsigned char cols[120];

static const unsigned char top_cell[20] = {
	0, 1, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 15, 16, 17, 18, 19, 20, 22, 23
};

static void glyph(unsigned char *p, char c)
{
	const unsigned char *g;
	int i;

	if (c < 0x20 || c > 0x7F)
		c = '?';
	g = font[c - 0x20];
	for (i = 0; i < 5; i++)
		p[i] = g[i];
}

static void send_row(int row)
{
	unsigned char hdr[3];
	int i;

	if (row == 0) {
		for (i = 0; i < 120; i++)
			cols[i] = 0;
		for (i = 0; i < 20; i++)
			glyph(cols + 5 * top_cell[i], text[0][i]);
	} else
		for (i = 0; i < LCD_COLS; i++)
			glyph(cols + 5 * i, text[row][i]);
	hdr[0] = 0xF0 | row;	/* RAM access: character mode, bank = row */
	hdr[1] = 0xE0;		/* device select: subaddress 0 */
	hdr[2] = 0x18;		/* X = 24, the PCF8578's first visible column */
	i2c_write(LCD_I2C, hdr, 3, cols, 120);
}

void lcd_init(void)
{
	static const unsigned char mode[] = {
		0xD7,		/* set mode: 1:24, mixed, display on */
		0x7C		/* start bank 0; last command */
	};

	i2c_write(LCD_I2C, mode, 2, 0, 0);
	lcd_clear();
	lcd_update();
}

void lcd_clear(void)
{
	int r, c;

	for (r = 0; r < LCD_ROWS; r++)
		for (c = 0; c < LCD_COLS; c++)
			text[r][c] = ' ';
	dirty = (1 << LCD_ROWS) - 1;
}

void lcd_puts(int row, int col, const char *s)
{
	int n = row == 0 ? 20 : LCD_COLS;

	while (*s && col < n) {
		if (text[row][col] != *s) {
			text[row][col] = *s;
			dirty |= 1 << row;
		}
		col++;
		s++;
	}
}

void lcd_update(void)
{
	int r;

	for (r = 0; r < LCD_ROWS; r++)
		if (dirty & (1 << r)) {
			dirty &= ~(1 << r);
			send_row(r);
			wdog_kick();
		}
}
