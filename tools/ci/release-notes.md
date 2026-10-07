**Emulator-tested only.** The R58 C build and the R40 firmware have run
only in the emulator ([moppe-emu](https://github.com/jeskko/moppe-emu)),
never on a real radio. Version 0.x means exactly that.

Trying one means burning a new EPROM and fitting it. Keep the original
EPROM: putting it back restores the radio. The only state the firmware
changes is the battery-backed NV RAM:

- **R58** (`r58-*.bin`, 64 KB EPROM0): the same NV layout as the
  released v3_Z ALs firmware; if settings come out wrong, the first-time
  setup (SAnE) resets them.
- **R40** (`r40-*.bin`, from EPROM address 0): keeps its settings in an
  NV area the Nokia firmware does not use, and only reads Nokia's factory
  calibration.

Transmit with care on the first try: TX power, deviation and CTCSS have
not been measured on hardware. Use a dummy load or a service monitor
first. Reports from real radios are welcome.
