# Open firmware bugs: history

Entries of notes/open-bugs.md once decided, with the user's answers as
written in the file. What was done is in hybrid-plan.md under "Firmware
behaviour the tests pinned down".

## Decided 2026-10-01

The user answered in open-bugs.md; the MBUS logger and the PH:GPSCFG
numbering were asked in the session (answers: zeros before a fix;
renumber the table and rewrite an old 9600Std, 4, to 3 at boot). The
locator edge had its fix written down already. All fixed, removed or
kept as decided on 2026-10-01.

### GPS

**Aisin Seiki binary GPS path is broken** (`cfg_gps_config` 3; asm
`gps_process_aisin_seiki_CACA` / `aisin_seiki_parse_latlon`, C
`c/gps.c`). Found 2026-09-28, shown by `test_gps_diff.py` AISIN_CASES.
- Course: heading × 45 is meant to be divided by 128; the code builds
  `H + 256 × bit 7 of L` of the product (`rl l` rotates only L). 90° shows
  45, 180° shows 90, 270° shows 390.
- Centiminutes: the ones byte is the low byte of a division remainder
  (0..1535), not a digit: 61°30'07" comes out as 30.1 and 0x80.
- Hemisphere: the N/S/E/W byte (`cfg_gps_latitude/longitude + 7`) is never
  written; it keeps whatever was there.
- Question to the user: is that GPS still in use? If not, drop the path. If
  yes, the first two are clear fixes; the hemisphere needs the unit's sign
  convention.
- Answer: I've never heard someone use this particular brand of GPS with
  this radio. I saw one email on old moppe-lista mailing list where the
  original author of the was asking about possible testers for that GPS
  model in 2004. We can remove the Aisin Seiki support pretty safely, in
  current market ebay and aliexpress is full of cheap gps modules with more
  sane output format.

**Locators exactly on a cell edge, south or west, have a last character
one low** (`packed_latlon_to_locator`): a southern/western locator is the
northern/eastern one of the absolute value, mirrored per character, and on
an exact edge (a latitude at .25' steps, a longitude at .50') the mirror
lands in the lower cell where Maidenhead puts the point in the upper one.
About 460 m in the eighth character; found 2026-09-30 against the model in
`test_signalling.OwnLocator`. Fix: compute the southern/western locator
from 90 - lat / 180 - lon instead of mirroring.

### MBUS / APRS

**Logger format dumps RAM before the first GPS fix** (`cfg_mbus_mprs` 4,
`mbus_mprs_out_logger`): it prints `gps_utc` up to EOS, and until a GPS
sentence sets it there is no EOS, so it goes on through `gps_date`, speed,
course and whatever follows until a 0xFF byte. Found by `test_aprs_diff.py`
(the two builds differed in a counter there); the test now sets a GPS time
first. Question (user): what should the time field hold before a fix
(blanks, zeros, or no field)? It depends on what reads the log.

### Repeater

**Held PTT with TBEEPMAX = 0 stalls the mainloop** (`repeater_idle` →
`repeater_opening` → `repeater_beep_too_long` → idle, all in one poll):
`repeater_check_beep` counts a pressed PTT as an access tone, the
zero-second beep limit sends opening straight to beep-too-long, and that
does not look at PTT, so it goes back to idle and round again for as long
as PTT is down. Verified 2026-09-28 in the emulator on both builds: nothing
else in the mainloop runs meanwhile, no watchdog reset, it recovers on
release. Only with a TBEEPMAX of 0. Question (user): should 0 mean no
limit, or too long at once?
Answer: 0 should be probably mean no limit.

**`repeater_operator_ptt` is dead code**: `pttcheck` returns before calling
it in repeater mode, and it returns unless in repeater mode. Harmless; kept.
Question (user): is operator PTT in repeater mode meant to do something
(talk through the repeater), or can it go?
In most cases it should be very rare for operator need to talk using the
repeater handset. If it didn't work in the asm version, we can remove it.

### Scanner

**Overlapping bands make the scanner loop between two channels**
(`scan_next_frequency`): slices are sorted by start only ("XXX also by
end ?" in the source). With band A 433400-433500 and band B 433475-433550
the scanner reaches 433500 (the end of A), goes to B's start 433475, which
is inside A again, steps to 433500, and so on for ever; later slices are
never scanned. Seen 2026-09-29 in `test_scan_diff.test_band_slices` (both
builds). A configuration error, but silent. Question (user): scan each
channel once (merge overlapping slices); which step wins where bands with
different steps overlap?
Answer: if it is relatively cheap to merge the ranges with overlapping slices
with different steps so each frequency would get scanned but each frequency
only once per scanning repeat, that would be probably optimal. 

**The busy-channel settling time never doubles** (`scan_did_step`, C
`scanner_run`): "make it double long if channel is busy" tests
`squelch_open`, but every frequency change (`temporary_change_rx_freq`)
has just closed the squelch, so it is always 0 there. Harmless; kept.
Question (user): fixing it changes scanner timing users have had since
v3_Z; wanted?
Answer: current behavior is probably the expected one.

### Menu

**SAnE does not reset CFG_DYN records** (`reset_menurec`), so the squelch
level stays 0 after SAnE although its REC default is 127. Question (user):
which DYN records should SAnE reset? The squelch levels yes, probably; the
RFC table is per-radio tuning and probably not.
Answer: let's keep the current CFG_DYN behavior.

(CFG_EXE, type 10, is defined but no record uses it: not a bug.)
