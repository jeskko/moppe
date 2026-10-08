# R40 ham firmware: user guide

An amateur radio firmware for the Nokia **R40** with a **CU43** control
head, replacing Nokia's trunking firmware: a VFO with duplex, 100
memories, scanning, CTCSS encode and a settings menu. One image serves
both models:

| Radio | Nokia's band | Ham band | Transmits | Tunes |
|---|---|---|---|---|
| **RD40** | D (400-470 MHz) | 70 cm | 430-440 MHz | 400-470 MHz |
| **RC40** | C (138-174 MHz) | 2 m | 144-146 MHz | 138-174 MHz |

The firmware takes the band from the radio's own service settings (see
"Band" below).

> **Emulator-tested only (0.x).** This firmware has run only in the
> emulator, never on a real radio. Keep the original Nokia EPROM:
> putting it back restores the radio. Transmit into a dummy load or a
> service monitor first; TX power, deviation and CTCSS are not measured
> on hardware yet. Reports from real radios are welcome.

## Installing

1. Take `r40-<version>.bin` from a release (or `make -C r40`:
   `r40/build/r40.bin`).
2. Burn it at address 0 of a **27C020** (the type Nokia used, IC53 on
   the logic board); leave the rest of the chip blank (FF).
3. Fit it in place of the Nokia EPROM and keep that one safe.

The firmware reads Nokia's factory calibration (band, receiver tuning,
TX power, deviation, squelch) from the radio's battery-backed memory and
never writes it, so the Nokia EPROM still finds it there. Its own
settings and memories go into an area Nokia's firmware does not use.

## Band

At start-up the firmware reads the band Nokia's service mode stored
(test 15x: 154 = C band, 155 = D band) and works on 2 m or 70 cm
accordingly. If the radio's memory has lost Nokia's data (flat backup
battery), it starts on 70 cm: on an RC40, choose **Band: 2 m** in the
settings menu. Leaving the menu after changing the band restarts the
firmware on the new band. Memories stored on the other band are hidden,
not deleted, and come back with that band.

## The display

```
433.50000 -  T        frequency (or what you are typing), duplex - / + / R,
                      T = CTCSS tone on, F = FNC pressed, M05 = memory 05
Vol 3         12.50k  volume, tuning step
BUSY             75   TX / BUSY (squelch open) / SCAN / LOCK / TOT, signal strength
```

## Keys

| Key | What it does |
|---|---|
| digits, then **OK** | Enter a frequency, MHz first: `4335` OK = 433.500, `43350625` OK = 433.50625, `1455` OK = 145.500 (rounded down to 6.25 kHz). **CLR** deletes the last digit. |
| **UP** / **DOWN** | Tune by one step (in memory mode: the next / previous stored memory). |
| **RCL** | Switch between the VFO and the memories. In memory mode two digits choose a channel (`05`). |
| **PTT** | Transmit. Only within the band's transmit range (430-440 or 144-146 MHz; "LOCK" otherwise); the time-out ends it ("TOT") until PTT is released. |
| **PWR** | Off. |

**FNC**, then one of these (FNC again or another key cancels):

| FNC + | |
|---|---|
| **UP** / **DOWN** | Volume |
| **1** | Next tuning step: 6.25, 12.5, 25, 100 kHz, 1 MHz |
| **#** | Duplex: simplex → − → + |
| **\*** | Shift: type it in kHz, then OK (`7600` OK = 7.6 MHz; the default is 7.6 MHz on 70 cm, 600 kHz on 2 m) |
| **0** | Reverse (listen on the transmit frequency; 'R' on the display) |
| **RCL** (STO) | Store what is on now: two digits name the memory (`00`-`99`) |
| **9** | Scan: the VFO steps through the transmit range, the memories through the stored ones. It stops on a signal and goes on 2 s after it ends. Any key or PTT ends the scan. |
| **OK** | Settings menu |

A memory keeps its frequency, duplex, shift, reverse and CTCSS tone.
Changing duplex or reverse on a memory lasts until it is recalled again;
FNC RCL stores the change.

## Settings menu

FNC OK opens it. **OK** goes to the next item, **UP** / **DOWN** change
the value (saved at once), **CLR** or **FNC** leaves.

| Item | Values |
|---|---|
| Squelch | **cal** (default: the factory-calibrated levels), open, 1-9 (higher = needs a stronger signal; the scale is a first guess) |
| Tone (CTCSS) | off, 67.0-254.1 Hz, for the current channel (VFO or memory). **Experimental**: whether the tone reaches the transmitter on a real radio is not known yet |
| Time-out | off, 30 s, 1, 2, 3, 5, 10 min |
| Beep | key beep on / off |
| TX power | low / mid / high: Nokia's factory power levels 1-3 for the frequency (mid is what Nokia used for simplex) |
| RX tune | a trim (-20..+20) on the receiver front-end tuning; the actual value is shown in brackets. Leave at 0 unless you are experimenting |
| RX self-cal | **UP** runs a self-calibration of the receiver tuning (below), **DOWN** goes back to Nokia's factory table. Shows "own" or "Nokia" |
| Band | auto (from Nokia's settings; the band in use in brackets), 2 m, 70 cm |

## Receiver self-calibration

The receiver front end is tuned per MHz by a value Nokia set at the
factory. If that calibration is missing, or the radio was tuned for
another part of the band, the self-calibration can find new values for
the transmit range (430-440 MHz on 70 cm, 144-146 MHz on 2 m):

1. Disconnect the antenna (or fit a dummy load), so that no signal is
   received.
2. FNC OK, OK until "RX self-cal", then UP. It takes about 8 seconds
   (3 on 2 m) and shows the frequency and the value found. Any key stops it, keeping
   the old values.

It looks for the setting where the receiver's own noise is strongest,
which is where the front end is tuned. This is untried on a real radio;
compare the sensitivity before and after, and use DOWN to go back to
Nokia's values.

## Known limits

- No receive CTCSS (tone squelch), no DTMF, no channel names.
- Only the CU43 head and the 2 m / 70 cm bands (not the 220 MHz RC40).
  Whether a given radio's synthesizer locks across the whole tuning
  range, or on 144 MHz for an RC40 aligned higher, is not known.
- On 2 m with Nokia's data lost, the receiver tuning starts from a flat
  placeholder: run the self-calibration.
- The squelch scale, TX power and RX tuning values come from the
  emulator and Nokia's data, not from measurements.

More detail for developers: [notes/r40-firmware.md](../notes/r40-firmware.md).
