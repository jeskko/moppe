**Emulator-tested only.** The R58 C build and the R40 firmware have run
only in the emulator ([moppe-emu](https://github.com/jeskko/moppe-emu)),
never on a real radio. Version 0.x means exactly that.

Trying one means burning a new EPROM and fitting it. Keep the original
EPROM: putting it back restores the radio. The only state the firmware
changes is the battery-backed NV RAM (and on the RB58VY its EEPROM):

- **R58** (`r58-<version>.bin`, 64 KB EPROM0): the same NV layout as the
  released v3_Z ALs firmware; if settings come out wrong, the first-time
  setup (SAnE) resets them. For the P8E / P8N cards (RB58, RC58, RD58).
- **RB58VY** (`r58-l8m-*`, L8M logic board): the same firmware built for
  that board; **not interchangeable** with the R58 image. Burn
  `-eprom0.bin` and `-eprom1.bin` into two 27C256 (the 64 KB
  `r58-l8m-*.bin` is both, for the emulator). It also keeps its
  essentials in the board's EEPROM, over what the original firmware kept
  there: read the EEPROM out first if you want to go back. No FFSK, CTCSS
  or DTMF decoding yet.
- **R40** (`r40-*.bin`, from EPROM address 0): keeps its settings in an
  NV area the Nokia firmware does not use, and only reads Nokia's factory
  calibration.

Transmit with care on the first try: TX power, deviation and CTCSS have
not been measured on hardware. Use a dummy load or a service monitor
first. Reports from real radios are welcome.
