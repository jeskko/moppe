# Emulator

The emulator moved to its own repo, **moppe-emu** (2026-10-01), which is
this repo's `emu/` submodule; public at <https://github.com/jeskko/moppe-emu>
since 2026-10-02 (fetch over https, push over ssh: `emu/`'s push URL is
git@github.com:jeskko/moppe-emu.git). Its design notes are
`emu/notes/emulator.md`.

Here stay the firmware tests that use it (`tests/r58/` and `tests/r40/`, with `difftest.py`
and `rflink.py` in `tests/r58/`) and `tools/r58/emuoracle.py`, the bit-identity check for any
emulator change (it needs the firmware build).

An emulator change: commit it in `emu/`, run `python3 tools/ci/runtests.py`
and `tools/r58/emuoracle.py` here, push `emu/` to GitHub, then commit the new
`emu` submodule pointer in this repo (a pointer to an unpushed commit
breaks fresh clones).
