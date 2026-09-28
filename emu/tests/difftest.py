"""
Differential testing harness (Phase 0 of notes/hybrid-plan.md).

Runs two firmware builds ("stock" and "candidate") side by side, feeding
both the same scripted scenario, and compares what an observer of the
radio would see: display, icons, synth registers, latches, events and the
NV image.  RAM addresses differ between builds (the C candidate's data
placement is not identical to the assembler original), so everything here
is either address-independent by construction (display text/icons/synth/
latches) or resolved through *each build's own* listing (symbol names,
`radio.poke(sym, ...)`, NV offsets).

A scenario is a list of steps, each a tuple `(kind, *args)`:

    ("boot", seconds)              run() the just-constructed radios
    ("run", seconds)               advance time
    ("keys", "433500#")            Radio.type()
    ("press", key[, hold[, gap]])  Radio.press()
    ("key_down", key) / ("key_up",)  Radio.key_down() / key_up()
    ("ptt", bool)                  Radio.ptt()
    ("adc", chan, value)           Radio.adc(); chan may be an AD_* name (str)
    ("poke", symbol, data)         Radio.poke(); symbol resolved per build
    ("power", bool)                Radio.power()
    ("hook", bool)                 Radio.hook()
    ("local", bool)                Radio.local()
    ("ccir", nibble)               Radio.ccir()
    ("multiboard", value)          Radio.multiboard()
    ("serial_rx", chan, data)      Radio.serial_rx()
    ("modem_rx", data)             Radio.modem_rx()
    ("reboot"[, off_s[, boot_s]])  power off, save NV, recreate both radios
                                   from their own ROM/listing with that NV,
                                   then run(boot_s) (like a real power cycle:
                                   only the NV survives)
    ("check", label)               snapshot + compare here
    ("tones", label, seconds)      run both radios for `seconds`, sampling
                                   the 8254 counter-1 pitch (Radio.tone_hz)
                                   every TONE_STEP_S, and compare the runs
                                   of equal pitch (CW elements and gaps,
                                   marker tones): pitch within 1 %,
                                   durations within the timing tolerance;
                                   one-sample runs are folded into the run
                                   before (half-loaded 8254 counts)
    ("trace", label, fn, seconds)  sample fn(radio) every TRACE_STEP_S for
                                   `seconds` and compare the sequences of
                                   values; when each change happens may
                                   differ by the timing tolerance
    ("probe", label, fn)           compare fn(radio) of both sides (state no
                                   display/NV/latch shows, e.g. a state
                                   machine's state resolved per build)

Every step except "check" and "reboot" is applied identically, in order,
to both radios.  Differences are collected only at "check" steps (state)
and are always collected for events, using the window since the previous
checkpoint (or scenario start).
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "emu", "python"))

from r58emu import Radio, CU53AN  # noqa: E402
import r58emu  # noqa: E402

# The candidate build may take a slightly different number of cycles to
# reach the same observable state (different code size/paths for the same
# effect); exact timing is therefore not a valid comparison.  This is the
# default slack allowed between a stock event and the corresponding
# candidate event before it is reported as a timing difference.
DEFAULT_TOLERANCE_S = 0.020

NV_BASE = 0xC000
NV_SIZE = 4096

_nv_symtab_cache = {}


# --------------------------------------------------------------- symbols

def _nv_symbol_table(listing):
    """{offset: (name, delta)} for every byte of the 4096-byte NV image
    (0xC000-0xCFFF), from the build's symbol table (r58emu.load_symbols:
    sdldz80 map or as80 listing).  Only labels carry a real size; for each
    byte we keep the *smallest* enclosing symbol (most specific name), e.g.
    a struct field rather than the whole table."""
    import r58emu
    syms = r58emu.load_symbols(listing)
    key = listing if listing in r58emu.LABELS else listing[:-4] + ".map"
    labels = r58emu.LABELS.get(key, set())
    sizes = r58emu.SIZES.get(key, {})
    entries = []
    for name in labels:
        addr, size = syms[name], sizes.get(name, 0)
        if size >= 1 and NV_BASE <= addr < NV_BASE + NV_SIZE:
            entries.append((addr, size, name))

    table = {}
    for off in range(NV_SIZE):
        addr = NV_BASE + off
        best = None  # (size, addr, name) - smallest size wins, then highest addr
        for a, size, name in entries:
            if a <= addr < a + size:
                if best is None or size < best[0] or (size == best[0] and a > best[1]):
                    best = (size, a, name)
        if best is not None:
            table[off] = (best[2], addr - best[1])
    return table


def _nv_symbol_at(listing, offset):
    table = _nv_symtab_cache.get(listing)
    if table is None:
        table = _nv_symbol_table(listing)
        _nv_symtab_cache[listing] = table
    if offset in table:
        name, delta = table[offset]
        return "%s+%d" % (name, delta) if delta else name
    return None


# --------------------------------------------------------------- observe

def observe(radio):
    """Address-independent snapshot of one radio's observable state:
    display text, raw display segments, icons, powered flag, output
    latches/DACs, synth registers (including the R/N/A load counters -
    see the module docstring below on why they are included) and the
    4096-byte NV image.

    Deliberately excluded: CPU registers/PC/SP, RAM addresses, and
    anything else whose *location* rather than *effect* would differ
    between an assembler and a C build.
    """
    up, lo = radio.display()
    icons = radio.icons()
    return {
        "display": (up, lo),
        "display_raw": radio.display_raw(),
        "icons": icons,
        "powered": radio.powered,
        "latches": radio.latches(),
        "synth": radio.synth(),
        "nv": radio.nv(),
    }


# Whether `observe()`/the comparator include the synth's rx_loads/tx_loads/
# ctrl_loads counters (how many times the R58's synthesizer chip has been
# reprogrammed).  These are a plausible timing artefact: if they were
# driven by a periodic/free-running tick rather than by discrete firmware
# events, two builds taking a different number of T-states for the same
# logical work could load the synth a different number of times without
# any real behavioural difference.
#
# Evidence they are NOT timing-sensitive here (checked by experiment,
# comparing firmware/build vs firmware/build-c, i.e. the C=1 candidate
# that replaces `squelch` and the packet-CRC routines):
#   - boot + frequency entry: rx_loads/tx_loads/ctrl_loads identical
#     (4/0/3) between stock and candidate, and identical across repeated
#     stock runs from the same NV (deterministic).
#   - squelch open/close over several seconds: still identical (4/0/3);
#     unsurprising since `squelch()` never touches the synth.
#   - 30 s of idle running (well beyond any test scenario's duration):
#     still identical between stock and candidate.
# So the counters are only incremented on discrete firmware actions
# (frequency/band changes, PTT), not on a free-running timer, and are
# left in the comparison by default. If a future candidate build touches
# synth-adjacent code and this starts flaking on incidental timing, drop
# "rx_loads"/"tx_loads"/"ctrl_loads" from SYNTH_KEYS below.
SYNTH_KEYS = ("rx_r", "rx_n", "rx_a", "tx_r", "tx_n", "tx_a", "ctrl",
              "ext_a", "ext_b", "rx_loads", "tx_loads", "ctrl_loads")

# out2, pio_a and pio_b are excluded from the default comparison: they are
# not held-state outputs but continuously bit-banged/multiplexed buses
# (out2: CU53AN display shift clock/data and keypad strobe, the I2C bus,
# and the CTCSS DDS square wave; pio_a/pio_b: keypad and ADC channel
# scanning). Sampling them at an arbitrary instant catches whatever phase
# of that background activity the CPU happened to be in, which is exactly
# as timing-sensitive as the synth load counters above - checked by
# experiment: with the radio otherwise idle (same build, same NV, no
# input changes), 1.5 ms-spaced snapshots over 0.6 s of sim time show
# out2 and pio_a/pio_b cycling between 2 values each while out0, out1,
# da_rfc, da_txpwr and csmem stay constant. Comparing the cycling ones
# between stock and candidate at a checkpoint was confirmed to produce
# differences (e.g. out2 0x38 vs 0x78) that track only which build's CPU
# happened to be mid-toggle at that wall-clock instant, not a behavioural
# difference - the settled/held latches, display and synth registers at
# the same checkpoints matched exactly. Add them back if a future
# candidate needs its bit-bang *sequence* (not instantaneous level)
# checked, e.g. via audio_edges()-style capture.
LATCH_KEYS = ("out0", "out1", "da_rfc", "da_txpwr", "csmem")


# --------------------------------------------------------------- compare

def _diff_nv(label, nv_a, nv_b, lst_a, lst_b, max_runs=20):
    diffs = []
    changed = [i for i in range(NV_SIZE) if nv_a[i] != nv_b[i]]
    if not changed:
        return diffs
    runs = []
    start = prev = changed[0]
    for i in changed[1:]:
        if i == prev + 1:
            prev = i
            continue
        runs.append((start, prev))
        start = prev = i
    runs.append((start, prev))

    for n, (start, end) in enumerate(runs):
        if n >= max_runs:
            diffs.append("%s: NV: %d more differing run(s) not shown" %
                          (label, len(runs) - n))
            break
        name = _nv_symbol_at(lst_a, start) or _nv_symbol_at(lst_b, start)
        loc = "NV+0x%03x" % start
        if end > start:
            loc += "..0x%03x" % end
        if name:
            loc += " (%s)" % name
        diffs.append("%s: %s: stock=%s cand=%s" % (
            label, loc, nv_a[start:end + 1].hex(), nv_b[start:end + 1].hex()))
    return diffs


def _diff_snapshot(label, a, b, lst_a, lst_b):
    diffs = []
    if a["display"] != b["display"]:
        diffs.append("%s: display: stock=%r cand=%r" % (label, a["display"], b["display"]))
    if a["display_raw"] != b["display_raw"]:
        diffs.append("%s: display raw segments: stock=%s cand=%s" %
                      (label, a["display_raw"].hex(), b["display_raw"].hex()))
    ia, ib = a["icons"], b["icons"]
    if ia != ib:
        if isinstance(ia, set) and isinstance(ib, set):
            diffs.append("%s: icons: stock only=%s cand only=%s" %
                          (label, sorted(ia - ib), sorted(ib - ia)))
        else:
            diffs.append("%s: icons: stock=%r cand=%r" % (label, ia, ib))
    if a["powered"] != b["powered"]:
        diffs.append("%s: powered: stock=%s cand=%s" % (label, a["powered"], b["powered"]))
    for k in LATCH_KEYS:
        if a["latches"][k] != b["latches"][k]:
            diffs.append("%s: latch %s: stock=0x%02x cand=0x%02x" %
                          (label, k, a["latches"][k], b["latches"][k]))
    for k in SYNTH_KEYS:
        if a["synth"][k] != b["synth"][k]:
            diffs.append("%s: synth %s: stock=%d cand=%d" %
                          (label, k, a["synth"][k], b["synth"][k]))
    if a["nv"] != b["nv"]:
        diffs += _diff_nv(label, a["nv"], b["nv"], lst_a, lst_b)
    return diffs


def _event_key(radio, ev):
    """Comparable (type, arg) for one event.  WDRESET's arg is a raw PC,
    which is address-dependent (differs trivially between builds), so it
    is symbolized through the owning radio's own listing before compare;
    every other event's arg is small data (a strobe id, a byte value, a
    0/1 flag) and is compared as-is."""
    _, ty, arg = ev
    if ty == "WDRESET":
        arg = radio.symbolize(arg)
    return (ty, arg)


def _diff_events(label, events_a, events_b, radio_a, radio_b, tolerance_s):
    """Per event type: the same sequence, each event within the timing
    tolerance.  Types are compared apart because independent outputs (two
    serial ports sending at once, MBUS and GPS) interleave differently when
    one build is a fraction of a millisecond later; the timestamps still tie
    them together."""
    diffs = []
    types = []
    for e in events_a + events_b:
        if e[1] not in types:
            types.append(e[1])
    for ty in types:
        ea = [e for e in events_a if e[1] == ty]
        eb = [e for e in events_b if e[1] == ty]
        keys_a = [_event_key(radio_a, e) for e in ea]
        keys_b = [_event_key(radio_b, e) for e in eb]
        if keys_a != keys_b:
            diffs.append("%s: %s event sequence differs: stock=%r cand=%r" %
                         (label, ty, keys_a, keys_b))
            continue  # timestamps are meaningless once the sequence differs
        for (ta, _, _), (tb, _, _), key in zip(ea, eb, keys_a):
            dt = tb - ta
            if abs(dt) > tolerance_s:
                diffs.append(
                    "%s: event %r timing differs: stock=%.4fs cand=%.4fs "
                    "(delta %.1fms > tolerance %.1fms)" %
                    (label, key, ta, tb, dt * 1000, tolerance_s * 1000))
                break
    return diffs


# --------------------------------------------------------------- runner

def _resolve_adc_channel(ch):
    return getattr(r58emu, ch) if isinstance(ch, str) else ch


def _apply_step(radio, step):
    kind = step[0]
    if kind == "run":
        radio.run(step[1])
    elif kind == "keys":
        radio.type(*step[1:])
    elif kind == "press":
        radio.press(*step[1:])
    elif kind == "key_down":
        radio.key_down(step[1])
    elif kind == "key_up":
        radio.key_up()
    elif kind == "ptt":
        radio.ptt(step[1])
    elif kind == "adc":
        radio.adc(_resolve_adc_channel(step[1]), step[2])
    elif kind == "poke":
        radio.poke(step[1], step[2])
    elif kind == "power":
        radio.power(step[1])
    elif kind == "hook":
        radio.hook(step[1])
    elif kind == "local":
        radio.local(step[1])
    elif kind == "ccir":
        radio.ccir(step[1])
    elif kind == "multiboard":
        radio.multiboard(step[1])
    elif kind == "serial_rx":
        radio.serial_rx(step[1], step[2])
    elif kind == "modem_rx":
        radio.modem_rx(step[1])
    else:
        raise ValueError("unknown scenario step %r" % (step,))


def _make_radio(rom_lst, kw, nv=None):
    rom, lst = rom_lst
    kw = dict(kw)
    if nv is not None:
        kw["nv"] = nv
    return Radio(rom, lst, **kw)


TONE_STEP_S = 0.005


def _tone_runs(radio, seconds):
    runs = []
    for _ in range(int(round(seconds / TONE_STEP_S))):
        radio.run(TONE_STEP_S)
        hz = radio.tone_hz()
        hz = round(hz) if hz is not None else None
        if runs and (runs[-1][0] == hz or (hz and runs[-1][0] and abs(runs[-1][0] - hz) <= hz * 0.01)):
            runs[-1][1] += TONE_STEP_S
        else:
            runs.append([hz, TONE_STEP_S])
    return runs


def _settled(runs):
    """Fold one-sample runs into the run before: the 8254 count is written
    a byte at a time, so a sample can catch a half-loaded count."""
    out = []
    for hz, d in runs:
        if out and d <= TONE_STEP_S * 1.5:
            out[-1][1] += d
        elif out and (out[-1][0] == hz or (hz and out[-1][0] and abs(out[-1][0] - hz) <= hz * 0.01)):
            out[-1][1] += d
        else:
            out.append([hz, d])
    return out


def _diff_tones(label, a, b, tolerance_s):
    a, b = _settled(a), _settled(b)

    def fmt(runs):
        return " ".join("%s:%.3f" % (hz, d) for hz, d in runs)
    # the first and last runs are cut by the window: compare their pitch only
    same = len(a) == len(b) and all(
        (ha == hb or (ha and hb and abs(ha - hb) <= ha * 0.01)) and
        (i in (0, len(a) - 1) or abs(da - db) <= tolerance_s)
        for i, ((ha, da), (hb, db)) in enumerate(zip(a, b)))
    return [] if same else ["%s: tones differ:\n  stock %s\n  cand  %s" % (label, fmt(a), fmt(b))]


TRACE_STEP_S = 0.005


def _trace(radio, fn, seconds):
    changes = []
    for i in range(int(round(seconds / TRACE_STEP_S))):
        radio.run(TRACE_STEP_S)
        v = fn(radio)
        if not changes or changes[-1][1] != v:
            changes.append(((i + 1) * TRACE_STEP_S, v))
    return changes


def _diff_trace(label, a, b, tolerance_s):
    same = len(a) == len(b) and all(
        va == vb and abs(ta - tb) <= tolerance_s + TRACE_STEP_S
        for (ta, va), (tb, vb) in zip(a, b))
    if same:
        return []
    fmt = lambda c: " ".join("%.3f:%r" % x for x in c)  # noqa: E731
    return ["%s: trace differs:\n  stock %s\n  cand  %s" % (label, fmt(a), fmt(b))]


def run_diff(scenario, stock, cand, tolerance_s=DEFAULT_TOLERANCE_S,
             stock_kw=None, cand_kw=None, **radio_kw):
    """Run `scenario` against the stock build (`stock = (rom, lst)`) and
    the candidate build (`cand = (rom, lst)`), and return a list of
    human-readable differences (empty list = the two behaved identically
    at every checkpoint).

    `radio_kw` (card=, cu=, nv=, prescaler=, if_hz=, ...) is passed to
    both Radio()s; `stock_kw`/`cand_kw` override it per side (e.g. to give
    the candidate a deliberately different starting NV image, for testing
    the harness itself). The same starting `nv` is normally valid for both
    sides: NV layout is v3_Z-compatible and build-independent."""
    stock_kw = dict(radio_kw, **(stock_kw or {}))
    cand_kw = dict(radio_kw, **(cand_kw or {}))
    lst = {"stock": stock[1], "cand": cand[1]}
    rom_lst = {"stock": stock, "cand": cand}
    kw = {"stock": stock_kw, "cand": cand_kw}
    radios = {side: _make_radio(rom_lst[side], kw[side]) for side in ("stock", "cand")}

    diffs = []
    for step in scenario:
        kind = step[0]
        if kind == "boot":
            seconds = step[1] if len(step) > 1 else 2.5
            for r in radios.values():
                r.run(seconds)
            continue
        if kind == "check":
            label = step[1] if len(step) > 1 else "check"
            ev = {side: radios[side].take_events() for side in radios}
            diffs += _diff_events(label, ev["stock"], ev["cand"],
                                   radios["stock"], radios["cand"], tolerance_s)
            snap = {side: observe(radios[side]) for side in radios}
            diffs += _diff_snapshot(label, snap["stock"], snap["cand"],
                                     lst["stock"], lst["cand"])
            continue
        if kind == "tones":
            runs = {side: _tone_runs(radios[side], step[2]) for side in radios}
            diffs += _diff_tones(step[1], runs["stock"], runs["cand"], tolerance_s)
            continue
        if kind == "trace":
            tr = {side: _trace(radios[side], step[2], step[3]) for side in radios}
            diffs += _diff_trace(step[1], tr["stock"], tr["cand"], tolerance_s)
            continue
        if kind == "probe":
            v = {side: step[2](radios[side]) for side in radios}
            if v["stock"] != v["cand"]:
                diffs.append("%s: stock %r, cand %r" % (step[1], v["stock"], v["cand"]))
            continue
        if kind == "reboot":
            off_s = step[1] if len(step) > 1 else 0.5
            boot_s = step[2] if len(step) > 2 else 2.5
            for side in radios:
                r = radios[side]
                r.power(False)
                r.run(off_s)
                nv = r.nv()
                radios[side] = _make_radio(rom_lst[side], kw[side], nv)
                radios[side].run(boot_s)
            continue
        for r in radios.values():
            _apply_step(r, step)
    return diffs
