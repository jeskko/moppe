# Toolchain history

## as80 era C modules (until 2026-09-28)

Replaced by linked SDCC objects when the build moved to sdasz80
(toolchain.md). The old flow:

`firmware/c/*.c` → SDCC 4.x (`-mz80 --sdcccall 1 --reserve-regs-iy
--opt-code-size`) → `tools/sdcc2as80.py` → `build-c/<mod>.inc` (code) and
`<mod>_data.inc` (RAM, included before `_end`), `#include`d by r58.asm under
`C_MODULES`. `firmware/c/crt.inc` provides `___sdcc_enter_ix`. Converter
rules: `#imm`→`imm`, `(mem)`→`[mem]`, `d (ix)`→`[ix+d]`, `<(x)`/`>(x)`→
`LO(x)`/`HI(x)`, implicit-A ALU forms, `n$` labels scoped per function,
externals `_x` bound to firmware `x`. See notes/rewrite-evaluation.md for
the register rules C code must follow.
