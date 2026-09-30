#!/bin/sh
# The CI pipeline (.github/workflows/ci.yml runs this; tools/ci/docker.sh
# runs it in a clean Ubuntu container): build the emulator and the
# firmware, rebuild the release byte-identical (make verify), the asm
# reference of the differential tests (make ref, needs the git tag
# asm-final), the bank test image, then the test suite.  Run from the
# repository root, with sdcc (tools/ci/install-sdcc.sh) on PATH.
set -eu

sdcc --version | head -1
make -C emu -j"$(nproc)"
make -C emu test
make -C firmware -j"$(nproc)"
make -C firmware -j"$(nproc)" verify ref banktest
python3 tools/ci/runtests.py
