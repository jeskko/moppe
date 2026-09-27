# as80 - Z80 assembler from the original R58 devkit (jas, 1996-97),
# ported to 64-bit Linux.  The parser (z80parse.c, y.tab.h) is pre-generated
# with Berkeley yacc (byacc), which this grammar relies on (yyname[] for
# keyword lookup, implicit token declarations).  Run `make parser` to
# regenerate it if base.y or z80.y change; that requires byacc.

CC      ?= cc
CFLAGS  ?= -O2
CFLAGS  += -std=gnu89 -w -fcommon
YACC    ?= byacc

as80: z80parse.c main.c lexer.c jas.h y.tab.h
	$(CC) $(CFLAGS) -o $@ z80parse.c main.c lexer.c

parser: base.y z80.y
	sed "/@@_CPU_SPECS_@@/r z80.y" < base.y > tmpcpu.y
	$(YACC) -d tmpcpu.y
	mv y.tab.c z80parse.c
	rm -f tmpcpu.y

clean:
	rm -f as80

.PHONY: parser clean
