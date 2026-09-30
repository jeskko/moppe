#!/bin/sh
# Collect the release files of a finished build (tools/ci/check.sh) into
# dist/, named for VERSION ($1: a tag such as v1.0, or nightly-...):
#   r58-VERSION.bin           the 64 KB EPROM0 image (27C512)
#   r58-VERSION.map           its link map (symbols, for the emulator)
#   r58-VERSION.setup         the setup map: menu record numbers
#   r58-banktest-VERSION.bin  the ROM window bench test image
#   SHA256SUMS
set -eu

v=$1
rm -rf dist
mkdir dist
cp firmware/build/r58.bin "dist/r58-$v.bin"
cp firmware/build/r58.map "dist/r58-$v.map"
cp firmware/build/r58.setup "dist/r58-$v.setup"
cp firmware/build-banktest/r58-banktest.bin "dist/r58-banktest-$v.bin"
(cd dist && sha256sum -- * > SHA256SUMS)
ls -l dist
