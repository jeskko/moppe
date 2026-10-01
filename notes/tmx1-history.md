# TMx-1 notes: history

## 2026-10-01: emulator implications (before the emulator existed)

- uPD7810 core with its on-chip timers (INTT0/1), timer/event counter, serial port and A/D: much more on-chip peripheral work than the 1802 or Z80.
- A full TMx-1 run means two 7810s (radio + handset) linked by MBUS, or the handset modelled at MBUS packet level.
- `pit.c` (8254) covers the i8253 modes used here.
- The licence limits test fixtures: keep the binaries local (like `reference/`), or ask OH3NWQ.

## 2026-10-02: emulator

Built the uPD7810 core, the radio unit and both handsets in moppe-emu in
one session. Data used: the 78C10A data sheet's instruction table (state
counts), as7810's grammar (989 instruction forms cross-checked), the
service manual's memory map, pin table and watchdog, and the firmware's
comments for every mode-register value. It booted the v5.0 firmware with
the HSN-2 at the first try; the only bring-up fixes were in the board
(TxD of a unit cut off mid-character stayed low; the host transmitter did
not wait for a free bus).
