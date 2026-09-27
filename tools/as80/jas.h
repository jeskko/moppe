
extern int  yydebug;
extern int  yyleng;
extern int  yylineno;
extern char yytext[];
extern char yyfile[];

FILE *fin;

int
	debug,
	pass,
	intext;

unsigned
	dot,
	textdot,
	datadot,
	lowtext,
	maxtext,
	lowdata,
	maxdata;

unsigned char *mem;

extern
	emitb(unsigned),
	emitw(unsigned);

typedef struct symbol {
	struct symbol *next;
	char          *name;
	unsigned       value;
	unsigned       size;
	unsigned       type:8,
	               defined:1,
	               :0;
} symbol;

symbol
	*symbols,
	*lastsym,
	*getsym(char *name);


/*
 * 64-bit port: YYSTYPE is a 32-bit unsigned, so pointers passed through
 * the parser (strings, symbols) are stored in a table and referred to by
 * index.  The table is reset at the start of each pass.
 */
unsigned p2u(void *p);
void    *u2p(unsigned u);
void     p2u_reset(void);
#define U2P(u) u2p(u)
