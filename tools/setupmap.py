#!/usr/bin/env python3
"""
The setup map: every menu record with the number that reaches it.

    setupmap.py firmware/r58.s > firmware/build/r58.setup

In the menu, digits and ENT go to a record: the first digit picks the group
(menu_quickspots), the rest the record in it, so "010" + ENT is group 0,
record 10.  The records come from the REC() lines of r58.s between
start_menu and end_menu, in the layout of the maps published with the old
firmware versions (r58p8x3Zi.setup): number, group:title, type, the help
text of the REC() line, the default, the variable (and the table or the draw
routine).
"""
import re
import sys

HEADER = """
 FREQ  taajuuskenttä, kopioi rx taajuus *:llä
 DPX   etumerkillinen taajuuskenttä, aseta 0 ja askella +/- suuntiin
 TAB   valintalista, askella +/-
 BYTE  alle 256
 cSEC  millisekunteja 10 msec tarkkuudella, alle 2.56 sec
 WORD  alle 65536
 STR   tekstikenttä, tyhjennä *:llä
 RST   resetoi tjms jotain kun annetaan 666
 DYN   jotain aivan muuta

 ABC1 DEF2 GHI3    alfataulukko
 JKL4 MNO5 PQR6
 STU7 VWX8 _YZ9
    /-?#$=.0

"""


def parse_records(path):
    """The REC() lines of r58.s in menu order: dicts with group (menu_N),
    idx (record in the group), tag, title, type, ptr, arg, default, help."""
    raw = open(path, "rb").read()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("latin-1")    # r58.asm converted afresh (build-release)
    src = text.split("\n")
    a = next(i for i, l in enumerate(src) if l.startswith("start_menu:"))
    b = next(i for i, l in enumerate(src) if l.startswith("end_menu:"))
    recs, skip, group, idx = [], False, -1, 0
    for line in src[a:b]:
        s = line.strip()
        if s.startswith("#if 0"):
            skip = True
        elif s.startswith("#endif"):
            skip = False
        if skip:
            continue
        m = re.match(r"menu_(\d):", s)
        if m:
            group, idx = int(m.group(1)), 0
            continue
        if not s.startswith("REC("):
            continue
        # REC(grp, name, type, ptr, arg, def, help): help runs to the last ')'
        f = s[4:].split(",", 6)
        recs.append(dict(group=group, idx=idx, tag=f[0].strip().strip('"'),
                         title=f[1].strip().strip('"'),
                         type=f[2].strip().replace("CFG_", ""),
                         ptr=f[3].replace(" ", "").strip(), arg=f[4].strip(),
                         default=int(f[5].strip(), 0),
                         help=f[6].rsplit(")", 1)[0].strip()))
        idx += 1
    return recs


def setup_map(recs):
    out = [HEADER]
    group = None
    for r in recs:
        if r["group"] != group:
            group = r["group"]
            out.append("\n%d ENT\n" % group)
        names = r["ptr"] + ("" if r["arg"] == "0" else " " + r["arg"])
        out.append(" %-3s %s:%s %-4s %-40s%5d %s \n" % (
            "%d%d" % (r["group"], r["idx"]), r["tag"], r["title"], r["type"],
            r["help"], r["default"], names))
    return "".join(out)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stdout.write(setup_map(parse_records(sys.argv[1])))


if __name__ == "__main__":
    main()
