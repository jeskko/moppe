#include <string.h>
#include <stdlib.h>

int strcmp(const char *a, const char *b)
{
	for (; *a && *a == *b; a++, b++)
		;
	return (unsigned char)*a - (unsigned char)*b;
}
