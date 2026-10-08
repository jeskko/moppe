#!/bin/sh
# Build OH5NXO's HaMDR 174 (MDR150 ham firmware) from his source tree in
# reference/ with the hc16 toolchain (tools/hc16/build.sh, built first if
# missing), check it against his own 2015 build, and write a symbol table
# with the local labels for the emulator.
#
#   tools/hc16/hamdr.sh            # -> build/hamdr/{hamdr.hex,hamdr.map,hamdr.sym}
#
# HaMDR has no licence: the build stays in build/ (gitignored), never
# committed.  Its Makefile is BSD make; this follows it: help.s from
# prconfig.c (host cc), every object of hamdr.ldscript, then the link.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
SRC=$TOP/reference/oh5nxo/mods/MDR150/hamdr
TC=$TOP/reference/toolchain/hc16
OUT=$TOP/build/hamdr
[ -f "$SRC/hamdr.c" ] || { echo "no HaMDR source in $SRC" >&2; exit 1; }
[ -x "$TC/gcc/build/xgcc" ] && [ -x "$TC/binutils/build/ld/ld-new" ] || "$HERE/build.sh"
AS=$TC/binutils/build/gas/as-new
LD=$TC/binutils/build/ld/ld-new
OBJDUMP=$TC/binutils/build/binutils/objdump
CC="$TC/gcc/build/xgcc -B$TC/gcc/build/"

rm -rf "$OUT"
mkdir -p "$OUT/tmp" "$OUT/doc"
cd "$SRC"
cp *.c *.h *.s *.inc *.ldscript loader.hdr "$OUT"/
cd "$OUT"
rm -f *.o hamdr.hex

cc -std=gnu89 -w prconfig.c -o prconfig
./prconfig s > help.s
./prconfig h > help.h
cmp -s help.s "$SRC/help.s" || echo "note: help.s differs from the archived one" >&2

# the INPUT lines outside /* */ (the unused modules are commented out)
OBJS=$(awk '/\/\*/ { c = 1 } !c && /^INPUT\("/ { gsub(/INPUT\("|\.o"\)/, ""); print } /\*\// { c = 0 }' hamdr.ldscript)
for o in $OBJS; do
    if [ -f "$o.c" ]; then
        $CC -pipe -O -ffreestanding -c "$o.c" -o "$o.o"
    else
        $AS -M -o "$o.o" "$o.s"
    fi
done
$LD -T hamdr.ldscript -Map hamdr.map --cref
cat loader.hdr hamdr.hex > hamdr.out
python3 "$HERE/hamdr_syms.py" "$OUT" "$OBJDUMP" > hamdr.sym

if cmp -s hamdr.hex "$SRC/hamdr.hex"; then
    echo "build/hamdr/hamdr.hex: identical to OH5NXO's build ($(wc -l < hamdr.sym) symbols in hamdr.sym)"
else
    echo "build/hamdr/hamdr.hex DIFFERS from $SRC/hamdr.hex" >&2
    exit 1
fi
