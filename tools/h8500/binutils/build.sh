#!/bin/sh
# Build GNU binutils 2.16.1 for the H8/500 (h8500-hms: gas, ld, objdump,
# objcopy ...), the last release before the target was dropped.
#
#   tools/h8500/binutils/build.sh
#
# Source: https://ftp.gnu.org/gnu/binutils/binutils-2.16.1.tar.bz2 (GPL),
# fetched into reference/toolchain/ (gitignored).  h8500.patch:
#   opcodes/h8500-opc.h  the disassembler table's mov:g.w #xx:8 lengths and
#                        missing cmp:g.w #xx:8 (from reference/r40work/
#                        h8500-opc.patch), RTD #xx:16 is 0x1C (was 0x14 in
#                        both tables: gas emitted wrong code), RTE (0x0A)
#                        added to both tables
#   gas/write.c, gas/config/tc-h8500.h
#                        md_relax_table declared where struct relax_type
#                        is complete (modern gcc rejects the old header)
#   gas/config/tc-h8500.c
#                        MOV:G.W / CMP:G.W #xx:8 (sign-extended) for small
#                        constants, explicit #xx:8 / #xx:16 honoured;
#                        bra.w etc. without :16; a branch to a number no
#                        longer crashes (absolute reloc); explicit 16-bit
#                        branches were 2 bytes off (md_pcrel_from)
#   bfd/coff-h8500.c     PCREL16 from the end of the field (linked 16-bit
#                        branches landed one byte past the target)
#   bfd/reloc16.c        relocs applied in address order (gas writes a
#                        relaxed branch's reloc last)
# Tests: tools/h8500/binutils/test_gas.py, tools/h8500/check_gas.py.
# Results: reference/toolchain/binutils-h8500/bin/h8500-hms-{as,ld,objdump,
# objcopy,nm,size}.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../../.." && pwd)
TC=$TOP/reference/toolchain
V=binutils-2.16.1
mkdir -p "$TC"
cd "$TC"
[ -f $V.tar.bz2 ] || curl -sfLO https://ftp.gnu.org/gnu/binutils/$V.tar.bz2
# a changed patch: fresh sources and build
SUM=$(md5sum < "$HERE/h8500.patch")
if [ "$(cat $V/.moppe-patched 2>/dev/null)" != "$SUM" ]; then
    rm -rf $V binutils-h8500/build
    tar xjf $V.tar.bz2
    patch -s -d $V -p1 < "$HERE/h8500.patch"
    echo "$SUM" > $V/.moppe-patched
fi
mkdir -p binutils-h8500/build
cd binutils-h8500/build
[ -f Makefile ] || CFLAGS="-O1 -g -std=gnu89 -fcommon -w" ../../$V/configure \
    --target=h8500-hms --disable-nls --disable-werror >configure.log 2>&1
make -j8 all-gas all-ld all-binutils >make.log 2>&1 || { tail -20 make.log; exit 1; }
mkdir -p ../bin
cp gas/as-new ../bin/h8500-hms-as
cp ld/ld-new ../bin/h8500-hms-ld
for p in objdump objcopy size; do cp binutils/$p ../bin/h8500-hms-$p; done
cp binutils/nm-new ../bin/h8500-hms-nm
echo "binutils: $TC/binutils-h8500/bin"
