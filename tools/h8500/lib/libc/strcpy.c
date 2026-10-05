#include <string.h>
#include <stdlib.h>

char *strcpy(char *d, const char *s)
{
	char *p = d;
	while ((*p++ = *s++) != 0)
		;
	return d;
}
