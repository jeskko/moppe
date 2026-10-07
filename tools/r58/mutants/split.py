# c/keys.c 'R' held with digits: shift and split (tools/r58/mutate.py; tests:
# test_keys_diff.KeysDiff.test_duplex_key test_keys_diff.KeysDiff.test_cu58af test_keys_diff.KeysDiff.test_p8n)
MUTANTS = [
    ("\tduplex_shift[0] = ~duplex_shift[0];\n", "\n"),
    ("\tduplex_shift[2] = ~duplex_shift[2];\n", "\n"),
    ("\tif (!++duplex_shift[0] && !++duplex_shift[1])\n\t\t++duplex_shift[2];", "\t++duplex_shift[0];"),
    ("\tif (!++duplex_shift[0] && !++duplex_shift[1])\n\t\t++duplex_shift[2];", ""),
    ("\tkeys_a2i(duplex_shift);\n\tduplex_state = DPX_DUPLEX;\n\tchanged_frequency_duplex_okay();\n}\n\n/* TX on", "\tduplex_state = DPX_DUPLEX;\n\tchanged_frequency_duplex_okay();\n}\n\n/* TX on"),
    ("\tduplex_state = DPX_SPLIT;", "\tduplex_state = DPX_DUPLEX;"),
    ("\tif (n < 3) {\n\t\tcopy3(tx_freq, memory_rec(a2i_byte()));", "\tif (n < 2) {\n\t\tcopy3(tx_freq, memory_rec(a2i_byte()));"),
    ("\t\tif (n < 5)\n\t\t\tfill_implied();\n\t\tkeys_a2i(tx_freq);", "\t\tkeys_a2i(tx_freq);"),
    ("\t\tcopy3(tx_freq, memory_rec(a2i_byte()));", "\t\tcopy3(tx_freq, memory_rec(a2i_byte()) + 3);"),
]
