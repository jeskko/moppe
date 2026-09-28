"""
Differential tests (Phase 0 of notes/hybrid-plan.md): run the stock
firmware build against a candidate build on the same scripted scenarios
and check the emulator agrees on every observable at each checkpoint.

Run from the repository root:
    make -C firmware && make -C firmware C=1 && make -C emu
    python3 -m unittest discover -s emu/tests -v

The reference is the released v3_Z ALs firmware as built by `make -C
firmware verify` (`firmware/build-release/`, byte-identical to the
release); override with R58_REF_ROM/R58_REF_LST. The candidate defaults to
the current source, `firmware/build/`; set R58_CAND_ROM/R58_CAND_LST for
another build, e.g. `firmware/build-c/r58.{bin,map}` (`make -C firmware
C=1`). The module is skipped if either build is missing.

NV starting images come from test_radio.make_sane_nv(), which always
builds from the *stock* firmware (it is cached per card/cu/synth_card,
not per ROM - see its docstring) and only touches documented NV fields,
so the same image is a valid starting point for both builds: NV layout
is v3_Z-compatible and independent of which build wrote it.
"""
import os
import sys
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "emu", "python"))

from r58emu import P8E, P8N, CU53AN, CU58AF, AD_SQL  # noqa: E402
from test_radio import make_sane_nv  # noqa: E402
from difftest import run_diff  # noqa: E402

STOCK_ROM = os.environ.get("R58_REF_ROM", os.path.join(ROOT, "firmware", "build-release", "r58.bin"))
STOCK_LST = os.environ.get("R58_REF_LST", os.path.join(ROOT, "firmware", "build-release", "r58.map"))
STOCK = (STOCK_ROM, STOCK_LST)

CAND_ROM = os.environ.get("R58_CAND_ROM", os.path.join(ROOT, "firmware", "build", "r58.bin"))
CAND_LST = os.environ.get("R58_CAND_LST", os.path.join(ROOT, "firmware", "build", "r58.map"))
CAND = (CAND_ROM, CAND_LST)


def setUpModule():
    for rom, lst, how in ((STOCK_ROM, STOCK_LST, "make -C firmware verify"),
                          (CAND_ROM, CAND_LST, "make -C firmware")):
        if not (os.path.exists(rom) and os.path.exists(lst)):
            raise unittest.SkipTest("build not found (%s / %s); run `%s`"
                                    % (rom, lst, how))


# --------------------------------------------------------------- scenarios

def _enter(digits):
    return [("keys", digits), ("press", "#"), ("run", 0.3)]


SCN_BOOT = [
    ("boot", 2.5),
    ("check", "boot"),
]

SCN_FREQUENCY_ENTRY = [
    ("boot", 2.5),
    ("keys", "433525"),
    ("check", "digits typed"),
    ("press", "#"), ("run", 0.3),
    ("check", "absolute entry"),
    *_enter("4500"),
    ("check", "implied entry"),
]

SCN_MEMORY_STORE_RECALL = [
    ("boot", 2.5),
    *_enter("433525"),
    ("keys", "12"), ("press", "#", 1.5), ("run", 0.3),
    ("check", "stored"),
    *_enter("433500"),
    ("check", "cleared"),
    ("keys", "12"), ("run", 0.3),
    ("check", "recalled"),
]

SCN_STEPPING = [
    ("boot", 2.5),
    *_enter("433500"),
    ("press", "3", 0.65), ("run", 0.3),
    ("check", "step up"),
    *_enter("433500"),
    ("press", "6", 0.65), ("run", 0.3),
    ("check", "step down"),
]

SCN_DUPLEX_TX = [
    ("boot", 2.5),
    *_enter("434700"),
    ("check", "rx duplex"),
    ("ptt", True), ("run", 0.3),
    ("check", "tx duplex"),
    ("ptt", False), ("run", 0.3),
    ("check", "tx off"),
]

SCN_OUT_OF_BAND_REFUSED = [
    ("boot", 2.5),
    *_enter("440000"),
    ("ptt", True), ("run", 0.3),
    ("check", "refused"),
    ("ptt", False), ("run", 0.3),
]

SCN_SETUP_MENU = [
    ("boot", 2.5),
    *_enter("433500"),
    ("press", "E"), ("run", 0.3),
    ("check", "menu entered"),
    ("keys", "200"), ("press", "E"), ("run", 0.3),
    ("check", "menu exited"),
    ("ptt", True), ("run", 0.3),
    ("check", "txpwr applied"),
    ("ptt", False), ("run", 0.3),
]

SCN_VOLUME = [
    ("boot", 2.5),
    ("check", "vol0"),
    ("press", "+"), ("press", "+"), ("press", "+"), ("press", "+"),
    ("check", "vol4"),
]

SCN_SQUELCH = [
    ("boot", 2.5),
    ("poke", "cfg_squelch_level", 127), ("run", 0.3),
    ("check", "closed"),
    ("adc", "AD_SQL", 0xC0), ("run", 0.5),
    ("check", "open"),
    ("adc", "AD_SQL", 0), ("run", 1.0),
    ("check", "closed again"),
]

SCN_NV_PERSISTENCE = [
    ("boot", 2.5),
    *_enter("433525"),
    ("keys", "7"), ("press", "#", 1.5), ("run", 0.3),
    ("reboot", 0.5, 2.5),
    ("keys", "7"), ("run", 0.3),
    ("check", "recalled after power cycle"),
]


class DiffTest(unittest.TestCase):
    """Stock (firmware/build) vs. candidate (default firmware/build-c,
    C=1) on the same scenario. An empty `run_diff()` result means the two
    builds produced the same display, icons, synth registers, held output
    latches, event sequence (within a timing tolerance) and NV image at
    every ("check", ...) step."""

    def diff(self, scenario, card=P8E, cu=CU53AN, synth_card=None):
        nv = make_sane_nv(card, cu, synth_card)
        diffs = run_diff(scenario, STOCK, CAND, card=card, cu=cu, nv=nv)
        self.assertEqual(diffs, [], "\n".join(diffs))

    # ---- the harness itself

    def test_stock_matches_itself(self):
        """No false positives: the stock build diffed against itself, on
        a scenario that touches display, memories, PTT and squelch, must
        show nothing."""
        nv = make_sane_nv(P8E, CU53AN)
        scenario = (SCN_FREQUENCY_ENTRY + SCN_MEMORY_STORE_RECALL[1:] +
                    SCN_DUPLEX_TX[1:] + SCN_SQUELCH[1:])
        diffs = run_diff(scenario, STOCK, STOCK, card=P8E, cu=CU53AN, nv=nv)
        self.assertEqual(diffs, [], "\n".join(diffs))

    def test_harness_detects_real_difference(self):
        """Proof the comparison is not vacuous: same stock ROM on both
        sides, but the candidate side starts from an NV image with a
        corrupted rx_freq, which must show up at the very first
        checkpoint (display and the derived synth registers, and the NV
        bytes themselves - rx_freq is copied to tx_freq at boot too when
        the repeater offset is zero, so that also differs)."""
        nv = make_sane_nv(P8E, CU53AN)
        sys.path.insert(0, os.path.join(ROOT, "emu", "python"))
        from r58emu import load_symbols
        rx_freq_off = load_symbols(STOCK_LST)["rx_freq"] - 0xC000
        bad_nv = bytearray(nv)
        bad_nv[rx_freq_off] ^= 0xFF
        diffs = run_diff(SCN_BOOT, STOCK, STOCK, card=P8E, cu=CU53AN,
                          stock_kw={"nv": nv}, cand_kw={"nv": bytes(bad_nv)})
        self.assertTrue(diffs, "expected the poked NV to produce a difference")
        self.assertTrue(any("rx_freq" in d for d in diffs), "\n".join(diffs))

    # ---- stock vs. candidate, default P8E/CU53AN

    def test_boot(self):
        self.diff(SCN_BOOT)

    def test_frequency_entry(self):
        self.diff(SCN_FREQUENCY_ENTRY)

    def test_memory_store_recall(self):
        self.diff(SCN_MEMORY_STORE_RECALL)

    def test_stepping(self):
        self.diff(SCN_STEPPING)

    def test_duplex_tx(self):
        self.diff(SCN_DUPLEX_TX)

    def test_out_of_band_refused(self):
        self.diff(SCN_OUT_OF_BAND_REFUSED)

    def test_setup_menu(self):
        self.diff(SCN_SETUP_MENU)

    def test_volume(self):
        self.diff(SCN_VOLUME)

    def test_squelch(self):
        self.diff(SCN_SQUELCH)

    def test_nv_persistence_over_power_cycle(self):
        self.diff(SCN_NV_PERSISTENCE)

    # ---- card/handset variants (kept to a couple of representative
    # scenarios each, to stay well under the runtime budget)

    def test_p8n_variant(self):
        self.diff(SCN_BOOT, card=P8N, cu=CU53AN)
        self.diff(SCN_FREQUENCY_ENTRY, card=P8N, cu=CU53AN)

    def test_cu58af_variant(self):
        self.diff(SCN_BOOT, card=P8E, cu=CU58AF)
        self.diff(SCN_FREQUENCY_ENTRY, card=P8E, cu=CU58AF)


if __name__ == "__main__":
    unittest.main()
