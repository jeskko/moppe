/*
 * Memory channels in the NV RAM after the settings block (nv.h): 100
 * slots of a struct chan plus a "used" byte and a checksum byte (the
 * slot's bytes sum to 0), so a half-written or never-written slot reads
 * as empty.
 */
#include "nv.h"
#include "mem.h"

#define MEM_BASE (NV_BASE + 0x100)
#define USED 0xA5

struct slot {
	struct chan c;
	unsigned char used;
	unsigned char sum;
};

#define SLOT(n) ((struct slot *)MEM_BASE + (n))

static unsigned char sum(const unsigned char *p, int n)
{
	unsigned char s = 0;

	while (n-- > 0)
		s += *p++;
	return s;
}

int mem_get(int n, struct chan *c)
{
	struct slot *s;

	if (n < 0 || n >= NMEM)
		return -1;
	s = SLOT(n);
	if (s->used != USED || sum((unsigned char *)s, sizeof *s) != 0)
		return -1;
	if (c)
		*c = s->c;
	return 0;
}

void mem_put(int n, const struct chan *c)
{
	struct slot *s = SLOT(n);

	s->used = 0;
	s->c = *c;
	s->sum = 0;
	s->used = USED;
	s->sum = 0 - sum((unsigned char *)s, sizeof *s - 1);
}

void mem_clear(int n)
{
	SLOT(n)->used = 0;
}

int mem_next(int n, int dir)
{
	int i;

	for (i = 1; i <= NMEM; i++) {
		int m = (n + dir * i + 2 * NMEM) % NMEM;

		if (mem_get(m, 0) == 0)
			return m;
	}
	return -1;
}
