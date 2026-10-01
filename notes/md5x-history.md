# Talkman MD5x: history

## 2026-10-02: emulator support

Wrote the CDP1802/1806 core and the MD50/MD59/ME59 board in moppe-emu
and booted both firmware lineages. Steps and findings:

- as06: the shipped 2008 i386 binary runs and reproduces the v3.18
  release binaries; listings carry a symbol table, so tests use symbols.
  OH1E's source assembles with the same as06.
- OCR (tesseract, fin; some pages auto-rotated) of the MD50 PE1A, PE2/PE2A
  and AP1 service PDFs found in reference/oh5nxo/mods/MD50bis/sch/; the
  facts went into md5x.md.
- First boot of mx5x on MD59 showed the version screen and the main
  screen at once. The handset turned out to be the R58 CU53AN protocol
  with the parallel-load bit 1 used as a key bit (OH1E's comments:
  idle 1 on CU53, 0 on CU59), so cu53an.c is shared.
- The 1750 Hz call tone measured 1745.6 Hz = the firmware's 132-cycle
  loop at 3.6864 MHz, confirming machine-cycle timing.
- OH1E needed two board details mx5x does not: TOFF must follow XM (its
  txoff waits for "no RF output"), and MD59's RF_OFF is on /EF2.
- OH1E's font packs glyph bits 6..4 one place up ("654_3210"); the
  Python harness converts.
