#!/bin/sh
# The H8/500 C toolchain's tests: lcc's own test programs (output compared
# with lcc's x86 results, or with test/<name>.1bk where only type sizes
# differ) and the soft-float check against the host (floatgen.c).
# Needs tools/h8500/lcc/build.sh to have run.
#
#   tools/h8500/test/run.sh
HERE=$(cd "$(dirname "$0")" && pwd)
H8=$HERE/..
L=$(cd "$H8/../.." && pwd)/reference/toolchain/lcc
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0
# switch, limits and fields assume a 32-bit int; paranoia and yacc need
# more of libc (signal, setjmp, stdio streams)
for t in 8q array cf cq cvt incr init sort spill stdarg struct wf1; do
    exp=$L/x86/linux/tst/$t.1bk
    [ -f "$HERE/$t.1bk" ] && exp=$HERE/$t.1bk
    if "$H8/h8cc.py" -o "$T/$t.bin" "$L/tst/$t.c" 2>"$T/err" &&
       "$H8/h8run" "$T/$t.bin" < "$L/tst/$t.0" > "$T/out" &&
       cmp -s "$T/out" "$exp"; then
        echo "$t ok"
    else
        echo "$t FAILED"; fail=1
    fi
done
cc -O -o "$T/floatgen" "$HERE/floatgen.c" -lm || exit 1
for seed in 1 2 3 4; do
    "$T/floatgen" 250 $seed > "$T/ft.c"
    r=$("$H8/h8cc.py" -o "$T/ft.bin" "$T/ft.c" 2>/dev/null && "$H8/h8run" "$T/ft.bin" | tail -1)
    echo "float seed $seed: $r"
    [ "$r" = "0 mismatches" ] || fail=1
done
exit $fail
