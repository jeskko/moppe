# C for the H8/500 (R40 ham firmware toolchain)

lcc 4.2 with a new H8/500 back end, Alfred Arnold's AS (asl) as
assembler and linker-by-concatenation, moppe-emu's CPU core as the test
machine. Decided 2026-10-05 (notes/r40.md "Ham firmware": no C compiler
for the H8/500 survives; an lcc back end was the realistic route).
Files: `tools/h8500/`.

## Start here (next session)

State: `tools/h8500/lcc/build.sh` builds everything; `h8cc.py` compiles
and links; `h8run` runs the image. lcc's own tests, compared with lcc's
x86 expected output: **8q, array, incr, init, sort, struct, wf1 match**;
stdarg matches except `%f` (no floats yet); switch, limits and fields
need a 32-bit int (not applicable). Work items, in order:

1. **spill.c crashes rcc** (`getregnum` assertion in `ea4`, function
   `f5`): an `ASGNF4` whose address is `INDIRP2(VREGP)` of a lcc
   temporary that has been spilled (its symbol has sclass AUTO, no
   regnode) and is not in `x.kids`. The 32-bit load/store code in
   `emit2` (cases INDIR / ASGN, `ea4`) must cope with a spilled
   address temporary: look at how gen.c's `genreload` rewrites
   `x.kids`, or restrict 32-bit memory rules to forms whose address is
   always in `x.kids`. Then rerun the lcc tests (command below).
2. Floats: rules exist (helper calls `__addf`, `__subf`, `__mulf`,
   `__divf`, `__cmpf`, `__ftoi2/4`, `__itof2/4`), the helpers do not.
   Needed for printf `%f` and cq.c/cvt.c; not for the ham firmware.
3. A differential test generator: random C over explicit 16/32-bit
   types, run on h8run and on the host (gcc with int16_t/int32_t and a
   cast after every operation), compare outputs. lcc's tests cover
   little register pressure.
4. Then: R40 start-up (vectors, watchdog kick, I/O through EP for pages
   A/B), and the firmware itself.

Run lcc's tests:

    L=reference/toolchain/lcc
    for t in 8q array incr init sort stdarg struct wf1 spill; do
      tools/h8500/h8cc.py -o /tmp/$t.bin $L/tst/$t.c 2>/dev/null &&
      tools/h8500/h8run /tmp/$t.bin < $L/tst/$t.0 | cmp - $L/x86/linux/tst/$t.1bk && echo "$t ok"
    done

## Pieces

| File | What |
|---|---|
| `lcc/h8500.md` | the back end (lburg grammar + C); `%include terms.inc` is replaced by `gen_terms.py`'s %term list (op codes for this target's sizes) |
| `lcc/build.sh` | fetches lcc (github drh/lcc) and AS into `reference/toolchain/`, applies `lcc.patch`, adds the target to bind.c and the makefile, builds rcc/cpp/asl and `h8run` |
| `lcc/lcc.patch` | fixes to lcc's front end for 16-bit int: hex/octal constants try `unsigned int` before `long` (C89; lcc's branch was unreachable), `sizeof` is `unsigned int` and pointer differences `int` where those hold a pointer (lcc hard-coded `unsigned long` / `long`) |
| `h8cc.py` | driver: cpp + rcc per C file, `-tag=` per unit for file-local names, asl fix-ups (indent, `@(0-n,r6)`), segment split on `;@code/;@data/;@bss`, library units linked only when they define something undefined, one asl run (`-U` case-sensitive), p2bin |
| `lib/crt0.asm` | reset vector, TP/DP/EP = 8, BR = FF, SP, copies data (ROM → RAM), clears bss, calls `_main`, then `_exit` |
| `lib/rt.asm` | helpers: `__divi2`, `__blkcpy`, `__shl4/__shr4/__sar4`, `__mul4`, `__divu4/__modu4/__divi4/__modi4` |
| `lib/sim.asm` | h8run console: `_putchar`, `_getchar`, `_exit` |
| `lib/include`, `lib/libc` | stdarg/stddef/stdio/stdlib/string/limits; printf (%d %u %x %o %c %s, l, width, 0, -), str*/mem*, malloc (bump) |
| `h8run.c` | runs an image on emu/h8500.c: ROM 0-3FFFF, RAM page 8, putchar 8FFF0, exit 8FFF1, getchar word 8FFF2; `-s` states, `-t lo-hi` trace |
| `check_asl.py` | asl round trip on every instruction the Nokia ROM executes: 8023, no errors, no differences (needs reference/ghidra-r40/coverage.bin) |

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
- lcc: a template starting with `#` calls emit2 (write a literal `#`
  as `%#`); register wildcards scan 32 slots; narrowing conversions
  arrive as LOAD nodes; a two-address (`?`) result is kept off the
  right operand's register only when the result register is free, so
  RET is not targeted (emit2 moves to r0); register-variable reads are
  not listed in `x.kids`.
- lcc licence (CPYRIGHT): free use and redistribution with the notice;
  not to be sold, nor products derived from it.
