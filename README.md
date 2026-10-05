# Mobira R58 / RD58 firmware workbench

Tools for developing the community ham firmware (OH5NXO et al., v3_Z "ALs",
24.09.2018) for the Mobira/Nokia R58 series (RB58 6 m, RC58 2 m, RD58 70 cm)
without burning an EPROM for every change.

## Status (2026-09-29)

| Area | State |
|---|---|
| Toolchain | SDCC's **sdasz80 + sdldz80** (with cpp and a small preprocessor). The source was converted from the original as80 dialect and rebuilds **byte-identical** to the released ALs binary (`make -C firmware verify`, which also checks the as80 build of the old source). |
| Emulator | Separate public repo **[moppe-emu](https://github.com/jeskko/moppe-emu)**, here as the `emu/` submodule. Boots the real firmware on emulated **P8E** (8.064 MHz Z80, 1 wait/M1) and **P8N** (4.032 MHz) cards with a **CU53AN** or **CU58AF** handset. Z80 core passes zexdoc and zexall. Since 2026-10-02 also the **Talkman MD50/MD59/ME59** (CDP1802/1806 core), running OH3NWQ's and OH1E's firmware ([notes/md5x.md](notes/md5x.md)), the **MC25 TVL/PTL** ([notes/mc25.md](notes/mc25.md)) and the **TMF-1/TMN-1** (uPD7810 core; radio and HSN-2/HSF-2 handset each on its own CPU, linked by MBUS) running OH5NXO/OH3NWQ's tmx1.asm v5.0 ([notes/tmx1.md](notes/tmx1.md)). Since 2026-10-05 the **Nokia R40** (H8/500 core) with the original Nokia RC40 firmware ([notes/r40.md](notes/r40.md)). |
| Tests | 322 tests. Firmware scenarios: first-time setup (SAnE), frequency entry, memories, stepping, duplex, TX keying and TX limits, setup menu, squelch, NV persistence, DTMF and **AX.25 APRS decoded from the emulated tone pin**, GPS NMEA into APRS, FFSK packets sent and received (call, remote display/config, relay, MPRS), remote configuration between two emulated radios over a simulated RF link, MBUS config dump/load (CFGSnd/CFGGEt); scanner, repeater access and CW ID, every menu record type (and the whole menu, asm vs C), low battery, TOT, typematic; ROM-window decode and code running from bank 1. **Differential tests** (`tests/test_diff.py`) run the released firmware and a candidate build side by side and compare display, synth, latches, events and NV. The DTMF/APRS tests fail if the CPU timing model is wrong. |
| C in firmware | The firmware is C plus assembler: `make` links the C modules (squelch, packet CRCs, systick timers, battery check, key dispatch and handlers, memories and VIP list, PTT/TX flow, the mainloop, display composition, frequency/band/duplex logic, scanner; banked: FSK packets, repeater/CW, GPS, MPRS/APRS, the setup menu engine) with r58.s as normal SDCC objects. Assembler is left only for interrupt code, hardware sequencing, the frequency kernel and display primitives. The differential tests show no behaviour difference to the last assembler build (git tag `asm-final`, `make ref`), which differs from the release by bug fixes and the removed Aisin Seiki GPS path. |
| Rewrite evaluation | [notes/rewrite-evaluation.md](notes/rewrite-evaluation.md): a full rewrite does not fit today's 32 KB ROM layout (both cards have banked ROM space that could hold more); an incremental C/asm hybrid works now and is what I recommend. |

| **Next** | [notes/hybrid-plan.md](notes/hybrid-plan.md), **start at its "Start here" section**. Bank 1 (EPROM0 chip 0xC000) holds the setup menu: its records and tables as asm data and the engine in C (`c/menu.c`); bank 2 (EPROM0 chip 0x8000, both cards) holds the FSK packet layer, repeater/CW, GPS and MPRS/APRS in C. CI and releases are prepared locally ([notes/ci.md](notes/ci.md)), not on GitHub until the original authors reply. Next: new features in the free space. Pending: the ROM window bench test on a real board (`make -C firmware banktest`, checks both pages). |

Open questions and hardware facts: [notes/hardware.md](notes/hardware.md).
Known firmware bugs left in place: [notes/open-bugs.md](notes/open-bugs.md) (none since 2026-10-01; decided ones in [notes/open-bugs-history.md](notes/open-bugs-history.md)).
Nokia R40 (RC40/RD40, H8/532): the emulator runs the original Nokia firmware to its self test and into service mode; hardware and open items in [notes/r40.md](notes/r40.md).
Emulator design, fidelity and limits: `emu/notes/emulator.md` (overview) and one note per radio, `emu/notes/r58.md` for the R58 (in the emulator repo).

## Quick start

Needs a C compiler, GNU `cpp`, Python 3 (numpy optional, speeds up audio
decoding), SDCC 4.x (sdasz80, sdldz80; tested with 4.6.0).

The emulator is a submodule: clone with `--recurse-submodules`, or run
`git submodule update --init --recursive` after cloning. The emulator is
public at <https://github.com/jeskko/moppe-emu>.

```sh
make -C firmware              # firmware/build/r58.bin (r58.s + the C modules)
make -C firmware verify ref   # release rebuilt byte-identical; the asm reference
make -C emu                   # emulator (r58emu, libr58.so)

python3 -m unittest discover -s tests          # test suite, ~4 min
python3 tools/ci/runtests.py                   # the same, one process per module (~1 min)
tools/ci/docker.sh                             # the CI pipeline in a clean Ubuntu container

python3 emu/python/r58tui.py --nv my.nv        # interactive radio in the terminal
python3 emu/python/r58tui.py --script '433500#. '   # headless: keys, then screen
```

In the TUI: digits `* #`, `c`=CL `s`=STO `r`=RCL `e`=ENT `b`=SHIFT `+ -`;
Space toggles PTT, `g` a received signal, `p` the power switch, Tab lengthens
the next key press (long presses reach store/step/squelch functions),
`q` quits and saves the NV (battery RAM) image. A missing NV file is
initialised with the firmware's own SAnE defaults.

Scripting from Python:

```python
import sys; sys.path.insert(0, "emu/python")
from r58emu import Radio
r = Radio("firmware/build/r58.bin", "firmware/build/r58.map", nv=open("my.nv","rb").read())
r.run(2.5)                    # boot
r.type("433500"); r.press("#"); r.run(0.3)
print(r.display(), r.rx_hz())  # ('000012', '    433500') 433500000.0
r.breakpoint("tx_on"); r.ptt(True); print(r.run(1.0), r.symbolize(r.cpu()["pc"]))
```

## Layout

| Path | What |
|---|---|
| `firmware/r58.s` | Firmware source (sdasz80 syntax, see [notes/toolchain.md](notes/toolchain.md)); `asm.h` helper macros |
| `firmware/r58.asm` | The original as80 source (from `reference/r58.asm.als`), reference only |
| `firmware/c/` | C modules, linked with r58.s |
| `tools/asmpp.py`, `link.py`, `cglue.py`, `ihx2bin.py` | Build steps around sdasz80/sdldz80 |
| `tools/jp2jr.py` | Size optimiser: `jp` → `jr` outside timing-critical code |
| `tools/bankxref.py` | Cross-references of a source block, before moving it to bank 1 |
| `tools/isrreach.py` | Routines reachable from interrupts (must stay in fixed ROM) |
| `tools/mutate.py` | Mutation check of a C module against the tests |
| `tools/banktest.py` | ROM window bench-test image (`make banktest`) |
| `tools/setupmap.py` | The setup map `build/r58.setup`: every menu record with its number (digits + ENT), built by `make` |
| `tools/as80tosdas.py` | One-shot as80 → sdasz80 source converter |
| `tools/as80/` | The original assembler (patched), for reference builds |
| `emu/` | Submodule: the emulator repo (moppe-emu). C emulator (`z80.c`, `cdp1802.c` and `upd7810.c` cores, `pio/sio/pit/daisy.c` chips, `cu53an.c`, `cu58af.c`, `cu41.c`, `tmx1hs.c` handsets, `r58.c`, `md5x.c`, `mc25.c` and `tmx1.c` boards, `*api.c` flat APIs), `python/` (harnesses and TUIs per radio, `afsk.py` AX.25 decoder, `upd7810dis.py`), its own unit, Z80 exerciser, Talkman, MC25 and TMx-1 tests |
| `tests/` | Firmware scenario and differential tests (`difftest.py` framework, `rflink.py` simulated RF link) |
| `experiments/c-density/` | C vs assembler code size measurement |
| `notes/` | Findings; `notes/reference/` has the detailed interface specs |
| `reference/` | Source material (not in git): manuals, original sources and binaries |

## License

The work of this project is under the MIT license ([LICENSE](LICENSE)):
the tests, the tools, the notes and our changes to the
firmware. The emulator (`emu/`) is its own repo, also MIT. Not covered,
because it is not ours to license:

| Path | Origin |
|---|---|
| `firmware/r58.asm`, the original code in `firmware/r58.s` | The R58 community ham firmware (OH5NXO et al.; archive at OH3TR); the v3_Z ALs version (OH1E and OH5NXO, 2018, decimal CTCSS tones) is published at <https://titanix.net/DMR/r58/> without a license, so its authors' terms apply. `firmware/c/` ports parts of it to C, so the same applies to the logic carried over. |
| `tools/as80/` | The "jas" assembler (1996-97) from the old R58 development kit, patched to build on modern systems (notes/toolchain.md). |
