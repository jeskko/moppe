#!/bin/sh
# The R58 pipeline (.github/workflows/ci.yml runs this; tools/ci/docker.sh
# runs it in a clean Ubuntu container): build the emulator and the
# firmware, rebuild the release byte-identical (make verify), the asm
# reference of the differential tests (make ref, needs the git tag
# asm-final), the bank test image, then the test suite.  Run from the
# repository root, with sdcc (tools/ci/install-sdcc.sh) on PATH.
set -eu

sdcc --version | head -1
# C objects from the cache (tools/ci/sdcc-cached.sh); entries unused for
# 60 days go
SDCC=$PWD/tools/ci/sdcc-cached.sh
export SDCC
cache=${R58_SDCC_CACHE:-$HOME/.cache/r58-sdcc-objs}
[ -d "$cache" ] && find "$cache" -mindepth 1 -maxdepth 1 -mtime +60 -exec rm -rf {} +
step() { t=$(date +%s); "$@"; echo "== $(( $(date +%s) - t )) s: $*"; }
step make -C emu -j"$(nproc)"
step make -C emu test
step make -C r58 -j"$(nproc)"
step make -C r58 -j"$(nproc)" verify ref
step make -C r58 -j"$(nproc)" banktest
step python3 tools/ci/runtests.py r58
