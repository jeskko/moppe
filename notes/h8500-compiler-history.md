# H8/500 C toolchain: session history

## 2026-10-05 (second session)

- spill.c's rcc crash: not a spilled temporary as first thought, but
  lcc's `reuse()` reducing `INDIRP2(VREGP)` of a temporary holding
  `ADDRGP2 x` as the address itself; emit2's 32-bit load/store looked
  at the original tree. Same mechanism made CSE'd constant shift counts
  go through the variable-shift loop (target() pinned them to r2).
  Fixed with `cse()`.
- Floats: soft float written in C (compiled by this lcc) with asm shims,
  checked bit-exact against host IEEE single arithmetic. Bugs found on
  the way: 32-bit `a - dst` with the result in the right operand's
  register (assert), CVIF2 clobber spilling its own result register,
  float compares branching unsigned, front-end unsigned→float lowering
  (wrong-size constant, double rounding), narrowing 32→16 LOAD marked
  as a copy (cvt.c: `s = l` stored the high word), shims clobbering
  r2/r3 that held a live operand (cvt.c).
- printf %f/%e, atof; crt0 passes argc/argv. cf, cq, cvt now pass;
  `test/run.sh` collects the suite.

## 2026-10-06

- intgen.py (random integer programs, expected values computed in
  Python) found on its first seeds: rcc's ralloc assertion for a
  two-address op pinned to r1 whose right operand was in r1; the
  miscompile `v = a - v` for a register variable; lcc's front end typing
  `unsigned short op unsigned short` as `int` when short is as wide as
  int (signed divide, sign extension). After the fixes ~1150 seeds pass,
  with switches (jump tables and compare chains), pointers and arrays
  added to the generator.

## 2026-10-06 (binutils)

- Built binutils 2.16.1 for h8500-hms (OH5NXO's 2.15 copy had its po/
  directories stripped, which is why the earlier full build failed).
  The round trip over the executed ROM instructions first looked clean
  for `rtd`: dis2 and gas share the table, whose 0x14 entry is wrong for
  #xx:16, so the ROM's `rtd #2` (14 02) plus the next byte read back as
  `rtd #0x212` and reassembled to the same bytes. The check now takes
  RTD and RTE from the bytes; the table is fixed.
