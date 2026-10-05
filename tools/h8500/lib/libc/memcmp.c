#include <string.h>
#include <stdlib.h>

int memcmp(const void *a, const void *b, size_t n)
{
	const unsigned char *p = a, *q = b;
	for (; n--; p++, q++)
		if (*p != *q)
			return *p - *q;
	return 0;
}
