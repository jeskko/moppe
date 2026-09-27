# Toolchain

## as80 (tools/as80)

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
