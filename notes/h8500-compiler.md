# C for the H8/500 (R40 ham firmware toolchain)

lcc 4.2 with a new H8/500 back end, Alfred Arnold's AS (asl) as
assembler and linker-by-concatenation, moppe-emu's CPU core as the test
machine. Decided 2026-10-05 (notes/r40.md "Ham firmware": no C compiler
for the H8/500 survives; an lcc back end was the realistic route).
Files: `tools/h8500/`.

## Start here (next session)

State: `tools/h8500/lcc/build.sh` builds everything; `h8cc.py` compiles
and links; `h8run` runs the image; `tools/h8500/test/run.sh [n]` runs
the tests (~10 s). lcc's tests **8q, array, cf, cq, cvt, incr, init,
sort, spill, stdarg, struct, wf1 pass** (cq against `test/cq.1bk`: x86's
output except the type-size lines). switch, limits and fields assume a
32-bit int; paranoia and yacc need signal/setjmp/stdio streams. Floats:
soft IEEE single in C (`lib/rt/float.c`), bit-exact against the host on
`test/floatgen.c`'s random cases. Random integer programs
(`test/intgen.py`: all operators over the eight integer types, casts,
?:, && ||, calls, arrays with computed indexes, pointers, if/for,
dense and sparse switch; expected values computed in Python under the
target's rules) pass: 550 seeds at two sizes with the full generator, 600 before switch/pointers/arrays were added. Work items:

1. R40 start-up (vectors, watchdog kick, I/O through EP for pages A/B),
   and the firmware itself.
2. Test gaps if the firmware needs them: structs (assignment, arguments,
   returns), local arrays, recursion, `register` pressure with longs,
   bit-fields (16-bit), function pointers. `intgen.py` is the place.
3. Code quality is unexamined (e.g. `mov.w @x,r3 / mov.w r3,r1` pairs).

Run the tests: `tools/h8500/test/run.sh` (exit status 0 = all pass).
Reduce an rcc crash: `test/reduce.py file.c 'assert text'` (line
deletion, then subexpressions to 1; weak on blocks).

## Pieces

| File | What |
|---|---|
| `lcc/h8500.md` | the back end (lburg grammar + C); `%include terms.inc` is replaced by `gen_terms.py`'s %term list (op codes for this target's sizes) |
| `lcc/build.sh` | fetches lcc (github drh/lcc) and AS into `reference/toolchain/`, applies `lcc.patch`, adds the target to bind.c and the makefile, builds rcc/cpp/asl and `h8run` |
| `lcc/lcc.patch` | fixes to lcc's front end for 16-bit int: hex/octal constants try `unsigned int` before `long` (C89; lcc's branch was unreachable), `sizeof` is `unsigned int` and pointer differences `int` where those hold a pointer (lcc hard-coded `unsigned long` / `long`); `binary()` and `promote()` treat `short`/`unsigned short` as `int`/`unsigned` when the same width (lcc compared types by identity, so `unsigned short % unsigned short` was signed `int`); unsigned → float converts through `long` (16-bit) or as `((u>>1)\|(u&1))*2` above the signed range (lcc's `(u>>1)*2.0 + (u&1)` rounds twice with a 24-bit mantissa, and built the `&1` as `unsigned int`) |
| `h8cc.py` | driver: cpp + rcc per C file, `-tag=` per unit for file-local names, asl fix-ups (indent, `@(0-n,r6)`), segment split on `;@code/;@data/;@bss`, library units (`lib/rt`, and `lib/libc` with `--lib sim`) linked only when they define something undefined, one asl run (`-U` case-sensitive), p2bin |
| `lib/crt0.asm` | reset vector, TP/DP/EP = 8, BR = FF, SP, copies data (ROM → RAM), clears bss, calls `main(0, {NULL})`, then `_exit` |
| `lib/rt.asm` | helpers: `__divi2`, `__blkcpy`, `__shl4/__shr4/__sar4`, `__mul4`, `__divu4/__modu4/__divi4/__modi4` |
| `lib/rt/` | library units linked on demand with any `--lib`: `float.c` (soft float: IEEE single, round to nearest even, denormals flushed to zero) and `floatrt.asm` (register shims `__addf` … `__itof4` → the C functions) |
| `test/run.sh`, `test/floatgen.c`, `test/intgen.py`, `test/cq.1bk` | the test suite; floatgen writes a C program of random float cases with the host's results, intgen random integer programs with expected values |
| `test/reduce.py` | shrinks a C file that crashes rcc |
| `lib/sim.asm` | h8run console: `_putchar`, `_getchar`, `_exit` |
| `lib/include`, `lib/libc` | stdarg/stddef/stdio/stdlib/string/limits; printf (%d %u %x %o %c %s %f %e, l, width, precision, 0, -; floats to about 7 digits), atof, str*/mem*, malloc (bump) |
| `h8run.c` | runs an image on emu/h8500.c: ROM 0-3FFFF, RAM page 8, putchar 8FFF0, exit 8FFF1, getchar word 8FFF2; `-s` states, `-t lo-hi` trace |
| `check_asl.py` | asl round trip on every instruction the Nokia ROM executes: 8023, no errors, no differences (needs reference/ghidra-r40/coverage.bin) |

## GNU binutils 2.16.1 (evaluated 2026-10-06, not used by h8cc)

`tools/h8500/binutils/build.sh` builds gas, ld, objdump, objcopy, nm and
size for `h8500-hms` (2.16.1, the last release with the target; its
H8/500 files are 2.15's plus cleanups, opcode table identical; a changed
`h8500.patch` triggers a fresh extract and build). Patched:

- opcode table: `rtd #xx:16` is 0x1C (gas emitted 0x14, the 8-bit
  opcode), RTE added, the disassembler table's `mov:g.w #xx:8` /
  `cmp:g.w #xx:8` fixes from r40work.
- gas: `mov:g.w` / `cmp:g.w` to a general EA use the sign-extended
  `#xx:8` form (06 / 04) for constants in -128..127 or 0xff80..0xffff;
  `#xx:8` / `#xx:16` written explicitly are honoured (`:8` out of range
  or without such a form is an error). A word op with an *immediate
  source EA* has no 8-bit form: 0x04 there means a byte operation
  (`add.w #5,r0` stays `0C 0005 20`). `bra.w`/`beq.w`/`bsr.w label`
  accepted. A branch to a number (`bra 0x1234`) no longer segfaults: a
  16-bit branch with an absolute reloc. Explicit 16-bit branches
  (`bra l:16`) were 2 bytes off (`md_pcrel_from` used the fix size 4).
- bfd/ld: `R_H8500_PCREL16` was computed from field+1 (linked 16-bit
  branches landed one byte past the target); relocs are applied in
  address order (gas writes a relaxed branch's reloc last, which was
  then applied in the wrong place).
- one header line modern gcc rejects.

Tests: `tools/h8500/binutils/test_gas.py` (immediate boundaries,
explicit sizes and errors, RTD/RTE, every branch form, two objects
linked at 0 and 0x2000; the build without the gas/bfd patches fails 16 checks and cannot assemble the link test) and
`tools/h8500/check_gas.py` (each executed ROM instruction assembled
alone at its address, ~2 s): **8028 instructions, 8023 byte-identical,
5 `cmp:g.w #xx:16,Rn` in the other equal-length form, 0 wrong**. The 7
word STC/LDC SR forms dis2 cannot decode assemble to the ROM's bytes
(checked by hand). ld links COFF objects; a two-file program ran on
h8run.

Still: comments are `!` (`;` separates statements). Versus asl: a real
linker (objects, sections, linker scripts with the h8500s/m/c/b model
emulations, archives); lcc's output would need gas syntax.

## ABI and model

- Small model: code in page 0 (JSR/RTS, 16-bit code addresses, must end
  below 0xFF80), data/bss/stack in page 8 with 16-bit pointers; const
  and initialized data live in RAM, copied by crt0 (asl `phase`).
- char 8 signed, short/int/pointer 16, long 32, float/double 32
  (helpers). Big-endian; a long in a register pair rN:rN+1 (N even),
  high word in rN.
- r0-r3 caller-saved temporaries, r4-r5 callee-saved (register
  variables; saved with STM after LINK), r6 = FP (LINK/UNLK), r7 = SP.
  Arguments pushed right to left as words, caller pops; results in r0
  or r0:r1. Args at @(4,fp); locals below FP.
- Float helpers take r0:r1 and r2:r3, return r0:r1 (`__cmpf` −1/0/1
  in r0, branched on signed); they keep every other register, r1-r3
  included, because an operand register may still hold a live temporary.
- MULXU/DIVXU need even pairs: target() pins 16-bit MUL/DIV/MOD to
  r0:r1 (divisor r2); signed 16-bit divide and all 32-bit mul/div/mod
  and variable 32-bit shifts are helper calls; 32-bit add/sub/logic,
  compares, constant shifts and conversions are inline from emit2.
- C names get a leading `_` (asl reserved words); file-local names
  `S_<tag>_`, labels `L_<tag>_`.

## Things learnt (asl, lcc)

- asl: H8/500 is `cpu HD6475328` + `maxmode on`; needs `assume dp/br`;
  `@aa:16` operands are written as full 24-bit addresses in DP's page;
  it picks the shortest encoding itself; `&` binds tighter than `+`
  (write `((sym+2)&$FFFF)`); no leading `-` in a displacement
  (`@(0-18,r6)`); labels must be in column 1, instructions indented;
  `dc.b/dc.w`, `ds.b`, `align`, `phase/dephase`.
- lcc: a read of a temporary whose value is a constant or an address
  (`u.t.cse` CNST/ADDR*) is reduced as that tree when a rule matches it
  at cost 0 (gen.c `reuse`, `x.mayrecalc`); emit2 and target() must look
  through it (`cse()` in h8500.md), or e.g. a CSE'd shift count looks
  like a register. `move(a)` marks a rule as a copy that `requate` may
  rename away: never for a LOAD that narrows a 32-bit pair (`move2`).
  clobber() must not spill a register of the node's own result.
- Two-address rules (`?mov.w %0,%c / op %1,%c`): lcc only protects a
  wildcard result from sharing the right operand's register. A result
  pinned by target() (`ktarget`) or an assignment to a register
  variable read by the right operand (`v = a - v`, which compiled to
  `mov a,v / sub v,v`) go through a LOAD instead (`loadtarget`).
- lcc: a template starting with `#` calls emit2 (write a literal `#`
  as `%#`); register wildcards scan 32 slots; narrowing conversions
  arrive as LOAD nodes; a two-address (`?`) result is kept off the
  right operand's register only when the result register is free, so
  RET is not targeted (emit2 moves to r0); register-variable reads are
  not listed in `x.kids`.
- lcc licence (CPYRIGHT): free use and redistribution with the notice;
  not to be sold, nor products derived from it.
