
/*
 *  'A'        character constant 0x41
 *  'AB'       character constant 0x4142
 *
 *  "a"        string (no automatic \0 but see .asciz directive)
 *
 *  07         octal
 *  7          decimal
 *  0xA        hex
 *  0b0101     binary
 *
 *  stuff # comments \n
 *  stuff ; stuff \n
 *  stuff \n
 *
 *  [._a-zA-Z0-9][_a-zA-Z0-9]* identifier
 *
 *  "C" operators + - % << etc.
 */

static const char version[] = "@(#)jas/lexer	v2b Aug 17 1996";

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include "y.tab.h"

extern FILE *fin;
extern unsigned yylval;

#include "jas.h"

int  relative_uniqs[10];

int  yylineno;
int  xxxidx;
int  yyleng;
char yyfile[256];
char yytext[16384];
char xxxline[16384];

static void yyret(x,s) { if(debug>1)fprintf(stderr, "yylex: %s %s\n", x, s); }
static void yyrtc(x,c) { if(debug>1)fprintf(stderr, "yylex: %s %c\n", x, c); }

void
lexrewind()
{
	intext = 1;
	dot = textdot = datadot = 0;
	lowtext = 0x10000;
	lowdata = 0x10000;
	maxtext = 0;
	maxdata = 0;
	yylineno = 1;
	xxxidx = 0;
	bzero(relative_uniqs, sizeof(relative_uniqs));
	p2u_reset();
}

void
yyerror(msg)
	char *msg;
{
	int c, x, n, i;

	if (x = xxxidx) {
		while ((c = get(1)) != EOF && c != '\n')
			;
	}
	n = fprintf(stderr, "%s(%d): %s: ",
		yyfile[0] ? yyfile : "(stdin)",
		yylineno, msg);

	for (i = 0; c = xxxline[i]; ++i)
			putchar(isspace(c) ? ' ' : c);
	putchar('\n');

	if (x) {
		while (--n >= 0)
			putchar(' ');
		while (--x > 0)
			putchar(' ');
		putchar('^');
		putchar('\n');
	}

	exit(1);
}

int
get(eofok)
{
	int c, c2;

again:
	c = getc(fin);

	if (c == '\\') {
		c2 = getc(fin);
		if (c2 == '\n') {
			yylineno++;
			goto again;
		}
		ungetc(c2, fin);
	}
	if (c == EOF && !eofok)
		yyerror("Unexpected EOF");

	if (c == '\n') {
		xxxidx = 0;
		yylineno++;
	} else {
		xxxline[xxxidx++] = c;
		xxxline[xxxidx]   = 0;
	}
	return (c);
}

void
unget(c)
	int c;
{
	if (c == '\n')
		yylineno--;
	else
	if (xxxidx > 0)
		xxxidx--;

	ungetc(c, fin);
}

getq(qc)
	int qc;
{
	int c, c2;

	while ((c = get(0)) != qc) {
		if (c == '\n')
			yyerror(qc == '"' ? "Newline in string"
			                  : "Newline in character constant");

		if (c == '\\') {
			c = get(0);
			switch (c) {
			case 'n': c = '\n'; break;
			case 'a': c = '\a'; break;
			case 'b': c = '\b'; break;

			case '0': case '1': case '2': case '3':
			case '4': case '5': case '6': case '7':
				c -= '0';
				c2 = get(0);
				if (c2 < '0' || c2 > '7') {
					unget(c2);
					break;
				}
				c = c * 8 + c2 - '0';
				c2 = get(0);
				if (c2 < '0' || c2 > '7') {
					unget(c2);
					break;
				}
				c = c * 8 + c2 - '0';
				break;

			case 'x': case 'X':
				c2 = get(0);
				if (!isxdigit(c2))
					yyerror("Invalid hex number");
				c2 -= c2 <= '9' ? '0' : ((c2 <= 'F' ? 'A' : 'a') - 10);
				c = c2;
				c2 = get(0);
				if (!isxdigit(c2)) {
					unget(c2);
					break;
				}
				c2 -= c2 <= '9' ? '0' : ((c2 <= 'F' ? 'A' : 'a') - 10);
				c = (c << 4) | c2;
				break;
			}
		}
		yytext[yyleng++] = c;
		yytext[yyleng]   = 0;
	}
	yytext[yyleng] = 0;
}

yylex()
{
	int c, c2;

	yyleng = 0;

	while ((c = get(1)) == 0 || isspace(c) && c != '\n')
		;
	if (c == EOF)
		return (yyret("EOF","EOF"), 0);

	if (c == '"') {
		getq('"');
		yylval = p2u(yytext);

		return (yyret("STRING",yytext), ySTRING);
	}
	if (c == '\'') {
		getq('\'');

		if (yyleng == 1)
			yylval = (unsigned) yytext[0];
		else
		if (yyleng == 2)
			yylval = ((unsigned) yytext[1]
			                | ((unsigned) yytext[0] << 8));
		else
			yyerror("Invalid character constant");

		return (yyret("VALUE",yytext), yVALUE);
	}
	if (c == '#' || c == '!') {
		/*
		 *  Comment, upto EOL.
		 *  Fall into newline case.
		 */
		do {
			yytext[yyleng++] = c;
			yytext[yyleng]   = 0;
		} while ((c = get(0)) != '\n');

		if ((!strncmp(yytext, "# ",     2) && isdigit(yytext[2]))
		 || (!strncmp(yytext, "#line ", 6) && isdigit(yytext[6]))) {
			int x;
			char tmp[256];

			if (sscanf(yytext, "# %d \"%[^\"]", &x, tmp) == 2) {
				yylineno = x;
				strncpy(yyfile, tmp, sizeof(yyfile) - 1);
			}
		}
	}
	if (c == '\n'
	 || c == ';') {
			if (c == '\n' && pass == 1 && debug && xxxline[0] != '#') {
				printf("# %s\n", xxxline);
				xxxline[0] = 0;
			}
		return (yyret("CHR",";"), ';');
	}

	if (isdigit(c)) {

		char *ep = "Z";
		unsigned x;
		char buf[256];

		do {
			yytext[yyleng++] = c;
			yytext[yyleng]   = 0;
			c = get(0);
		} while (isalnum(c) || c == '_');
		unget(c);

		x = strtoul(yytext, &ep, 0);

		if (x != 0 && yyleng == 1 && c == ':') {

			sprintf(buf, "_relative_label_%d_%d_",
					x, ++relative_uniqs[x]);
			yylval = p2u(getsym(buf));
			return (yyret("SYMBOL",buf), ySYMBOL);
		}
		if (x != 0 && yyleng == 2 && (c = yytext[1]) == 'f' || c == 'b') {
			sprintf(buf, "_relative_label_%d_%d_",
					x, relative_uniqs[x] + (c == 'f'));
			yylval = p2u(getsym(buf));
			return (yyret("SYMBOL",buf), ySYMBOL);
		}
		if (*ep) {
			if ((!strncmp(yytext, "0b0", 3) || !strncmp(yytext, "0b1", 3))
			 && strspn(yytext + 2, "01") == strlen(yytext + 2)) {
				char *p = yytext + 2;
				for (x = 0; *p; ++p)
					x = (x << 1) | (*p == '1');
			} else
				yyerror("Invalid number");
		}
		yylval = x;
		return (yyret("VALUE",yytext), yVALUE);
	}

	if (c == '.' || isalpha(c) || c == '_') {

		symbol *sym;
		int x;

		do {
			yytext[yyleng++] = c;
			yytext[yyleng]   = 0;
			c = get(0);
		} while (isalnum(c) || c == '_');
		unget(c);

		if (x = getkeyword(yytext))
			return (yyret("KW",yytext), x);

		yylval = p2u(getsym(yytext));
		return (yyret("SYMBOL",yytext), ySYMBOL);
	}
	if (c == '>') {
		if ((c2 = get(0)) == '>')
			return (yyret("CHR",">>"), ySHR);
		if (c2 == '=')
			return (yyret("CHR",">="), yGTE);
		unget(c2);
	}
	if (c == '<') {
		if ((c2 = get(0)) == '<')
			return (yyret("CHR","<<"), ySHL);
		if (c2 == '=')
			return (yyret("CHR","<="), yLTE);
		unget(c2);
	}
	if (c == '!') {
		if ((c2 = get(0)) == '=')
			return (yyret("CHR","!="), yNEQ);
		unget(c2);
	}
	if (c == '=') {
		if ((c2 = get(0)) == '=')
			return (yyret("CHR","=="), yEQU);
		unget(c2);
	}
	if (c == '|') {
		if ((c2 = get(0)) == '|')
			return (yyret("CHR","||"), yOR);
		unget(c2);
	}
	if (c == '&') {
		if ((c2 = get(0)) == '&')
			return (yyret("CHR","&&"), yAND);
		unget(c2);
	}
	return (yyrtc("CHR",c), c);
}


/* 64-bit port: pointer <-> 32-bit parser value table, see jas.h */

static void   **ptrtab;
static unsigned nptr, maxptr;

void
p2u_reset(void)
{
	nptr = 1;	/* 0 stays invalid */
}

unsigned
p2u(void *p)
{
	if (nptr >= maxptr) {
		maxptr = maxptr ? 2 * maxptr : 4096;
		ptrtab = realloc(ptrtab, maxptr * sizeof(*ptrtab));
		if (!ptrtab) {
			fprintf(stderr, "out of memory\n");
			exit(1);
		}
	}
	ptrtab[nptr] = p;
	return (nptr++);
}

void *
u2p(unsigned u)
{
	if (u == 0 || u >= nptr) {
		fprintf(stderr, "internal error: bad pointer handle %u\n", u);
		exit(1);
	}
	return (ptrtab[u]);
}
