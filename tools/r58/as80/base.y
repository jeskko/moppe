
%{

# 4 "base.y"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char version[] = "@(#)jas/base.y	v2 Jan 03 1997";

#include "jas.h"

int flag;

#define YYSTYPE unsigned
#define YYDEBUG 1 /* we use yyname[] */

%}

%token	ySTRING ySYMBOL yVALUE
%token	yDOT yORG yTEXT yDATA
%token	yRS yBYTE yWORD yASCII yASCIZ
%token	yHI yLO ySIZE yASSERT
%token	yALIGN yFILL yCKSUM yASG

%right	'='
%left	'+' '-'
%left	'*' '/' '%'
%left	yEQU yNEQ yLTE yGTE yOR yAND '>' '<'
%left	ySHL ySHR
%left	'|' '&' '^'
%left	yUPLUS yUMINUS '~' '!'

%start program

%%

program		:
			| program labels line ';' {
				setsize();
			}
			;

line		:
			| directive
			| instruction
			;

labels		:
			| labels ySYMBOL ':' {
				define(U2P($2), dot, 'l');
			}
			;

directive	: yORG expr { *(intext ? &textdot : &datadot) = dot = $2; }

			| yTEXT { intext = 1; dot = textdot; }
			| yDATA { intext = 0; dot = datadot; }

			| yASSERT '(' expr ')' {
				if (! ($$ = $3))
					yyerror("Assert");
			}
			| ySYMBOL yASG expr {
				define(U2P($1), $3, 'a');
			}
			| ySYMBOL '=' expr {
				define(U2P($1), $3, 'a');
			}
			| yRS {
				emit(NULL, 1);
			}
			| yRS expr {
				emit(NULL, $2);
			}
			| yFILL expr ',' expr {
				fill($4, $2);
			}
			| yALIGN expr {
				align(0, $2);
			}
			| yALIGN expr ',' expr {
				align($4, $2);
			}
			| yBYTE  { flag = 'b'; } exprlist
			| yWORD  { flag = 'w'; } exprlist
			| yASCII { flag = 'i'; } stringlist
			| yASCIZ { flag = 'z'; } stringlist
			;

stringlist	: ySTRING {
				emit(U2P($1), yyleng + (flag == 'z'));
			}
			| stringlist ',' ySTRING {
				emit(U2P($3), yyleng + (flag == 'z'));
			}
			;
exprlist	: expr {
				(flag == 'b' ? emitb : emitw)($1);
			}
			| exprlist ',' expr {
				(flag == 'b' ? emitb : emitw)($3);
			}
			;

expr		: yDOT {
				$$ = dot;
			}
			| ySYMBOL {
				$$ = symval(U2P($1));
			}
			| yVALUE {
				$$ = $1;
			}
			| yHI '(' expr ')' {
				$$ = $3 >> 8;
			}
			| yLO '(' expr ')' {
				$$ = $3 & 0xFF;
			}
			| ySIZE '(' ySYMBOL ')' {
				$$ = symsize(U2P($3));
			}
			| yCKSUM '(' expr ',' expr ')' {
				$$ = cksum($3, $5);
			}
			| '(' expr ')' {
				$$ = $2;
			}
			| '+' expr %prec yUPLUS  { $$ = + $2; }
			| '-' expr %prec yUMINUS { $$ = - $2; }
			| '!' expr               { $$ = ! $2; }
			| '~' expr               { $$ = ~ $2; }

			| expr '|' expr { $$ = $1 | $3; }
			| expr '&' expr { $$ = $1 & $3; }
			| expr '^' expr { $$ = $1 ^ $3; }
			| expr '*' expr { $$ = $1 * $3; }
			| expr '/' expr { $$ = $1 / $3; }
			| expr '%' expr { $$ = $1 % $3; }
			| expr '+' expr { $$ = $1 + $3; }
			| expr '-' expr { $$ = $1 - $3; }

			| expr yEQU expr { $$ = $1 == $3; }
			| expr yNEQ expr { $$ = $1 != $3; }
			| expr '<'  expr { $$ = $1 <  $3; }
			| expr '>'  expr { $$ = $1 >  $3; }
			| expr yLTE expr { $$ = $1 <= $3; }
			| expr yGTE expr { $$ = $1 >= $3; }
			| expr yOR  expr { $$ = $1 || $3; }
			| expr yAND expr { $$ = $1 && $3; }

			| expr ySHL expr { $$ = $1 << $3; }
			| expr ySHR expr { $$ = $1 >> $3; }

			;

/* @@_CPU_SPECS_@@ */

# 159 "base.y"

int
getkeyword(name)
	char *name;
{
	int i;

	for (i = YYERRCODE + 1; i <= YYMAXTOKEN; ++i)
		if (isupper(*yyname[i]) && !strcasecmp(yyname[i], name))
			return (i);

#define MAP(x,y) if (!strcmp(name, x)) return (y);

	MAP(".",      yDOT)

	MAP(".rs",    yRS)
	MAP(".org",   yORG)
	MAP(".text",  yTEXT)
	MAP(".data",  yDATA)
	MAP(".byte",  yBYTE)
	MAP(".word",  yWORD)
	MAP(".ascii", yASCII)
	MAP(".asciz", yASCIZ)
	MAP(".align", yALIGN)
	MAP(".fill",  yFILL)
	MAP(".cksum", yCKSUM)
	MAP("equ",    yASG)

	MAP("HI",     yHI)
	MAP("LO",     yLO)
	MAP("SIZE",   ySIZE)
	MAP("ASSERT", yASSERT)

	return (0);
}

