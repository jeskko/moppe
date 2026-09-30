# CI and releases

Prepared locally 2026-10-01; **not on GitHub yet**: the repository has no
remote, and publishing waits for the original authors' reply (the user
asked OH1E on 2026-10-01; OH5NXO's address is not known). A private
GitHub repository works meanwhile: the Free plan's 2000 minutes a month
on 2-vCPU runners is about 100-150 runs of this pipeline; public
repositories get unlimited minutes on 4-vCPU runners.

## Files

| File | What |
|---|---|
| `.github/workflows/ci.yml` | on push (master/main, `v*` tags), pull request, manual: job `check` runs the pipeline and uploads `dist/` as the `firmware` artifact (30 days); job `publish` makes a GitHub release for a `v*` tag, and for a push to master replaces the `nightly` pre-release (tag moved to the commit) |
| `tools/ci/check.sh` | the pipeline: emulator (+ its unit test), `make` firmware, `make verify ref banktest`, the test suite |
| `tools/ci/install-sdcc.sh` | the pinned SDCC: the official 4.6.0 amd64 binary tarball from SourceForge, SHA-256 checked, into `~/.cache/sdcc-4.6.0` (cached by the workflow) |
| `tools/ci/runtests.py` | the test suite one module per process, `-j` CPU count: 178 s on 16 cores (bound by `test_menu_diff`), 9 min serial |
| `tools/ci/package.sh VERSION` | `dist/`: `r58-VERSION.bin` (64 KB EPROM0), `.map`, `.setup`, `r58-banktest-VERSION.bin`, `SHA256SUMS` |
| `tools/ci/docker.sh` | the pipeline in a clean `ubuntu:24.04` container (the runner's OS) from the working tree and `.git`; `CPUS=4` limits it like a runner; `dist/` comes back |

actionlint (with shellcheck): clean.

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
- Full container run (fresh apt, SDCC cached in a volume): see the table
  below.

| Run | Where | Result | Time |
|---|---|---|---|
| 2026-10-01 | docker.sh, 16 CPUs | 316 OK, verify OK | tests 178 s |

## Open

- First real run on GitHub (after the repository is created): check the
  runner time and the minutes a run costs, the cache hit, the nightly
  release replacement.
- Version naming: `v*` tags; nightlies `nightly-YYYYMMDD-<sha>`.
- If minutes get tight on a private repository: nightly only on
  `workflow_dispatch`, or tests split into a matrix (does not save
  minutes, only wall time).
