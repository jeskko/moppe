# c/mainloop.c: mainloop and its per-pass checks (tools/mutate.py; tests:
# test_mainloop_diff test_gps_diff test_keys_diff.KeysDiff.test_default_memory
# test_ptt_diff.PttDiff.test_spontaneous_mprs)
MUTANTS = [
    # mainloop
    ("\t\tif (cfg_bus_rf_relay)\n\t\t\tbus_rf_relay();", "\t\tbus_rf_relay();"),
    ("\t\tif (cfg_spontaneous_mprs)\n\t\t\tspontaneous_mprs_check();", ""),
    ("\t\tccircheck();\n", "\n"),
    ("\t\tdim_lights_if_idle();\n", "\n"),
    ("\t\tidlefn_check();\n", "\n"),
    ("\t\tredrawcheck();\n", "\n"),
    # NMEA gatherer
    ("\tif (gps_hist_idx == rp)\n\t\treturn;", "\tif (gps_hist_idx == rp + 1)\n\t\treturn;"),
    ("\tlen = gps_sentence_len;\n", "\tlen = 0;\n"),
    ("if (len >= GPS_SENTENCE_SIZE)", "if (len >= GPS_SENTENCE_SIZE - 1)"),
    ("\t\tif (c == '$')\n\t\t\tgoto rewind;", ""),
    ("\t\tif (c == 0x0A) {", "\t\tif (c == 0x0D) {"),
    ("if (len >= GPS_MIN_SENTENCE)", "if (len > GPS_MIN_SENTENCE)"),
    ("\t\t*dst++ = c;\n\t\tlen++;", "\t\t*dst++ = c;"),
    ("\t\tlen = 0;\n\t\tdst = gps_sentence;", "\t\tlen = 0;"),
    ("\tgps_hist_rp = rp;\n\tgps_sentence_len = len;", "\tgps_sentence_len = len;"),
    ("\tgps_hist_rp = rp;\n\tgps_sentence_len = len;", "\tgps_hist_rp = rp;"),
    # scripts
    ("\topen_selective();\t\t/* before the script", "\t/* before the script"),
    ("\tscript_req = 0;\n", "\n"),
    ("\tif (c == 1)\n\t\tsp = cfg_onhook_script;", "\tif (c == 1)\n\t\tsp = cfg_offhook_script;"),
    ("\telse if (c == 2)\n\t\tsp = cfg_offhook_script;\n\telse\n\t\treturn;", "\telse\n\t\tsp = cfg_offhook_script;"),
    ("\tn = SIZE_STR;\n\tdo {", "\tn = SIZE_STR - 1;\n\tdo {"),
    ("\t\tif (c == EOS)\n\t\t\treturn;", ""),
    ("\t\tkey_time = 0;\t\t\t/* only quick simple presses */", ""),
    ("\t\tkey = 0xFF;\n", "\n"),
    # idle function
    ("\tidlefn_flag = 0;\n", "\n"),
    ("\tif (cfg_idlefn == 1)\n\t\tscanner_start();", "\tif (cfg_idlefn == 3)\n\t\tscanner_start();"),
    ("\telse if (cfg_idlefn == 2)\n\t\tdef_memo(0);", "\telse if (cfg_idlefn >= 2)\n\t\tdef_memo(0);"),
    # relay
    ("if (mbusrx_cnt < RELAY_BYTES)", "if (mbusrx_cnt < RELAY_BYTES - 1)"),
    ("outpacket[0] = PKT_RELAY;", "outpacket[0] = 0x51;"),
    ("for (n = 1; n <= RELAY_BYTES; n++)", "for (n = 1; n < RELAY_BYTES; n++)"),
    ("\tappend_long_packet_crc();\n", "\n"),
    ("fsk_send(LONG_PACLEN);", "fsk_send(LONG_PACLEN - 1);"),
    # small ones
    ("if (cfg_light_seconds < lights_timer)", "if (cfg_light_seconds <= lights_timer)"),
    ("\tredraw_req = 0;\n", "\n"),
    ("\tding_req = 0;\n", "\n"),
    ("\tif (!ding_req)\n\t\treturn;", ""),
]
