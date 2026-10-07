#!/bin/sh
# The R40 pipeline (.github/workflows/ci.yml runs this; tools/ci/docker.sh
# runs it in a clean Ubuntu container): the H8/500 C toolchain from
# source (lcc 4.2 with moppe's back end, GNU binutils 2.16.1 patched,
# into reference/toolchain/; tools/h8500/lcc/build.sh) and its tests, the
# emulator, the firmware (r40/), then its scenarios in the emulator.
# Run from the repository root.  Tests that need the Nokia ROM (not
# distributable) skip.
set -eu

step() { t=$(date +%s); "$@"; echo "== $(( $(date +%s) - t )) s: $*"; }
step env H8_NO_ASL=1 tools/h8500/lcc/build.sh
step tools/h8500/test/run.sh
step python3 tools/h8500/binutils/test_gas.py
step make -C emu -j"$(nproc)"
step make -C r40
step python3 tools/ci/runtests.py r40
