# c/freq.c RFC table fill (tools/r58/mutate.py; tests: test_rfc_diff test_menu_diff.MenuDiff.test_dyn_rfc)
MUTANTS = [
    ("\twhile (!rfctab[x2]);", "\twhile (!rfctab[x2] && x2 < 98);"),
    ("\tdy = rfctab[x2] - rfctab[x];", "\tdy = rfctab[x2] - rfctab[x] - 1;"),
    ("\tdx = x2 - x;", "\tdx = x2 - x + 1;"),
    ("\t\tif (dx < dy) {", "\t\tif (dx <= dy) {"),
    ("\t\t\t} while (sum < dy);", "\t\t\t} while (sum <= dy);"),
    ("\t\t\tsum -= dy;\n\t\t} else {", "\t\t\tsum = 0;\n\t\t} else {"),
    ("\t\t\tif (sum >= dx) {", "\t\t\tif (sum > dx) {"),
    ("\t\t\t\tsum -= dx;\n\t\t\t\ty++;", "\t\t\t\ty++;"),
    ("\trx = x;\n}", "\trx = x - 1;\n}"),
    ("\tif (!rfctab[99])\n\t\trfctab[99] = 0xFF;", "\tif (!rfctab[99])\n\t\trfctab[99] = 0xFE;"),
    ("\t} while (rx < 98);", "\t} while (rx < 97);"),
    ("\t\tif (!rfctab[rx + 1])\n\t\t\trfc_fill_one_hole();", "\t\tif (!rfctab[rx])\n\t\t\trfc_fill_one_hole();"),
    ("\trx = 0;\n\tdo {", "\trx = 1;\n\tdo {"),
]
