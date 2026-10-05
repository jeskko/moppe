/*
 * Settings in the battery-backed SRAM.  With P9.2 = 0 the window
 * 0x80000-0x83FFF shows the half the Nokia firmware uses for its working
 * copy and stack; its checksummed copies (calibration included, notes/
 * r40.md "NV RAM") are in the other half, which this firmware leaves
 * alone.  The block sits at 0x3000, above anything Nokia's working copy
 * uses.  Battery RAM has no wear, so every change is written at once;
 * the header and checksum catch an empty, old or half-written block.
 */
#include "hw.h"
#include "audio.h"
#include "radio.h"
#include "ui.h"
#include "nv.h"

static unsigned sum(const unsigned char *p, int n)
{
	unsigned s = 0;

	while (n-- > 0)
		s += *p++;
	return s;
}

int nv_load(void)
{
	struct nv_cfg *c = NV_CFG;
	int n = (int)((char *)&c->sum - (char *)c);

	if (c->magic != NV_MAGIC || c->version != NV_VERSION ||
	    c->size != sizeof(struct nv_cfg) ||
	    (unsigned)(sum((unsigned char *)c, n) + c->sum) != 0)
		return -1;
	vfo_hz = c->vfo_hz;
	shift_hz = c->shift_hz;
	duplex = c->duplex;
	reverse = c->reverse;
	volume = c->volume & 7;
	ui_step = c->step;
	sq_level = c->sq_level;
	rfc = c->rfc;
	tpc = c->tpc;
	return 0;
}

void nv_save(void)
{
	struct nv_cfg *c = NV_CFG;
	int n = (int)((char *)&c->sum - (char *)c);

	c->magic = NV_MAGIC;
	c->version = NV_VERSION;
	c->size = sizeof(struct nv_cfg);
	c->vfo_hz = vfo_hz;
	c->shift_hz = shift_hz;
	c->duplex = duplex;
	c->reverse = reverse;
	c->volume = volume;
	c->step = ui_step;
	c->sq_level = sq_level;
	c->rfc = rfc;
	c->tpc = tpc;
	c->sum = 0 - sum((unsigned char *)c, n);
}
