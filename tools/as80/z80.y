
constant	: expr {
				$$ = $1;
			}
			;
memory		: '[' constant ']' {
				$$ = $2;
			}
			;
indexed		: '[' xy ']' {
				$$ = $2;
			}
			| '[' xy '+' constant ']' {
				$$ = $2 | ((+ $4) << 8);
			}
			| '[' xy '-' constant ']' {
				$$ = $2 | ((- $4) << 8);
			}
			;
reg			: B {
				$$ = 0;
			}
			| C {
				$$ = 1;
			}
			| D {
				$$ = 2;
			}
			| E {
				$$ = 3;
			}
			| H {
				$$ = 4;
			}
			| L {
				$$ = 5;
			}
areg		: reg {
				$$ = $1;
			}
			| A {
				$$ = 7;
			}
			;
cc			: NZ {
				$$ = 0;
			}
			| Z {
				$$ = 1;
			}
			| NC {
				$$ = 2;
			}
			| C {
				$$ = 3;
			}
			| PO {
				$$ = 4;
			}
			| PE {
				$$ = 5;
			}
			| P {
				$$ = 6;
			}
			| M {
				$$ = 7;
			}
			;
xy			: IX {
				$$ = 0xdd;
			}
			| IY {
				$$ = 0xfd;
			}
			;
pp			: bcdesp {
				$$ = $1;
			}
			| IX {
				$$ = 2;
			}
			;
rr			: bcdesp {
				$$ = $1;
			}
			| IY {
				$$ = 2;
			}
			;
pr			: bcdehl {
				$$ = $1;
			}
			| AF {
				$$ = 3;
			}
			;
bcde		: BC {
				$$ = 0;
			}
			| DE {
				$$ = 1;
			}
			;
bcdehl		: bcde {
				$$ = $1;
			}
			| HL {
				$$ = 2;
			}
			;
bcdesp		: bcde {
				$$ = $1;
			}
			| SP {
				$$ = 3;
			}
			;
bcdehlsp	: bcdehl {
				$$ = $1;
			}
			| SP {
				$$ = 3;
			}
			;
jrflag		: C {
				$$ = 0x38;
			}
			| NC {
				$$ = 0x30;
			}
			| Z {
				$$ = 0x28;
			}
			| NZ {
				$$ = 0x20;
			}
			;

instruction	: LD A ',' areg {
				op(0x40 | (7 << 3) | $4);
			}
			| LD reg ',' areg {
				op(0x40 | ($2 << 3) | $4);
			}
			| LD A ',' constant {
				op2(0x06 | (7 << 3), $4);
			}
			| LD reg ',' constant {
				op2(0x06 | ($2 << 3), $4);
			}
			| LD A ',' '[' HL ']' {
				op(0x46 | (7 << 3));
			}
			| LD reg ',' '[' HL ']' {
				op(0x46 | ($2 << 3));
			}
			| LD A ',' indexed {
				op3($4, 0x46 | (7 << 3), $4 >> 8);
			}
			| LD reg ',' indexed {
				op3($4, 0x46 | ($2 << 3), $4 >> 8);
			}
			| LD '[' HL ']' ',' areg {
				op(0x70 | $6);
			}
			| LD indexed ',' areg {
				op3($2, 0x70 | ($4), $2 >> 8);
			}
			| LD '[' HL ']' ',' constant {
				op2(0x36, $6);
			}
			| LD indexed ',' constant {
				op4($2, 0x36, $2 >> 8, $4);
			}
			| LD A ',' '[' bcde ']' {
				op(0x0a | ($5 << 4));
			}
			| LD A ',' memory {
				op3(0x3a, $4, $4 >> 8);
			}
			| LD '[' bcde ']' ',' A {
				op(0x02 | ($3 << 4));
			}
			| LD memory ',' A {
				op3(0x32, $2, $2 >> 8);
			}
			| LD A ',' IV {
				op2(0xed, 0x57);
			}
			| LD A ',' R {
				op2(0xed, 0x5f);
			}
			| LD IV ',' A {
				op2(0xed, 0x47);
			}
			| LD R ',' A {
				op2(0xed, 0x4f);
			}
			| LD SP ',' constant {
				op3(0x01 | (3 << 4), $4, $4 >> 8);
			}
			| LD bcdehl ',' constant {
				op3(0x01 | ($2 << 4), $4, $4 >> 8);
			}
			| LD xy ',' constant {
				op4($2, 0x21, $4, $4 >> 8);
			}
			| LD bcdehl ',' memory {
				if ($2 == 2)
					op3(0x2a, $4, $4 >> 8); /* HL */
				else
					op4(0xed, 0x4b | ($2 << 4), $4, $4 >> 8); /* BC DE SP */
			}
			| LD SP ',' memory {
				op4(0xed, 0x4b | (3 << 4), $4, $4 >> 8);
			}
			| LD xy ',' memory {
				op4($2, 0x2a, $4, $4 >> 8);
			}
			| LD memory ',' bcdehlsp {
				if ($4 == 2)
					op3(0x22, $2, $2 >> 8); /* HL */
				else
					op4(0xed, 0x43 | ($4 << 4), $2, $2 >> 8);
			}
			| LD memory ',' xy {
				op4($4, 0x22, $2, $2 >> 8);
			}
			| LD SP ',' HL {
				op(0xf9);
			}
			| LD SP ',' xy {
				op2($4, 0xf9);
			}
			| PUSH pr {
				op(0xc5 | ($2 << 4));
			}
			| PUSH xy {
				op2($2, 0xe5);
			}
			| POP pr {
				op(0xc1 | ($2 << 4));
			}
			| POP xy {
				op2($2, 0xe1);
			}
			| EX DE ',' HL {
				op(0xeb);
			}
			| EX HL ',' DE {
				op(0xeb);
			}
			| EX AF {
				op(0x08);
			}
			| EXX {
				op(0xd9);
			}
			| EX '[' SP ']' ',' HL {
				op(0xe3);
			}
			| EX HL ',' '[' SP ']' {
				op(0xe3);
			}
			| EX '[' SP ']' ',' xy {
				op2($2, 0xe3);
			}
			| EX xy ',' '[' SP ']' {
				op2($2, 0xe3);
			}
			| LDI {
				op2(0xed, 0xa0);
			}
			| LDIR {
				op2(0xed, 0xb0);
			}
			| LDD {
				op2(0xed, 0xa8);
			}
			| LDDR {
				op2(0xed, 0xb8);
			}
			| CPI {
				op2(0xed, 0xa1);
			}
			| CPIR {
				op2(0xed, 0xb1);
			}
			| CPD {
				op2(0xed, 0xa9);
			}
			| CPDR {
				op2(0xed, 0xb9);
			}
			| ADD areg {
				op(0x80 | $2);
			}
			| ADD constant {
				op2(0xc6, $2);
			}
			| ADD '[' HL ']' {
				op(0x86);
			}
			| ADD indexed {
				op3($2, 0x86, $2 >> 8);
			}
			| ADC areg {
				op(0x88 | $2);
			}
			| ADC constant {
				op2(0xce, $2);
			}
			| ADC '[' HL ']' {
				op(0x8e);
			}
			| ADC indexed {
				op3($2, 0x8e, $2 >> 8);
			}
			| SUB areg {
				op(0x90 | $2);
			}
			| SUB constant {
				op2(0xd6, $2);
			}
			| SUB '[' HL ']' {
				op(0x96);
			}
			| SUB indexed {
				op3($2, 0x96, $2 >> 8);
			}
			| SBC areg {
				op(0x98 | $2);
			}
			| SBC constant {
				op2(0xde, $2);
			}
			| SBC '[' HL ']' {
				op(0x9e);
			}
			| SBC indexed {
				op3($2, 0x9e, $2 >> 8);
			}
			| AND areg {
				op(0xa0 | $2);
			}
			| AND constant {
				op2(0xe6, $2);
			}
			| AND '[' HL ']' {
				op(0xa6);
			}
			| AND indexed {
				op3($2, 0xa6, $2 >> 8);
			}
			| OR areg {
				op(0xb0 | $2);
			}
			| OR constant {
				op2(0xf6, $2);
			}
			| OR '[' HL ']' {
				op(0xb6);
			}
			| OR indexed {
				op3($2, 0xb6, $2 >> 8);
			}
			| XOR areg {
				op(0xa8 | $2);
			}
			| XOR constant {
				op2(0xee, $2);
			}
			| XOR '[' HL ']' {
				op(0xae);
			}
			| XOR indexed {
				op3($2, 0xae, $2 >> 8);
			}
			| CP areg {
				op(0xb8 | $2);
			}
			| CP constant {
				op2(0xfe, $2);
			}
			| CP '[' HL ']' {
				op(0xbe);
			}
			| CP indexed {
				op3($2, 0xbe, $2 >> 8);
			}
			| INC areg {
				op(0x04 | ($2 << 3));
			}
			| INC '[' HL ']' {
				op(0x34);
			}
			| INC indexed {
				op3($2, 0x34, $2 >> 8);
			}
			| DEC areg {
				op(0x05 | ($2 << 3));
			}
			| DEC '[' HL ']' {
				op(0x35);
			}
			| DEC indexed {
				op3($2, 0x35, $2 >> 8);
			}
			| DAA {
				op(0x27);
			}
			| CPL {
				op(0x2f);
			}
			| NEG {
				op2(0xed, 0x44);
			}
			| CCF {
				op(0x3f);
			}
			| SCF {
				op(0x37);
			}
			| NOP {
				op(0x00);
			}
			| HALT {
				op(0x76);
			}
			| DI {
				op(0xf3);
			}
			| EI {
				op(0xfb);
			}
			| IM0 {
				op2(0xed, 0x46);
			}
			| IM1 {
				op2(0xed, 0x56);
			}
			| IM2 {
				op2(0xed, 0x5e);
			}
			| ADD HL ',' bcdehlsp {
				op(0x09 | ($4 << 4));
			}
			| ADC HL ',' bcdehlsp {
				op2(0xed, 0x4a | ($4 << 4));
			}
			| SBC HL ',' bcdehlsp {
				op2(0xed, 0x42 | ($4 << 4));
			}
			| ADD IX ',' pp {
				op2(0xdd, 0x09 | ($4 << 4));
			}
			| ADD IY ',' rr {
				op2(0xfd, 0x09 | ($4 << 4));
			}
			| INC bcdehlsp {
				op(0x03 | ($2 << 4));
			}
			| INC xy {
				op2($2, 0x23);
			}
			| DEC bcdehlsp {
				op(0x0b | ($2 << 4));
			}
			| DEC xy {
				op2($2, 0x2b);
			}
			| RLCA {
				op(0x07);
			}
			| RLA {
				op(0x17);
			}
			| RRCA {
				op(0x0f);
			}
			| RRA {
				op(0x1f);
			}
			| RLC areg {
				op2(0xcb, $2);
			}
			| RLC '[' HL ']' {
				op2(0xcb, 0x06);
			}
			| RLC indexed {
				op4($2, 0xcb, $2 >> 8, 0x06);
			}
			| RL areg {
				op2(0xcb, 0x10 | $2);
			}
			| RL '[' HL ']' {
				op2(0xcb, 0x16);
			}
			| RL indexed {
				op4($2, 0xcb, $2 >> 8, 0x16);
			}
			| RRC areg {
				op2(0xcb, 0x08 | $2);
			}
			| RRC '[' HL ']' {
				op2(0xcb, 0x0e);
			}
			| RRC indexed {
				op4($2, 0xcb, $2 >> 8, 0x0e);
			}
			| RR areg {
				op2(0xcb, 0x18 | $2);
			}
			| RR '[' HL ']' {
				op2(0xcb, 0x1e);
			}
			| RR indexed {
				op4($2, 0xcb, $2 >> 8, 0x1e);
			}
			| SLA areg {
				op2(0xcb, 0x20 | $2);
			}
			| SLA '[' HL ']' {
				op2(0xcb, 0x26);
			}
			| SLA indexed {
				op4($2, 0xcb, $2 >> 8, 0x26);
			}
			| SRA areg {
				op2(0xcb, 0x28 | $2);
			}
			| SRA '[' HL ']' {
				op2(0xcb, 0x2e);
			}
			| SRA indexed {
				op4($2, 0xcb, $2 >> 8, 0x2e);
			}
			| SRL areg {
				op2(0xcb, 0x38 | $2);
			}
			| SRL '[' HL ']' {
				op2(0xcb, 0x3e);
			}
			| SRL indexed {
				op4($2, 0xcb, $2 >> 8, 0x3e);
			}
			| RLD {
				op2(0xed, 0x6f);
			}
			| RRD {
				op2(0xed, 0x67);
			}
			| BIT constant ',' areg {
				op2(0xcb, 0x40 | ($2 << 3) | $4);
			}
			| BIT constant ',' '[' HL ']' {
				op2(0xcb, 0x46 | ($2 << 3));
			}
			| BIT constant ',' indexed {
				op4($4, 0xcb, $4 >> 8, 0x46 | ($2 << 3));
			}
			| SET constant ',' areg {
				op2(0xcb, 0xc0 | ($2 << 3) | $4);
			}
			| SET constant ',' '[' HL ']' {
				op2(0xcb, 0xc6 | ($2 << 3));
			}
			| SET constant ',' indexed {
				op4($4, 0xcb, $4 >> 8, 0xc6 | ($2 << 3));
			}
			| RES constant ',' areg {
				op2(0xcb, 0x80 | ($2 << 3) | $4);
			}
			| RES constant ',' '[' HL ']' {
				op2(0xcb, 0x86 | ($2 << 3));
			}
			| RES constant ',' indexed {
				op4($4, 0xcb, $4 >> 8, 0x86 | ($2 << 3));
			}
			| JP constant {
				op3(0xc3, $2, $2 >> 8);
			}
			| JP cc ',' constant {
				op3(0xc2 | ($2 << 3), $4, $4 >> 8);
			}
			| JR constant {
				int off = $2 - dot - 2;
				if (pass == 2 && (off < -125 || off > 125))
					yyerror("relative out of range");
				op2(0x18, off);
			}
			| JR jrflag ',' constant {
				int off = $4 - dot - 2;
				if (pass == 2 && (off < -125 || off > 125))
					yyerror("relative out of range");
				op2($2, off);
			}
			| JP '[' HL ']' {
				op(0xe9);
			}
			| JP '[' xy ']' {
				op2($3, 0xe9);
			}
			| DJNZ constant {
				int off = $2 - dot - 2;
				if (pass == 2 && (off < -125 || off > 125))
					yyerror("relative out of range");
				op2(0x10, $2 - dot - 2);
			}
			| CALL constant {
				op3(0xcd, $2, $2 >> 8);
			}
			| CALL cc ',' constant {
				op3(0xc4 | ($2 << 3), $4, $4 >> 8);
			}
			| RET {
				op(0xc9);
			}
			| RET cc {
				op(0xc0 | ($2 << 3));
			}
			| RETI {
				op2(0xed, 0x4d);
			}
			| RETN {
				op2(0xed, 0x45);
			}
			| RST constant {
				op(0xc7 | ($2 << 3));
			}
			| IN A ',' '[' constant ']' {
				op2(0xdb, $5);
			}
			| IN A ',' '[' C ']' {
				op2(0xed, 0x40 | (7 << 3));
			}
			| IN reg ',' '[' C ']' {
				op2(0xed, 0x40 | ($2 << 3));
			}
			| INI {
				op2(0xed, 0xa2);
			}
			| INIR {
				op2(0xed, 0xb2);
			}
			| IND {
				op2(0xed, 0xaa);
			}
			| INDR {
				op2(0xed, 0xba);
			}
			| OUT '[' constant ']' ',' A {
				op2(0xd3, $3);
			}
			| OUT '[' C ']' ',' areg {
				op2(0xed, 0x41 | ($6 << 3));
			}
			| OUTI {
				op2(0xed, 0xa3);
			}
			| OTIR {
				op2(0xed, 0xb3);
			}
			| OUTD {
				op2(0xed, 0xab);
			}
			| OTDR {
				op2(0xed, 0xbb);
			}
	/* UNDOC illegal Z80 */
			| INC hlxy {
				op2($2 >> 8, 0x24 | ($2 << 3));
			}
			| DEC hlxy {
				op2($2 >> 8, 0x25 | ($2 << 3));
			}
			| LD hlxy ',' constant {
				op3($2 >> 8, 0x26 | ($2 << 3), $4);
			}
			| LD hlxy ',' reg {
				if ($4 & ~3)
					yyerror("H/L X/Y only from ABCDE");
				op2($2 >> 8, 0x60 | ($2 << 3) | $4);
			}
			| LD hlxy ',' A {
				op2($2 >> 8, 0x60 | ($2 << 3) | 7);
			}
			| LD reg ',' hlxy {
				if ($2 & ~3)
					yyerror("H/L X/Y only to ABCDE");
				op2($4 >> 8, 0x44 | ($2 << 3) | $4);
			}
			| LD A ',' hlxy {
				op2($4 >> 8, 0x44 | (7 << 3) | $4);
			}
			;

hlxy		: HX {
				$$ = 0xdd00;
			}
			| LX {
				$$ = 0xdd01;
			}
			| HY {
				$$ = 0xfd00;
			}
			| LY {
				$$ = 0xfd01;
			}
			;

%%

char *cpu_family = "z80";

