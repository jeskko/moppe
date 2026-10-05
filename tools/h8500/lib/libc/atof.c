#include <stdlib.h>

/* decimal only, in float precision */
double atof(const char *s)
{
	double x = 0, scale = 1;
	int neg = 0, e = 0, eneg = 0;

	while (*s == ' ' || *s == '\t' || *s == '\n')
		s++;
	if (*s == '-' || *s == '+')
		neg = *s++ == '-';
	for (; *s >= '0' && *s <= '9'; s++)
		x = x * 10 + (*s - '0');
	if (*s == '.')
		for (s++; *s >= '0' && *s <= '9'; s++) {
			scale /= 10;
			x += (*s - '0') * scale;
		}
	if (*s == 'e' || *s == 'E') {
		s++;
		if (*s == '-' || *s == '+')
			eneg = *s++ == '-';
		for (; *s >= '0' && *s <= '9'; s++)
			e = e * 10 + *s - '0';
		while (e-- > 0)
			x = eneg ? x / 10 : x * 10;
	}
	return neg ? -x : x;
}
