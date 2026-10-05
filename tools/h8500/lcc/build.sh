#!/bin/sh
# Build lcc with the H8/500 back end (h8500.md) and the AS assembler.
#
#   tools/h8500/lcc/build.sh
#
# Sources, fetched on first use into reference/toolchain/ (gitignored):
#   lcc 4.2   https://github.com/drh/lcc   (licence: lcc's CPYRIGHT: free
#             to use and redistribute with acknowledgement, not to sell)
#   AS (asl)  http://john.ccac.rwth-aachen.de:8000/as/  (GPL)
# Results: reference/toolchain/lcc/build/{rcc,cpp}, reference/toolchain/
# asl-current/{asl,p2bin}, tools/h8500/h8run.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../../.." && pwd)
TC=$TOP/reference/toolchain
mkdir -p "$TC"
[ -d "$TC/lcc" ] || git clone -q https://github.com/drh/lcc "$TC/lcc"
if [ ! -x "$TC/asl-current/asl" ]; then
    [ -d "$TC/asl-current" ] || (cd "$TC" &&
        curl -sfL http://john.ccac.rwth-aachen.de:8000/ftp/as/source/c_version/asl-current.tar.gz | tar xz)
    cp "$TC/asl-current/Makefile.def-samples/Makefile.def-x86_64-unknown-linux" "$TC/asl-current/Makefile.def"
    make -C "$TC/asl-current" -j8 binaries >/dev/null
fi

L=$TC/lcc
# moppe's fixes to lcc itself (lcc.patch): hex constants try unsigned int
# before long; sizeof and pointer differences use the pointer-sized ints;
# unsigned long to float masks with an unsigned long 1.  A changed patch
# is applied to clean sources.
git -C "$L" apply --reverse --check "$HERE/lcc.patch" 2>/dev/null || {
    git -C "$L" checkout -- src
    git -C "$L" apply "$HERE/lcc.patch"
}
# the back end, with the %term list for this target's type sizes
python3 "$HERE/gen_terms.py" "$L/src/ops.h" > "$HERE/terms.inc"
sed -e "/^%include terms.inc/r $HERE/terms.inc" -e "/^%include terms.inc/d" \
    "$HERE/h8500.md" > "$L/src/h8500.md"
grep -q h8500IR "$L/src/bind.c" ||
    sed -i 's|^xx(x86/linux,    x86linuxIR) \\|&\nxx(h8500/asl,    h8500IR) \\|' "$L/src/bind.c"
grep -q 'Bh8500' "$L/makefile" || {
    sed -i 's|^\t\$Bx86linux\$O$|&\\\n\t$Bh8500$O|' "$L/makefile"
    printf '\n$Bh8500$O:\t$Bh8500.c;\t$(CC) $(CFLAGS) -c -Isrc -o $@ $Bh8500.c\n$Bh8500.c:\t$Blburg$E src/h8500.md; $Blburg src/h8500.md $@\n' >> "$L/makefile"
}
mkdir -p "$L/build"
make -s -C "$L" HOSTFILE=etc/linux.c BUILDDIR=build CFLAGS="-g -std=gnu89 -w" LDFLAGS=-g rcc cpp
cc -O2 -Wall -I"$TOP/emu" -o "$HERE/../h8run" "$HERE/../h8run.c" "$TOP/emu/h8500.c"
echo "rcc: $L/build/rcc -target=h8500/asl"
