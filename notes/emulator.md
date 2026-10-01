# Emulator

The emulator moved to its own repo, **moppe-emu** (2026-10-01), which is
this repo's `emu/` submodule. Its design notes are `emu/notes/emulator.md`.

Here stay the firmware tests that use it (`tests/`, with `difftest.py`
and `rflink.py`) and `tools/emuoracle.py`, the bit-identity check for any
emulator change (it needs the firmware build).

An emulator change: commit it in `emu/`, run `python3 tools/ci/runtests.py`
and `tools/emuoracle.py` here, then commit the new `emu` submodule pointer
in this repo.
