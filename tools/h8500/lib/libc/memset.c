#include <string.h>
#include <stdlib.h>

void *memset(void *d, int c, size_t n)
{
	char *p = d;
	while (n--)
		*p++ = c;
	return d;
}
