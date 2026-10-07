#!/bin/sh
# sdcc with an object cache, for CI: `make SDCC=tools/ci/sdcc-cached.sh`
# (an absolute path: make runs in r58/ and build-ref/).  The key is
# the compiler's version line, the arguments and the contents of the
# source and of every header beside it; a hit copies the .rel and its
# .asm/.lst/.sym, which are what sdcc would have written.  The pinned
# SDCC 4.6.0 binary needs over 3 minutes for c/scan.c (another build of
# the same version takes 9 s), and the bank test image compiles the same
# modules again: both come from the cache.
#
# Only `sdcc ... -c SRC -o OUT.rel` is cached; anything else runs sdcc.
set -eu

cache=${R58_SDCC_CACHE:-$HOME/.cache/r58-sdcc-objs}
src= out= prev=
for a in "$@"; do
	case $prev in -o) out=$a ;; esac
	case $a in *.c) src=$a ;; esac
	prev=$a
done
case $out in *.rel) ;; *) exec sdcc "$@" ;; esac
[ -n "$src" ] || exec sdcc "$@"

key=$({
	sdcc --version 2>&1 | head -1
	printf '%s\n' "$@" | grep -v -e '\.c$' -e '\.rel$'
	cat "$src" "$(dirname "$src")"/*.h
} | sha256sum | cut -c1-32)
base=${out%.rel}
hit=$cache/$key

if [ -f "$hit/o.rel" ]; then
	touch "$hit"			# used: kept by check-r58.sh's pruning
	for x in rel asm lst sym; do
		[ -f "$hit/o.$x" ] && cp "$hit/o.$x" "$base.$x"
	done
	exit 0
fi
sdcc "$@"
mkdir -p "$hit.tmp.$$"
for x in rel asm lst sym; do
	[ -f "$base.$x" ] && cp "$base.$x" "$hit.tmp.$$/o.$x"
done
mv "$hit.tmp.$$" "$hit" 2>/dev/null || rm -rf "$hit.tmp.$$"
