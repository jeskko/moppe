/* Settings kept in the battery-backed NV RAM. */
#ifndef NV_H
#define NV_H

#include "mem.h"

#define NV_BASE  0x3000		/* 0x83000 with P9.2 = 0 (page 8) */
#define NV_MAGIC 0x5234		/* "R4" */
#define NV_VERSION 6

struct nv_cfg {
	unsigned magic;
	unsigned char version, size;
	struct chan vfo;
	unsigned char mem_mode, mem_ch;
	unsigned char volume;
	unsigned char step;	/* index into ui.c's steps */
	unsigned char sq_index, tot_index, beep;
	unsigned char tx_level;
	signed char rx_trim;
	unsigned sum;		/* 0 - (sum of the bytes before) */
};

#define NV_CFG ((struct nv_cfg *)NV_BASE)

int nv_load(void);		/* 0 if valid, -1: defaults kept */
void nv_save(void);

#endif
