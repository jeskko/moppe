#!/bin/sh
# Install the OZVR4 H8/500 SLEIGH module (reference/ghidra-h8, cloned from
# https://github.com/OZVR4/Ghidra-H8-Processor) as a Ghidra user extension,
# with moppe's fixes (ghidra-h8.patch) and an added H8/532 language (H8:BE:32:H8532) for the Nokia R40 ROM.
#
#   tools/ghidra-r40/install.sh [GHIDRA_INSTALL_DIR]     (default /opt/ghidra)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
GHIDRA=${1:-${GHIDRA_INSTALL_DIR:-/opt/ghidra}}
SRC=$TOP/reference/ghidra-h8
[ -d "$SRC" ] || git clone https://github.com/OZVR4/Ghidra-H8-Processor "$SRC"
# moppe's fixes to the module (ghidra-h8.patch), applied once
git -C "$SRC" apply --reverse --check "$HERE/ghidra-h8.patch" 2>/dev/null ||
    git -C "$SRC" apply "$HERE/ghidra-h8.patch"
VER=$(sed -n 's/^application.version=//p' "$GHIDRA/Ghidra/application.properties")
REL=$(sed -n 's/^application.release.name=//p' "$GHIDRA/Ghidra/application.properties")
EXT=${GHIDRA_EXT_DIR:-$HOME/.config/ghidra/ghidra_${VER}_${REL}/Extensions}/H8
rm -rf "$EXT"
mkdir -p "$EXT"
cp -r "$SRC/h8/data" "$SRC/h8/Module.manifest" "$SRC/h8/extension.properties" "$EXT/"
rm -rf "$EXT/data/src"            # the purge analyzer needs a gradle build; not used
sed -i "s/^version=.*/version=$VER/" "$EXT/extension.properties"
L=$EXT/data/languages
python3 "$HERE/gen_pspec.py" "$L"
# add the H8/532 language next to the module's three
python3 - "$L/h8.ldefs" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
entry = '''  <language processor="H8"
            endian="big"
            size="32"
            variant="H8/532"
            version="1.0"
            slafile="h8539f.sla"
            processorspec="h8532.pspec"
            id="H8:BE:32:H8532">
    <description>H8/532 mode 3 (maximum mode, Nokia R40)</description>
    <compiler name="default" spec="h8539f.cspec" id="default"/>
  </language>
'''
if "H8:BE:32:H8532" not in s:
    s = s.replace("</language_definitions>", entry + "</language_definitions>")
open(p, "w").write(s)
PY
for spec in h8539f h8520 h8538f; do
    "$GHIDRA/support/sleigh" "$L/$spec.slaspec" "$L/$spec.sla" >/dev/null 2>&1
done
echo "installed $EXT"
