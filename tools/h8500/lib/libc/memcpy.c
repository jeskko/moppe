#include <string.h>
#include <stdlib.h>

void *memcpy(void *d, const void *s, size_t n)
{
	char *p = d;
	const char *q = s;
	while (n--)
		*p++ = *q++;
	return d;
}
