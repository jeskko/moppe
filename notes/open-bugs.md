# Open firmware bugs (left in place)

Known v3_Z bugs and quirks that are **not** fixed. Fixed bugs are listed
in hybrid-plan.md under "Firmware behaviour the tests pinned down"; decided
entries move to open-bugs-history.md. When fixing one: a test that fails
on the release (`R58_ROM=r58/build-release/r58.bin R58_LST=...r58.map`),
the fix in C, then move the entry. Ordered by likely user impact.

The 2026-10-01 decisions are done (entries and answers in
open-bugs-history.md).

## Setup menu

**Hook scripts typed in the menu can probably hold only digits**
(TENTATIVE, found 2026-10-02, not yet tried through the menu).
- Scripts (`GE:onHoo` 09, `GE:oFFHoo` 010, `cfg_onhook_script` /
  `cfg_offhook_script`) are up to 8 key codes; digits are the values 0-9,
  other keys their codes (`#`, `+`, `K`, ...; `r58/c/keys.c:21`). The runner
  (`script_check`, `r58/c/mainloop.c:104`) feeds them to `dokey_not_menu`:
  with key codes `4 3 3 5 5 0 #` lifting the handset sets 433.550 MHz
  (checked in the emulator).
- The menu stores a STR value from the digit-entry buffer (`r58/c/menu.c:490`),
  and only digit keys enter that buffer (`insdig`, `r58/c/keys.c:423`). So a
  script typed in the menu holds digits only: no `#` to finish a frequency
  or memory entry, no volume or other function keys. Other scripts only
  through an MBUS config load (CFGGEt) or an NV image. Same in v3_Z.
- Question: is that the intended use (digits only, e.g. `#`-less shortcuts
  the firmware completes some other way), or should the editor accept
  function keys? To confirm first: enter a script through the menu in the
  emulator and dump `cfg_offhook_script`.

## Timing (not bugs, differences of the C build)

- The C APRS path starts transmitting ~10 ms later per report (bit
  stuffing before the audio). Accepted (user, 2026-10-01: "does not sound
  like critical difference").
