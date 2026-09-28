"""
Phase 0 safety-net tests (notes/hybrid-plan.md, "widen the safety net"):
scanner, repeater function, and repeater CW identification. These areas
were listed as untested gaps before porting them to C.

Expected values are derived from firmware/r58.asm (line numbers cited in
each test), the same way as emu/tests/test_radio.py, not from emulator
runs. Run from the repository root:

    make -C firmware && make -C emu && python3 -m unittest discover -s emu/tests -v
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_radio import RadioTest  # noqa: E402
from r58emu import AD_SQL  # noqa: E402

EOS = 0xFF  # r58.asm L432
SIZE_STR = 8  # r58.asm L447


def cw_str(s):
    """Pack a short ASCII message into an 8-byte CFG_STR field (EOS-padded,
    r58.asm L447 `#define STRING : .rs SIZE_STR`)."""
    b = s.encode("ascii") + bytes([EOS] * SIZE_STR)
    return b[:SIZE_STR]


def poke_word(r, name, v):
    """Poke a little-endian WORD RAM/NV cell (r.poke only auto-widens a
    plain int to a single byte)."""
    r.poke(name, bytes([v & 0xFF, (v >> 8) & 0xFF]))


# ---------------------------------------------------------------------
# CW timing, derived from cw_calc_delays (r58.asm L15932-15958) at the
# SAnE defaults cfg_cw_speed=120 (L17973) and cfg_cw_pitch=140 (L17974,
# deci-Hz units). div248 (L14146-14165) is plain truncating integer
# division, so the slot length is genuinely floor(652/120), not the
# continuous 652/120 value.

_SPEED = 120
_PITCH_DECIHZ = 140
SLOT_S = (652 // _SPEED) * 0.01          # ticks (10 ms each) -> seconds
DASH_S = 3 * SLOT_S                      # cw_ditdash, NC (dash): L16078-16084
DIT_S = 1 * SLOT_S                       # cw_ditdash, CY (dit)
# Gap after the last element of a character: cw_pause_1 (1 slot, played
# inside cw_chr_1 for every element including the last) plus cw_pause_2
# (2 slots, added by the cw_chr wrapper) = 3 slots. r58.asm L16035-16076.
GAP_S = 3 * SLOT_S
PITCH_HZ = 4032000.0 / (403200 // _PITCH_DECIHZ)  # L15950-15956 -> 1400 Hz

# cw_tab entries used by the test messages (r58.asm L16237-16263):
#   E = 0b11000000 -> one dit (".")
#   T = 0b01000000 -> one dash ("-")


def sample_tone_runs(r, duration, pitch_hz, step=0.01, tol=0.05):
    """Poll r.tone_hz() every `step` s for `duration` s and coalesce into
    (kind, seconds) runs, kind "tone" if the 8254 counter-1 (pitch) is
    within `tol` of pitch_hz, else "silence". cw_pause_1/cw_pause_2
    (r58.asm L16067-16076) implement silence by reprogramming the same
    counter to a reload of 4 (~1 MHz, i.e. clearly not `pitch_hz`)
    instead of gating the tone off, so this distinguishes tone from gap
    without needing to read OUT0's CCIRC/MTC latch bits."""
    runs = []
    cur_kind, cur_dur = None, 0.0
    lo, hi = pitch_hz * (1 - tol), pitch_hz * (1 + tol)
    for _ in range(int(duration / step)):
        r.run(step)
        hz = r.tone_hz()
        kind = "tone" if (hz is not None and lo <= hz <= hi) else "silence"
        if kind == cur_kind:
            cur_dur += step
        else:
            if cur_kind is not None:
                runs.append((cur_kind, cur_dur))
            cur_kind, cur_dur = kind, step
    if cur_kind is not None:
        runs.append((cur_kind, cur_dur))
    return runs


def tone_and_gaps(runs):
    """From sample_tone_runs() output, return (tone_durations,
    gap_after_each_tone) -- the silence run immediately following each
    tone run, i.e. the inter-element/inter-character gap."""
    tones, gaps = [], []
    for i, (kind, dur) in enumerate(runs):
        if kind == "tone":
            tones.append(dur)
            if i + 1 < len(runs) and runs[i + 1][0] != "tone":
                gaps.append(runs[i + 1][1])
    return tones, gaps


# ---------------------------------------------------------------------
# Repeater FSM state, derived from repeater_state (r58.asm L19456, a
# "jump pointer" WORD). repeater_setstate (L15065-15068) pops the return
# address pushed by `call repeater_setstate` and stores it as the resume
# point for the *next* repeater_run tick, so the stored value is not the
# state label itself but somewhere inside that state's own code. Since
# as80 lays out the file in order, bucket the address between
# consecutive state labels (r58.asm L15243-15538).

STATE_LABELS = [
    "repeater_boot", "repeater_idle", "repeater_opening",
    "repeater_beep_too_long", "repeater_open", "repeater_active",
    "repeater_closing", "repeater_reopening", "repeater_lockout",
]


def repeater_state_name(r):
    marks = sorted((r.sym[n], n) for n in STATE_LABELS)
    name = marks[0][1]
    pc = r.peek16("repeater_state")
    for addr, n in marks:
        if pc >= addr:
            name = n
        else:
            break
    return name


# send_cw_prolog does not simply return: it falls into send_cw_epilog's
# own tail through a shared `1:` label (r58.asm L15969-16013, `jp 1f` at
# L15996 lands on L16009 inside send_cw_epilog), so *every* CW message --
# even a blank one -- costs two ccir_tx_timer_wait(20) calls (prolog and
# epilog), i.e. at least 2 * 20 * 10 ms = 400 ms before repeater_open_by_
# reset's call chain (L15306-15312) reaches `jp repeater_open`. Poll
# rather than assume a fixed margin.
CW_PROLOG_EPILOG_FLOOR_S = 0.4


def wait_for_state(r, test, name, timeout=2.0, step=0.05):
    for _ in range(int(timeout / step)):
        if repeater_state_name(r) == name:
            return
        r.run(step)
    test.assertEqual(repeater_state_name(r), name)


def key_access(r, method, hold=0.35):
    """Simulate an over long enough to satisfy repeater_check_beep /
    repeater_check_carrier_access (r58.asm L15072-15139), then release.
    The repeater only actually opens once the accessing carrier drops
    (repeater_opening's `call repeater_check_carrier; jp nz,1f` at
    L15303-15306: it waits while carrier is still up)."""
    r.poke("cfg_squelch_level", 127)
    if method == "1750":
        r.adc(AD_SQL, 0xC0)
        # r58.c L754-756 r58_set_ccir: nibble 8 -> pioa_data top nibble
        # 0x80, matching the "1750 Hz" code check at r58.asm L15091-15095
        # / L15121-15129 (>= 250 ms via ccir_tonetime, L15125-15126).
        r.ccir(8)
    elif method == "dtmf_star":
        r.adc(AD_SQL, 0xC0)
        # dtmf_decoder (r58.asm L3159-3183) masks the multiboard byte
        # with 0xF8: bit7 = StD, bits6..3 = the MT8870 Q output. Q=0xB is
        # '*' (repeater_check_beep's comparison at L15097-15101 is
        # literally 0x80 | (0xB << 3)).
        r.multiboard(0x80 | (0xB << 3))
    elif method == "carrier":
        r.adc(AD_SQL, 0xC0)
    else:
        raise ValueError(method)
    r.run(hold)
    r.ccir(0x0F)          # r58.c L661: 0x0f is the power-on "no tone" nibble
    r.multiboard(0)
    r.adc(AD_SQL, 0)


class Scanner(RadioTest):
    def test_scan_default_start_covers_configured_bands(self):
        # No digits before 'S': the previous scan_mask (0, fresh NV) is
        # kept and scanner_start defaults to 0x0003 = bands 1 and 2
        # (build_scan_mask/scanner_start, r58.asm L5442-5460). S8D SAnE
        # band defaults: band1 433400-433600, band2 434600-435000
        # (notes/reference/firmware-rf-ui.md §1.7).
        r = self.boot()
        r.press("S", hold=0.3)
        r.run(0.05)
        self.assertEqual(r.peek("scan_on"), 1)

        seen_band1 = seen_band2 = False
        for _ in range(80):
            r.run(0.03)
            f = r.peek24("rx_freq")
            seen_band1 = seen_band1 or 433400 <= f < 433600
            seen_band2 = seen_band2 or 434600 <= f < 435000
            if seen_band1 and seen_band2:
                break
        self.assertTrue(seen_band1, "band 1 never visited")
        self.assertTrue(seen_band2, "band 2 never visited")

    def test_scan_covers_memory_block_when_selected(self):
        # Store a scannable memory outside the default bands, reachable
        # only via the memory-block bits of scan_mask.
        r = self.boot()
        self.enter("440000")
        r.type("30")
        r.press("#", hold=1.5)          # VALID|SCANNABLE, r58.asm L9366ff
        r.run(0.3)
        self.assertLower("30  440000")

        # Digit '0' before 'S' sets the mask bits for memory decades
        # 0x..6x (digit_to_scan_mask, r58.asm L5582-5586), which covers
        # memory 30 ("3x" -> bit 9, scan_this_memblock L5588-5637).
        r.type("0")
        r.press("S", hold=0.3)
        r.run(0.05)
        self.assertEqual(r.peek16("scan_mask"), 0x1FC0)

        seen = False
        for _ in range(100):
            r.run(0.03)
            if r.peek("mem_idx") == 30 and r.peek("mem_flags") & 0x04:
                seen = True
                break
        self.assertTrue(seen, "scanner never recalled memory 30")

    def test_scan_stops_on_signal_and_resumes_when_it_drops(self):
        r = self.boot()
        r.poke("cfg_squelch_level", 127)
        # Shorten the tail-listen delay (b1:SCtAIL, default 2 s, r58.asm
        # L17845 / L18951 -- a cfg_* NV field) so the "resumes" half of
        # this test stays quick.
        r.poke("cfg_band1_sctail", 1)
        r.type("1")                     # mask = band 1 only (bit 0)
        r.press("S", hold=0.3)
        r.run(0.3)
        self.assertEqual(r.peek("scan_on"), 1)

        # AD_SQL open: squelch opens (cfg_squelch_level=127, as in
        # test_radio.Squelch), and is_sql_over_level (r58.asm L5893-5900,
        # bypassing hysteresis) pauses the scanner (scan_did_step,
        # L5916-5946) once the per-step settle wait elapses.
        r.adc(AD_SQL, 0xC0)
        r.run(0.5)
        self.assertEqual(r.peek("scan_paused"), 1)
        frozen = r.peek24("rx_freq")
        r.run(0.4)
        self.assertEqual(r.peek24("rx_freq"), frozen, "paused: no stepping")

        # Signal drops: after the squelch close hangtime and then the
        # band's (now 1 s) scan tail (L5973-6007), scanning resumes.
        r.adc(AD_SQL, 0)
        r.run(0.3)
        self.assertEqual(r.peek("scan_paused"), 1, "still in the tail wait")
        moved = False
        for _ in range(40):
            r.run(0.05)
            if r.peek24("rx_freq") != frozen:
                moved = True
                break
        self.assertTrue(moved, "scanner never resumed stepping")

    def test_scan_mask_toggle_digit_during_scan(self):
        r = self.boot()
        r.type("1")
        r.press("S", hold=0.3)
        r.run(0.1)
        before = r.peek16("scan_mask")
        self.assertEqual(before, 0x0001)

        # A digit pressed *while scanning* toggles a scan_mask bit
        # instead of being buffered (insdig_or_scan_toggle, r58.asm
        # L4501-4507 dispatch, L4902-4907 scan_on check). The toggle
        # table (L5499-5541) differs from digit_to_scan_mask (used only
        # to build the initial mask before 'S' is pressed): digit '2'
        # toggles memory decade 2x, bit 0x0100 (L5508-5510).
        r.press("2", hold=0.3)
        r.run(0.1)
        self.assertEqual(r.peek16("scan_mask"), before ^ 0x0100)

        r.press("2", hold=0.3)          # toggling again clears it back
        r.run(0.1)
        self.assertEqual(r.peek16("scan_mask"), before)

    def test_scan_reject_skips_frequency(self):
        r = self.boot()
        r.poke("cfg_squelch_level", 127)
        # A two-channel band: start <= f < end at a 25 kHz step gives
        # exactly {433400, 433425} (locate_band/build_scan_slicetab,
        # r58.asm L12211-12237, L5645-5722).
        r.poke24("cfg_band1_start", 433400)
        r.poke24("cfg_band1_end", 433450)
        # Permanently reject the first channel (is_freq_rejected_perm,
        # L5289-5317, checked by scan_did_step_freq, L5902-5906, before
        # any settle wait).
        r.poke24("cfg_reject_0", 433400)

        r.type("1")
        r.press("S", hold=0.3)
        r.run(0.2)

        r.adc(AD_SQL, 0xC0)
        paused_freq = None
        for _ in range(60):
            r.run(0.05)
            if r.peek("scan_paused"):
                paused_freq = r.peek24("rx_freq")
                break
        self.assertIsNotNone(paused_freq, "scanner never settled")
        self.assertEqual(paused_freq, 433425, "rejected channel was not skipped")
        r.adc(AD_SQL, 0)
        r.run(0.3)


class Repeater(RadioTest):
    def enter_repeater_idle(self, r, access_method=None):
        """Enable rPtr (cfg_function=1) and fast-forward past the 60 s
        boot safety window (repeater_boot, r58.asm L15250-15260) instead
        of waiting it out in real emulated time."""
        r.poke("cfg_function", 1)
        if access_method is not None:
            r.poke("repeater_cfg_access_method", access_method)
        r.run(0.2)
        self.assertEqual(repeater_state_name(r), "repeater_boot")
        # repeater_timer_other (WORD RAM, not NV) is set to 60 once on
        # entry (L15251-15252) and ticks down once a second by
        # repeater_step_1sec (L15205-15221); fast-forward it.
        poke_word(r, "repeater_timer_other", 1)
        r.run(1.2)
        self.assertEqual(repeater_state_name(r), "repeater_idle")

    def test_enable_repeater_via_menu_then_boot_delay_blocks_access(self):
        # Fn:Func is group 7, record 0 (menu_7, r58.asm L17962-17963);
        # tab_func = Std(0)/rPtr(1)/Slave(2) (L18128-18131).
        r = self.boot()
        r.poke("cfg_squelch_level", 127)
        r.type("7")
        r.press("E")
        r.run(0.3)
        self.assertUpper("Func  ")
        self.assertLower("Fn     Std")

        r.type("1")
        r.press("#")
        r.run(0.2)
        self.assertLower("Fn    rPtr")
        r.press("E")
        r.run(0.3)
        self.assertEqual(r.peek("cfg_function"), 1)

        # repeater_run (r58.asm L14868-14871): cfg_function==1 but the
        # state machine was just (re)initialised, so it is in
        # repeater_boot -- a 60 s window where nothing is checked at all
        # (not even carrier), "to allow std function to be restored".
        r.run(0.2)
        self.assertEqual(repeater_state_name(r), "repeater_boot")
        r.adc(AD_SQL, 0xC0)
        r.run(1.0)
        self.assertEqual(repeater_state_name(r), "repeater_boot")
        self.assertFalse(r.transmitting())
        r.adc(AD_SQL, 0)
        r.run(0.3)

        poke_word(r, "repeater_timer_other", 1)
        r.run(1.2)
        self.assertEqual(repeater_state_name(r), "repeater_idle")

    def test_access_by_1750hz_tone_keys_tx_and_sends_greet_cw(self):
        r = self.boot()
        # repeater_cfg_access_method default is 0 = "tonES" (L17976,
        # tab_rep_access L18114-18117): carrier alone is not enough, an
        # access tone or DTMF '*' is required (repeater_check_beep,
        # L15106-15139).
        self.enter_repeater_idle(r)
        r.poke("repeater_cfg_id_greet1", cw_str("TE"))
        r.poke("repeater_cfg_id_greet2", cw_str(""))
        r.poke("repeater_cfg_id_greet3", cw_str(""))

        key_access(r, "1750", hold=0.35)
        r.run(0.05)
        self.assertEqual(repeater_state_name(r), "repeater_opening")

        runs = sample_tone_runs(r, 1.5, PITCH_HZ)
        self.assertEqual(repeater_state_name(r), "repeater_open")
        self.assertTrue(r.transmitting(), "TX not keyed for the CW ID")

        tones, gaps = tone_and_gaps(runs)
        self.assertGreaterEqual(len(tones), 2, "expected 2 CW elements (T, E)")
        # T = dash (3 slots), E = dit (1 slot) at the SAnE default
        # cfg_cw_speed=120 -> slot = 652 // 120 = 5 ticks = 50 ms.
        self.assertAlmostEqual(tones[0], DASH_S, delta=0.03, msg="'T' element")
        self.assertAlmostEqual(tones[1], DIT_S, delta=0.03, msg="'E' element")
        # Inter-letter gap (cw_pause_1 + cw_pause_2 = 3 slots).
        self.assertGreaterEqual(len(gaps), 1)
        self.assertAlmostEqual(gaps[0], GAP_S, delta=0.03, msg="inter-letter gap")

    def test_access_by_dtmf_star(self):
        r = self.boot()
        self.enter_repeater_idle(r)   # access method still default "tonES"
        r.poke("repeater_cfg_id_greet1", cw_str("E"))
        r.poke("repeater_cfg_id_greet2", cw_str(""))
        r.poke("repeater_cfg_id_greet3", cw_str(""))

        key_access(r, "dtmf_star", hold=0.35)
        r.run(0.05)
        self.assertEqual(repeater_state_name(r), "repeater_opening")

        runs = sample_tone_runs(r, 1.0, PITCH_HZ)
        self.assertEqual(repeater_state_name(r), "repeater_open")
        self.assertTrue(r.transmitting())
        tones, _ = tone_and_gaps(runs)
        self.assertEqual(len(tones), 1, "expected a single dit ('E')")
        self.assertAlmostEqual(tones[0], DIT_S, delta=0.03)

    def test_access_by_carrier_then_topen_closes_and_sends_bye_cw(self):
        r = self.boot()
        # 1 = "CArr": carrier alone opens the repeater, no access tone
        # needed (repeater_check_carrier_access, r58.asm L15072-15085).
        self.enter_repeater_idle(r, access_method=1)
        r.poke("repeater_cfg_id_greet1", cw_str(""))
        r.poke("repeater_cfg_id_bye1", cw_str("T"))
        r.poke("repeater_cfg_id_bye2", cw_str(""))
        r.poke("repeater_cfg_id_bye3", cw_str(""))
        # Shorten the "carrier holds it open" and "closing" timers (both
        # cfg_* NV WORDs, seconds) so this test does not need to wait
        # out the 15 s / 30 s SAnE defaults (r58.asm L17965-17969).
        poke_word(r, "repeater_cfg_TOPEN", 1)
        poke_word(r, "repeater_cfg_TCLS", 1)

        key_access(r, "carrier", hold=0.35)
        # The empty greet still costs the 400 ms prolog/epilog floor
        # (see CW_PROLOG_EPILOG_FLOOR_S) before repeater_open_by_reset
        # reaches `jp repeater_open`, even with nothing to key.
        wait_for_state(r, self, "repeater_open", timeout=2.0)
        self.assertTrue(r.transmitting())

        # TOPEN (1 s) elapses with no carrier/PTT/beep -> txoff, "closing"
        # (repeater_open's end-of-open handling, r58.asm L15365-15378).
        r.run(1.3)
        self.assertEqual(repeater_state_name(r), "repeater_closing")
        self.assertFalse(r.transmitting())

        # TCLS (1 s) elapses -> repeater_send_id_bye, then idle
        # (repeater_closing, L15445-15474; test_id_bye_length skips this
        # only if id_bye is empty and MPRS-bye is off, L15604-15619). The
        # bye CW also pays the 400 ms prolog/epilog floor.
        runs = sample_tone_runs(r, 2.2, PITCH_HZ)
        wait_for_state(r, self, "repeater_idle", timeout=1.0)
        self.assertFalse(r.transmitting(), "TX should be back off after the bye ID")
        tones, _ = tone_and_gaps(runs)
        self.assertEqual(len(tones), 1, "expected a single dash ('T' bye message)")
        self.assertAlmostEqual(tones[0], DASH_S, delta=0.03)

    def test_during_id_while_open(self):
        r = self.boot()
        self.enter_repeater_idle(r, access_method=1)   # carrier access
        r.poke("repeater_cfg_id_during1", cw_str("E"))
        r.poke("repeater_cfg_id_during2", cw_str(""))
        r.poke("repeater_cfg_id_during3", cw_str(""))
        # Force a during-ID a few seconds in, but stay open well past it
        # (both cfg_* NV WORDs, seconds; r58.asm L17965-17966).
        poke_word(r, "repeater_cfg_TID", 2)
        poke_word(r, "repeater_cfg_TOPEN", 20)

        key_access(r, "carrier", hold=0.35)
        # The empty greet still costs the 400 ms prolog/epilog floor
        # (CW_PROLOG_EPILOG_FLOOR_S) before reaching "open".
        wait_for_state(r, self, "repeater_open", timeout=2.0)
        self.assertTrue(r.transmitting())

        # Sample continuously (rather than a coarse run() then a short
        # sampling window) so a single wide r.run() call cannot jump
        # straight over the short during-ID dit: repeater_open's
        # check_timer_ID fires around the 2 s TID mark and calls
        # repeater_send_id_during (r58.asm L15360-15364), restarting the
        # TID timer -- TX must stay keyed throughout (unlike the bye ID).
        runs = sample_tone_runs(r, 2.5, PITCH_HZ)
        tones, _ = tone_and_gaps(runs)
        self.assertEqual(len(tones), 1, "expected a single dit ('E' during-ID)")
        self.assertAlmostEqual(tones[0], DIT_S, delta=0.03)
        self.assertEqual(repeater_state_name(r), "repeater_open")
        self.assertTrue(r.transmitting(), "still open/keyed after the during-ID")


if __name__ == "__main__":
    unittest.main()
