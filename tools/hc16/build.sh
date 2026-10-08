#!/bin/sh
# Build the 68HC16 toolchain HaMDR (the MDR150 ham firmware) was built
# with: the Real-Time Systems hc1x port of GNU binutils 2.9.1 (as, ld,
# objdump, nm) and gcc 2.8.1 (cc1, cpp, xgcc), from OH5NXO's patched
# trees in his archive, as a 32-bit Linux host build.
#
#   tools/hc16/build.sh
#
# Needs gcc with -m32 (multilib), make and curl.  Sources:
#   reference/oh5nxo/mods/MDR150/gnu/{binutils,gcc}  OH5NXO's trees with the
#       Real-Time Systems patches applied (GPL); from oh5nxo.mods.2018.tar.gz
#       (oh3tr.fi/~ftp/modifications/sorsat/), see notes/mdr150.md
#   gcc-2.8.1.tar.gz from ftp.gnu.org: only its config/i386 (host files the
#       archived tree lacks), fetched into reference/toolchain/
# Results in reference/toolchain/hc16/: binutils/build/{gas/as-new,
# ld/ld-new,binutils/objdump,binutils/nm-new}, gcc/build/{xgcc,cc1,cpp,as}.
# Compile with: xgcc -B<gcc/build>/ (gcc/build/as is the assembler).
#
# The fixes, all to copies of the trees (notes/mdr150.md "HaMDR build"):
# stale in-tree configure state removed; old config.sub needs an i686
# host; libiberty's sys_nerr/sys_nsig declared and lconfig.h written by
# hand; bfd/doc stubbed out.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
GNU=$TOP/reference/oh5nxo/mods/MDR150/gnu
OUT=$TOP/reference/toolchain/hc16
HOSTCC="gcc -m32 -std=gnu89 -fcommon -w"
CONF="--host=i686-pc-linux-gnu --build=i686-pc-linux-gnu --target=hc16-coff"
[ -d "$GNU/binutils" ] && [ -d "$GNU/gcc" ] ||
    { echo "no $GNU/{binutils,gcc}: extract OH5NXO's archive into reference/oh5nxo" >&2; exit 1; }
mkdir -p "$OUT"

# drop the configure results the archive's trees carry from their own build
clean_tree() {
    find "$1" -name config.status | while read -r f; do
        d=$(dirname "$f")
        rm -f "$d/config.status" "$d/Makefile" "$d/config.cache" "$d/config.h"
    done
}

# ---- binutils 2.9.1
B=$OUT/binutils
if [ ! -x "$B/build/gas/as-new" ] || [ ! -x "$B/build/ld/ld-new" ]; then
    rm -rf "$B"
    mkdir -p "$B"
    cp -a "$GNU/binutils" "$B/src"
    clean_tree "$B/src"
    # glibc no longer declares sys_nerr / sys_nsig: libiberty's own static ones
    sed -i 's#^//static int sys_nerr;#static int sys_nerr;#' "$B/src/libiberty/strerror.c"
    sed -i 's#^//static int sys_nsig;#static int sys_nsig;#' "$B/src/libiberty/strsignal.c"
    mkdir -p "$B/build"
    cd "$B/build"
    CC="$HOSTCC" CFLAGS="-O1" ../src/configure $CONF --prefix="$OUT/install" --disable-nls >cfg.log 2>&1
    # first pass: creates the subdirectories' make state; libiberty stops
    # at lconfig.h (its "errors" probe of the host C library)
    make -k all-gas all-ld all-binutils >make1.log 2>&1 || true
    touch libiberty/errors
    mkdir -p bfd/doc
    printf 'all:\ninstall:\ninfo:\n' > bfd/doc/Makefile
    make -k all-gas all-ld all-binutils >make2.log 2>&1 || true
    cat >> libiberty/lconfig.h <<'EOF'
#define NEED_sys_nerr 1
#define NEED_sys_errlist 1
#define NEED_sys_siglist 1
#define NEED_sys_nsig 1
#define NEED_strsignal 1
EOF
    make all-gas all-ld all-binutils >make3.log 2>&1 ||
        { echo "binutils build failed: $B/build/make3.log" >&2; exit 1; }
fi

# ---- gcc 2.8.1 (C only)
G=$OUT/gcc
if [ ! -x "$G/build/cc1" ] || [ ! -x "$G/build/xgcc" ]; then
    rm -rf "$G"
    mkdir -p "$G"
    cp -a "$GNU/gcc" "$G/src"
    clean_tree "$G/src"
    rm -f "$G/src/tconfig.h" "$G/src/hconfig.h" "$G/src/tm.h" "$G/src/auto-config.h" \
          "$G/src/options.h" "$G/src/specs.h" "$G/src/Make-hooks" "$G/src/Make-host" \
          "$G/src/Make-target" "$G/src/Make-lang" "$G/src/cstamp-h"
    # the archived tree has no i386 host configuration: take upstream's
    T=$TOP/reference/toolchain/gcc-2.8.1.tar.gz
    [ -s "$T" ] || curl -sfL -o "$T" https://ftp.gnu.org/gnu/gcc/gcc-2.8.1.tar.gz
    (cd "$G" && tar xzf "$T" gcc-2.8.1/config/i386 && cp -a gcc-2.8.1/config/i386 src/config/ &&
        rm -rf gcc-2.8.1)
    mkdir -p "$G/build"
    cd "$G/build"
    CC="$HOSTCC" ../src/configure $CONF --prefix="$OUT/install" >cfg.log 2>&1
    make LANGUAGES=c CFLAGS="-O1" cc1 cpp xgcc >make.log 2>&1 ||
        { echo "gcc build failed: $G/build/make.log" >&2; exit 1; }
fi
ln -sf "$B/build/gas/as-new" "$G/build/as"
echo "hc16 toolchain: $OUT (xgcc -B$G/build/, as $B/build/gas/as-new, ld $B/build/ld/ld-new)"
