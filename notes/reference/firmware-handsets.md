> Provenance: written 2026-09-28 by a research subagent from the firmware source
> (line numbers `Lnnnn` = unmodified `reference/r58.asm.als`) or the scanned manuals.
> Items the emulator tests exercise are confirmed; everything else is as-read.
> Corrections found since: see notes/hardware.md.

# R58 firmware ↔ control unit (handset) interface — emulator spec

Source: `r58/r58.asm` (line numbers `Lnnnn` refer to this file). Addresses come from
`r58/build/r58.lst` (build `-DP8x`). This document uses only what the firmware does.
Anything about device behaviour that the firmware cannot tell us is marked **[DEVICE]**.

Key addresses (P8x build):

| symbol | addr | symbol | addr |
|---|---|---|---|
| sioa_esc | 0x06CD | keypad | 0x3A44 |
| cu_handler_stub | 0x06E0 | slight_delay | 0x3A3E |
| cu_handler_unknown | 0x06E4 | display | 0x42B9 |
| cu_handler_cu53 | 0x06E5 | display_cu53an | 0x42C0 |
| cu_handler_cu58af | 0x070B | display_group / _byte / _bit | 0x42FA / 0x430C / 0x4318 |
| dosir | 0x096C | cu_now_known | 0x4329 |
| pull_down_DCU / release_DCU | 0x0EE4 / 0x0EEC | probe_cu58af | 0x433D |
| main | 0x0EF9 | cu58af_init | 0x440D |
| cu53an_font | 0x0500 | keypad_cu58af | 0x446B |
| res_set_stubs | 0x0590 | display_cu58af | 0x44E6 |
| CU53AN_segs_bottom_row | 0x00C9 | i2c_getbit…i2c_recv | 0x4511…0x45CC |
| keytbl_cu53an | 0x4C68 | i2c_dtmf / i2c_dtmf_tone | 0x43A6 / 0x4396 |
| keytbl_cu58af | 0x4C88 | dpydig | 0x5D12 |
| cu58af_font | 0x4CD0 | | |
| RAM: segments[64] | 0xDB00 | indicators | 0xDB40 |
| sir / nosir | 0xD0AC / 0xD0AD | key / dark / keydown | 0xD0B0 / 0xD0B1 / 0xD0B4 |
| piob_mode | 0xD0D7 | dtmf_code / cu58af_buttons | 0xD0DA / 0xD0DB |
| cu_is_alfa | 0xD0DD | cu_handler (word) | 0xD0DE |

---------------------------------------------------------------------------

## 1. Physical signals shared by both CUs

### 1.1 OUT2 latch (port 0x80), write-only (L676-690)

| bit | name | CU53AN meaning | CU58AF meaning |
|---|---|---|---|
| 0x01 | O2_RA14 | – (RAM bank on P8N; always 0 in every OUT2 write) | – |
| 0x02 | O2_RA15 | – (always 0) | – |
| 0x04 | O2_RS | **never set** anywhere in the firmware | – |
| 0x08 | O2_SMEM | always 1 (`O2_XXX = O2_SMEM`, L685). Cleared only by P8N NV-RAM code (L14213-14290, `#ifdef P8N`, not in the P8x build) | always 1 |
| 0x10 | O2_CS1 | select code bit 0 | always 0 |
| 0x20 | O2_CS2 | select code bit 1 | always 0 |
| 0x40 | O2_CLK | serial clock | **I2C SCL**, push-pull from the latch (L682) |
| 0x80 | O2_DP  | serial data to CU | always 0 |

Select codes (L687-690), written as the complete OUT2 value:

| value | name | CS2 CS1 | meaning |
|---|---|---|---|
| 0x08 | O2_KEYPAD | 0 0 | keypad shift register load/strobe. Also the value that I2C code writes for SCL=0 |
| 0x18 | O2_LATCH  | 0 1 | indicator (LED) latch strobe |
| 0x28 | O2_LCD1   | 1 0 | LCD driver 1. Also the idle/rest state of the CU53 bus |
| 0x38 | O2_LCD2   | 1 1 | LCD driver 2 |

The firmware never reads OUT2 back and has no shadow copy of it. Every write is a full byte.
Only three kinds of code write OUT2: the boot init, the CU53 display/keypad code, and the
I2C SCL routines. They never run at the same time, because display and keypad work runs only
inside `dosir` and the probe runs before soft interrupts are allowed.

Boot value: `OUT2 = 0x08` (L1072-1073), which is KEYPAD select with CLK=0 and DP=0.

### 1.2 PIO B bit 3 = PB_DCU (L705, L711-712)

- For CU53 it is the serial data line **from** the CU (keypad bits and the LDR bit).
- For CU58AF it is **I2C SDA**, open-drain emulated by switching the pin's direction:
  - The PIO B output data register bit 3 is always 0. BDATA is written only with values whose
    bit 3 is clear (L1095, L1112, L2550, L2570, L2579, L10091).
  - `pull_down_DCU` (L3230) clears bit 3 in `piob_mode`, making the pin an output that drives 0.
  - `release_DCU` (L3235) sets the bit, making the pin an input. **[DEVICE]** an external pull-up must take SDA high.
  - Both routines write PIO B control `0xCF` (mode 3), then `[piob_mode]` (the direction mask, 1=input) (L3238-3243).
  - `piob_mode` starts as `PB_INPUTS = 0x2E` (L1091-1092, again after the BSS clear at L1154-1155).
    The mode-3 mask in `init_chips` is **0x3E** (L912), so bit 4 is an input until the first
    pull_down/release call rewrites the mask to 0x2E / 0x26. An emulator must honour each new
    mode-3 mask.
- Reading is always `in a,[PIO+BDATA]; and 0x08`, the raw pin level.

### 1.3 SIO A /CTS = SA_DA (L717, RR0_CTS = 0x20, L639)

- CU53: DA ("data available") line. CU58AF: the I2C `/INT` line.
- The firmware reads RR0 (`in a,[SIO+ACTRL]`, register pointer 0) and tests bit 0x20. The Z80
  SIO reports the **inverse** of the /CTS pin in RR0 bit 5. The code comments agree:
  "/CTS inverts the input" (L1795) and "go if DA high" when the bit reads 0 (L1797).
  - **pin high → RR0.5 = 0**. CU53: DA high = key made. CU58AF: /INT idle (high).
  - **pin low → RR0.5 = 1**. CU53: DA low = idle / key broken. CU58AF: /INT asserted.
- SIO A WR1 = STATUS_VECTOR | ESCINT_ENB | TXINT_ENB | INT_ALLC (L932). Every CTS transition
  raises an Ext/Status interrupt → `sioa_esc` (L1758). The handler calls
  `cu_handler_stub` → `jp [cu_handler]` (L1774-1777), then `modem_handler`, then a dummy
  TMR read, then `WR0_RESET_ESCINT` (L1765-1766). The CU handler reads RR0 **before** the
  reset. With real SIO latching, it therefore sees the latched level from the change.
- `cu_handler` is `cu_handler_unknown` (a bare `ret`) from L1521 until `cu_now_known` runs.

### 1.4 Other CU-related inputs

- PIO A bit 1 `PA_HOOK` (L697): hook switch. It is polled in `systick` (L2029-2047). 0 = handset off
  cradle (L2339-2340 comment "handset off cradle"). This is not part of the serial protocol.
- The CU58AF "OFFHOOK" bit in its I2C port is **never used** by the firmware. See §3.5.

---------------------------------------------------------------------------

## 2. CU53AN (numeric handset, shift-register bus)

### 2.1 Bit primitive: `display_bit` (L11568-11580)

The routine is entered with A = the current select value, which has CLK=0 and DP=0. Carry holds the data bit.

```
  (carry=1) A |= DP           ; display_bit_one
            A |= CLK
  OUT2 = A      ; DP=data, CLK=1  (DP and CLK change in the same write)
  A &= ~CLK
  OUT2 = A      ; CLK falls, DP still = data
  A &= ~DP
  OUT2 = A      ; DP back to 0
```

- DP is already valid when CLK rises, because it is set in the same OUT, and stays valid through
  the falling edge. It returns to 0 about 18 T later. **An emulator can sample DP on the CLK
  rising edge or the falling edge. Both give the same bit.** A real device probably samples on
  the falling edge, since the rising edge has zero setup time. **[DEVICE]**
- Timing: about 18 T between each pair of OUTs (`and n` 7T + `out (n),a` 11T), plus M1 wait states on
  P8E. That is ≈2.2-2.5 µs at 8.064 MHz and ≈4.5 µs at 4.032 MHz. Each bit takes about 88 T
  including the call and ret.

`display_byte` (L11558-11566): 8 bits from `[hl++]`, **LSB first** (`srl c` → carry).

### 2.2 LCD frame: `display_cu53an` (L11508-11542)

Sequence, where every step is a full OUT2 write:

```
OUT2 = O2_LCD2 (0x38)                          ; L11512-11513
group(LCD1): OUT2=0x28; bit 0; 32 bits segments[0..3];   bit 0     ; LCD1 "half 0"
group(LCD2): OUT2=0x38; bit 0; 32 bits segments[4..7];   bit 0     ; LCD2 "half 0"
group(LCD1): OUT2=0x28; bit 0; 32 bits segments[8..11];  bit 1     ; LCD1 "half 1"
group(LCD2): OUT2=0x38; bit 0; 32 bits segments[12..15]; bit 1     ; LCD2 "half 1"
OUT2 = O2_LCD1 (0x28)                          ; L11531 "unselect LATCH"
8 bits indicators, LSB first, clocked with select = LCD1 (0x28|DP|CLK)   ; L11534-11535
OUT2 = O2_LATCH (0x18)                         ; L11537-11538 latch strobe (~18 T wide)
OUT2 = O2_LCD1 (0x28)                          ; L11539-11540
```

`display_group` (L11544-11552) writes the select, sends one leading **0** bit, then 4 bytes
(32 bits, LSB of the lowest byte first). The caller then appends one trailing bit: **0 for
the first pass, 1 for the second pass**. Each LCD transfer is therefore **34 clocks**:
`0, d0…d31, H`, where H selects which half (backplane set) is loaded.

Selection is always changed by rewriting OUT2. The previous chip is deselected when the next
select value is written (LCD1→LCD2→LCD1→LCD2→LCD1).

Suggested emulator model (**[DEVICE]**). The observed pattern matches a duplex CBUS LCD driver
(PCF2111-like), where the chip enable is its select code, a 0 start bit is followed by 32 data
bits and a load bit, and data is latched when the enable is removed:

- On the rising (or falling) edge of CLK while the chip is selected, shift in DP.
- On deselect, if exactly 34 bits arrived and the first bit was 0, load bits 1..32 into half H
  (the 34th bit). Otherwise ignore the transfer.
- This rule matters. LCD1 is also "selected" (0x28) during the 8 indicator clocks and the 5
  keypad clocks (§2.4). Those runs are 8 or 5 bits long, or longer if they follow each other
  without a deselect. They must not corrupt LCD1. The firmware assumes they don't.

### 2.3 Indicator latch (LEDs and backlight)

Eight bits from RAM `indicators` (0xDB40) go out LSB first on DP/CLK. The latch then gets one
select pulse, `O2_LATCH`. **[DEVICE]** The CU presumably has a serial-in shift register
clocked by CLK, whatever the select code, with an output latch strobed by the LATCH select.
After 8 clocks, byte bit 0 is the one shifted in first.

`indicators` bit meanings for CU53AN (L785-792):

| bit | name | used by |
|---|---|---|
| 0 | AVAIL | "not connected" |
| 1 | CALL | cu_call_on/off L10829-10849 |
| 2 | ROAM | used as the TX LED: light/dim_transmit_led L10740-10760 |
| 3 | KEYLIGHT | cu_lights_on/off L10766-10804 |
| 4 | SERV | squelch open/close: cu_serv_on/off L10807-10827 |
| 5 | ON | light_on_led L10729-10738 (set once at boot) |
| 6 | LCDLIGHT | cu_lights_on/off |
| 7 | BRIGHT | defined, never written |

A value of 1 means "on". **[DEVICE]** The output polarity is not known.

### 2.4 Keypad read: `keypad` CU53 branch (L10197-10255)

It runs only from `dosir` when `KEYSIR` is set (see §2.6). Every OUT2 write below is followed by
`slight_delay` (L10166, `call`+5×`nop`+`ret` = 47 T, plus 7 wait T on P8E).

```
OUT2 = 0x28 (LCD1)        ; idle
OUT2 = 0x08 (KEYPAD)      ; select keypad register
OUT2 = 0x48 (KEYPAD|CLK)  ; CLK rising while KEYPAD selected: "strobe the data into shifter"
OUT2 = 0x08 (KEYPAD)
OUT2 = 0x28 (LCD1)        ; delay ×2
read PB3 -> dark = PB3 & 0x08          ; LDR bit, raw level, NOT inverted (L10228-10230)
repeat 5 times:
    OUT2 = 0x68 (LCD1|CLK) ; delay
    OUT2 = 0x28 (LCD1)     ; delay ×2
    read PB3: bit = (PB3 == 0) ? 1 : 0 ; `and 8; sub 1` -> carry  (L10247-10249)
    c = (c << 1) | bit                 ; rl c  -> first bit read = code bit 4 (MSB)
key = keytbl_cu53an[c]                 ; c = 0..31 (L10253-10255)
```

So the CU shift register is loaded in parallel on the CLK pulse made while KEYPAD is selected.
Its serial output on PB3 then shows the **LDR** bit first, before any shift clock, followed by
the 5 keycode bits **MSB first**, one per CLK pulse made with select = LCD1. The code bits are
**active low**: a low pin means 1. **[DEVICE]** Whether the shift happens on the rising or falling
CLK edge cannot be determined. PB3 is sampled at least 2×47 T after the falling edge, so
shifting on the rising edge is safe to emulate.

The CU58AF probe (§3.6) also clocks SCL=OUT2.6 with select 00 (KEYPAD). A CU53 therefore
receives many strobe pulses at boot. The firmware assumes they do no harm (comment L11601).

`dark` (0xD0B1) is initialised to 0xFF (L1167-1168) and written only here. **Nothing reads it.**
The LDR has no effect on firmware behaviour.

### 2.5 `keytbl_cu53an` (L13097-13101), code → key

Digits are stored as the binary values 0-9, not ASCII. Letters are ASCII.

| code | key | code | key | code | key | code | key |
|---|---|---|---|---|---|---|---|
| 0-11 | 'Z' (none) | 12 | '+' | 13 | '-' | 14 | '?' |
| 15 | 'B' | 16 | 'E' | 17 | '*' | 18 | 0 |
| 19 | '#' | 20 | 'R' | 21 | 7 | 22 | 8 |
| 23 | 9 | 24 | 'S' | 25 | 4 | 26 | 5 |
| 27 | 6 | 28 | 'C' | 29 | 1 | 30 | 2 |
| 31 | 3 | | | | | | |

The CU53 path does not filter 'Z'. A code 0..11 is passed on as key 'Z'.

The common post-processing (L10259-10366) sets `lastkey`, `key` and the typematic parameters.
'*' and 'B' never repeat. Digits: `lastdigit`, where a quick release gives the digit and holding
it gives digit|0x80 (typematic L10368-10388). With PTT down, digits become DTMF.

### 2.6 DA / ESC handling and debounce (CU53)

`cu_handler_cu53` (L1793-1814):
- RR0.CTS = 0, meaning DA pin high (key made): if `keydown == 0`, set `keydown = 1`.
- RR0.CTS = 1, meaning DA pin low (key broken): clear `key_timer` and `keydown`. If `lastdigit != -1`,
  set `key = lastdigit` (a quick press of a dual-purpose digit) and `lastdigit = -1`.

In `systick` (100 Hz, L2123-2136), if `keydown != 0` it is incremented. It saturates, never wrapping
to 0. When it reaches **10**, `sir.KEYSIR` is set. `dosir` (L2254-2260) then calls `keypad`. The
CU is read about **90 ms** after DA rises, and only once per make. The DA level is not checked
again at read time.

**[DEVICE]** The firmware expects DA to rise on make and fall on break (L1786). It also expects
the keycode to stay stable until at least 90 ms after make.

### 2.7 `segments` → CU53 glyphs

The 7-segment font `cu53an_font` (L1358-1478, page-aligned at 0x0500, 128 bytes) has one byte
per ASCII code, and codes 0x00-0x10 hold hex digits 0-F and 'G'. Bits:

| font bit | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| segment (derived from glyphs) | f (upper-left) | e (lower-left) | c (lower-right) | b (upper-right) | a (top) | g (middle) | d (bottom) |

These segment letters come from glyph shapes: '1'=0x0C (bits 2,3), '-'=0x20, '_'=0x40, '^'=0x10,
'`'=0x01, 'L'=0x43, '7'=0x1C. Codes 0x11-0x1F are 0xFF in the binary, meaning all on. Codes ≥0x80
would index beyond the table into res_set_stubs code bytes, so they are undefined.

`dpydig` (L16491-16513) with `DE` pointing at a 7-byte "position" entry calls
`segment_onoff_XXX` 7 times (L11473-11498). Font bit *i* (bit 0 first) goes to position
byte *i*. A position byte `p` means **`segments[p>>3]` bit `p&7`**: set if the font bit is 1,
cleared if 0, using the res/set stub table at L1493. `DE` advances by 7, so consecutive `dpydig` calls
move one digit to the right.

Position tables (L995-1014). Each entry is `{4 positions in half 0, 3 positions in half 1}`,
which is `{f,e,c,b},{a,g,d}`:

| digit | positions f,e,c,b | a,g,d | driver |
|---|---|---|---|
| d9 | 56-59 | 120-122 | LCD2 |
| d8 | 60-63 | 124-126 | LCD2 |
| d7 | 0-3 | 64-66 | LCD1 |
| d6 | 4-7 | 68-70 | LCD1 |
| d5 | 8-11 | 72-74 | LCD1 |
| d4 | 12-15 | 76-78 | LCD1 |
| d3 | 16-19 | 80-82 | LCD1 |
| d2 | 20-23 | 84-86 | LCD1 |
| d1 | 24-27 | 88-90 | LCD1 |
| d0 | 28-31 | 92-94 | LCD1 |
| u5 | 32-35 | 96-98 | LCD2 |
| u4 | 36-39 | 100-102 | LCD2 |
| u3 | 40-43 | 104-106 | LCD2 |
| u2 | 44-47 | 108-110 | LCD2 |
| u1 | 48-51 | 112-114 | LCD2 |
| u0 | 52-55 | 116-118 | LCD2 |

Mapping from the serial stream (§2.2) to positions:
**position = 64·H + 32·(chip−1) + j**, where chip ∈ {1,2}, H is the trailing half bit and j = 0..31
is the data-bit index after the leading 0. So each digit uses 4 driver output lines. On
backplane-set H=0 those lines carry f,e,c,b. On H=1 they carry a,g,d plus one special icon on the 4th line.

Special segments (L796-811), set and cleared through `segset_hl`/`segres_hl` (L487-488):

| define | pos | seg byte.bit | driver/half/j | used |
|---|---|---|---|---|
| V_U | 0x43 | 8.3 | LCD1 H1 j3 | dpx ind (tx above rx) L11003-11008 |
| PHONE | 0x47 | 8.7 | LCD1 H1 j7 | remote display active L11010-11016 |
| CLOCK | 0x4B | 9.3 | LCD1 H1 j11 | draw/clear_clock_icon |
| COLON_UR | 0x4F | 9.7 | LCD1 H1 j15 | upper colons |
| V_D | 0x53 | 10.3 | LCD1 H1 j19 | dpx ind (tx below) |
| COLON_D | 0x57 | 10.7 | LCD1 H1 j23 | lower colon (after menu tag d9,d8) |
| PHONE_NO | 0x5B | 11.3 | LCD1 H1 j27 | CTCSS rx on |
| MAST | 0x5F | 11.7 | LCD1 H1 j31 | CTCSS tx on |
| COLON_UL | 0x63 | 12.3 | LCD2 H1 j3 | upper colons |
| BAR_L | 0x67 | 12.7 | LCD2 H1 j7 | never used |
| STAR | 0x6B | 13.3 | LCD2 H1 j11 | squelch forced |
| BAR_R | 0x6F | 13.7 | LCD2 H1 j15 | never used |
| KEY | 0x73 | 14.3 | LCD2 H1 j19 | selective mute |
| BOOK | 0x77 | 14.7 | LCD2 H1 j23 | GPS in fix |
| CAR_D | 0x7B | 15.3 | LCD2 H1 j27 | never used |
| CAR_U | 0x7F | 15.7 | LCD2 H1 j31 | scanner running |

Only `segments[0..15]` are sent to the CU53.

### 2.8 CU53 screen layout (from draw code; comment L985-991)

```
      u5 u4 u3 u2 u1 u0            upper row, 6 digits, aligned above d5..d0
d9 d8 d7 d6 d5 d4 d3 d2 d1 d0      lower row, 10 digits
```

- Upper row, normal view (`draw_upper_row` L11038-11106, starting at `CU53AN_segs_u_digit_5`):
  txpwr(1) vol(1) squelch(2) rssi(2), with the STAR icon for forced squelch and the UL/UR colons.
  Call timer is HH MM SS. Locator is 6 characters. Menu title is 6 characters (L16712).
- Lower row (`draw_lower_row` L11371-11444, starting at `CU53AN_segs_bottom_row` = d9):
  mem#(2) status(1) frequency(7) in the normal view. Other views put 10 characters here.

---------------------------------------------------------------------------

## 3. CU58AF (alphanumeric handset, I2C)

### 3.1 Pins

- **SCL = OUT2 bit 6**. `i2c_scl_low` writes OUT2=0x08 and `i2c_scl_high` writes OUT2=0x48 (L11975-11985).
  SCL is push-pull and never read back, so **clock stretching is not supported**.
- **SDA = PB3**, open-drain by direction switching (§1.2). `i2c_sda_low`/`i2c_sda_high` (L11959-11973)
  wrap pull_down/release_DCU in `di`/`ei`.
- **/INT = SIO A /CTS** (§1.3).
- `i2c_delay` (L11988-11999) is 3× `out [WD],a`, which also kicks the watchdog, plus `ret`: 43 T.
  Every primitive ends with a `jp i2c_delay`. SCL high time is about 88 T ≈ 11 µs at 8 MHz, and a
  bit takes roughly 250-300 T. That is far below 100 kHz.

### 3.2 Bit and byte level (L11944-12106)

- `i2c_getbit` (L11944): `in PB; and 8; sub 1` gives **carry = 1 if SDA is LOW**. The received bit is the
  **inverted line level**.
- `i2c_sendbit` (L12003): `sla c`, where the MSB goes into carry and the byte is sent **MSB first**. It calls
  `putbit`: SDA released if carry=1, pulled low if 0, so written data is **not inverted**. Then SCL high, then SCL low.
  SDA changes only while SCL is low.
- `i2c_recvbit` (L12010): SCL high, sample SDA while SCL is high, `rl c`, SCL low. Received bits arrive **MSB first**.
- `i2c_wrbyte` (L12020): 8×sendbit, then release SDA, SCL high, sample (ACK), SCL low. The result is
  carry=1 if SDA was low (ACK). The comment says the opposite ("carry clear if acknowledged", L12038).
  **No caller checks the ACK.** Missing devices do not stop the firmware.
- `i2c_rdbyte` (L12043): release SDA, then 8×recvbit. **The master generates no 9th (ACK/NACK) clock.**
- `i2c_start` (L12059): SDA↑, SCL↑, SDA↓ (START), SCL↓.
- `i2c_stop` (L12069): SCL↓, SDA↓, SCL↑, SDA↑ (STOP).
- `i2c_send(C=addr, B=data)` (L12082): `res 0,c` (write). START, wrbyte(addr), wrbyte(data), STOP.
  `i2c_send_a` is the same with B=A.
- `i2c_recv(C=addr)` (L12096): `set 0,c` (read). START, wrbyte(addr|1), rdbyte, STOP. It returns
  **A = bitwise NOT of the byte the slave put on SDA**.

**Emulator notes on reads:**
1. The slave drives 8 data bits. After the 8th falling SCL edge it must release SDA, since it
   expects the master to ACK or NACK.
2. `i2c_stop` then pulls SDA low while SCL is low and raises SCL. The slave sees this as a 9th
   clock with SDA=0, a master **ACK**. SDA then rises while SCL is still high, which is a **STOP
   during the 9th clock's high phase**, with no falling edge. The slave model must treat this as
   STOP and must not start driving the next byte on SDA.
3. Polarity: everything the firmware says about read values assumes it sees the inverted line
   level. Example: "colmask 1, 2 or 4" means a pressed key is 1 in firmware, so the key pulls the
   line to 0. This is consistent with PB3 reading SDA directly, not through an inverter, and with
   active-low PCF8574-type ports. Emulate PB3 = SDA line level, the wired-AND of the CPU drive and
   the slave drive, with a pull-up.

### 3.3 Device addresses (8-bit address byte, R/W bit is bit 0) (L726-760)

| define | addr byte (W/R) | 7-bit | role (from usage) | likely part **[DEVICE]** |
|---|---|---|---|---|
| CU58AF_COLBTN | 0x40 / 0x41 | 0x20 | keypad columns + buttons, bidirectional port | PCF8574, A=000 |
| CU58AF_LED | 0x44 / – | 0x22 | LED/backlight output port | PCF8574, A=010 |
| CU58AF_DTMF | 0x48 / – | 0x24 | DTMF generator ("pcf3312") | PCD3312-type |
| CU58AF_ROW | 0x4C / 0x4D | 0x26 | keypad rows, bidirectional port | PCF8574, A=110 |
| CU58AF_LCD | 0x70 / – | 0x38 | LCD driver (command set matches PCF8576) | PCF8576, SA0=0 |
| CU58AF_CTRL | 0x7C / – | 0x3E | audio control port | PCF8574A, A=110 |

### 3.4 LED port (0x44)

`display_cu58af` writes it with the raw `indicators` byte (L11914-11917). `cu58af_init` writes
`0x64` = LED_ON | KBRLIGHT | LCDLIGHT (L11755-11757). The bits (L745-750, L776-783):

| bit | LED define | indicators name | use |
|---|---|---|---|
| 0 | LED_SERV | BIT_SERV | squelch open |
| 1 | LED_CALL | BIT_CALL | call |
| 2 | LED_ON | BIT_ON | power |
| 3 | LED_ROAM | BIT_ROAM | TX LED |
| 4 | – | BIT_AVAIL | "not connected" |
| 5 | KBRLIGHT | BIT_KEYLIGHT | keypad backlight |
| 6 | LCDLIGHT | BIT_LCDLIGHT | LCD backlight |
| 7 | – | BIT_BRIGHT | never set |

1 means on. Writes are not inverted. **[DEVICE]** The output stage polarity is unknown.
`probe_cu58af` sets `indicators = 0` when a CU58AF is found (L11612-11613).

### 3.5 Keypad: COLBTN (0x40) and ROW (0x4C)

Idle configuration, written by `cu58af_init` and restored after every scan:
COLBTN ← 0xFF (all inputs/high) and ROW ← 0x00 (rows driven low) (L11763-11769, L11870-11878).

In **firmware polarity** (inverted wire), the COLBTN read value is (L737-741):

| bit | define | meaning (1 = active) | used? |
|---|---|---|---|
| 7 | OFFHOOK | handset off hook | **never read** |
| 6 | TANGENT | PTT on handset | `is_ptt_pressed` L4464-4467 |
| 5 | SPEAKER | speaker button | a 0→1 edge produces key 'K' → `step_audio_dst` (L11816-11824, L4552) |
| 4 | LDR | light sensor | **never read** |
| 3 | – | unnamed | see the quirk below |
| 2..0 | COL_MASK | keypad column lines | yes |

`keypad_cu58af` (L11808-11907):
1. `A = recv(COLBTN)`. `rising = (old ^ A) & A`. If `rising & SPEAKER`, set `key = 'K'`. Store `cu58af_buttons = A`.
2. If `(A & 7) == 0`, no column is active. Under `di`: if `lastdigit != -1` then `key = lastdigit` and
   `lastdigit = -1`. Clear `keydown` and `key_timer`. Return Z (no key). **This is how a key
   release is detected on the CU58AF.**
3. **Quirk (L11830-11834):** the code does `ld b,c` (the whole current byte, not the rising
   edges), then `A = (A&7) ^ b = A & 0xF8`, then `ret z`. **A key is decoded only if at least one of
   bits 3..7 of the COLBTN value is 1 in firmware polarity, meaning wire 0.** If all of hook, tangent,
   speaker, LDR and bit 3 read inactive (wire 1), a column press returns "no key". **[DEVICE]** The
   firmware seems to rely on a line that is normally low on the wire, possibly bit 3 or the LDR.
   An emulator should provide one. Wire COLBTN bit 3 = 0 is the least intrusive choice, because
   the firmware never interprets that bit otherwise.
4. The scan:
   - `send(ROW, 0xFF)` makes the rows inputs.
   - `send(COLBTN, 0xF8)` drives the columns low. This is `~COL_MASK`, so bits 3..7 stay high.
   - `R = recv(ROW)` gives the row mask in firmware polarity, with the pressed row = 1.
   - `send(COLBTN, 0xFF)`, `send(ROW, 0x00)`, then `recv(COLBTN)` to flush /INT.
5. `row` = index of the lowest set bit of R, 0..7. If R=0 then row=8 (the `scf` sentinel, L11886-11889).
   `col = (cu58af_buttons & 7) >> 1`, which gives 1→0, 2→1, 4→2. Multiple columns give 3→1, 5→2, 6→3, 7→3.
   `index = col + 3·row`. `key = keytbl_cu58af[index]`. The routine returns Z if key == 'Z' (no key).
   Otherwise it returns NZ with A = key (L11891-11907). Then `keypad` calls `cu_manipulated` and
   `blip` and does the same post-processing as the CU53 (L10183-10193).

`CU58AF_ROW_MASK` (0x7F) is defined but unused.

`keytbl_cu58af` (L13104-13109). Digits are binary 0-9. Columns col0..col2:

| row | col0 | col1 | col2 | index |
|---|---|---|---|---|
| 0 | 'Z' | 'Z' | 'B' | 0-2 |
| 1 | 4 | 2 | 1 | 3-5 |
| 2 | 5 | 6 | 3 | 6-8 |
| 3 | 7 | 8 | 9 | 9-11 |
| 4 | '*' | 0 | '#' | 12-14 |
| 5 | '-' | 'C' | 'E' | 15-17 |
| 6 | '+' | 'S' | 'R' | 18-20 |
| 7 | 'Z' | 'Z' | 'Z' | 21-23 |
| 8 (no row) | 'Z' | 'Z' | 'Z' | 24-26 |
| col=3 cases | index 27-39 | all 'Z' | | |

The row 1 order (4,2,1) and the row 2 order (5,6,3) are exactly as in the table.
**[DEVICE]** The physical wiring is unknown.

**/INT and debounce:** `cu_handler_cu58af` (L1816-1822) sets `keydown = 1` whenever the ESC
interrupt sees /INT low (RR0.CTS=1). It ignores /INT high. The 100 Hz tick sets KEYSIR at
keydown==10, about 90 ms later. `keypad_cu58af` runs from `dosir` with interrupts enabled, so
/INT edges caused by the scan (rows and columns changing direction) can re-arm `keydown=1`
while the scan is running. The final COLBTN read clears /INT. **[DEVICE]** The firmware expects
/INT to go low on any input change of the port devices and to clear on a read. That is PCF8574
behaviour.

### 3.6 Detection: `probe_cu58af` (L11599-11616)

```
cu58af_init; cu58af_init          ; flush /INT twice
if RR0.CTS == 1 (pin LOW)  -> CU53 (DA idles low)      ; cu_is_alfa stays 0
else          (pin HIGH)   -> CU58AF (/INT idles high) ; cu_is_alfa=1, indicators=0
```

- The firmware performs the full CU58AF init I2C traffic **before** it knows which CU is attached, even if a CU53 is fitted.
- Consequences: with no CU at all, the result depends on what /CTSA floats to. **[DEVICE]** A pull-up means "CU58AF".
  A CU53 key held at power-on makes DA high, so it is detected as a CU58AF.
- `cu_is_alfa` is never re-evaluated. There is no hot-plug support.

### 3.7 `cu58af_init` (L11753-11806): exact transactions

1. `W 0x44 : 0x64` (LEDs ON + both backlights)
2. `dtmf_code=0`, then `i2c_dtmf` (§3.9): `W 0x48 : 0x00`, then `W 0x7C : <ctrl>`. This also updates OUT0.INH.
3. `W 0x40 : 0xFF`
4. `W 0x4C : 0x00`
5. LCD: `START, 0x70, 0xCC, 0x80, 0xE0, 0xF8, 0x70, 0xFF ×40, STOP` (one transaction, 47 bytes)
   - 0xCC: C=1, mode set: enabled, 1/2 bias, 1:4 multiplex (4 backplanes) (comment L11778)
   - 0x80: C=1, load data pointer 0
   - 0xE0: C=1, device select 0
   - 0xF8: C=1, bank select 0
   - 0x70: C=0 (last command), blink off
   - then 40 data bytes of 0xFF, all segments on
6. `R 0x41`, `R 0x4D`, `R 0x41`, `R 0x4D` (flush /INT)

### 3.8 `display_cu58af` (L11912-11939)

1. `W 0x44 : indicators`
2. `START, 0x70, 0x80 (C=1, data pointer 0), 0x60 (C=0, device select 0), segments[0..39], STOP`

Bytes go out in increasing address order, each MSB first. **[DEVICE]** The mapping of data bits
to segment pins and backplanes is set by the PCF8576-type driver. In 1:4 mode each byte probably
fills 2 segment pins × 4 backplanes, MSB first. The firmware alone cannot confirm this.

### 3.9 DTMF generator (0x48) and CTRL port (0x7C) (L11629-11748)

`dtmf_cu58af` (L11642-11659) is used during TX (`handle_key_during_tx` L4629-4634). It converts the key to a code:

- digits 0-9 → `0x10 | d`
- `pcf3312_map` (L11630-11636): 'S'→0x1A, 'R'→0x1B, 'C'→0x1C, 'E'→0x1D, '*'→0x1E, '#'→0x1F
- any other key → the byte after the table, 0x3F ("1760 Hz from button")
- 0x10 is ORed into every code.

The result goes into `dtmf_code`, and DTMFSIR is set. `stop_dtmf_tone` sets `dtmf_code=0` and
DTMFSIR (L11661-11670). `dosir` calls `i2c_dtmf` only if `cu_is_alfa` (L2271-2276). DTMFSIR is also
set by every `set_vola` (L4793-4849).

`i2c_dtmf` / `i2c_dtmf_tone`:
- tone on (`dtmf_code != 0`): `W 0x7C : 0x36` (AUDIO|EAR|VOL_MIN|DTMFCTRL), then `W 0x48 : dtmf_code`.
- tone off: `W 0x48 : 0x00`, then `W 0x7C : ctrl`, where:
  - `volume == 0` → ctrl = `0x0D`. OUT0 is not touched in this case. B is 0 here, left over from the previous send.
  - otherwise v = min(volume−1, 7), vol bits = v<<5 (VOL_MASK 0xE0), and ctrl = vol | 0x0C | X, where
    - `audio_dst==0`: X=0x01 (NSPKRCTRL). OUT0.INH is **cleared** (radio loudspeaker on).
    - `audio_dst==1`: X=0x00. OUT0.INH is **set** (handset loudspeaker).
    - `audio_dst==2`: X=0x11 (EAR|NSPKR). OUT0.INH is set (earpiece).

CTRL bits (L752-760): 0x01 NSPKRCTRL, 0x02 DTMFCTRL, 0x04 AUDIOCTRL, 0x08 MICCTRL, 0x10 EARCTRL,
0xE0 volume. **[DEVICE]** The actual hardware effect is unknown. Only the written bytes are defined.

### 3.10 CU58AF glyphs and layout

`dpydig` alfa branch (L16514-16521) copies the 16-bit word `cu58af_font[ch]` to `[DE]` with 2×`ldi`.
The **low byte goes first**: `segments[2n]` = bits 7..0 and `segments[2n+1]` = bits 15..8. DE advances by 2.

Font bit diagram (L13131-13136):
```
  -----       3            top = 3, bottom = C
  |\|/|   6 2 E F B        6 UL vert, 2 UL diag '\', E upper centre, F UR diag '/', B UR vert
  -- --     5   A          5 mid-left, A mid-right
  |/|\|   4 0 1 D 9        4 LL vert, 0 LL diag '/', 1 lower centre, D LR diag '\', 9 LR vert
  -----       C
```
Bits 7 and 8 are not in the diagram, but most glyphs from 'H' onward and most punctuation have
them set (0x0180). **[DEVICE]** Their physical meaning is unknown. Font gaps 0x11-0x1F are 0xFFFF.

Full `cu58af_font` (index(char)=word):
```
00=9A59 01=4002 02=1C38 03=1E28 04=0E60 05=1668 06=1678 07=0A08 08=1E78 09=1E68
0A=0E78 0B=B078 0C=1058 0D=5A0A 0E=1478 0F=0478 10=1658 11..1F=FFFF
20(SP)=0000 !=918C "=41C0 #=17B0 $=57EA %=83C1 &=B18D '=01C0 (=A180 )=0185 *=E5A7 +=45A2
,=0181 -=05A0 .=0190 /=8181 0=9A59 1=4002 2=1C38 3=1E28 4=0E60 5=1668 6=1678 7=0A08
8=1E78 9=1E68 :=01D0 ;=4181 <=A180 ==15A0 >=0185 ?=818A @=5DD8
A=0E78 B=B078 C=1058 D=5A0A E=1478 F=0478 G=1658 H=0FF0 I=518A J=1B90 K=A1F0 L=11D0
M=8BD4 N=2BD4 O=1BD8 P=0DF8 Q=3BD8 R=2DF8 S=318C T=418A U=1BD0 V=81D1 W=2BD1 X=A185
Y=8186 Z=9189 [=0180 \=2184 ]=0180 ^=0180 _=1180 `=0184
a..z = same as A..Z   {=0180 |=4182 }=0180 ~=0188 7F=0180
```

Full `cu53an_font` (index=byte, for §2.7):
```
00-10: 5F 0C 7A 7C 2D 75 77 1C 7F 7D 3F 67 53 6E 73 33 57   11-1F: FF
SP=00 !=79 "=09 #=66 $=25 %=05 &=6A '=08 (=0C )=03 *=70 +=23 ,=02 -=20 .=02 /=2A
0-9 = as 00-09   :=50 ;=48 <=2C ==60 >=23 ?=3A @=7E
A=3F B=67 C=53 D=6E E=73 F=33 G=57 H=2F I=0C J=4E K=23 L=43 M=1F N=26 O=5F P=3B Q=3D
R=1B S=75 T=13 U=4F V=6F W=56 X=70 Y=6D Z=7A [=53 \=25 ]=5C ^=10 _=40 `=01
a=26 b=67 c=62 d=6E e=62 f=33 g=7D h=27 i=04 j=44 k=23 l=42 m=1F n=26 o=66 p=3B q=3D
r=22 s=75 t=63 u=46 v=6F w=56 x=70 y=2D z=7A {=62 |=02 }=64 ~=10 7F=00
```

Character cells (L974-982). Each cell is one 16-bit word n at `segments + 2n`:

| words | use |
|---|---|
| 0 | never written by the firmware; 0 after the BSS clear |
| 1 | high byte = `segments[3]` holds icons: bit1 EXP (clock icon, L10949-10966), bit2 CAR (scanner), bit3 PHONE (defined, unused), bit4 ARROW0 (dpx: tx below), bit5 ARROW1 (dpx: tx above), bit6 ARROW2 and bit7 ARROW3 (unused). Defines are `24+k` → byte 3 bit k (L762-769) |
| 2..9 | upper row, 8 chars u7..u0 (`CU58AF_segs_u_digit_7` = word 2) |
| 10 | never written |
| 11..19 | lower row, 9 chars d8..d0 (`CU58AF_segs_bottom_row` = word 11) |

Upper row content in the normal view: txpwr(1) vol(1) audio_dst('>'=1, '<'=2, ' ') squelch(2)
'*'/' ' rssi(2) (L11062-11106). The lower row is mem#(2) status(1) freq(6), using the
`yucko_alfa_draw_long_6_only` flag (L11424-11425, L16361). Text views are limited to 9
characters (L11303-11310, L11331-11336). The alfa display has no colon or CTCSS/GPS icons (L10851-10855).

---------------------------------------------------------------------------

## 4. Scheduling and startup

- `nosir` = 0xFF from the BSS init (L1170) until `cu_now_known` clears it (L11595-11596). While it is non-zero, the
  softint dispatcher skips `dosir` (L2209-2211), so there is **no keypad read, display update or DTMF I2C**.
  `nosir` is also set temporarily during modem TX (L9305/L9319) and CW (L15978/L15995).
- `dosir` (L2254-2279) runs at soft level from the 100 Hz tick, with interrupts enabled, in this order:
  KEYSIR → `keypad`, then DPYSIR → `display` (CU53 frame or CU58AF I2C), then DTMFSIR → `i2c_dtmf` (alfa only).
  `redraw` sets DPYSIR (L10712-10726). Other code sets it too, for example the squelch open/close handlers (L2704, L2765) and hook changes (L2055).

Boot order relevant to CUs:
1. L1054-1073: OUT0/OUT1, then **OUT2=0x08**.
2. L1091-1112: piob_mode=0x2E, PIO B data=0, PIO A/B init (B mask 0x3E, so SDA is released). SIO A/B init (CTS ESC interrupt enabled).
3. L1139-1170: BSS clear (segments, indicators, cu_is_alfa, keydown all 0). piob_mode=0x2E, dark=0xFF, nosir=0xFF.
4. L1519-1522: `cu_handler = cu_handler_unknown`. `load_nvdata`, which restores volume and audio_dst.
5. L1544-1557: a 2×256×256 delay loop "Give time for LCD to reset itself". Each iteration is ~43 T + waits, so the loop takes about 0.7 s at 8 MHz.
6. L1590-1596: IM2, `jp main`. `main` (L3247): `ei`, then **`probe_cu58af`** (L3250). The two `cu58af_init` calls run here from the
   main line with interrupts on. ESC interrupts during this time go to `cu_handler_unknown`.
7. ccir/dtmf decoder init, modem enable, `set_vola` (sets DTMFSIR, still blocked), menu/LPF init, and so on.
8. **`cu_now_known`** (L3261, L11586-11597): installs `cu_handler_cu53` or `cu_handler_cu58af` and sets `nosir = 0`.
9. L3262-3266: wait until `is_key_down` (keydown==0) and PTT are released. `light_on_led` sets the ON bit.
   Two `redraw` calls then produce the first real display frame. On a CU58AF, the display is all-on from init until that frame.
