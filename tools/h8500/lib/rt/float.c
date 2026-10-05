/* Software floating point for lcc H8/500 programs: IEEE single
   precision (float and double are both 32 bits), round to nearest even.
   Simplifications: denormal inputs read as zero and results that would
   be denormal become zero; NaNs are not distinguished from infinities
   in comparisons.  Called through the register shims in floatrt.s;
   values are passed as their bit patterns. */

typedef unsigned long u32;

#define SIGN 0x80000000UL
#define EXP(a) ((int)((a) >> 23) & 0xFF)
#define MAN(a) (((a) & 0x7FFFFFUL) | 0x800000UL)
#define INF 0x7F800000UL

/* m (the leading 1 at bit 30 or 31, any bits below are fraction) times
   2^(e-127-30), rounded, packed */
static u32 pack(u32 s, int e, u32 m)
{
	u32 r;

	if (m == 0)
		return s;
	while (!(m & 0xC0000000UL)) {
		m <<= 1;
		e--;
	}
	if (m & SIGN) {
		m = (m >> 1) | (m & 1);
		e++;
	}
	r = m & 0x7F;
	m >>= 7;
	if (r > 0x40 || (r == 0x40 && (m & 1)))
		if (++m == 0x1000000UL) {
			m >>= 1;
			e++;
		}
	if (e >= 255)
		return s | INF;
	if (e <= 0)
		return s;
	return s | (u32)e << 23 | (m & 0x7FFFFFUL);
}

/* m >> n, keeping a sticky bit */
static u32 shr(u32 m, int n)
{
	if (n >= 32)
		return m != 0;
	if (n <= 0)
		return m;
	return m >> n | ((m & ((1UL << n) - 1)) != 0);
}

u32 _fpadd(u32 a, u32 b)
{
	int ea = EXP(a), eb = EXP(b);
	u32 ma, mb, t;

	if (ea == 255 || eb == 255) {
		if (ea == 255 && eb == 255 && (a ^ b) & SIGN)
			return 0x7FC00000UL;		/* inf - inf */
		return ea == 255 ? a : b;
	}
	if (eb == 0)
		return ea == 0 ? a & b & SIGN : a;
	if (ea == 0)
		return b;
	if ((a & 0x7FFFFFFFUL) < (b & 0x7FFFFFFFUL)) {	/* |a| >= |b| */
		t = a; a = b; b = t;
		ea = EXP(a); eb = EXP(b);
	}
	ma = MAN(a) << 7;
	mb = shr(MAN(b) << 7, ea - eb);
	if ((a ^ b) & SIGN) {
		ma -= mb;
		if (ma == 0)
			return 0;
	} else
		ma += mb;
	return pack(a & SIGN, ea, ma);
}

u32 _fpsub(u32 a, u32 b)
{
	return _fpadd(a, b ^ SIGN);
}

u32 _fpmul(u32 a, u32 b)
{
	int ea = EXP(a), eb = EXP(b);
	u32 s = (a ^ b) & SIGN, ma, mb, al, bl, ah, bh, hi, lo, mid, p;

	if (ea == 255 || eb == 255) {
		if (ea == 0 || eb == 0)
			return 0x7FC00000UL;		/* 0 * inf */
		return s | INF;
	}
	if (ea == 0 || eb == 0)
		return s;
	ma = MAN(a); mb = MAN(b);
	ah = ma >> 16; al = ma & 0xFFFF;
	bh = mb >> 16; bl = mb & 0xFFFF;
	p = al * bl;
	mid = ah * bl + al * bh;
	hi = ah * bh + (mid >> 16);
	lo = mid << 16;
	lo += p;
	if (lo < p)
		hi++;
	/* the 48-bit product hi:lo has its leading 1 at bit 46 or 47 */
	return pack(s, ea + eb - 127, hi << 16 | lo >> 16 | ((lo & 0xFFFF) != 0));
}

u32 _fpdiv(u32 a, u32 b)
{
	int ea = EXP(a), eb = EXP(b), i;
	u32 s = (a ^ b) & SIGN, r, d, q;

	if (ea == 255)
		return eb == 255 ? 0x7FC00000UL : s | INF;
	if (eb == 255)
		return s;
	if (eb == 0)
		return ea == 0 ? 0x7FC00000UL : s | INF;
	if (ea == 0)
		return s;
	r = MAN(a); d = MAN(b);
	ea = ea - eb + 127;
	if (r < d) {
		r <<= 1;
		ea--;
	}
	q = 0;
	for (i = 0; i < 31; i++) {
		q <<= 1;
		if (r >= d) {
			r -= d;
			q |= 1;
		}
		r <<= 1;
	}
	return pack(s, ea, q | (r != 0));
}

/* -1, 0 or 1 as a <, ==, > b */
int _fpcmp(u32 a, u32 b)
{
	if (EXP(a) == 0)
		a &= SIGN;
	if (EXP(b) == 0)
		b &= SIGN;
	if (((a | b) & 0x7FFFFFFFUL) == 0 || a == b)
		return 0;
	if ((a ^ b) & SIGN)
		return a & SIGN ? -1 : 1;
	if (a & SIGN)
		return a > b ? -1 : 1;
	return a < b ? -1 : 1;
}

/* truncate towards zero; out of range saturates */
long _fptoi(u32 a)
{
	int e = EXP(a) - 150;
	u32 m;

	if (EXP(a) < 127)
		return 0;
	if (e > 7)
		return a & SIGN ? (long)SIGN : 0x7FFFFFFFL;
	m = MAN(a);
	m = e >= 0 ? m << e : m >> -e;
	return a & SIGN ? -(long)m : (long)m;
}

u32 _itofp(long i)
{
	u32 s = 0, m = i;

	if (i < 0) {
		s = SIGN;
		m = 0 - m;
	}
	return pack(s, 127 + 30, m);
}
