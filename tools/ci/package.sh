#!/bin/sh
# Collect a finished build's release files into dist/ (created if
# missing; other files there are kept), named for VERSION (a tag such as
# v1.0, or nightly-...):
#   package.sh r58 VERSION  (after tools/ci/check-r58.sh)
#     r58-VERSION.bin           the 64 KB EPROM0 image (27C512)
#     r58-VERSION.map           its link map (symbols, for the emulator)
#     r58-VERSION.setup         the setup map: menu record numbers
#     r58-banktest-VERSION.bin  the ROM window bench test image
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
