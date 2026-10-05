/* A small printf for the lcc H8/500 programs: %d %i %u %x %X %o %c %s
   %%, the l modifier, width, '0' and '-' flags. */
#include <stdarg.h>
#include <stdio.h>

int puts(const char *s)
{
	while (*s)
		putchar(*s++);
	putchar('\n');
	return 0;
}

static int out(char *p, int n, int width, int left, int zero)
{
	int k = n;
	if (!left)
		for (; k < width; k++)
			putchar(zero ? '0' : ' ');
	while (n-- > 0)
		putchar(*p++);
	if (left)
		for (; k < width; k++)
			putchar(' ');
	return k;
}

int printf(const char *fmt, ...)
{
	va_list ap;
	char buf[12];
	int count = 0;

	va_start(ap, fmt);
	for (; *fmt; fmt++) {
		int width = 0, left = 0, zero = 0, lng = 0, base = 10, neg = 0, n;
		unsigned long v;
		char *p;

		if (*fmt != '%') {
			putchar(*fmt);
			count++;
			continue;
		}
		fmt++;
		if (*fmt == '-') {
			left = 1;
			fmt++;
		}
		if (*fmt == '0') {
			zero = 1;
			fmt++;
		}
		while (*fmt >= '0' && *fmt <= '9')
			width = width * 10 + *fmt++ - '0';
		if (*fmt == 'l') {
			lng = 1;
			fmt++;
		}
		switch (*fmt) {
		case 'c':
			buf[0] = va_arg(ap, int);
			count += out(buf, 1, width, left, 0);
			continue;
		case 's':
			p = va_arg(ap, char *);
			for (n = 0; p[n]; n++)
				;
			count += out(p, n, width, left, 0);
			continue;
		case 'd': case 'i':
			if (lng) {
				long x = va_arg(ap, long);
				if (x < 0) {
					neg = 1;
					x = -x;
				}
				v = x;
			} else {
				int x = va_arg(ap, int);
				if (x < 0) {
					neg = 1;
					x = -x;
				}
				v = (unsigned)x;
			}
			break;
		case 'u': case 'x': case 'X': case 'o':
			base = *fmt == 'u' ? 10 : *fmt == 'o' ? 8 : 16;
			v = lng ? va_arg(ap, unsigned long) : va_arg(ap, unsigned);
			break;
		default:
			putchar(*fmt);
			count++;
			continue;
		}
		p = buf + sizeof buf;
		do {
			int d = v % base;
			*--p = d < 10 ? '0' + d : (*fmt == 'X' ? 'A' : 'a') + d - 10;
			v /= base;
		} while (v);
		if (neg) {
			if (zero && width > 0) {
				putchar('-');
				count++;
				width--;
			} else
				*--p = '-';
		}
		count += out(p, buf + sizeof buf - p, width, left, zero);
	}
	va_end(ap);
	return count;
}
