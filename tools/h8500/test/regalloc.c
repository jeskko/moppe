/*
 * Register-allocator regressions (lcc.patch, gen.c spillee): 32-bit
 * values in register pairs while single registers hold other live
 * values.  lcc asserted or spilled forever on each of these.  Prints
 * "N mismatches" like intgen.py's programs.
 */
#include <stdio.h>

static int bad;

static void ck(int line, long got, long want)
{
	if (got != want) {
		printf("line %d: got %ld, want %ld\n", line, got, want);
		bad++;
	}
}

/* h < q[0] || h > q[1]: q stays live in one register across both */
static int outside(unsigned long h, unsigned long *q)
{
	return h < q[0] || h > q[1] ? -1 : 0;
}

/* a comparison kept as a value, then a shift by a 32-bit expression */
static int shift(int x, int c)
{
	int v = (x < 1);

	return v + (1 << (int)(c + 5L));
}

int main(void)
{
	unsigned long r[2] = { 430000000L, 440000000L };

	ck(__LINE__, outside(433500000L, r), 0);
	ck(__LINE__, outside(429999999L, r), -1);
	ck(__LINE__, outside(440000001L, r), -1);
	ck(__LINE__, outside(440000000L, r), 0);
	ck(__LINE__, outside(0x10000000L, r), -1);
	ck(__LINE__, shift(0, 2), 1 + 128);
	ck(__LINE__, shift(5, 0), 32);
	printf("%d mismatches\n", bad);
	return 0;
}
