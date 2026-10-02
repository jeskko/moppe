# Multiboard-ng: history

Session narrative for `notes/multiboard-ng.md`. Current state lives there.

## 2026-10-02: from XIAO to RP2354B + USB-C (moved from notes/hardware.md)

**Module candidate and the radio around it (2026-10-02).** User facts: the
5 V bus comes from a **7805CP (TO-220) on the audio board**; there is plenty
of free board space next to the FX429 socket; the case is properly shielded,
so a wireless module needs an external antenna; +13.8 V should be on one of
the CPU-card/audio-card headers (not yet located). Candidate: XIAO
ESP32-S3 Plus (20 GPIO incl. 9 rear castellations, Wi-Fi + BLE, U.FL
antenna). Inferred: it cannot answer Z80 reads in software (~100 ns from
/CS on the P8E, no /WAIT on the socket) and is not 5 V tolerant, so it needs
a hardware mailbox in front: 74LVC574 at 3.3 V for writes (clock = /CS OR
R/W), preloaded 74HCT574s for the 0xA2/0xA3 reads, or one CPLD with SPI.
Alternative front end: an RP2350 (PIO answers the bus directly; its digital
GPIOs are 5 V tolerant). Open: the 7805's heatsinking and present load (an
ESP32-S3 adds ~30-100 mA average, ~350 mA Wi-Fi TX peaks); which header pin
carries 13.8 V; the antenna route out of the case. Voice-grade audio (mic,
speaker, Wi-Fi audio) would need an I²S codec (e.g. ES8311 mono, ES8388
stereo; I²S + I²C ≈ 6-7 pins, so with a codec the CPLD/SPI front end is the
one that fits the pin budget). The ESP32-S3 has BLE only, no Classic
Bluetooth, so no A2DP/HFP headsets. The XIAO size is not required (user,
2026-10-02: larger is fine if available and reasonably priced). Leading
idea (inferred, not prototyped): a carrier with a Pico 2 (RP2350: PIO bus
interface, DSP, I²S codec) plus an ESP32 module with U.FL (wireless only),
linked by SPI or UART; it replaces the CPLD. BT headsets are a bonus, not
required (user, 2026-10-02), so the plan is an **ESP32-S3-WROOM-1U** (newer
chip, PSRAM variants for web UI / OTA / audio buffers), optionally with a
second footprint for an ESP32-WROOM-32UE (the only common ESP32 with
Classic BT) wired to the same few link pins. Chip-down alternative for the
real-time side: RP2354B (RP2350B with 2 MB flash in the package, 48 GPIO,
8 ADC inputs; needs PCB assembly, QFN-80). The radio stays a certified
module: Raspberry Pi's RM2 (CYW43439, Classic BT, same SDK) has only a PCB
antenna, useless in the shielded case. Variant (idea, 2026-10-02): only the
RP2354B inside, its USB (device, CDC and maybe USB Audio) out through a
filtered bulkhead; wireless becomes an optional external "puck" in a plastic
box (e.g. a Pico 2 W or ESP32-S3 board as USB host; on-board antennas are
fine outside, Pico 2 W adds Classic BT), or a PC/phone directly. No RF
inside, UF2 updates from outside. Risk: a 12 Mbit/s cable leaving a VHF
radio (birdies in, TX RF in, ESD): common-mode choke, TVS, shield bonded
at the entry; test early. A slow UART link out is easier to filter.
USB Wi-Fi/BT dongles inside were considered and rejected (2026-10-02):
microcontrollers have no practical dongle drivers, so it means a Linux SoC
(RV1103/1106, V3s, SAMA5D2 SiP) next to the RP2354B, with boot time,
power-loss-safe storage, more current and a networked OS to maintain. If
Linux is wanted, it fits better outside as the puck (e.g. a Pi Zero 2 W).
**Chosen direction (user, 2026-10-02): RP2354B inside, USB-C bulkhead on the
case**; a computer, phone or wireless puck plugs in there. This supersedes
the ESP32-inside plan above (kept for the record). The radio is a
self-powered USB device: VBUS only for detection, never tied to the radio's
5 V; a puck therefore needs its own supply (open: or make the port a power
source later). Connector shell bonded to the case all round.
