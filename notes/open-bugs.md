# Open firmware bugs (left in place)

Known v3_Z bugs and quirks that are **not** fixed, in both the assembler
build and the C port (the ports keep them bit for bit unless noted). Fixed
bugs are listed in hybrid-plan.md under "Firmware behaviour the tests
pinned down". When fixing one: a test that fails on the release, the fix in
asm and C, then move the entry there.

Ordered by likely user impact.

## GPS

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

**Southern latitudes read as northern** (`mprs_degmin_pack`,
`gps_own_locator`, their C copies in `c/fsk.c` / `c/aprs.c`): only 'W' sets
the sign bit, 'S' does not. The MPRS report and the own locator are wrong
south of the equator. User (2026-09-28): the radios are used in Finland,
low priority.

## MBUS / APRS

**Logger format dumps RAM before the first GPS fix** (`cfg_mbus_mprs` 4,
`mbus_mprs_out_logger`): it prints `gps_utc` up to EOS, and until a GPS
sentence sets it there is no EOS, so it goes on through `gps_date`, speed,
course and whatever follows until a 0xFF byte. Found by `test_aprs_diff.py`
(the two builds differed in a counter there); the test now sets a GPS time
first.

## Repeater

**Held PTT with TBEEPMAX = 0 stalls the mainloop** (`repeater_idle` →
`repeater_opening` → `repeater_beep_too_long` → idle, all in one poll):
`repeater_check_beep` counts a pressed PTT as an access tone, the
zero-second beep limit sends opening straight to beep-too-long, and that
does not look at PTT, so it goes back to idle and round again for as long
as PTT is down. Verified 2026-09-28 in the emulator on both builds: nothing
else in the mainloop runs meanwhile, no watchdog reset, it recovers on
release. Only with a TBEEPMAX of 0.

**`repeater_operator_ptt` is dead code**: `pttcheck` returns before calling
it in repeater mode, and it returns unless in repeater mode. Harmless; kept.

## Arithmetic

**Other `div248` callers not checked for divisors ≥ 128**: `div248` is only
a true division while 2 × remainder + 1 < 256. The CW counts were fixed with
`div248_full`; the blip Hz (`blip_hz`), frequency, GPS and locator callers
have not been checked. The frequency code also relies on the carry `div248`
leaves, so do not swap it blindly (notes: hybrid-plan.md, CW entry).

**QRB metres-per-minute table read past its end** for own latitudes of 90°
and more (invalid settings; `mprs_qrb`, 90 entries). The assembler reads the
code bytes after the table; the C port uses the 89° entry instead (the one
deliberate difference in `c/aprs.c`).

## Scanner

**Overlapping bands make the scanner loop between two channels**
(`scan_next_frequency`): slices are sorted by start only ("XXX also by
end ?" in the source). With band A 433400-433500 and band B 433475-433550
the scanner reaches 433500 (the end of A), goes to B's start 433475, which
is inside A again, steps to 433500, and so on for ever; later slices are
never scanned. Seen 2026-09-29 in `test_scan_diff.test_band_slices` (both
builds). A configuration error, but silent.

## Menu

**Remote config while a DC reply is shown writes the reply buffer**
(`remote_config_execute` → `menu_new_value` → `load_menu_ptr`): while
`display_buffer_time` runs, the value pointer of every record is
`remote_display_buffer`, so an Enter-config packet from a third radio
stores its value there instead of in the variable (verified: 12 sent,
variable stays 7, buffer byte 0 becomes 12), and on a DYN or RST record
the engine would call into that RAM buffer as code. Keys cannot reach
this: every key press clears `display_buffer_time` (`cu_manipulated`)
before the menu handler runs.

**Remote config search also matches the slot after the last record**
(`remote_config_execute`): the loop compares a record's pointer before
it checks for `end_menu`, so the 16 bytes after the records (the first
TAB table: pointer field 0x43FF in both builds) count as a record. An
Enter-config packet for 0x43FF sets `menu_ptr = end_menu` (a type 0xFF
"record", no value stored), and walking on from there never meets
`end_menu` again. Needs the password; harmless otherwise.

**cSEC entry drops the last typed digit**: "150" stores 15 (shown as 150 ms).

**SAnE does not reset CFG_DYN records** (`reset_menurec`), so the squelch
level stays 0 after SAnE although its REC default is 127.

(CFG_EXE, type 10, is defined but no record uses it: not a bug.)

## Timing (not bugs, differences of the C build)

- The C APRS path starts transmitting ~10 ms later per report (bit
  stuffing before the audio).
