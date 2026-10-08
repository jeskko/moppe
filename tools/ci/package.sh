#!/bin/sh
# Collect a finished build's release files into dist/ (created if
# missing; other files there are kept), named for VERSION (a tag such as
# v1.0, or nightly-...):
#   package.sh r58 VERSION  (after tools/ci/check-r58.sh)
#     r58-VERSION.bin           the 64 KB EPROM0 image (27C512)
#     r58-VERSION.map           its link map (symbols, for the emulator)
#     r58-VERSION.setup         the setup map: menu record numbers (both
#                               builds: no menu record depends on L8M)
#     r58-banktest-VERSION.bin  the ROM window bench test image
#     r58-l8m-VERSION.bin       the RB58VY (L8M board) image, 64 KB: EPROM0
#                               at 0x0000, EPROM1 at 0x8000 (for the emulator)
#     r58-l8m-VERSION-eprom0.bin, -eprom1.bin  its two 27C256 halves (to burn)
#     r58-l8m-VERSION.map       its link map
#   package.sh r40 VERSION  (after tools/ci/check-r40.sh)
#     r40-VERSION.bin           the Nokia R40 image (from EPROM address 0)
#     r40-VERSION.map           its link map
# and SHA256SUMS over everything in dist/.
set -eu

fw=$1
v=$2
mkdir -p dist
case $fw in
r58)
	cp r58/build/r58.bin "dist/r58-$v.bin"
	cp r58/build/r58.map "dist/r58-$v.map"
	cp r58/build/r58.setup "dist/r58-$v.setup"
	cp r58/build-banktest/r58-banktest.bin "dist/r58-banktest-$v.bin"
	cp r58/build-l8m/r58.bin "dist/r58-l8m-$v.bin"
	cp r58/build-l8m/r58.map "dist/r58-l8m-$v.map"
	head -c 32768 r58/build-l8m/r58.bin > "dist/r58-l8m-$v-eprom0.bin"
	tail -c 32768 r58/build-l8m/r58.bin > "dist/r58-l8m-$v-eprom1.bin"
	;;
r40)
	cp r40/build/r40.bin "dist/r40-$v.bin"
	cp r40/build/r40.map "dist/r40-$v.map"
	;;
*)
	echo "usage: $0 r58|r40 VERSION" >&2
	exit 2
	;;
esac
(cd dist && rm -f SHA256SUMS && sha256sum -- * > SHA256SUMS)
ls -l dist
