# Multiboard-ng: expansion card in the FX429 socket

Status: high-level design only (2026-10-02). No protocol, emulator model or
schematic yet, by choice. Session narrative and rejected options:
`notes/multiboard-ng-history.md`. Socket and radio facts: `notes/hardware.md`
("Idea (2026-09-28)", "Radio around the module", "Modem socket audio lines").
Applies to the P8x CPU cards only: the RB58VY's L8M board has no FX429
socket (FX419 modem on SIO A, `notes/rb58vy.md`).

## Direction (user, 2026-10-02)

- A carrier PCB in the FX429 socket: Z80 bus (0xA0-0xA3, FX429-compatible
  at 0xA2/0xA3), FFSKIN/FFSKOUT, plus wired taps to the mic and the point
  that feeds the speaker/earphone amplifier.
- **RP2354B** (RP2350B with 2 MB flash in the package) does the bus (PIO),
  the modem/DSP and the codec. No radio module inside.
- **USB-C bulkhead** on the case: a PC, a phone or an external wireless
  "puck" (Pico 2 W, ESP32-S3 board, Pi Zero 2 W) plugs in there.
- The Z80 keeps hardware control and the TX fail-safe, and stays a complete
  radio without the card.
- The card can **power external modules** from the port, and during
  development it can **run from USB power** alone.

## USB-C power and data roles: no PD controller needed

Type-C without PD covers both wishes at 5 V, up to 3 A by the Rp
advertisement:

| Far end | Card's role | Power |
|---|---|---|
| PC | device (UFP), sink | PC powers the card (development) or card self-powered, VBUS unused |
| Puck (USB device firmware) | host (DFP), source | card supplies 5 V, advertises 1.5 A |
| Phone (host app) | device, sink | phone supplies VBUS; the card draws ~nothing when the radio is on |

This needs a **dual-role (DRP) Type-C CC controller**, not PD: it toggles
Rp/Rd, reports which role was made, and the firmware switches TinyUSB
between host and device. The RP2350's native USB does both (one at a time).
PD is only needed for >5 V, for charging a phone that stays USB host (power
and data roles split), or for >3 A. None is planned.

## High-level BOM (candidates, not checked for stock)

| Block | Qty | Part (candidate) | Notes |
|---|---|---|---|
| **MCU** | 1 | RP2354B (QFN-80) | 48 GPIO, 8 ADC; needs PCB assembly |
| | 1 | 12 MHz crystal + caps | |
| | 1 | 3.3 µH inductor for the RP2350 core regulator | the type Raspberry Pi specifies (Pico 2 uses an Abracon AOTA-B201610S3R3) |
| | opt. 1 | APS6404L 8 MB QSPI PSRAM | audio buffers, recordings |
| | | SWD pads (Tag-Connect), BOOTSEL + RUN buttons, LED | |
| **Z80 bus** | 1 | DIL plug matching the FX429 socket | turned pins; the card sits on it or on a short ribbon |
| | 2 | SN74LVC8T245 | one for D0-D7 (DIR/OE from PIO), one for A0, A1, /CS, R/W (+ CLK) inputs. Dual supply: B side on the radio's 5 V, A side 3.3 V; outputs go high-Z if either supply is off, so the card on USB power cannot back-feed a radio that is off |
| | 1 | 2N7002 | /IRQ as open drain onto the shared SIO A DCD line |
| **Audio** | 1 | ES8388 (or TLV320AIC3204) | stereo codec over I²S/I²C: in L FFSKIN, in R mic; out L FFSKOUT, out R speaker-amp feed |
| | 1 | dual rail-to-rail op-amp | buffer the mic tap (high impedance, no loading) and drive the speaker-amp injection |
| | opt. 1-2 | analog switch (SPDT) | if injection must replace, not sum with, the radio's own audio; the Z80's OUT0 mutes may make it unnecessary |
| | | AC coupling, bias, RC filters, level trimmers | values from the audio-board traces |
| **USB-C** | 1 | USB-C receptacle on the card + panel-mount extension to the bulkhead | the extension must carry CC; shell bonded to the case all round |
| | 1 | DRP CC controller without PD (TUSB320-class) | FUSB302B instead if PD might be wanted later (needs a firmware stack) |
| | 1 | USB ESD array (USBLC6-2-class) | |
| | 1 | common-mode choke on D+/D- | birdie and TX-RF defence |
| | 2 | 27 Ω series resistors | RP2350 USB requirement |
| | 1 | current-limited VBUS load switch, reverse blocking | source mode only, enabled only when the 13.8 V buck is up |
| **Power** | 1 | input protection: fuse, reverse-polarity FET, TVS (~33 V class) | vehicle supply |
| | 1 | buck 13.8 V → 5 V, 2 A, ≥40 V input (LMR36015-class) | shielded inductor, input and output LC filters, shield can |
| | 1 | 5 V power mux / ideal-diode OR (TPS2121 or LM66200 class) | picks buck 5 V or USB VBUS |
| | 1 | 3.3 V LDO, ~300 mA | digital: RP2354B, translators' A side |
| | 1 | low-noise 3.3 V LDO + ferrite | codec analog supply |
| | | dividers into ADC: 13.8 V monitor, radio-5 V present | |
| **Connectors** | 1 | 13.8 V + GND lead to the CPU/audio header | pin not yet located |
| | 1 | audio tap lead (mic, speaker feed, GND) | |
| | opt. 1 | aux UART header (GPS, debug) | |

The radio's 7805 then supplies only the translators' 5 V side (µA). The
card, and anything on the USB port, runs from its own buck.

Rough cost, small quantities: parts ~$20-25 + assembled PCB + the bulkhead
extension (~$5-10): ~$40-50 a board.

## Open

1. Which header pin carries 13.8 V; the FX429 socket pin count/footprint.
2. The mic tap point (before or after the mic amplifier) and the speaker
   amplifier's input point, with levels and bias.
3. Whether FFSKIN is de-emphasized; where FFSKOUT enters the TX chain.
4. Phone attach: both ends DRP, so the role is chosen by the CC controllers
   (Try.SNK on the card would make the phone the host); check the part.
5. Birdie test with USB connected and the squelch open (early prototype).
6. Hardware test of the RS window and EPROM1 banking (unrelated, still pending).
