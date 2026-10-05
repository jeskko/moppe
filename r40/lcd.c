/*
 * CU43 LCD: a PCF8578 (I2C 0x78, subaddress 0, columns at X 24-39) and
 * three PCF8579 (40 columns each) give 120 columns x 3 text banks plus
 * an icon bank (notes/r40.md "Control head").  No character generator:
 * each character is five column bytes from font.c, 24 cells per row.
 * The top row's glass has 20 characters: cells 2, 9, 14 and 21 are
 * gaps, so text column c of row 0 goes to cell top_cell[c].
 *
 * The bus is slow (45 kHz, ~0.25 ms a byte), so an update sends only
 * the cells that differ from what the glass shows, and at most one row
 * per call: the main loop is not held up for long.
 */
#include "hw.h"
#include "i2c.h"
#include "lcd.h"

#define LCD_I2C 0x78

static char text[LCD_ROWS][LCD_COLS];	/* cells: row 0 includes gaps */
static char shown[LCD_ROWS][LCD_COLS];	/* what the glass has */
static unsigned char dirty;		/* bit per row */
static unsigned char cols[120];
static unsigned char next_row;

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

/* cells first..last of a row; column c of the glass is in device 0 at
   X 24 + c (c < 16), else device 1 + (c - 16) / 40 at X (c - 16) % 40,
   and the RAM address runs on into the next device */
static void send_cells(int row, int first, int last)
{
	unsigned char hdr[3];
	int i, c = 5 * first;

	for (i = first; i <= last; i++) {
		glyph(cols + 5 * (i - first), text[row][i]);
		shown[row][i] = text[row][i];
	}
	hdr[0] = 0xF0 | row;	/* RAM access: character mode, bank = row */
	if (c < 16) {
		hdr[1] = 0xE0;	/* device select: subaddress 0 */
		hdr[2] = 24 + c;	/* load X, the last command (bit 7 clear) */
	} else {
		hdr[1] = 0xE0 | (1 + (c - 16) / 40);
		hdr[2] = (c - 16) % 40;
	}
	i2c_write(LCD_I2C, hdr, 3, cols, 5 * (last - first + 1));
}

static void send_row(int row)
{
	int first, last;

	for (first = 0; first < LCD_COLS && shown[row][first] == text[row][first]; first++)
		;
	if (first == LCD_COLS)
		return;
	for (last = LCD_COLS - 1; shown[row][last] == text[row][last]; last--)
		;
	send_cells(row, first, last);
}

void lcd_init(void)
{
	static const unsigned char mode[] = {
		0xD7,		/* set mode: 1:24, mixed, display on */
		0x7C		/* start bank 0; last command */
	};

	int r;

	i2c_write(LCD_I2C, mode, 2, 0, 0);
	lcd_clear();
	for (r = 0; r < LCD_ROWS; r++) {
		send_cells(r, 0, LCD_COLS - 1);	/* all of it, gaps included */
		wdog_kick();
	}
	dirty = 0;
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
		char *t = &text[row][row == 0 ? top_cell[col] : col];

		if (*t != *s) {
			*t = *s;
			dirty |= 1 << row;
		}
		col++;
		s++;
	}
}

/* one changed row per call, round robin */
void lcd_update(void)
{
	int i, r;

	for (i = 0; i < LCD_ROWS; i++) {
		r = next_row;
		next_row = (next_row + 1) % LCD_ROWS;
		if (dirty & (1 << r)) {
			dirty &= ~(1 << r);
			send_row(r);
			return;
		}
	}
}

/* everything out now (before switching off) */
void lcd_flush(void)
{
	while (dirty) {
		lcd_update();
		wdog_kick();
	}
}
