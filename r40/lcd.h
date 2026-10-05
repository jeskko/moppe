/* CU43 dot-matrix LCD: three text rows (20, 24, 24 characters). */
#ifndef LCD_H
#define LCD_H

#define LCD_ROWS 3
#define LCD_COLS 24		/* the top row shows 20 */

extern const unsigned char font[96][5];

void lcd_init(void);
void lcd_clear(void);
void lcd_puts(int row, int col, const char *s);
void lcd_update(void);		/* sends one changed row */
void lcd_flush(void);		/* sends all changes */

#endif
