# Open firmware bugs (left in place)

Known v3_Z bugs and quirks that are **not** fixed. Fixed bugs are listed
in hybrid-plan.md under "Firmware behaviour the tests pinned down"; decided
entries move to open-bugs-history.md. When fixing one: a test that fails
on the release (`R58_ROM=firmware/build-release/r58.bin R58_LST=...r58.map`),
the fix in C, then move the entry. Ordered by likely user impact.

No open bugs: the 2026-10-01 decisions are done (entries and answers in
open-bugs-history.md).

## Timing (not bugs, differences of the C build)

- The C APRS path starts transmitting ~10 ms later per report (bit
  stuffing before the audio). Accepted (user, 2026-10-01: "does not sound
  like critical difference").
