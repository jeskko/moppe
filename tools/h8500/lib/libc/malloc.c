/* malloc for test programs: a bump allocator from the end of bss
   (__bss_end, from h8cc) towards the stack; free() does nothing */
#include <stdlib.h>

extern char _bss_end[];		/* asl: __bss_end */
static char *brk;

void *malloc(size_t n)
{
	char *p;

	if (!brk)
		brk = _bss_end;
	n = (n + 1) / 2 * 2;
	if ((unsigned)brk + n > 0xF000u)	/* leave the stack 3.75 KB */
		return NULL;
	p = brk;
	brk += n;
	return p;
}

void free(void *p)
{
}
