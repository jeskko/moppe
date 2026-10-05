#!/bin/sh
# Create the Ghidra project reference/ghidra-r40/R40 (gitignored: it holds
# the proprietary ROM) from the RC40 Cr 13.04 EPROM image, run the R40
# set-up and auto-analysis, seed the code the emulator executed
# (coverage.py, run first) and export the decoded instructions to
# reference/ghidra-r40/insns.txt.  Run install.sh first.
#
#   tools/ghidra-r40/import.sh [ROM] [GHIDRA_INSTALL_DIR]
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
ROM=${1:-$TOP/reference/oh5nxo/mods/R40-manuals/rc40_rom/ABSBIN}
GHIDRA=${2:-${GHIDRA_INSTALL_DIR:-/opt/ghidra}}
OUT=$TOP/reference/ghidra-r40
mkdir -p "$OUT"
"$GHIDRA/support/analyzeHeadless" "$OUT" R40 -overwrite \
    -import "$ROM" -loader BinaryLoader -loader-baseAddr 0 \
    -processor H8:BE:32:H8532 -cspec default \
    -scriptPath "$HERE" -preScript ImportR40.java \
    -postScript SeedCoverage.java "$OUT/coverage.bin" \
    -postScript ExportInsns.java "$OUT/insns.txt" \
    -analysisTimeoutPerFile 1800
