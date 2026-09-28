"""
Phase 0 safety-net tests (notes/hybrid-plan.md): setup-menu record-type
editing, low-battery/TOT power-down, typematic key timing, and CU58AF
handset depth -- areas the existing emu/tests/test_radio.py does not
cover yet.

Expected values are derived from firmware/r58.asm (line numbers cited in
comments beside each assertion), not from emulator runs; runs were used
only to *verify* the derivation while writing these tests, per the
project's "verify claims ... before recording them as confirmed" rule.

Run:
    make -C firmware && make -C emu
    python3 -m unittest discover -s emu/tests -v
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_radio import RadioTest  # noqa: E402
from r58emu import CU58AF, AD_BATT  # noqa: E402


def enter_menu(r, digits):
    """Position the setup menu at group/record 'digits' via 'E'.

    toggle_or_position_menu (r58.asm L17122-17222): 1 digit -> group,
    record 0; 2 digits -> group, record; >=3 digits -> group = n/100,
    record = n%100 (L17155-17188). Navigation confirmed against the
    known examples in notes/reference/firmware-rf-ui.md sec 3.5/4 and
    against a printout of every REC() group/index in r58.asm.
    """
    r.type(digits)
    r.press("E")
    r.run(0.3)


# ----------------------------------------------------------------------
# Setup menu: one scenario per REC() field type (r58.asm L419-428 for the
# CFG_* constants, L17760-18106 for the record tables). CFG_EXE (10) is
# defined (L428) but no REC() in this build uses it (confirmed by
# grep - see final report), so there is nothing to exercise for it.
# ----------------------------------------------------------------------

class MenuByte(RadioTest):
    """CFG_BYTE: dF:EntLen = cfg_enter_time (REC at L18080)."""

    def test_edit_byte_record(self):
        r = self.boot()
        enter_menu(r, "832")  # group 8, record 32 (dF:EntLen)
        self.assertUpper("EntLen")
        self.assertEqual(r.peek("cfg_enter_time"), 0)
        # draw_menu_byte (L16854-16858): 4 blanks + dpyval255(0) = "      0"
        self.assertLower("dF       0")

        r.type("5")
        r.press("#")
        r.run(0.2)
        # menu_new_value -> menu_new_value_byte (L17391-17420): a2i_byte, store
        self.assertEqual(r.peek("cfg_enter_time"), 5)
        self.assertLower("dF       5")
        r.press("E")
        r.run(0.2)
        self.assertEqual(r.peek("cfg_enter_time"), 5, "value survives menu exit")


class MenuWord(RadioTest):
    """CFG_WORD: Pr:SndInt = cfg_mprs_seconds, default 900 (REC L17789)."""

    def test_edit_word_record(self):
        r = self.boot()
        enter_menu(r, "024")  # group 0, record 24 (Pr:SndInt)
        self.assertUpper("SndInt")
        self.assertEqual(r.peek16("cfg_mprs_seconds"), 900)
        # draw_menu_word (L16873-16880): 2 blanks + zero-blanked 5 digits
        self.assertLower("Pr     900")

        r.type("12345")
        r.press("#")
        r.run(0.2)
        # menu_new_value_word (L17434-17446): a2i_word, store 16 bits
        self.assertEqual(r.peek16("cfg_mprs_seconds"), 12345)
        self.assertLower("Pr   12345")


class MenuFreq(RadioTest):
    """CFG_FREQ: b1:StArt = cfg_band1_start (REC L17841).

    After SAnE the S8D per-card default is 433400 (defaults_70cm,
    L18325-18332, applied by set_defaults_band L18343)."""

    def test_edit_freq_record(self):
        r = self.boot()
        enter_menu(r, "40")  # group 4, record 0 (b1:StArt)
        self.assertUpper("StArt ")
        self.assertEqual(r.peek24("cfg_band1_start"), 433400)
        # draw_menu_freq -> draw_long (L16882-16887, L16586-16621): 7
        # zero-blanked digits
        self.assertLower("b1  433400")

        r.type("433450")
        r.press("#")
        r.run(0.2)
        # menu_new_value_freq (L17544-17549): plain a2i, no sign handling
        self.assertEqual(r.peek24("cfg_band1_start"), 433450)
        self.assertLower("b1  433450")


class MenuTab(RadioTest):
    """CFG_TAB: PH:SynCrd = cfg_synth_card, tab_synth_card = S8d/S8c/S8b
    (REC L18044, table at L18151-18154)."""

    def test_select_each_entry(self):
        r = self.boot()
        enter_menu(r, "8")  # group 8, record 0 (PH:SynCrd)
        self.assertUpper("SynCrd")
        self.assertEqual(r.peek("cfg_synth_card"), 0)
        # draw_menu_tab (L16903-16921): index into the STR table, right-just
        self.assertLower("PH     S8d")

        r.type("2")
        r.press("#")
        r.run(0.2)
        self.assertEqual(r.peek("cfg_synth_card"), 2)
        self.assertLower("PH     S8b")

        r.type("1")
        r.press("#")
        r.run(0.2)
        self.assertEqual(r.peek("cfg_synth_card"), 1)
        self.assertLower("PH     S8c")

    def test_typed_out_of_range_clamps(self):
        # menu_new_value_tab (L17447-17462): typed index >= count clamps
        # to count-1 (2 = S8b), it never stores the raw out-of-range digit.
        r = self.boot()
        enter_menu(r, "8")
        self.assertEqual(r.peek("cfg_synth_card"), 0)
        r.type("9")
        r.press("#")
        r.run(0.2)
        self.assertEqual(r.peek("cfg_synth_card"), 2)
        self.assertLower("PH     S8b")

    def test_out_of_range_value_shows_question_marks(self):
        # Only reachable via a corrupted/foreign NV value (menu editing
        # itself always clamps, see test_typed_out_of_range_clamps).
        # draw_menu_tab (L16903-16921): if the stored index is >= the
        # table's count, it draws "???" (L16918-16921) instead of a name.
        # The menu only redraws on navigation (menu_next/menu_prev call
        # redraw explicitly), so force one after poking the NV byte.
        r = self.boot()
        enter_menu(r, "8")
        r.poke("cfg_synth_card", 7)
        r.press("R")   # menu_prev: previous record (L17282)
        r.run(0.1)
        r.press("#")   # menu_next: back to SynCrd (L17262 area)
        r.run(0.1)
        self.assertUpper("SynCrd")
        self.assertLower("PH     ???")


class MenuDpx(RadioTest):
    """CFG_DPX: b1:duPL = cfg_band1_duplex (REC L17843), signed 3-byte."""

    def test_edit_and_flip_sign(self):
        r = self.boot()
        enter_menu(r, "42")  # group 4, record 2 (b1:duPL)
        self.assertUpper("duPL  ")
        self.assertEqual(r.peek24("cfg_band1_duplex"), 0)
        # draw_menu_dpx (L16889-16901): 0 shows "    oFF"
        self.assertLower("b1     oFF")

        r.type("1600")
        r.press("#")
        r.run(0.2)
        # menu_new_value_dpx (L17551-17560): plain a2i, sign kept from the
        # previous (non-negative) value here, so +1600
        self.assertEqual(r.peek24("cfg_band1_duplex"), 1600)
        self.assertLower("b1    1600")

        r.press("-")
        r.run(0.1)
        # menu_step_value_dpx (L17591-17597): +/- both just negate the
        # value (direction is ignored), stored as a 24-bit two's complement
        self.assertEqual(r.peek24("cfg_band1_duplex"), (1 << 24) - 1600)
        self.assertLower("b1 -  1600")

        r.press("-")
        r.run(0.1)
        self.assertEqual(r.peek24("cfg_band1_duplex"), 1600)
        self.assertLower("b1    1600")


class MenuCsec(RadioTest):
    """CFG_cSEC: Sq:oPEn = cfg_squelch_head, default 10 (REC L17825).

    cSEC stores value/10 and shows value*10 with a fake trailing zero
    digit (comment at L17742, draw_menu_csec L16860-16871); entering it
    needs a dummy trailing digit too (menu_new_value_csec, L17424-17433,
    drops the last typed digit before a2i_byte)."""

    def test_edit_csec_record(self):
        r = self.boot()
        enter_menu(r, "23")  # group 2, record 3 (Sq:oPEn)
        self.assertUpper("oPEn  ")
        self.assertEqual(r.peek("cfg_squelch_head"), 10)
        self.assertLower("Sq     100")

        r.type("150")
        r.press("#")
        r.run(0.2)
        self.assertEqual(r.peek("cfg_squelch_head"), 15)
        self.assertLower("Sq     150")


class MenuStr(RadioTest):
    """CFG_STR: Pr:CALL = cfg_mprs_callsign, 8 bytes (REC L17778,
    SIZE_STR = 8 at L447)."""

    def test_alpha_entry(self):
        r = self.boot()
        enter_menu(r, "013")  # group 0, record 13 (Pr:CALL)
        self.assertUpper("CALL  ")
        # draw_menu_str -> draw_string_rightjust_scores (L16933-16935,
        # L16341-16368): empty field is '_'-padded, right justified
        self.assertLower("Pr _______")

        # Holding a digit past the 0.5s auto-repeat threshold delivers
        # 0x80|d to insdig_alpha (L4974-5010) instead of a plain digit.
        # For '3': (3-1)*4 = row 2 of alpha_tab (L4951-4960) = 'G','H','I',3;
        # the first repeat (key_time==1) selects column 0 = 'G' (0x47).
        r.press("3", hold=0.65)
        r.run(0.1)
        self.assertEqual(r.peek("digbuf"), ord("G"))

        r.press("#")
        r.run(0.2)
        # menu_new_value_str (L17522-17542): digbuf copied in, rest EOS (0xFF)
        self.assertEqual(r.peek("cfg_mprs_callsign", 8), b"G" + b"\xff" * 7)
        self.assertLower("Pr ______G")


class MenuDyn(RadioTest):
    """CFG_DYN: Sq:SqL = cfg_squelch_level via menu_sql_change/draw_sql_dpy
    (REC L17821). NOTE: reset_menurec (L17684-17709) does not handle
    CFG_DYN, so SAnE never resets this field -- it stays at its zeroed-bss
    value (0), not the REC "def" column (127); see
    emu/tests/test_radio.py's Squelch class for the same observation."""

    def test_edit_dyn_record(self):
        r = self.boot()
        enter_menu(r, "2")  # group 2, record 0 (Sq:SqL)
        self.assertUpper("SqL   ")
        self.assertEqual(r.peek("cfg_squelch_level"), 0)

        r.type("150")
        r.press("#")
        r.run(0.2)
        # menu_sql_change, digits case (L16991-16996): a2i_byte, direct store
        self.assertEqual(r.peek("cfg_squelch_level"), 150)

        r.press("+")
        r.run(0.1)
        # menu_sql_change, +/- case (L16997-17001): [hl] += signed delta
        self.assertEqual(r.peek("cfg_squelch_level"), 151)
        r.press("-")
        r.run(0.1)
        r.press("-")
        r.run(0.1)
        self.assertEqual(r.peek("cfg_squelch_level"), 149)


class MenuRst(RadioTest):
    """CFG_RST: dF:CH rSt = wipe_memories (REC L18074, function at
    L18585-18600). Distinct from the SAnE reset the test fixture itself
    uses. Every RST routine starts with check_for_666 (L18413-18419) and
    is a no-op unless the typed digits are exactly 666."""

    def test_reset_needs_666(self):
        r = self.boot()
        r.type("433525")
        r.press("#")
        r.run(0.2)
        r.type("5")
        r.press("#", hold=1.5)  # save_memory (L9366+): store into slot 5
        r.run(0.2)
        mem5 = r.peek("memories", 130 * 12)[5 * 12:5 * 12 + 12]
        self.assertEqual(mem5[6], 5, "VALID|SCANNABLE flags stored (L437-440-ish)")

        enter_menu(r, "827")  # group 8, record 27 (dF:CH rSt)
        self.assertUpper("CH rSt")
        self.assertLower("dF   666 ?")  # draw_menu_rst (L16929-16931)

        r.type("123")
        r.press("#")
        r.run(0.2)
        mem5 = r.peek("memories", 130 * 12)[5 * 12:5 * 12 + 12]
        self.assertEqual(mem5[6], 5, "wrong code: check_for_666 aborts, ret nz")

        r.type("666")
        r.press("#")
        r.run(0.2)
        mem5 = r.peek("memories", 130 * 12)[5 * 12:5 * 12 + 12]
        self.assertEqual(mem5, b"\x00" * 12, "666: wipe_memories zeroes the table")


# ----------------------------------------------------------------------
# Backspace / CL (shared by menu_input L4569 and dokey_not_menu L4512-4515)
# ----------------------------------------------------------------------

class Backspace(RadioTest):
    def test_quick_tap_erases_one(self):
        r = self.boot()
        r.type("4335")
        self.assertEqual(r.peek("digidx"), 4)
        r.press("C", hold=0.15)   # keydown < 20 (200ms) at the initial fetch
        r.run(0.1)
        # backspace (L4927-4946): digidx -= 1
        self.assertEqual(r.peek("digidx"), 3)
        self.assertLower("433_      ")

    def test_held_erases_all(self):
        r = self.boot()
        self.enter("433500")
        r.type("4335")
        self.assertEqual(r.peek("digidx"), 4)
        # 'C' is a generic non-digit key: first delivery at keydown==10
        # (100ms, erase-one), the auto-repeat re-delivery arrives 1s later
        # (key_timer/key_speed = 100/100, L10357-10363) with keydown by
        # then far past 20 -> erase all (L4935-4946).
        r.press("C", hold=1.2)
        r.run(0.1)
        self.assertEqual(r.peek("digidx"), 0)
        self.assertLower("    433500")  # back to the plain frequency display


# ----------------------------------------------------------------------
# Low battery / TOT power-down
# ----------------------------------------------------------------------

class LowBattery(RadioTest):
    """AD_BATT thresholds in battcheck (L4384-4404) and battcheck_lobatt
    (L4354-4381), called every mainloop iteration (L3308-3310) and
    repeatedly during a held PTT (L9632, L9644).

    Compile-time constants confirmed in firmware/build/r58.lst: 8V =
    0x83 (131), 9V = 0x93 (147), 10V = 0xA4 (164)."""

    def test_no_recent_tx_warning_icon(self):
        # txtail_timer == 0 (no recent TX) branch (L4397-4404): between
        # 147 (9V) and 164 (10V) just lights the low-battery clock icon,
        # no shutdown.
        r = self.boot()
        r.adc(AD_BATT, 150)
        r.run(0.3)
        self.assertIn("CLOCK", r.icons())
        self.assertTrue(r.powered)
        self.assertLower("          ")  # not the lobatt feedback text

    def test_no_recent_tx_lobatt_and_recover(self):
        # Below 147 (9V): battcheck_lobatt (L4354-4381) shows feedback and
        # busy-waits; if AD_BATT climbs back over 164 before the ~5s
        # timeout it returns without powering off.
        r = self.boot()
        r.adc(AD_BATT, 100)
        r.run(0.3)
        # feedback_lobatt (L11296-11298): " Lo batt  "
        self.assertLower(" Lo batt  ")
        self.assertTrue(r.powered)

        r.adc(AD_BATT, 220)
        r.run(1.0)
        self.assertTrue(r.powered, "battery recovered before the timeout")
        self.assertLower("          ")  # fresh SAnE nv has rx_freq == 0
        wd = [e for e in r.events if e[1] == "WDRESET"]
        self.assertEqual(wd, [])

    def test_no_recent_tx_powers_down_if_it_stays_low(self):
        # If it never recovers, battcheck_lobatt's ~5s poll (L4359-4370,
        # "seconds" wraps modulo 60) calls powerdown_now.
        r = self.boot()
        r.adc(AD_BATT, 50)
        r.run(6.0)
        self.assertFalse(r.powered)
        self.assertIn("POWEROFF", [e[1] for e in r.events])

    def test_recent_tx_uses_more_lenient_thresholds(self):
        # battcheck (L4384-4404): "jr z, 2f" on txtail_timer==0 selects
        # the 147/164 pair (label 2:, L4397-4404); falling through
        # (txtail_timer != 0, L2110-2120 counts it down after a TX) uses
        # the lower 131/147 pair instead (L4390-4396) -- i.e. a recent TX
        # is given more slack before the low-battery warning, presumably
        # because the supply sags under load. 140 is below the no-TX
        # threshold (147) but inside [131, 147), so it trips lobatt only
        # when idle, and only the warning icon (no shutdown) right after
        # a TX.
        no_tx = self.boot()
        no_tx.poke("txtail_timer", 0)
        no_tx.adc(AD_BATT, 140)
        no_tx.run(0.3)
        self.assertLower(" Lo batt  ")

        recent_tx = self.boot()
        recent_tx.poke("txtail_timer", 50)
        recent_tx.adc(AD_BATT, 140)
        recent_tx.run(0.3)
        self.r = recent_tx
        self.assertLower("          ")
        self.assertIn("CLOCK", recent_tx.icons())
        self.assertTrue(recent_tx.powered)


class TxTimeout(RadioTest):
    """TOT: once_per_minute counts the firmware clock's minute boundaries
    while txon is set (tx_on zeroes tx_tot_timer) and powers down when the
    count exceeds cfg_tx_tot_minutes, so TX lasts N..N+1 minutes.  (v3_Z
    compared before counting: N+1..N+2 minutes; fixed 2026-09-28.)"""

    def tx_with_tot(self, minutes, seconds):
        r = self.boot()
        r.type("433500")
        r.press("#")
        r.run(0.3)
        r.poke("cfg_tx_tot_minutes", minutes)
        r.poke("seconds", seconds)      # phase of the next minute boundary
        r.ptt(True)
        return r

    def test_not_before_n_minutes(self):
        # boundary 1 right after TX on, boundary 2 one minute later
        r = self.tx_with_tot(1, 59)
        r.run(59)
        self.assertTrue(r.powered)
        self.assertTrue(r.transmitting())
        r.run(4)
        self.assertFalse(r.powered)
        self.assertIn("POWEROFF", [e[1] for e in r.events])
        self.r = None  # powered off, tearDown's WDRESET check is moot

    def test_at_most_n_plus_1_minutes(self):
        # boundaries 1 and 2 at ~60 s and ~120 s after TX on
        r = self.tx_with_tot(1, 0)
        r.run(115)
        self.assertTrue(r.powered)
        r.run(8)
        self.assertFalse(r.powered)
        self.r = None

    def test_255_is_no_limit(self):
        r = self.tx_with_tot(255, 59)
        r.run(185)                      # past 3 boundaries
        self.assertTrue(r.powered)
        self.assertTrue(r.transmitting())
        r.ptt(False)
        r.run(0.3)


# ----------------------------------------------------------------------
# Typematic timing (keypad L10190-10380, typematic L10381-10404)
# ----------------------------------------------------------------------

class Typematic(RadioTest):
    def test_step_key_330ms_repeat(self):
        # digit '3' = up_freq (0x83), in the "2356" group: key_timer=50
        # (0.5s), key_speed=33 (0.33s) (L10312-10319). First delivery is
        # ~0.5s after the 100ms debounce fetch, so held 1.30s gives 3
        # deliveries (~0.6, ~0.93, ~1.26s), each one channel step (25kHz,
        # step_channel_up L12467).
        r = self.boot()
        r.type("433500")
        r.press("#")
        r.run(0.3)
        r.press("3", hold=1.30)
        r.run(0.2)
        self.assertEqual(r.peek24("rx_freq"), 433575)

    def test_squelch_key_80ms_repeat_is_faster(self):
        # digit '1' = up_sqlv (0x81), in the "14" group: key_speed=8
        # (0.08s) (L10336-10343), much faster than the 330ms step group.
        r = self.boot()
        self.assertEqual(r.peek("cfg_squelch_level"), 0)
        r.press("1", hold=0.95)
        r.run(0.2)
        self.assertEqual(r.peek("cfg_squelch_level"), 5)

        r2 = self.boot()
        r2.press("1", hold=1.03)
        r2.run(0.2)
        self.r = r2
        self.assertEqual(r2.peek("cfg_squelch_level"), 6, "one more 80ms tick")

    def test_default_key_group_is_1s_and_fires_on_release(self):
        # digit '9' = def_freq (0x89), in the "7890" group: key_speed=100
        # (1.0s) (L10328-10335). def_freq (L5109-5117) shows "dEFAULt"
        # then calls waitkey -- it only applies cfg_def_frequency (0 after
        # SAnE, since it is a FREQ record and not part of the per-card
        # defaults table) once the key is released.
        r = self.boot()
        r.type("433500")
        r.press("#")
        r.run(0.3)
        self.assertEqual(r.peek24("rx_freq"), 433500)
        r.press("9", hold=0.75)
        r.run(0.3)
        self.assertEqual(r.peek24("rx_freq"), 0)
        self.assertLower("          ")


# ----------------------------------------------------------------------
# CU58AF handset depth (existing CU58AFBoot in test_radio.py only checks
# handset detection, frequency entry and that "TPC" appears somewhere).
# ----------------------------------------------------------------------

class CU58AFDepth(RadioTest):
    cu = CU58AF

    def test_menu_text_and_navigation(self):
        r = self.boot()
        r.press("E")
        r.run(0.3)
        # draw_menu_title (L16725-16751): 6-char title + 2 extra spaces
        # for an alfa handset; draw_menu_lower_row (L16755-16792) has no
        # colon/space for alfa, so the value field follows the tag
        # directly.
        self.assertUpper("TPC     ")
        self.assertLower("GE      0")

        r.press("#")
        r.run(0.2)
        self.assertUpper("CTCSST  ")
        # draw_menu_tab right-justifies the STR table entry; tab_ctcss_tx_hz
        # entry 0 is "oFF" (L18299-18300ish, .ascii uppercased by the LCD font)
        self.assertLower("GE    OFF")

    def test_frequency_display_is_six_digits(self):
        r = self.boot()
        r.type("433500")
        r.press("#")
        r.run(0.3)
        # draw_lower_row (L11384-11450): memory info (3 chars, blank when
        # not on a memory) + draw_long with yucko_alfa_draw_long_6_only
        # set (L16589-16619), which drops the leading (always-zero) 7th
        # digit for an alfa handset.
        self.assertLower("   433500")

    def test_volume(self):
        r = self.boot()
        self.assertEqual(r.peek("volume"), 0)
        up, lo = r.display()
        # draw_upper_row (L11051-11113): P V <audio_dst> QQ <ind> SS;
        # txpwr=0, volume=0, audio_dst default is ' ' (neither '>' nor '<'),
        # squelch 0 (dpydiv99 always prints both digits, L16480-16487)
        self.assertEqual(up[0:5], "00 00")

        for _ in range(3):
            r.press("+")
        r.run(0.1)
        self.assertEqual(r.peek("volume"), 3)
        up, lo = r.display()
        self.assertEqual(up[1], "3")
        self.assertEqual(up[0], "0")  # txpwr digit unaffected


class MenuColon(RadioTest):
    def test_lower_colon_steady_while_transmitting_in_menu(self):
        """The menu row lights the lower colon. v3_Z cleared it at the start
        of every redraw and the menu drawer set it again, so with the
        tight redraw loop while transmitting in the menu about 10 % of the
        frames sent to the handset lacked it. Fixed 2026-09-28."""
        r = self.boot()
        self.enter("433500")
        enter_menu(r, "200")
        r.ptt(True)
        r.run(0.1)
        off = 0
        for _ in range(300):
            r.run(0.001)
            off += "COLON_D" not in r.icons()
        r.ptt(False)
        r.run(0.3)
        self.assertEqual(off, 0, "%d of 300 samples without the colon" % off)



class MenuMemoryCtcss(RadioTest):
    """On a memory channel the CTCSS records edit the memory's tones
    (mem_ctcss_tx/rx_hz, what get_ctcss_tx/rx_hz use there), saved into
    the memory when the menu is left. v3_Z did that only for BYTE
    records: GE:CtCSSt is a TAB record, so it changed the VFO tone
    (cfg_ctcss_tx_hz) and the memory kept its own. Fixed 2026-09-29."""

    def recalled_memory(self):
        r = self.boot()
        self.enter("433525")
        r.type("12")
        r.press("#", 1.5)
        r.run(0.3)
        r.type("12")
        r.run(0.5)
        self.assertTrue(r.peek("mem_flags") & 1)
        r.press("C")        # the recall digits stay typed: erase them
        r.press("C")
        r.run(0.3)
        self.assertEqual(r.peek("digidx"), 0)
        self.assertTrue(r.peek("mem_flags") & 1)
        return r

    def test_ctcsst_edits_the_memory(self):
        r = self.recalled_memory()
        enter_menu(r, "001")                 # GE:CtCSSt
        self.assertUpper("CtCSSt")
        r.press("+")
        r.run(0.2)
        self.assertEqual(r.peek("mem_ctcss_tx_hz"), 1)
        self.assertEqual(r.peek("cfg_ctcss_tx_hz"), 0, "VFO tone unchanged")
        self.assertLower("GE     670")
        r.press("E")                         # leave: saved into the memory
        r.run(0.3)
        rec = r.addr("memories") + 12 * r.sym["mem_SIZE"]
        self.assertEqual(r.peek(rec + r.sym["mem_CTCSSt"]), 1, "stored in memory 12")
        self.assertEqual(r.peek("cfg_ctcss_tx_hz"), 0)

    def test_ctcssr_edits_the_memory(self):
        r = self.recalled_memory()
        enter_menu(r, "002")                 # GE:CtCSSr (BYTE, worked in v3_Z)
        r.press("+")
        r.run(0.2)
        self.assertEqual((r.peek("mem_ctcss_rx_hz"), r.peek("cfg_ctcss_rx_hz")), (1, 0))

    def test_vfo_edits_cfg(self):
        r = self.boot()
        self.enter("433500")
        enter_menu(r, "001")
        r.press("+")
        r.run(0.2)
        self.assertEqual((r.peek("cfg_ctcss_tx_hz"), r.peek("mem_ctcss_tx_hz")), (1, 0))


if __name__ == "__main__":
    unittest.main()
