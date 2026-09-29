# c/display.c indicators (tools/mutate.py; tests: test_display_diff
# test_diff.DiffTest.test_display_states test_diff.DiffTest.test_display_states_cu58af)
MUTANTS = [
    ("\t\tdpy_ch(squelch_forced ? '*' : ' ');", "\t\tdpy_ch(squelch_forced ? '*' : '-');"),
    ("\t\tSEG(CU53AN_SEG_STAR, squelch_forced);", "\t\tSEG(CU53AN_SEG_STAR, !squelch_forced);"),
    ("\tfor (i = 3; i--; ) {", "\tfor (i = 2; i--; ) {"),
    ("dpx_ind_flags = tx_freq[i] < rx_freq[i] ? 1 : 2;", "dpx_ind_flags = tx_freq[i] > rx_freq[i] ? 1 : 2;"),
    ("\t\tSEG(CU58AF_SEG_ARROW0, c & 1);", "\t\tSEG(CU58AF_SEG_ARROW0, c & 2);"),
    ("\t\tSEG(CU58AF_SEG_ARROW1, c & 2);", "\t\tSEG(CU58AF_SEG_ARROW1, c & 1);"),
    ("\tSEG(CU53AN_SEG_V_D, c & 1);", "\tSEG(CU53AN_SEG_V_D, c & 2);"),
    ("\tSEG(CU53AN_SEG_V_U, c & 2);", "\tSEG(CU53AN_SEG_V_U, 0);"),
    ("\tSEG(CU53AN_SEG_PHONE, display_buffer_time);", "\tSEG(CU53AN_SEG_PHONE, 0);"),
    ("\tif (cu_is_alfa)\n\t\treturn;\n\tSEG(CU53AN_SEG_MAST", "\tSEG(CU53AN_SEG_MAST"),
    ("\tSEG(CU53AN_SEG_MAST, get_ctcss_tx_hz());", "\tSEG(CU53AN_SEG_MAST, get_ctcss_rx_hz());"),
    ("\tSEG(CU53AN_SEG_PHONE_NO, get_ctcss_rx_hz());", "\tSEG(CU53AN_SEG_PHONE_NO, get_ctcss_tx_hz());"),
    ("\tSEG(CU53AN_SEG_KEY, squelch_muted & 2);", "\tSEG(CU53AN_SEG_KEY, squelch_muted);"),
    ("\tSEG(CU53AN_SEG_BOOK, gps_valid_seconds);", "\tSEG(CU53AN_SEG_BOOK, 0);"),
    ("#define CU53AN_SEG_BOOK\t\t0x77", "#define CU53AN_SEG_BOOK\t\t0x76"),
    ("\t\t\tsegments[(s) >> 3] &= ~(1 << ((s) & 7)); \\", "\t\t\t; \\"),
]
