/* A small printf for the lcc H8/500 programs: %d %i %u %x %X %o %c %s
   %f %e %%, the l modifier, width, precision (%f %e, at most 9), '0'
   and '-' flags.  %f and %e work in float precision (about 7 digits). */
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

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

/* the digits of x >= 0 at p, prec after the point; returns the end */
static char *fdigits(char *p, double x, int prec, int efmt)
{
	int e = 0, z = 0, i;
	unsigned long ip;
	char *q;
	double r = 0.5;

	if (x != x)
		return strcpy(p, "nan") + 3;
	if (x > 3.4028235e38)
		return strcpy(p, "inf") + 3;
	if (efmt && x != 0) {
		while (x >= 10) {
			x /= 10;
			e++;
		}
		while (x < 1) {
			x *= 10;
			e--;
		}
	}
	for (i = 0; i < prec; i++)
		r /= 10;
	x += r;
	if (efmt && x >= 10) {
		x /= 10;
		e++;
	}
	for (; x >= 1e9; z++)		/* digits beyond float precision: zeros */
		x /= 10;
	ip = (unsigned long)x;
	x -= ip;
	q = p;
	do {
		*q++ = '0' + ip % 10;
		ip /= 10;
	} while (ip);
	for (i = 0; i < (q - p) / 2; i++) {
		char c = p[i];
		p[i] = q[-1 - i];
		q[-1 - i] = c;
	}
	while (z-- > 0)
		*q++ = '0';
	if (prec > 0)
		*q++ = '.';
	while (prec-- > 0) {
		int d;
		x *= 10;
		d = (int)x;
		*q++ = '0' + d;
		x -= d;
	}
	if (efmt) {
		*q++ = 'e';
		*q++ = e < 0 ? '-' : '+';
		if (e < 0)
			e = -e;
		*q++ = '0' + e / 10;
		*q++ = '0' + e % 10;
	}
	return q;
}

int printf(const char *fmt, ...)
{
	va_list ap;
	char buf[56];
	int count = 0;

	va_start(ap, fmt);
	for (; *fmt; fmt++) {
		int width = 0, prec = -1, left = 0, zero = 0, lng = 0, base = 10, neg = 0, n;
		unsigned long v;
		char *p, *end = buf + sizeof buf;

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
		if (*fmt == '.')
			for (prec = 0, fmt++; *fmt >= '0' && *fmt <= '9'; )
				prec = prec * 10 + *fmt++ - '0';
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
		case 'f': case 'e': {
			double x = va_arg(ap, double);
			if (x < 0) {
				neg = 1;
				x = -x;
			}
			p = buf + 1;
			end = fdigits(p, x, prec < 0 ? 6 : prec > 9 ? 9 : prec, *fmt == 'e');
			break;
		}
		default:
			putchar(*fmt);
			count++;
			continue;
		}
		if (end == buf + sizeof buf) {
			p = end;
			do {
				int d = v % base;
				*--p = d < 10 ? '0' + d : (*fmt == 'X' ? 'A' : 'a') + d - 10;
				v /= base;
			} while (v);
		}
		if (neg) {
			if (zero && width > 0) {
				putchar('-');
				count++;
				width--;
			} else
				*--p = '-';
		}
		count += out(p, end - p, width, left, zero);
	}
	va_end(ap);
	return count;
}
