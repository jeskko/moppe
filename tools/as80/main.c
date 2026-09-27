#include <unistd.h>
#include <fcntl.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

static const char version[] = "@(#)jas/main	v2 Jan  3 1997";

#include "jas.h"

extern char *cpu_family;
char *me;
char cppcmd[512];
char *ofile = "a.out";

main(argc, argv)
	int    argc;
	char **argv;
{

	sprintf(cppcmd, "\
cpp -undef -nostdinc -traditional -Wcomment \
-DLANGUAGE_ASSEMBLY -D%s\
",
		cpu_family);

	if (me = strrchr(argv[0], '/'))
		me++;
	else
		me = argv[0];

	while (*++argv && **argv == '-') {
		if (!strcmp(*argv, "--")) {
			argv++;
			break;
		}
		if (!strcmp(*argv, "-o") && argv[1]) {
			ofile = *++argv;
			continue;
		}
		if (!strcmp(*argv, "-d")) {
			debug++;
			continue;
		}
		if (!strcmp(*argv, "-yd")) {
			yydebug = 1;
			continue;
		}
		if (!strncmp(*argv, "-D", 2)
		 || !strncmp(*argv, "-I", 2)) {
			strcat(cppcmd, " ");
			strcat(cppcmd, *argv);
			continue;
		}
	usage:
		fprintf(stderr, "\
Usage: %s [-l] [-o output] [-Ddef] [-Idir] file\n", me);
		exit(2);
	}
	if (!*argv)
		goto usage;

	strcat(cppcmd, " ");
	strcat(cppcmd, *argv++);

	if (*argv)
		goto usage;

	mem = malloc(0x10000);
	memset(mem, 0xFF, 0x10000);

	if (debug)
		printf("# %s\n", cppcmd);

	for (pass = 0; pass < 2; ++pass) {

		lexrewind();

		if ((fin = popen(cppcmd, "r")) == NULL)
			pexit("popen cpp");

		if (yyparse())
			yyerror("Oops");

		if (pclose(fin)) {
			fprintf(stderr, "%s: cpp failed\n", me);
			exit(1);
		}
		if (pass == 0)
			cksyms();
	}
	dumpsyms();
	dumpprog();

	exit(0);
}

pexit(locus)
	char *locus;
{
	fprintf(stderr, "%s: %s: %s\n", me, locus, strerror(errno));
	exit(1);
}

dumpprog()
{
	int fd, cc;

	if (maxtext > lowtext)
		cc = maxtext - lowtext;
	else {
		cc = 0;
		fprintf(stderr, "%s: Warning: empty output\n", me);
	}
	if ((fd = creat(ofile, 0666)) == -1)
		pexit(ofile);

	if (write(fd, mem + lowtext, cc) != cc)
		pexit(ofile);

	if (close(fd))
		pexit(ofile);
}

dumpsyms()
{
	symbol *sym;

	printf("\n# Symbols:\n\n");

	for (sym = symbols; sym; sym = sym->next)
		if (debug>1 || sym->name[0] != '_')
			printf("# %-16s %c 0x%04X %5d  %5d\n",
				sym->name, sym->type,
				sym->value, sym->value,
				sym->size);

	if (lowtext <= maxtext) {
		printf("# %-16s %c 0x%04X %5d  %5d\n",
			"_text", 'a',
			lowtext, lowtext,
			maxtext - lowtext);
		printf("# %-16s %c 0x%04X %5d\n",
			"_etext", 'a',
			maxtext, maxtext,
			0);
	}
	if (lowdata <= maxdata) {
		printf("# %-16s %c 0x%04X %5d  %5d\n",
			"_data", 'a',
			lowdata, lowdata,
			maxdata - lowdata);
		printf("# %-16s %c 0x%04X %5d\n",
			"_edata", 'a',
			maxdata, maxdata,
			0);
	}
	printf("\n");

	if (maxtext > lowdata)
		fprintf(stderr, "Warning: text/data overlap or abnormal layout\n");
}

cksyms()
{
	symbol *sym;
	int nundef = 0;

	for (sym = symbols; sym; sym = sym->next) {
		if (sym->defined)
			continue;
		if (nundef++ == 0)
			fprintf(stderr, "Undefined symbols:\n");
		fprintf(stderr, "    %s\n", sym->name);
	}
	if (nundef)
		exit(1);
}

symbol *
getsym(name)
	char *name;
{
	symbol **spp;

	for (spp = &symbols; *spp; spp = &(*spp)->next)
		if (!strcmp((*spp)->name, name))
			return (*spp);

	(*spp) = calloc(1, sizeof(**spp));
	(*spp)->name = strdup(name);

	return (*spp);
}

define(s, v, t)
	symbol *s;
	unsigned v;
{
	s->defined = 1;
	s->value   = v;
	s->type    = t;

	lastsym = s;
}

setsize()
{
	if (lastsym) {
		lastsym->size = dot - lastsym->value;
		lastsym = NULL;
	}
}

symval(s)
	symbol *s;
{
	return (s->value);
}

symsize(s)
	symbol *s;
{
	return (s->size);
}

symtype(s)
	symbol *s;
{
	return (s->type);
}

xemit(p, n)
	unsigned char *p;
	int n;
{
	static nzd;

	while (n--) {
		if (intext) {
			if (lowtext > dot)
				lowtext = dot;
			if (p)
				mem[dot] = *p++;
			dot++;
			if (maxtext < dot)
				maxtext = dot;
		} else {
			if (lowdata > dot)
				lowdata = dot;
			if (p && *p++ && nzd++ == 0)
				fprintf(stderr, "Warning: Emitted nonzero data\n");
			dot++;
			if (maxdata < dot)
				maxdata = dot;
		}
		dot &= 0xFFFF;

		if (intext)
			textdot = dot;
		else
			datadot = dot;
	}
}

emit(p, n)
	unsigned char *p;
	int n;
{
	if (p && pass == 1 && debug) {
		int i;
		printf("L%04X:", dot);
		for (i = 0; i < n; ++i)
			printf(" %02X", p[i]);
		printf("\n");
	}
	xemit(p, n);
}

fill(v, n)
	unsigned char v;
	int n;
{
	if (pass == 1 && debug) {
		printf("L%04X:", dot);
		if (n)
			printf(" %02X [ %02X ]", v, n);
		printf("\n");
	}
	while (n--)
		xemit(&v, 1);
}

align(v, bits)
	unsigned char v;
	int bits;
{
	unsigned mask = (unsigned) 0xFFFF >> (16 - bits);
	int n = 0;

	while (dot & mask) {
		xemit(&v, 1);
		n++;
	}
	if (n && pass == 1 && debug) {
		printf("L%04X:", dot - n);
		if (n)
			printf(" %02X [ %02X ]", v, n);
		printf("\n");
	}
}

op(op)
	unsigned op;
{
	emit(&op, 1);
}

opb(op, b)
	unsigned op, b;
{
	char tmp[2];

	tmp[0] = op;
	tmp[1] = b;
	emit(tmp, 2);
}

op2(a, b)
{
	char tmp[2];

	tmp[0] = a;
	tmp[1] = b;
	emit(tmp, 2);
}

op3(a, b, c)
{
	char tmp[3];

	tmp[0] = a;
	tmp[1] = b;
	tmp[2] = c;
	emit(tmp, 3);
}

op4(a, b, c, d)
{
	char tmp[4];

	tmp[0] = a;
	tmp[1] = b;
	tmp[2] = c;
	tmp[3] = d;
	emit(tmp, 4);
}

emitb(b)
	unsigned b;
{
	char tmp[1];

	tmp[0] = b;
	emit(tmp, 1);
}

emitw(w)
	unsigned w;
{
	char tmp[2];

	tmp[0] = w & 0xFF;
	tmp[1] = w >> 8;
	emit(tmp, 2);
}

cksum(from, end)
{
	int i, n;

	n = 0;
	for (i = from; i < end; ++i)
		n += mem[i];

	return (256 - n);
}

