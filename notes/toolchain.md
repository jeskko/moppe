# Toolchain

## Build (2026-09-28): cpp + asmpp + sdasz80 + sdldz80

`firmware/r58.s` is the firmware source, in sdasz80 syntax. `make -C
firmware`:

```
r58.s --cpp -traditional--> --tools/asmpp.py--> r58.pp.s --sdasz80--> r58.rel
      --tools/link.py (sdldz80)--> r58.ihx, r58.map --tools/ihx2bin.py--> r58.bin
```

`make verify` checks the toolchain against the released v3_Z ALs binary
twice: `build-release/` (`r58.asm` converted afresh by as80tosdas.py and
built with this toolchain) and `build-as80/` (`r58.asm` with as80). Both
must be byte-identical. `build-release` is also the reference build of the
differential tests. `r58.s` itself differs from the release since Phase 2
(notes/hybrid-plan.md). `r58.s` was produced from `r58.asm` by
`tools/as80tosdas.py` (one-shot converter, kept for re-running on other
as80 sources such as the ALr variant), then the `C_MODULES` blocks were
edited by hand for the linked C objects; `r58.asm` is now reference only.

### Source dialect

Plain sdasz80 (`(mem)`, `#imm`, `;` comments, `.db/.dw/.ds/.ascii`) plus:

| Feature | Provided by |
|---|---|
| `#define`, `#if`, macros with arguments | GNU `cpp -traditional` (as before; params are substituted inside strings, e.g. `STR("dHz")`) |
| `@` statement separator (macro bodies, since cpp cannot emit newlines) | asmpp |
| as80 local labels `1:` … `1b` / `1f` (digits 1-9, nearest before/after, no scoping by other labels) | asmpp |
| `HI(x)` = `x >> 8` (unmasked, as as80), `LO(x)` = `x & 0xFF` | `firmware/asm.h` |
| `ALIGN(bits, fill)`, `FILL(n, v)` | asm.h (`.rept`) |
| `ASSERT_EQ/LT/LE/GT/GE(a, b)`, `ASSERT_NZ(x)` → `.iif ..., .error 1` | asm.h |
| `name: BYTE` / `WORD` / `FREQ` / `STRING` / `BUF(n)` | `#define`s in r58.s (`.ds n`) |
| `x_size` equates for as80's `SIZE(x)` (bytes of the statement defining x) | emitted by the converter |
| ROM checksum byte `rom_cksum` (as80 `.cksum(0, .)`) | patched by ihx2bin.py |

**Absolute symbols (asmpp).** sdas treats every label as relocatable, even
in an ABS area, and then rejects arithmetic on it (`lbl & 0xFF`, `lbl >> 8`)
or, worse, **assembles some of it silently wrong**: `.dw lbl >> 8` emits
`lbl`, and `>lbl + 1` drops the `+ 1` (tested with sdas 4.6.0). This
firmware does address arithmetic everywhere (page-aligned tables, `LO()`
compares, layout asserts). So asmpp rewrites an area that begins with
`.area NAME (ABS)` / `.org N`: every label `x:` becomes the absolute symbol
`x = N + . - __base_NAME`, every `.` in an expression becomes that value, and
a later `.org E` becomes `.ds E - .` (0xFF gap, as with as80). Arithmetic on
labels is then exact. Only symbols of relocatable areas (the C modules) stay
relocatable: **assembler code may `call`/`ld rr, #` them but must not do
arithmetic on them** (`HI(_cfun)` would be one of the silent cases).

**Expression precedence.** sdas: `* / %` > `+ -` > `<< >>` > `^` > `&` > `|`
(not C's order). as80 had `+ -` lowest, then `* / %`, comparisons, shifts,
and `| & ^` together, tightest. The converter re-parenthesised where the two
disagree. Four as80 ASSERTs could never fail because of as80's order
(`ASSERT(a == b + 8)` parsed as `(a == b) + 8`, etc.); they were converted
as intended and hold.

Other sdas facts found: `.ascii` escape handling is inconsistent (`"\\b"`
gives 5C 08), so the converter writes special bytes as `.db`; sdas macro
arguments are split at spaces even inside quotes, which is why cpp stays
the macro processor; `.bndry` does not fill; makebin/ihx2bin gaps are 0xFF.

`make SRC=... BUILD=...` builds another source into another directory.
asmpp also writes `build/r58.labels` (label names) and `build/r58.linemap`
(listing line → source file:line) for tools; `tools/jp2jr.py` uses the
listing, `r58.sym` and the line map to shorten `jp` to `jr` in r58.s.

### Bank 1

`.area BANK1 (ABS)` / `.org 0x8000` in r58.s (after the fixed ROM) is
absolutized by asmpp like ROM. ihx2bin maps ihx 0x8000-0xBFFF to file
0xC000-0xFFFF and pads the image to 64 KB. Assembler calls into it go
through `far_*` stubs (`call bank1_call / .dw fn`), C `__banked` calls
through SDCC's `___sdcc_bcall_ehl`; both use `set_bank`.

### Bank 2

`.area BANK2 (ABS)` / `.org 0x28000`: a virtual address, so it does not
overlap bank 1 in the .ihx (extended linear address records). Labels are
0x28000 + offset; 16-bit uses of them truncate to the window address.
ihx2bin maps 0x28000-0x2BFFF to file 0x8000-0xBFFF. Stubs: `far2_X: call
bank2_call / .dw X`. Banked C (`#pragma bank N`, area `_CODE_N`) is placed
by link.py after `bankN_end`; the emulator masks bank-2 symbols to 16 bits.
link.py fails when a C module references a symbol inside a bank it does
not run in (bank-2 C → bank 1, fixed C → either bank); calls between banks
go through the fixed-ROM `far_*` stubs. `ADDRESS_ONLY` in link.py lists
symbols C only compares as numbers.

### C modules (`make C=1`)

`c/*.c` → `sdcc -mz80 --sdcccall 1 --reserve-regs-iy --opt-code-size -c` →
`.rel`, linked with the firmware by `tools/link.py`:

- `_CODE` is placed at `rom_end` (after the assembler ROM image and its
  checksum byte), `_DATA` at `c_bss`, a block reserved in firmware RAM
  (`C_BSS_SIZE`, inside the `_bss`…`_end` range the startup code zeroes).
  link.py fails if `_CODE` passes 0x8000, `_DATA` overflows `c_bss`, or any
  other relocatable area is non-empty (no initialised C data: nothing copies
  `_INITIALIZER`).
- SDCC runtime helpers come from SDCC's `z80.lib`, searched in every build
  (the assembler uses its banked-call trampoline `___sdcc_bcall_ehl`).
- C → firmware names: C `x` is `_x`; `tools/cglue.py` emits `_x = x` for
  every `_x` the C objects reference (`build-c/cglue.inc`, included by
  r58.s).
- Firmware → C: a `#define squelch _squelch` block at the top of r58.s
  under `C_MODULES`, and the assembler version under `#ifndef C_MODULES`.

See notes/rewrite-evaluation.md for the register rules C code must follow.

### Symbols for the emulator

`r58emu.load_symbols()` reads `build/r58.map` (all symbols are global:
`sdasz80 -a`), and `build/r58.labels` (written by asmpp) to tell code labels
from equates. A label's size is the distance to the next label. A `.lst`
path is still accepted (as80 listings; for an sdas listing the `.map` next
to it is used).

## as80 (tools/as80) — reference only

The original assembler from `reference/old-devkit/as80` ("jas", 1996-97,
yacc grammar + GNU `cpp -traditional` as macro preprocessor). Dialect:
`!` and `#` comments, `[...]` for memory operands, `ld iv, a` for `ld i, a`,
`ex af` for `ex af, af'`, `1:`/`1b`/`1f` local labels, `#define` macros.

Changes needed to reproduce the released binaries on modern Linux:

| Change | Why |
|---|---|
| `ADD IX,pp` emitted `DD 49+` instead of `DD 09+` (z80.y) | Bug in the devkit copy. The released ROMs contain `DD 09/19/29/39`, so the author's copy was fixed. |
| `(c ? a : b) = x` → `*(c ? &a : &b) = x` (base.y) | Old GCC extension, rejected by modern C. |
| Pointer handle table (`p2u`/`u2p` in lexer.c, jas.h) | Parser values are 32-bit `unsigned`; symbols/strings were stuffed into them as pointers. Crashed on 64-bit. |
| `yytext`/`xxxline` 1 KiB → 16 KiB | Long macro expansions overflowed the listing buffer (cosmetic listing corruption). |
| Parser pre-generated with byacc into `z80parse.c` | Grammar relies on byacc features (`yyname[]` keyword table, implicit tokens); bison rejects it. |

## Verified reproductions (2026-09-28)

| Source | Binary | Result |
|---|---|---|
| `reference/r58.asm.als` (3_Z ALs 24.09.2018) | `reference/r58p8x3Z.bin.als` | identical |
| `reference/r58.asm.alr` (3_Z ALr 23.09.2018) | `reference/r58p8x3Z.bin` | identical |
| `reference/oh3tr/r58p8x3Zi.asc` (3_Z ALi, posted 2011) | `reference/r58p8x3Zi.bin` (2005) | same size, 212 bytes differ — address shifts; the .asc is a slightly different revision than the .bin |

`make -C firmware verify` re-checks the ALs build against its sha256.

Note: `r58p8x3Zi.bin` is **older** (ALi, 17.04.2005) than the ALs source
(24.09.2018), despite being "3.Zi, recommended production version" on the
OH3TR page. The changelog in the source lists ALi before ALJ…ALs.

## Later changes (no effect on output binaries)

- Listing symbol table now includes `_`-prefixed symbols (only as80's
  internal `_relative_label_*` names are hidden), so C symbols are visible.


Superseded: the as80-era C module flow is in toolchain-history.md.
