# MDR150: history

## 2026-10-08: HaMDR rebuild, then emulator

- First rebuild of binutils 2.9.1 and gcc 2.8.1 from `MDR150/gnu/` was done by hand in the session scratchpad (32-bit host build); every HaMDR 174 object and the linked `hamdr.hex` came out byte-identical to OH5NXO's 2015 build. The fixes it needed went into `tools/hc16/build.sh`, and `tools/hc16/hamdr.sh` + `hamdr_syms.py` (symbol table for the emulator's `load_syms()`) followed.
- Emulator order: CPU16 core and HC16Z1 modules with the board (APRS out/in, digipeating, KISS), then the terminal UI, then DTR as the mode switch (HaMDR reads DTR at start: command mode with it) and `load_syms()`.
