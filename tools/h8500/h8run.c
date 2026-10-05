/*
 * h8run: run an H8/500 program image on moppe-emu's CPU core (h8500.c)
 * with a bare memory map, for testing compiled code:
 *
 *   00000-3FFFF  ROM (the image; vectors at 0)
 *   80000-8FFFF  RAM (page 8: data, bss, stack)
 *   8FFF0        write: putchar
 *   8FFF1        write: exit with this status
 *   8FFF2/3      read (a word, high byte first): next stdin byte, FFFF at EOF
 *
 * Any exception other than TRAPA (invalid instruction, address error,
 * zero divide) stops the run with status 125 and the address.
 *
 *   h8run [-s] [-n MAXSTATES] [-t LO-HI] image.bin
 *     -s   print the number of states used to stderr
 *     -t   trace every instruction at LO..HI (hex) to stderr: PC, R0-R7
 *
 * Build: cc -O2 -I../../emu -o h8run h8run.c ../../emu/h8500.c
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "h8500.h"

static uint8_t rom[0x40000];
static uint8_t ram[0x10000];
static int done = -1;
static unsigned in_latch;

static uint8_t
rd(void *ctx, uint32_t a)
{
	(void)ctx;
	a &= 0xFFFFF;
	if (a < 0x40000)
		return rom[a];
	if (a == 0x8FFF2) {
		int ch = getchar();
		in_latch = ch == EOF ? 0xFFFF : (unsigned)ch;
		return in_latch >> 8;
	}
	if (a == 0x8FFF3)
		return in_latch & 0xFF;
	if ((a >> 16) == 8)
		return ram[a & 0xFFFF];
	return 0xFF;
}

static void
wr(void *ctx, uint32_t a, uint8_t v)
{
	(void)ctx;
	a &= 0xFFFFF;
	if (a == 0x8FFF0) {
		putchar(v);
		return;
	}
	if (a == 0x8FFF1) {
		done = v;
		return;
	}
	if ((a >> 16) == 8)
		ram[a & 0xFFFF] = v;
}

static int
states(void *ctx, uint32_t a)
{
	(void)ctx;
	(void)a;
	return 2;
}

int
main(int argc, char **argv)
{
	h8500 c;
	h8500_bus bus = { NULL, rd, wr, states };
	unsigned long long max = 2000000000ULL;
	int show = 0, i;
	unsigned long tlo = 1, thi = 0;
	FILE *f;

	for (i = 1; i < argc && argv[i][0] == '-'; i++) {
		if (!strcmp(argv[i], "-s"))
			show = 1;
		else if (!strcmp(argv[i], "-n") && i + 1 < argc)
			max = strtoull(argv[++i], NULL, 0);
		else if (!strcmp(argv[i], "-t") && i + 1 < argc)
			sscanf(argv[++i], "%lx-%lx", &tlo, &thi);
	}
	if (i != argc - 1) {
		fprintf(stderr, "usage: h8run [-s] [-n maxstates] image.bin\n");
		return 2;
	}
	if (!(f = fopen(argv[i], "rb"))) {
		perror(argv[i]);
		return 2;
	}
	memset(rom, 0xFF, sizeof rom);
	if (fread(rom, 1, sizeof rom, f) == 0) {
		fprintf(stderr, "%s: empty\n", argv[i]);
		return 2;
	}
	fclose(f);
	h8500_init(&c, &bus);
	h8500_reset(&c);
	while (done < 0) {
		uint32_t pc = h8500_pc24(&c);
		if (pc >= tlo && pc <= thi)
			fprintf(stderr, "%05X  %04X %04X %04X %04X %04X %04X %04X %04X\n", (unsigned)pc,
				c.r[0], c.r[1], c.r[2], c.r[3], c.r[4], c.r[5], c.r[6], c.r[7]);
		h8500_step(&c);
		if (c.last_exc >= 0 && c.last_exc != H8_VEC_RESET
		    && !(c.last_exc >= H8_VEC_TRAPA && c.last_exc < H8_VEC_TRAPA + 16)) {
			fflush(stdout);
			fprintf(stderr, "h8run: exception %d at %05X\n", c.last_exc,
				(unsigned)c.op_addr);
			return 125;
		}
		if (c.states > max) {
			fflush(stdout);
			fprintf(stderr, "h8run: state limit at %05X\n", (unsigned)h8500_pc24(&c));
			return 124;
		}
	}
	fflush(stdout);
	if (show)
		fprintf(stderr, "states: %llu\n", (unsigned long long)c.states);
	return done;
}
