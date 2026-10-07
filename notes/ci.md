# CI and releases

Prepared locally 2026-10-01 (R58), 2026-10-07 for a **public**
repository with both firmwares: the R58 and R40 pipelines run as two
parallel jobs; a release carries both. Not on GitHub yet (no remote).
The licensing of the published tree: README "License" (MIT for our
work; the R58 firmware and as80 keep their authors' unknown terms;
patches to binutils and lcc under their licenses). Public repositories
get unlimited minutes on 4-vCPU runners.

## Files

| File | What |
|---|---|
| `.github/workflows/ci.yml` | on push (master/main, `v*` tags), pull request, manual: jobs `r58` and `r40` run their pipelines and upload `dist/` as artifacts `firmware-r58` / `firmware-r40` (30 days); job `publish` merges them, writes SHA256SUMS, makes a GitHub release for a `v*` tag, and for a push to master replaces the `nightly` pre-release (tag moved to the commit) |
| `tools/ci/check-r58.sh` | the R58 pipeline: emulator (the `emu/` submodule; + its unit test), `make -C r58`, `make verify ref`, `make banktest`, `runtests.py r58` (tests/r58); prints each step's seconds |
| `tools/ci/check-r40.sh` | the R40 pipeline: the H8/500 toolchain from source (`H8_NO_ASL=1 tools/h8500/lcc/build.sh`: lcc from GitHub, binutils 2.16.1 from ftp.gnu.org, into `reference/toolchain/`, cached by the workflow on the toolchain files' hash), its tests (`tools/h8500/test/run.sh`, `binutils/test_gas.py`), emulator, `make -C r40`, `test_r40fw`. The Nokia ROM is not distributable: its tests (`check_gas.py`, the emulator's R40 tests, one firmware test) skip |
| `tools/ci/version.sh` | the build's name: the tag, or `nightly-YYYYMMDD-<sha>` |
| `tools/ci/install-sdcc.sh` | the pinned SDCC: the official 4.6.0 amd64 binary tarball from SourceForge, SHA-256 checked, into `~/.cache/sdcc-4.6.0` (cached by the workflow) |
| `tools/ci/sdcc-cached.sh` | `SDCC=` for make (check-r58.sh sets it): C objects cached by compiler version, flags, source and headers in `~/.cache/r58-sdcc-objs` (a workflow cache; check-r58.sh prunes entries unused for 60 days). Outputs are byte-identical (sdcc writes nothing path-dependent) |
| `tools/ci/runtests.py` | the suites (`r58`, `r40`, or module names; default all) one module per process, `-j` CPU count: 62 s on 16 cores, ~4 min serial (2026-10-01, after the emulator speed-up) |
| `tools/ci/package.sh r58\|r40 VERSION` | into `dist/`: `r58-VERSION.bin` (64 KB EPROM0), `.map`, `.setup`, `r58-banktest-VERSION.bin`; `r40-VERSION.bin`, `.map`; `SHA256SUMS` |
| `tools/ci/docker.sh [r58] [r40]` | the pipelines (default both) in a clean `ubuntu:24.04` container (the runner's OS) from the working tree and `.git`; `CPUS=4` limits it like a runner; volumes keep SDCC and the R40 toolchain; `dist/` comes back |

actionlint (with shellcheck): clean on 2026-10-01; not rerun after the
2026-10-07 split (not installed).

## Facts

- **SDCC output depends on the SDCC build, not only its version.** The
  official 4.6.0 tarball and Arch's `sdcc 4.6.0-1.1` (both `#16555`)
  allocate registers differently in aprs, freq, gps, menu, rptr and scan:
  the images differ (fixed ROM a few bytes, every later address). The
  test suite passes with both. Release images come from CI (the tarball);
  a local build is not byte-identical to them unless it uses
  `install-sdcc.sh`'s SDCC (`PATH=$(tools/ci/install-sdcc.sh):$PATH make`).
- `make ref` builds the tag `asm-final` with `git archive`: CI checks out
  with `fetch-depth: 0`, docker.sh copies `.git`.
- `make verify` compares with a SHA-256 of the v3_Z ALs binary; the
  binary itself is not needed (`reference/` is git-ignored).
- The emulator needs only a C compiler; numpy (optional) speeds up audio
  decoding and is installed in CI.
- The pinned SDCC needed ~200 s for `c/scan.c` (Arch's build of the same
  version: 9 s): `scanner_run` was one function with gotos and a switch
  into its middle, and the register allocator's search blew up on it.
  **Fixed 2026-10-01**: the blocks between its labels are functions
  driven by a table (same work per mainloop pass); 6 s now, a cold
  firmware build 44 s at -j4 (measured). The object cache still saves the bank test
  build and unchanged runs. `tools/r58/sdccprof.py` profiles compile time per
  function (stub one at a time) to find the next such function.
- Emulator speed: 20-29x real time before 2026-10-01, ~2x that after
  the lazy 8254 clocking (emu/notes/r58.md); all test time is
  emulation (Python-side comparison < 1 %).
- R40 toolchain on Ubuntu (2026-10-07): lcc's lburg needs `yacc`
  (`byacc` installed), and Ubuntu's gcc fortifies by default, which made
  binutils 2.16.1's `ar` abort (`sprintf` of the archive header's date
  field, archive.c:1353, checked with gdb): binutils is built with
  `-U_FORTIFY_SOURCE`. The R40 image is byte-identical between Arch
  and the container.
- Full container run (fresh apt, SDCC cached in a volume): see the table
  below.

| Run | Where | Result | Time |
|---|---|---|---|
| 2026-10-01 | docker.sh, 16 CPUs | 316 OK, verify OK | tests 178 s |
| 2026-10-01 | docker.sh, `CPUS=4` | 316 OK, verify OK | 1119 s total: two cold C builds ~440 s (scan.c), tests 224 s; before the object cache and the emulator speed-up |
| 2026-10-01 | docker.sh, `CPUS=4`, cold (no SDCC, no objects) | 316 OK, verify OK | 520 s: firmware 395 s (scan.c), bank test 0 s, tests 93 s |
| 2026-10-01 | docker.sh, `CPUS=4`, warm object cache | 316 OK, verify OK | 114 s: builds ~2 s, tests 90 s |
| 2026-10-07 | docker.sh r58 r40, `CPUS=4`, new layout | R58: 324 OK, verify OK, 99 s tests; R40: failed (no yacc) | |
| 2026-10-08 | docker.sh r40, `CPUS=4`, after the yacc and fortify fixes | toolchain tests OK, 44 OK | toolchain 21 s (lcc warm, binutils rebuilt), tests 23 s |

## Open

- First real run on GitHub (after the repository is created): check the
  runner time and the minutes a run costs, the cache hit, the nightly
  release replacement.
- Version naming (user, 2026-10-07): `v*` tags, nightlies
  `nightly-YYYYMMDD-<sha>`. **0.x = emulator-tested only**: `v0.*` tags
  publish as GitHub pre-releases (never "Latest"); the first is
  **v0.1.1**. 1.0 waits for hardware checks of both firmwares (or a tag
  prefix per firmware, `r58-v…` / `r40-v…`, if one matures first). Every
  release and nightly carries `tools/ci/release-notes.md` (emulator-only
  disclaimer, keep the original EPROM, NV, transmit carefully).
- If minutes get tight on a private repository: nightly only on
  `workflow_dispatch`, or tests split into a matrix (does not save
  minutes, only wall time).
