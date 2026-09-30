; sdasz80 source, built by cpp + tools/asmpp.py + sdasz80 (notes/toolchain.md).
; Converted from the as80 source by tools/as80tosdas.py.
; HI/LO, ALIGN/FILL, ASSERT_*: firmware/asm.h
#include "asm.h"

/* routines replaced by C (c/*.c); C symbols carry a leading underscore */
#define squelch			_squelch
#define once_per_second		_once_per_second
#define once_per_minute		_once_per_minute
#define once_per_hour		_once_per_hour
#define battcheck		_battcheck
#define draw_upper_row		_draw_upper_row
#define draw_lower_row		_draw_lower_row
#define changed_frequency_duplex_okay		_changed_frequency_duplex_okay
/* c/menu.c (bank 1): the stub targets and the DYN/RST record routines */
#define init_menu		_init_menu
#define update_gpio12_foo		_update_gpio12_foo
#define toggle_or_position_menu		_toggle_or_position_menu
#define menu_enter_or_walk		_menu_enter_or_walk
#define menu_defval_or_exec		_menu_defval_or_exec
#define menu_up_value		_menu_up_value
#define menu_dn_value		_menu_dn_value
#define menu_next_group		_menu_next_group
#define menu_prev		_menu_prev
#define decoder_hist_rewind		_decoder_hist_rewind
#define leaved_setup		_leaved_setup
#define draw_menu_title		_draw_menu_title
#define draw_menu_lower_row		_draw_menu_lower_row
#define menu_rfc_change		_menu_rfc_change
#define menu_sql_change		_menu_sql_change
#define menu_sqB_change		_menu_sqB_change
#define draw_rfc_dpy		_draw_rfc_dpy
#define draw_sql_dpy		_draw_sql_dpy
#define draw_sqB_dpy		_draw_sqB_dpy
#define ccir_hist_walk		_ccir_hist_walk
#define dtmf_hist_walk		_dtmf_hist_walk
#define fsk_hist_walk		_fsk_hist_walk
#define gps_hist_walk		_gps_hist_walk
#define draw_ccir_hist		_draw_ccir_hist
#define draw_dtmf_hist		_draw_dtmf_hist
#define draw_fsk_hist		_draw_fsk_hist
#define draw_gps_hist		_draw_gps_hist
#define all_config_get		_all_config_get
#define all_config_send		_all_config_send
#define disaster		_disaster
#define wipe_memories		_wipe_memories
#define sane_defaults		_sane_defaults
#define wipe_rfctab		_wipe_rfctab
#define do_reboot		_do_reboot
/* c/scan.c */
#define scanner_start		_scanner_start
#define scanner_stop		_scanner_stop
#define toggle_scan_mask		_toggle_scan_mask
/* c/keys.c: key handlers, memories, VIP list */
#define execute			_execute
#define backspace		_backspace
/* c/ptt.c: the PTT/TX flow */
#define tx_error		_tx_error
/* c/display.c: the indicators */
#define draw_dpx_ind		_draw_dpx_ind
#define draw_ctcss_and_mute_and_gps_ind	_draw_ctcss_and_mute_and_gps_ind
/* c/freq.c: the RFC table fill */
#define rfc_fill_blanks		_rfc_fill_blanks

; XXX build_scan_mask/toggle_scan_mask - empty slices/memblocks ? select s/m

; XXX ctcss off before aprs send
; XXX
; repeater timers, 65535 ~ eternity ?
;
; second ROM socket:
; 0x80xx /RD
;    dtmf decoder status (3 LSbits are don't care) expected in databus

#define ALLOW_6_25_kHz

;----------------------------------------------------------------------

#define DATE    "24.09.2018"
#define VERSION "3_Z"
#define PATCHED "ALs"

;-------------
;
;  For R58 logics P8N/P8E and A8N
;  RF decks:
;   RB58  64/45.0    S8B
;   RC58  64/21.4    S8C
;   RD58 128/86.5125 S8D
;
;   RB660 synthesizer works as syncrd=s8c, (logics swapped to P8x/A8N)
;   some changes needed:
;   tpc-line (add resistor (only if power settings do not work))
;   on txvco (+ ->|- VBUFF ????? only during tuneup ????),
;   and txon-line (remove one inverter from circuit).
;
;   RB58VY or RB580 do NOT work like RB660.
;
;-------------
;;
;; 2.0 000421 Too many changes here and there to mention specifically.
;; 2.1 000507 TX does not affect reception if Func != Std.
;;            1kHz off rx_freq dpy (because of + and - of if_freq) fixed.
;; 2.2 000508 Scanner things. Works after 42 nanosec of testing.
;; 2.3 000510 Ghost digit after bitbanged dtmf fixed.
;;            Perm rejects honored.
;;            It already was fixed in v1.7. ugh.
;;            Fix rejecting a memory if scanning (vip_freq, not the mem index)
;;            CU58AF fix. Was broken from 2.0.
;;            Display during opened squelch.
;; 2.4 000513 Tail-less squelch with fully quieting signals.
;;            Tail timer was not always properly rewound.
;; 2.5 000514 Shorter "quick press" of "monitor" thingy.
;;            RFC wipe and blank-filler in setup. No default RFC (of 85 if 0).
;; 2.6 000514 Repeater stuff first cuts.
;; 2.7 000515 Second cuts. Blips etc. Just placeholders really.
;;            Setup "tabs" show ??? if value out-of-range.
;;            SqL BIG display similar like SqL display.
;;            Pathetic troubles with OUT0 cleanup.
;;            Why on earth was AUDIOC on during CCIR xmit ? Local noise
;;            audible when signalling in duplex mode !
;;            Repeater tx_on left SERV & audio open with certain conditions.
;;            Scanner fouled slices badly in sort.
;; 2.8 000715 Stuff for repeater CW.
;;            Wrong check of [txon] in DTMF-keypad, [pttdn] instead now.
;;            Cumbersome alpha input in menu.
;; 3.0 000718 DTMF * repeater open. repeater opens when /PTT released.
;;            Open squelch required to accept 1750 Hz or DTMF *.
;;            Check for 0xC0 Call packet (will be other formats)
;;            #9 closes repeater.
;;            ## "gives a report". Report scaling needs more work.
;; 3.1 000718 UR_59 with 5x if tailless sqclose, 4x if tail.
;;            In basic display, 99-rssi instead of 99-txpwr, if rptr.
;; 3.2 000723 Additional A/D inputs, first cuts.
;; 3.3 000723 PA HOT and ANT BAD alert messages from repeater, blip-time.
;;            Sense of AF relaying wrt /MIC selectable.
;; 3.4 000725 Tone Access bypass flag for repeater.
;;            powerdown keeps power relay on, if not Std Function.
;; 3.5 000730 FSK pager receiver wrong in versions 3.0 upto including 3.4.
;; 3.6 000805 Toggling scanmask bits leaves channel immediately.
;;            Carrier access to repeater gave excess ID messages.
;;            Scanner pushed all spikes into "vip list", now only those
;;            which really open squelch.
;;            single-digit+PTT indirect from shortcut 0...9.
;;            Repeater MIC selection might have failed until local PTT used.
;;            Remote config first cuts.
;;            Squelch lights up handset, just like local manipulation.
;;            Separate Greet, During and Bye repeater cwid messages.
;;            Backspace in menu is now really backspace, basic dpy
;;            retains "clear all" CL effect.
;; 3.7 000807 Secretive config passwd rearranged, hide it and only it
;;            from remote queries.
;;            Requirement for repeater access, initial carrier less than
;;            10 seconds, more than 1/4 second. Else stays idle.
;;            Accesstone for "closing" repeater waits tone to end,
;;            then tx and open audio.
;;            Accept DisplayConfig packet only when own cfg_remote_id is set.
;;            Repeater access methods.
;; 3.8 000808 Remote access of CFG_DYN values. Yucko stuff, as always.
;;            Squelch tightening and txpower increase as DTMF commands.
;;            Display phone icon when setup has remote data visible.
;; 3.9 000810 Config packets lengthened.
;;            Some new packets added.
;;            Remote access also to set values, not only get.
;; 3.A 000811 Cursor _ for digbuf.
;;            First erase one chr, then all if CL kept down.
;;            Separate, slightly slower scroll of letter input.
;;            Fixed bug with 8 characters of remote config sent.
;;            Empty remote record by trying to set 9 or more chrs.
;;            String records have _ padding (so leading spaces stand out).
;;            volume/audio_dst changed positions, silly debug.
;;            slight delay into CU53 keypad. Fixed probs reported by OH2BGN.
;; 3.B 001029 SPEECH ja SC:AutoSC
;; 3.C 001030 Fixes to try to solve stuck FSK receive.
;;            Fixes to try to solve nvram foulup.
;;            un-SERV at txon (audio/led/status-pin)
;;            ad_tp4 aka TEMP slope is negative for increasing temperature.
;;            autoqsy - generalization of AutoSC
;;            save_nvdata after FSK configuration.
;;            continuous redraw when PTT down in menu - status displays
;; 3.D 001110 keyclick pitch table
;; 3.E 001121 UnReject timeout.
;;            Quick setup positioning with n(n(n)) ENT.
;;            dtmf 1,2 alarm strings in setup, wrong nvram addresses.
;; 3.F 001124 SC:nodAtA
;; 3.F 010213 "ILL" 4 more out-of-band tx spots.
;; 3.F 010216 PH:LO Inj above/below for 220 things
;; 3.F 010616 -DTCXO=<kHz> compilation switch
;; 3.F 010703 PTT in repeater mode mimics access (simple linking method)
;;            Separate blip for normal use and link use.
;;            Separate cw pitches for above blips.
;; 3.G 011003 CTCSS tones were wrong. 
;; 3.H 011220 6.25kHz step tried.
;; 3.J 020409 If id_bye == "", tx unnecessary.
;;            PA_Hot and ant_bad messages as strings in setup,
;;              no fixed usage (though very suggestive names).
;;            Repeater USEcnt open counter.
;;            Repeater USEhrS transmitter hours.
;;            Repeater blip is pre-empted by carrier.
;;            Repeater (re-)enters open state when /LOCAL pin rises,
;;             useful for triggering cwid externally.
;;            Repeater gives better S-reports (setup S1rSSi, S9rSSi),
;;             rssi below s1rSSi = 1, rssi above S9rSSi = 9.
;;            6.25kHz step hidden.
;;            Power relay is toggled with delay when battery dries,
;;             relay stays in On position with bench supply,
;;             Lo_batt shown in LCD,
;;             If voltage rises back over 10 volts,
;;             lo_batt ends and normal operation resumes.
;;            Powering up powerbutton in off-position, the livelock removed.
;;            CCIR CALL also rings bell.
;;            FSK modem is re-enabled every hour (unstuck).
;;            Repeater CTCSS access method, input EXIN2, polarity selectable
;;             with rP:CtCPol = POS/nEG, configured with rP:ACCESS = CtCSS.
;;            CTCSS freq and channel step are kept separately in memories.
;;            CTCSS tx indicator is the little mast icon.
;;            GE:onHook/oFFHook scripts. REMEMBER to clear them from setup.
;;            Command input fixed to understand either 0xC or 'C' for CL.
;;            Little button just aborts scanner, if scanning.
;;        XXX halfway with mute operation.
;;            onHook-script can execute 'T' -> selkun Taakse. any key,
;;             hook or alarm bell clears the mute (no re-triggers here).
;;            Mute (Selective) indicator is the little key icon.
;;            Repeater CCIR commands like DTMF commands, using prefix
;;             from rP:ccirPF, for example when prefix is "1234"
;;             ccir 1234 = dtmf ##, 12340 = #0, 12341 = #1 and 12349 = #9.
;;             multidigit commands are not (yet) understood.
;;            Temporary rejects now max 20, parameter rJ:n_tEmP can trim
;;             the lifo length into 1...20 (0=20)
;;            APRS transmit aux ptt from /LOCAL. Quick qsy into other freq,
;;             tx while /LOCAL is low and qsy back to original frequency.
;;             Settings are GE:APrS=off/on and tr:trAPrS=kHz
;;            APRS /PTT sense was wrong.
;;            Scanner 'carrier wait' lingering parameters b*:SCtAIL
;;             now presented in seconds.
;;            Repeater 'hog' message now configureable.
;;            Scanner b*:SCLIStEn value 255 means now 'infinite patience'.
;;
;;            Setup checklist:
;;                 b*:SCtAIL   unit is now seconds
;;                 GE:onHoo    clear this
;;                 GE:oFFHoo   clear this
;;
;; 3.L 020523 Sq:BonGo Hz for local blip from closing squelch.
;;            Key blip and serv blip setting 0 -> no corresponding blip.
;;            dF:EntLen safety for entering setup.
;;     020527 Memory uses the corresponding b?-band, setting band_xxx
;;             variables ok.
;;            Also CTCSS updates in setup use the mem- or the vfo-variable
;;             as needed.
;;     AL3    EXAL changeable from keypad, fsk, dtmf and ccir.
;;             GE:GPio1 has the control on/off state;
;;             io:ctl 1c and io:ctl 1d are command prefixes to set it
;;             from ccir and dtmf, respectively.
;;            warm boot thru setup (dF:reboot).
;;            repeater suspension (rP:SUSP*).
;;            display "CALL" runs also a HH:MM:SS counter.
;;            rP:HidE_9 pass/hide to block abuse of #9 command.
;;     AL4    repeater_TBLIP cSEC counter.
;; 3.N 020703 Hide9 bug fixed (when hidden, #9 tightened squelch instead).
;;            Longstanding bug in piob_mode fixed, overwritten by _bss bzero.
;;     030109 rP:SInPLE on/oFF flag for wierd simplex mode of repeater.
;;              this disables rx during repeater tx.
;; 3.P 030129 quick/slow qsy in scanner.
;;     030129 oops, forgot defaults of the new qsy-parameters.
;;            autoreject.
;;            repeater sitter's special.
;;     030131 Started NMEA input stuff.
;;     030208 GP:GPSxxx - more crap into setup. Delightful NMEA parsing.
;;            GE:PttApr - send callsign and lat/lon when ptt released.
;;            show received callsign in display-data buffer.
;;            simple form of APRS rx into MBUS.
;;            MBUS message munged into TNC-emulating format.
;;            lat/lon nonvolatile. remote_display_buffer outside menu.
;;      BEF   all 10 characters in remote_display_buffer set from aprs.
;;            MBUS aprs strings end now in EOS, not 0. Checking for 'W' West,
;;            in NMEA, not East because manually entered E is 0xE.
;;            feedback/remote buffer EOS shown as blanks
;;            locator display from aprs packet.
;;      BEH   own locator to GP:GridSq
;; 3.Q 030210 South/West locator fixes.
;; 3.R 030212 mbus aprs line: remove blanks from callsigns.
;;      ALb   sio-a RX_ENB was missing ! humph. Also CRLF to the APRS-mbus.
;;      ALc   /RXON as GPio2. GPctlc ja GPctld renamed. 0/1 set exal,
;;            2/3 set /RXON. one of gpio-blips if EXAL or /RXON are set.
;;            R-ack of GPIO set/reset.
;;            ctcss detect moved into squelch, from specialcased access method.
;;             ctcss overrides squelch levels but drag timers are active.
;;      ALd   GPS checksum bug (compared agaist wrong register, not E reg).
;;      ALF   using decimal minutes, not seconds in MPRS. names changed _m_prs.
;;            mbus mprs format selection (tnc/kiss/3rdparty/logger)
;;            symbol and ssid in mprs, reserved bits masked.
;;            gps speed as km/h. AprCut "smart" squelch.
;;            waypoint uploads with $GPWPL.
;; 3.T 030222 All Config Send/Get MBUS stuff.
;;            Magellan waypoint upload added.
;;      AL3   ctcss-squelch is now AND with regular SQL.
;;            suspension "QRT" message and unsuspension id.
;;      AL4   MPRS SSID in wrong bits.
;; 3.U 030226 lakki -edition. CTCSS detector input is now TMR0 and
;;            EXAL, EXIN2, /RXON are gpio1, gpio2a and gpio2b resp.
;;            gpio1 and 2 have separate command prefixes.
;;            NOTE: TMR0 must be disconnected from old circuit before
;;            detector wire is soldered into it.
;;            ctcss_output_when valinnat off/transmitter/signal.
;;      AL1   distance mess.
;;      AL2   PH:SErCtA/B generic 16 bit dat/clk/strobe (SD CLK and RAS/TPS).
;;            FX465 CTCSS loaded rx and tx modes from SD CLK and TPS.
;;             But in duplex functions, FX465 is rx-only.
;;            Repeater GPio blip Hz.
;;      AL3   musical notes for blips. rP:BLIPS = Norse/Notes.
;;            4 different rssi-bongos, rssi A/B/C and corresponding strings.
;;      AL4   rP:BrSSiS off/on - send rssi bongos. #5 dtmf toggle.
;;      AL5   MPRS symbol 15 == [SSID] == take APRS symbol from SSID.
;;            If MPRS symbol is 15 and SSID is 0, resulting APRS symbol is // (Dot).
;;            band-autorejects were BYTEs, not on/off TABs as they should be.
;;      AL6   GPio12 and serctls are updated only when the vars change in setup,
;;             or from commands from ccir/dtmf decoders. distance_bearing.
;;      AL7   pwm-dtmf fix, sin-table had too small and too large values,
;;            0+0 = 65536 counts really and also 65+65 = 130 slots which
;;             overflow the constant time loop (130 slots). Interference
;;             results.
;;      AL8   mbus logger timeformat ascii. distance calc had ahl reload bug.
;;      AL9   Arghawa. sio-A tx and txint enables.
;;      ALA   Arghawargharrr, gps_upload and nmea cksum fouled DE ptr.
;;      ALB   8-character locators in setup. bootup gpio update.
;; 3.U  ALD   waypoint length restricted NOT YET DONE.
;;      ALE   GPRMC time might have ".NNN" decimal seconds, skip those.
;;            cu53 font slightly touched.
;;      ALF   step channel up - new frequency rounded up, first, to handle
;;             xxx187 + 12 = xxx199 and later xxx200 but step is still wrong.
;;             Also trying to fix down-stepping from slice start.
;;            NMEA: GridSq calculation was forgotten, if menu was visible.
;;            CTCSS squelch is disabled when CTCSS Hz is 0 meaning OFF.
;;            Mast shows nonzero ctcss encode, Crossed Handset shows decode.
;;            One T-state out from ADC routine, XXX can do better.
;;            Deviation control in setup.
;;      ALG   repeater sitter's special bug fixed.
;; 3.Y 030504 signalling deviation vs. speech deviation tested.
;;      AL1   bus-rf relay.
;;            repeater mprs id.
;;      AL3   id_bye "" but still bye mprs.
;;      AL4   spontaneous mprs.
;;      AL5   fx465 in rom socket.
;;      AL6   ax25 pwm generation for aprs report.
;;      AL7   bug fixed, nothing was emitted, missing exx.
;;      AL8   bitstuff bug.
;;      AL9   ax25 phincs into setup for trial and error correction
;;      ALA   ax25 test tones.
;;      ALb   adjusting ax25 pwm loop, only p8e this time.
;;      ALC   digipeater selections for ax25
;;      ALd   adjusting ax25 pwm loop, only p8e, one T-time more.
;;      ALE   longitude bug in aprs packet (ascify bug, what else)
;;      ALF   removed the ax.25 tone finetunes.
;;      ALG   trying to make sense of the P8E ax.25 timing problem.
;;            replacing some double-M1 instructions with benign ones,
;;            taking into account some other prefixes.
;;            It worked. hooray.
;;      ALH   tdELAY and PAdbit. *** BSS REARRANGED, WATCH OUT ***
;;      ALJ   fsk silencer.
;;            shaved off some fsk sync bits, was 40, now 24 syncbits.
;;      ALL   stretching squelch opening to end of muted packet, if reqd.
;;      ALn   Episode 'salpabugi'. ADC input optimized, interval doubled.
;;      ALP   'salpabugi' continues, interval doubled again.
;;            A/D reorganized, reading RSSI/SQL often and others not.
;;            Snipped few T-times out from systick with jr/jp honing.
;;            Also just minor optim of nmea collect/checksum.
;;      ALq   from lakki, behaviour of beep in the closing state in repeater.
;;      ALr   MIC-E encoding option.
;;      ALt   MIC-E encoding option - forgotten parameter Pr:StAtuS.
;;      ALt   MIC-E encoding option - custom messages.
;;      ALu   misleading parameter tdELAy re-baptised as PLLdEL.
;;      ALy   more selections to aprs digipeater list.
;;            APdiGo 'other' for one variable digipeater call.
;;            How about RFC dac to generate ctcss ? Had to drop i8253
;;            code to fit into 32kB.
;;            two large tables deleted, now calculating ctcss divisor
;;            and ctcss phinc. i8253-ctcss is back.
;;            spontaneous mprs/aprs is deferred until tx goes off,
;;             in repeater/slave functions too.
;;   3Y AbZ   CtCGen - select one of many possible methods of ctcss tx.
;;            CtGAin - adjust the amplitude of tone in rfc dac method.
;;            CtHAnG - hang time without ctcss at the end of over.
;;   3Y AcZ   rfc-dac-ctcss AC is centered around the real rfc adjustment DC,
;;             so there is little if any effect to duplex receiver.
;;   3Y AdZ   GPULSc and GPULSd commands for pulsing EXAL.
;;   3Y AEZ   GPS initialization.
;;   3Z AL0   GPS initialization bug fix 1. SiRF is the name. (GPSCFG)
;;   3Z AL1   GPS initialization bug fix 2. 38k4 it is.
;;   3Z AL2   GPS initialization bug fix 3. timing trbl.
;;   3Z AL4   GPS initialization bug fix 4. goddamit. do it by counting cycles.
;;   3Z AL6   GPS initialization bug fix 6. BRK is slugglish with X32 CLK.
;;   3Z AL7   SiRF nmea-sentences, selection of generic and tailored.
;;   3Z AL8   Aisin-Seiki GPS. GPSCFG=AiSin
;;            APRS tab_ax25_digi indirection was wrong.
;;            MIC-E position encoding was wrong.
;;   3Z AL9   MIC-E encoding fixed again, previous fix in a wrong place.
;;   3Z ALA   Aisin-Seiki checksum, some reordering in process_CACA().
;;            gps_reported_speed. XXX not used yet
;;   3Z ALB   rfc-dac ctcss-method optimised. changing PIOA interrupt vector.
;;             No overhead of checking a variable in every pioa_int().
;;            some code shuffled around, hard to stay inside 32kB.
;;            AX25 tone debug was removed to conserve space.
;;            tidy up ccir_from_digbuf.
;;   3Z ALC   pttdn cleanups, preparing for for ax.25 rx.
;;            cleanup escalation in cu58af_keypad().
;;            lowest parts of ax.25 rx added. No real functionality yet.
;;            ax.25 crc calculation tidyed.
;;            aligned tables moved around to squeeze out slack.
;;            rummaged in interrupt handlers. hopefully mostly positively.
;;            No more bleep when serial input overruns.
;;   3Z ALd   gps_configure again after one second.
;;            Book shows up on display for 5 seconds whenever gps "in fix".
;;   3Z ALF   RP:AF_Src new option, "thru" when /MIC does not control it.
;;   3Z ALG   ctcss decoder with new multiboard lpf+slicer
;;            FX614 stuff jettisoned, tight fit.
;;   3Z ALh   sinetab gain calculations for dtmf, ctcss and ax.25
;;   3Z ALi   accumulator change for dsp ctcss, more selective perhaps ?
;;            rfcdac encoder average rounded slightly more correctly.
;;            a2i rationalized. a2i_word fixed (clamp at FFFF not FF).
;;   3Z ALJ   space (time?) saving cleanups.
;;            CSE/SPD to ascii APRS report, if speed over 1 knots.
;;            many CP 1; CP 2; etc optimised with successive DEC A,
;;            also other nano-optimisations here and there.
;;   3Z ALn   ctcss_output_when option CUSTOM (signal in plus blips)
;;   3Z ALo   repeater_sig is peak rssi during an over
;;            temperature window, hot or cold
;;            temperature and swr alerts after ID, not after every over
;;   3Z ALp   no tx off/on glitch before id bye, if repeater_TCLS is zero.
;;            fix for squelch noise during an id, if over ends during it.
;;            sql_bi works with RSSI, not with SQL
;;   3Z ALq   ctcss forced changed offset to 0.5 Hz lower
;;	      ToDo: later to all ctcss  -OH1E
;;   3Z ALr   Added new mode to GPS config, 9600Std what means a unstandard
;;	      NMEA working at 9600baud -OH1E
;;	      Disable TX-CTCSS when end of ptt, send other stuff (aprs etc) 
;;	      without CTCSS tones. with cleaner signal -OH1E
;;	      Changed behavior of spontanius packet send, only when sql is close
;;	      to avoid duplicate transmit traffic in a working frequency. -OH1E
;;	      ToDo: only when repeater shift is on..
;;   3Z ALs   Added proper CTCSS tx.
;----------------------------------------------------------------------

#if P8x + L8M != 1
#error Compilation must choose -DP8x or -DL8M cpu card
#endif

;  Looks like P8E works all right with (unnecessary) P8N saves/restores.

#ifdef P8x
#define P8N
#define P8E
#endif

#ifdef L8M
#error Sorry, L8M missing in action
#endif
;----------------------------------------------------------------------

#ifndef TCXO
#define TCXO 12800 /* kHz as all frequencies here */
#endif

;----------------------------------------------------------------------
; selectable channel steps (logical, not physical)

#define STEP_25 0
#define STEP_20 1
#define STEP_15 2
#define STEP_12 3
#define STEP_10 4
#define STEP_6  5

; RF decks

#define S8D 0
#define S8C 1
#define S8B 2

; datatypes in setup, note the ugliness of cSEC

#define CFG_BYTE    1
#define CFG_WORD    2
#define CFG_FREQ    3
#define CFG_TAB     4
#define CFG_DYN     5
#define CFG_RST     6
#define CFG_STR     7
#define CFG_DPX     8 /* like freq but signed */
#define CFG_cSEC    9 /* like byte but fake 0 at end to show as millisec */
#define CFG_EXE    10

; setup strings are padded with this, 0x00 is valid and means '0'

#define EOS 0xFF
;----------------------------------------------------------------------
;
;  duplex states

#define DPX_SIMPLEX 0
#define DPX_DUPLEX  1
#define DPX_REVERSE 2
#define DPX_SPLIT   3

;----------------------------------------------------------------------
;
;	Convenience macros
;
#define SIZE_FREQ 3
#define SIZE_STR  8

#define BUF(n) .ds n
#define BYTE   .ds 1
#define WORD   .ds 2
#define FREQ   .ds SIZE_FREQ
#define STRING .ds SIZE_STR

#define sla4 sla a @ sla a @ sla a @ sla a

#define imm_ahl(I) ld hl, #(I) % 65536 @ ld a, #(I) / 65536

#define load_ahl(A) ld hl, (A) @ ld a, ((A) + 2)
#define save_ahl(A) ld (A), hl @ ld ((A) + 2), a
#define load_abc(A) ld bc, (A) @ ld a, ((A) + 2)
#define save_abc(A) ld (A), bc @ ld ((A) + 2), a

#define load_ahl_ix_0 ld l, (ix+0) @ ld h, (ix+1) @ ld a, (ix+2)
#define load_cde_ix_0 ld e, (ix+0) @ ld d, (ix+1) @ ld c, (ix+2)
#define load_ahl_ix_3 ld l, (ix+3) @ ld h, (ix+4) @ ld a, (ix+5)
#define load_cde_ix_3 ld e, (ix+3) @ ld d, (ix+4) @ ld c, (ix+5)

#define save_ahl_ix_0 ld (ix+0), l @ ld (ix+1), h @ ld (ix+2), a
#define save_ahl_ix_3 ld (ix+3), l @ ld (ix+4), h @ ld (ix+5), a

#define sub_ahl_immde(I) ld de, #(I) % 65536 @ and a @ sbc hl, de @ sbc a, #(I) / 65536

#define add_ahl_de(A) ld de, (A) @ add hl, de @ ld de, ((A) + 2) @ adc a, e @
#define sub_ahl_de(A) ld de, (A) @ and a @ sbc hl, de @ ld de, ((A) + 2) @ sbc a, e @

; from hl to de, bc also mashed

#define ldi_1(_dst) ld de, #_dst @ ldi
#define ldi_2(_dst) ld de, #_dst @ ldi @ ldi
#define ldi_3(_dst) ld de, #_dst @ ldi @ ldi @ ldi
#define ldi_6(_dst) ld de, #_dst @ ldi @ ldi @ ldi @ ldi @ ldi @ ldi
#define ldi_7(_dst) ld de, #_dst @ ldi @ ldi @ ldi @ ldi @ ldi @ ldi @ ldi

#define ldi_10(_dst) ld de, #_dst @ ldi @ ldi @ ldi @ ldi @ ldi @ ldi @ ldi @ ldi @ ldi @ ldi @

#define segset_hl(_s) ld hl, #segments + ((_s) / 8) @ set (_s) % 8, (hl)
#define segres_hl(_s) ld hl, #segments + ((_s) / 8) @ res (_s) % 8, (hl)

;----------------------------------------------------------------------
;
;	I/O map
;
#define PIO   0x00
#define SIO   0x10
#define TMR   0x20
#define DA0   0x30
#define DA1   0x40
#define AD    0x50
#define OUT0  0x60
#define OUT1  0x70
#define OUT2  0x80
#define WD    0x90
#define MDM   0xA0

#define CSMEM 0xB0	/* P8E SMEM flipflop  */

#define ADATA 0
#define BDATA 1
#define ACTRL 2
#define BCTRL 3

#define TMRCTRL 3

#define AD_RSSI  (AD + 0)
#define AD_SQL   (AD + 1)
#define AD_BATT  (AD + 2)
#define AD_TPC   (AD + 3)
#define AD_FPM   (AD + 4)
#define AD_RPM   (AD + 5)
#define AD_TP4   (AD + 6)
#define AD_IN7   (AD + 7)

#define DA_RFC   DA0
#define DA_TXPWR DA1

;----------------------------------------------------------------------
;
;	FX429
;
#define MDMDATA	2
#define MDMCTRL 3

#define MDM_TXENB	0x01
#define MDM_TXPAR	0x02
#define MDM_RXENB	0x04
#define MDM_RXFMT	0x08
#define MDM_TIMER	0xF0

#define MDM_XXX		0x00	/* Nothing enabled */

#define MDM_RXRDY	0x01
#define MDM_RXTRUE	0x02
#define MDM_DCD		0x04
#define MDM_TXRDY	0x08
#define MDM_TXIDL	0x10
#define MDM_TMRINT	0x20
#define MDM_SYNC	0x40
#define MDM_SYNT	0x80

;----------------------------------------------------------------------
;
;	8254 timer
;

#define TMR_0		0x00
#define TMR_1		0x40
#define TMR_2		0x80
#define TMR_INTTC	0x00	/* mode 0, intr on terminal cnt */
#define TMR_ONESHOT	0x02	/* mode 1, one shot */
#define TMR_RATEGEN	0x04	/* mode 2, rate generator */
#define TMR_SQWAVE	0x06	/* mode 3, square wave */
#define TMR_SWTRIGG	0x08	/* mode 4, s/w triggered strobe */
#define TMR_LSB		0x10	/* r/w counter LSB */
#define TMR_MSB		0x20	/* r/w counter MSB */
#define TMR_BOTH	0x30	/* r/w counter 16 bits, LSB first */

;----------------------------------------------------------------------
;
;	SIO defs
;

#define WR0_SEND_ABORT			0x08
#define WR0_RESET_ESCINT		0x10
#define WR0_CHANNEL_RESET		0x18
#define WR0_REARM_1STC			0x20
#define WR0_RESET_TXINT			0x28
#define WR0_ERROR_RESET			0x30
#define WR0_RETINT				0x38
#define WR0_RESET_RXCRC			0x40
#define WR0_RESET_TXCRC			0x80
#define WR0_RESET_UNDERRUN		0xc0

#define WR1_ESCINT_ENB			0x01
#define WR1_TXINT_ENB			0x02
#define WR1_STATUS_VECTOR		0x04
#define WR1_RXINT_DISABLE		0x00
#define WR1_INT_1STC			0x08
#define WR1_INT_ALLC			0x10
#define WR1_INT_ALLC_PNS		0x18
#define WR1_WAITREADY_RT		0x20
#define WR1_WAITREADY_FN		0x40
#define WR1_WAITREADY_ENB		0x80

#define WR3_RX_ENB				0x01
#define WR3_SYNCLOAD_INHIBIT	0x02
#define WR3_ADDRESS_SEARCH_MODE	0x04
#define WR3_RXCRC_ENB			0x08
#define WR3_ENTER_HUNT			0x10
#define WR3_AUTO_ENABLES		0x20
#define WR3_5BIT_RX				0x00
#define WR3_6BIT_RX				0x40
#define WR3_7BIT_RX				0x80
#define WR3_8BIT_RX				0xc0

#define WR4_PARITY_ENB			0x01
#define WR4_PARITY_ODD			0x00
#define WR4_PARITY_EVEN			0x02
#define WR4_SYNC_MODES			0x00
#define WR4_1STOPBIT			0x04
#define WR4_15STOPBIT			0x08
#define WR4_2STOPBIT			0x0c
#define WR4_8BITSYNC			0x00
#define WR4_16BITSYNC			0x10
#define WR4_SDLC_MODE			0x20
#define WR4_EXTSYNC				0x30
#define WR4_X1_CLK				0x00	/* 153600 bd, but... */
#define WR4_X16_CLK				0x40	/*   9600 bd */
#define WR4_X32_CLK				0x80	/*   4800 bd */
#define WR4_X64_CLK				0xc0	/*   2400 bd */

#define WR5_TXCRC_ENB			0x01
#define WR5_RTS					0x02
#define WR5_CCITT_CRC			0x00
#define WR5_CRC16_CRC			0x04
#define WR5_TX_ENB				0x08
#define WR5_SEND_BREAK			0x10
#define WR5_5BIT_TX				0x00
#define WR5_7BIT_TX				0x20
#define WR5_6BIT_TX				0x40
#define WR5_8BIT_TX				0x60
#define WR5_DTR					0x80

#define RR0_RCA					0x01
#define RR0_INT_PENDING			0x02
#define RR0_TBE					0x04
#define RR0_DCD					0x08
#define RR0_SYNC				0x10
#define RR0_CTS					0x20
#define RR0_UNDERRUN			0x40
#define RR0_BREAK_ABORT			0x80

#define RR1_ALL_SENT			0x01

#define RR1_PARER				0x10
#define RR1_ROVER				0x20
#define RR1_FRMERR				0x40
#define RR1_CRCERR				0x40
#define RR1_ENDFRAME			0x80

;----------------------------------------------------------------------
;
;	Output latch bits
;
#define O0_VOLUME 0x07
#define O0_INH    0x08
#define O0_AUDIOC 0x10
#define O0_CCIRC  0x20
#define O0_MTC    0x40
#define O0_MICM   0x80
#define O0_MTCBIT 6

#define O1_SRE    0x01
#define O1_SCE    0x02
#define O1_STE    0x04
#define O1_CLK    0x08
#define O1_SD     0x10
#define O1_RAS    0x20
#define O1_TPS    0x40
#define O1_TXOFF  0x80

;
;	Bits 0-3 select the memory bank (see set_bank); every writer keeps the
;	current ones from out2_bank.  CS1/CS2/CLK/DP are the handset bus.
;

#define O2_RA14   0x01
#define O2_RA15   0x02
#define O2_RS     0x04
#define O2_SMEM   0x08
#define O2_CS1    0x10
#define O2_CS2    0x20
#define O2_CLK    0x40	/* I2C SCL for CU58AF */
#define O2_DP     0x80

#define O2_BANK   (O2_SMEM | O2_RS | O2_RA15 | O2_RA14)
#define O2_XXX    O2_SMEM	/* bank 0, the power-on state */

/* handset bus states, without the bank bits */
#define O2_KEYPAD 0
#define O2_LATCH  O2_CS1
#define O2_LCD1   O2_CS2
#define O2_LCD2   (O2_CS2 | O2_CS1)

/* A = bus state | current bank bits, for OUT2 */
#define LD_A_OUT2(bus) ld a, (out2_bank) @ or #bus

;----------------------------------------------------------------------
;
;	PIO and SIO controls
;
#define PA_CLK2   0x01
#define PA_HOOK   0x02
#define PA_WDR    0x04
#define PA_PWR    0x08
#define PA_CCIR   0xf0	/* all inputs */

#define PB_RAMA12 0x01	/*                         out */
#define PB_EXIN1  0x02	/* aka /POR                out 0 if SERV */
#define PB_EXIN2  0x04  /* aka /IGN aka /EMG       out 0 if GPio2b 0 */
#define PB_DCU    0x08	/* I2C SDA for CU58AF      out 0 if SDA 0 */
#define PB_RXOFF  0x10  /*                         out */
#define PB_TMR0   0x20  /*                         in CTCSS-detect */
#define PB_EXAL   0x40	/*                         out */
#define PB_PWROFF 0x80	/*                         out */

#define PB_INPUTS 0x2E
#define PB_BIT_EXIN1 1
#define PB_BIT_EXIN2 2
#define PB_BIT_DCU   3

#define SA_KKINT  RR0_DCD
#define SA_DA     RR0_CTS	/* I2C /INT for CU58AF */

#define SB_PTT    RR0_CTS
#define SB_LOCAL  RR0_SYNC
#define SB_DMIDLE RR0_DCD	/* No MBUS activity */
#define SB_MON    WR5_DTR	/* Master ON pulse */

;----------------------------------------------------------------------
;
;	CU58AF defines
;
#define CU58AF_DTMF       0b01001000

#define CU58AF_LCD        0b01110000

#define CU58AF_ROW        0b01001100
#define CU58AF_ROW_MASK   0b01111111

#define CU58AF_COLBTN     0b01000000

#define CU58AF_OFFHOOK    0b10000000
#define CU58AF_TANGENT    0b01000000
#define CU58AF_SPEAKER    0b00100000
#define CU58AF_LDR        0b00010000
#define CU58AF_COL_MASK   0b00000111

#define CU58AF_LED        0b01000100

#define CU58AF_LED_SERV   0b00000001
#define CU58AF_LED_CALL   0b00000010
#define CU58AF_LED_ON     0b00000100
#define CU58AF_LED_ROAM   0b00001000
#define CU58AF_KBRLIGHT   0b00100000
#define CU58AF_LCDLIGHT   0b01000000

#define CU58AF_CTRL       0b01111100

#define CU58AF_NSPKRCTRL  0b00000001
#define CU58AF_DTMFCTRL   0b00000010
#define CU58AF_AUDIOCTRL  0b00000100
#define CU58AF_MICCTRL    0b00001000
#define CU58AF_EARCTRL    0b00010000
#define CU58AF_VOL_MASK   0b11100000
#define CU58AF_VOL_MIN    0b00100000

#define CU58AF_SEG_ARROW3   (24 + 7)
#define CU58AF_SEG_ARROW2   (24 + 6)
#define CU58AF_SEG_ARROW1   (24 + 5)
#define CU58AF_SEG_ARROW0   (24 + 4)

#define CU58AF_SEG_PHONE    (24 + 3)
#define CU58AF_SEG_CAR      (24 + 2)
#define CU58AF_SEG_EXP      (24 + 1)

;----------------------------------------------------------------------
;
;	LATCH bits
;

#define CU58AF_BIT_AVAIL    4	/* not connected */
#define CU58AF_BIT_ROAM     3
#define CU58AF_BIT_KEYLIGHT 5
#define CU58AF_BIT_SERV     0
#define CU58AF_BIT_ON       2
#define CU58AF_BIT_CALL     1
#define CU58AF_BIT_LCDLIGHT 6
#define CU58AF_BIT_BRIGHT   7

#define CU53AN_BIT_AVAIL    0	/* not connected */
#define CU53AN_BIT_ROAM     2
#define CU53AN_BIT_KEYLIGHT 3
#define CU53AN_BIT_SERV     4
#define CU53AN_BIT_ON       5
#define CU53AN_BIT_CALL     1
#define CU53AN_BIT_LCDLIGHT 6
#define CU53AN_BIT_BRIGHT   7

;	Special LCD segments

#define CU53AN_SEG_V_U      0x43
#define CU53AN_SEG_V_D      0x53
#define CU53AN_SEG_PHONE    0x47
#define CU53AN_SEG_CLOCK    0x4b
#define CU53AN_SEG_COLON_UR 0x4f
#define CU53AN_SEG_COLON_UL 0x63
#define CU53AN_SEG_COLON_D  0x57
#define CU53AN_SEG_PHONE_NO 0x5b
#define CU53AN_SEG_MAST     0x5f
#define CU53AN_SEG_BAR_L    0x67
#define CU53AN_SEG_BAR_R    0x6f
#define CU53AN_SEG_STAR     0x6b
#define CU53AN_SEG_KEY      0x73
#define CU53AN_SEG_BOOK     0x77
#define CU53AN_SEG_CAR_D    0x7b
#define CU53AN_SEG_CAR_U    0x7f

;----------------------------------------------------------------------
;
;	realstart
;
	.area ROM (ABS)

	.org 0

	di
	ld sp, #0			; stack down from end of ram (last 16kB)

	ld a, #O0_INH
	out (OUT0), a
	ld a, #O1_TXOFF
	out (OUT1), a

#if 0
	in a, (PIO+ADATA)
	and #PA_WDR
	jp nz, .			; Not watchdog reset ?!?
#endif

	; [3J] got power, but on/off-button in off-position. shut down.

	ld hl, #init_chips
	ld b, #PIOA_INIT
	ld c, #PIO+ACTRL
	otir                    ; configure port to be able to read /PWR pin
	in a, (PIO+ADATA)
	and #PA_PWR
	jp nz, powerdown_now



	ld hl, #0x0FFF	; Depends on clock freq... XXX shit
1:
	dec hl
	ld a, h
	or l
	jr nz, 1b		; Wait but not too long for defined wd state

	out (WD), a		; ok, now start
	jp start

;----------------------------------------------------------------------

	.org 0x0038

	di
	out (WD), a
	ld sp, #0			; stack down from end of ram (last 16kB)
	jp start

;----------------------------------------------------------------------
;
;	NMI
;
	.org 0x0066

v_nmi:
	di				; IFF1 and IFF2 cleared
	out (WD), a

	jp save_nvmisc_and_restart

;----------------------------------------------------------------------

	.ascii "@(#)"
banner:
	.ascii "R58 "
	.ascii "v"
version:
	.ascii VERSION
	.ascii " "
	.ascii PATCHED
	.ascii " "
	.ascii DATE
	.ascii " "
#ifdef P8x
	.ascii "P8E/P8N "
	.ascii "S8B/S8C/S8D "
#endif
	.ascii "CU53xx/CU58AF"
	.db 0x0A
	.db EOS

;----------------------------------------------------------------------
;
;	Initialization commands for PIO, SIO and 8254
;	In that order, A/B, A/B, 0/1/2 !
;

init_chips:
1:
	.db LO(pioa_base)	; load interrupt vector
	.db 0xcf			; set operating mode 3
	.db 0xff			; i/o selection, 1 for input, 0 for output
	.db 0x97			; set interrupt control, IE, OR, LOW, MASK
	.db 0xfe			; input bit monitoring mask, A0.
PIOA_INIT = . - 1b

1:
	.db LO(piob_base)	; load interrupt vector
	.db 0xCF			; set operating mode 3
	.db 0x3E			; i/o selection, 1 for input, 0 for output
	.db 0x97			; set interrupt control, IE, OR, LOW, MASK
	;.byte 0xDF			! input bit monitoring mask, only B5 (TMR0)
	.db 0xFF			; input bit monitoring mask, nothing
PIOB_INIT = . - 1b

1:
	.db WR0_CHANNEL_RESET
	.db 4, WR4_1STOPBIT | WR4_X32_CLK
	.db 3, WR3_8BIT_RX | WR3_RX_ENB
	.db 5, WR5_8BIT_TX | WR5_RTS | WR5_DTR | WR5_TX_ENB
	.db 1, WR1_STATUS_VECTOR | WR1_ESCINT_ENB | WR1_TXINT_ENB | WR1_INT_ALLC
SIOA_INIT = . - 1b

1:
	.db WR0_CHANNEL_RESET
	.db 4, WR4_1STOPBIT | WR4_X16_CLK
	.db 3, WR3_8BIT_RX | WR3_RX_ENB
	.db 5, WR5_8BIT_TX | WR5_RTS | WR5_DTR | WR5_TX_ENB
	.db 1, WR1_STATUS_VECTOR | WR1_ESCINT_ENB | WR1_TXINT_ENB | WR1_INT_ALLC
	.db 2, LO(sio_base)
SIOB_INIT = . - 1b

; XXX double Error reset / Reset Ext/Status for sios XXX
;
;	All timer-gates are fixed on.
;	timer-clocks 0 and 1 are 4.032 MHz, 2 is 1968.75 Hz
;
;	System hz is 100, from PIO A0 change-interrupt 1968.75 Hz
;   divided with software
;
#define MT_CALCHZ(f) (4032000 / (f))

MT_300HZ  = MT_CALCHZ(300)
MT_500HZ  = MT_CALCHZ(500)
MT_600HZ  = MT_CALCHZ(600)
MT_1000HZ = MT_CALCHZ(1000)
MT_1200HZ = MT_CALCHZ(1200)
MT_1400HZ = MT_CALCHZ(1400)
MT_1500HZ = MT_CALCHZ(1500)
MT_1750HZ = MT_CALCHZ(1750)
MT_2000HZ = MT_CALCHZ(2000)
MT_2500HZ = MT_CALCHZ(2500)
MT_3000HZ = MT_CALCHZ(3000)
MT_3500HZ = MT_CALCHZ(3500)

;----------------------------------------------------------------------
;
;    76543210
;   876543210
;
;     PV QQ SS        Pwr Vol sQuelch Sig
;   MM-434775           mem  frequency
;
; 0 1  23456789
; 10 1112

#define CU58AF_segs_bottom_row (segments + 2 * 11)
#define CU58AF_segs_d_digit_8  (segments + 2 * 11)
#define CU58AF_segs_d_digit_6  (segments + 2 * 13)

;	top row

#define CU58AF_segs_u_digit_7  (segments + 2 * 2)
#define CU58AF_segs_u_digit_4  (segments + 2 * 5)
#define CU58AF_segs_u_digit_1  (segments + 2 * 8)

;----------------------------------------------------------------------
;
;     XXYYZZ
;   9876543210
;
;      V P S        vola pwr srssi
;   CH  433500    channel  frequency
;

;	bottom row

CU53AN_segs_bottom_row:
CU53AN_segs_d_digit_9:		.db 56, 57, 58, 59,	120, 121, 122
CU53AN_segs_d_digit_8:		.db 60, 61, 62, 63,	124, 125, 126
CU53AN_segs_d_digit_7:		.db  0,  1,  2,  3,	 64,  65,  66
CU53AN_segs_d_digit_6:		.db  4,  5,  6,  7,	 68,  69,  70
CU53AN_segs_d_digit_5:		.db  8,  9, 10, 11,	 72,  73,  74
CU53AN_segs_d_digit_4:		.db 12, 13, 14, 15,	 76,  77,  78
CU53AN_segs_d_digit_3:		.db 16, 17, 18, 19,	 80,  81,  82
CU53AN_segs_d_digit_2:		.db 20, 21, 22, 23,	 84,  85,  86
CU53AN_segs_d_digit_1:		.db 24, 25, 26, 27,	 88,  89,  90
CU53AN_segs_d_digit_0:		.db 28, 29, 30, 31,	 92,  93,  94

;	top row

CU53AN_segs_u_digit_5:		.db 32, 33, 34, 35,	 96,  97,  98
CU53AN_segs_u_digit_4:		.db 36, 37, 38, 39,	100, 101, 102
CU53AN_segs_u_digit_3:		.db 40, 41, 42, 43,	104, 105, 106
CU53AN_segs_u_digit_2:		.db 44, 45, 46, 47,	108, 109, 110
CU53AN_segs_u_digit_1:		.db 48, 49, 50, 51,	112, 113, 114
CU53AN_segs_u_digit_0:		.db 52, 53, 54, 55,	116, 117, 118

;----------------------------------------------------------------------
;
;	Interrupt table, short-aligned, on one page.
;   IV is a flag for save_nvxxx, boot complete.
;
	ALIGN(4, 0)

intvec:                 ASSERT_EQ(HI(intvec), 1) ; gah, as bug, no != in ASS()

sio_base:
	.dw siob_tbe
	.dw siob_esc
	.dw siob_rca
	.dw siob_src
	.dw sioa_tbe
	.dw sioa_esc
	.dw sioa_rca
	.dw sioa_src

pioa_base:
	.dw pioa_int
piob_base:
	.dw piob_int

pioa_base_during_ctcss:
	.dw pioa_int_during_ctcss

	ASSERT_EQ(HI(intvec), HI(.))

;======================================================================
;
;	Initialization before main
;

start:
	di
	out (WD), a

	ld sp, #0			; stack down from end of ram (last 16kB)

	;
	;  Output latches
	;

	ld a, #O0_INH			; volume setting at lowest level
	ld (output_0), a
	out (OUT0), a

	ld a, #O1_TXOFF		; no tx, idle all
	ld (output_1), a
	out (OUT1), a

	out (WD), a
	;
	;  Prep RAM selects for max workspace
	;
	ld a, #O2_XXX		; select ram 0, i hope, on P8N
	out (OUT2), a

	ld a, #1
	out (CSMEM), a		; select full 16k page of ram on P8E, nop on P8N

	out (WD), a

	;
	;  Disable NMT modem
	;

	ld a, #MDM_XXX
	out (MDM + MDMCTRL), a

	;
	;  PIO, SIO and 8254
	;

	ld a, #PB_INPUTS
	ld (piob_mode), a

	xor a
	out (PIO+BDATA), a	; B0, EXAL, /RXON, OFF all zero. SDA low but direction read.

	ld hl, #init_chips   ; few runs of 'otir' below -------------

	ld b, #PIOA_INIT
	ld c, #PIO+ACTRL
	otir
	out (WD), a

	ld b, #PIOB_INIT
	ld c, #PIO+BCTRL
	otir
	out (WD), a

	; Set output bits, and check if restarted from powerdown nmi.

	xor a
	out (PIO+BDATA), a	; B0, EXAL, /RXON, OFF all zero, again ?

	in a, (PIO+ADATA)
	and #PA_PWR
	jp nz, powerdown_now

	ld b, #SIOA_INIT
	ld c, #SIO+ACTRL
	in a, (c)
	otir
	out (WD), a

	ld b, #SIOB_INIT
	ld c, #SIO+BCTRL
	in a, (c)
	otir                       ; last otir -------------------
	out (WD), a

	call check_for_P8E_cpu     ; timers messed up

	out (WD), a

	call init_timer1
	call ctcss_off_nohang

	out (WD), a

	; ----------------- zero variables ------------------------
	ld de, #_bss
	xor a
1:
	out (WD), a
	ld (de), a
	inc de
	ld hl, #_end
	and a
	sbc hl, de
	jr nz, 1b

	;
	;  Initialize variables after bss clear
	;
	ld a, #PB_INPUTS
	ld (piob_mode), a                   ; 3.N fix after bss bzero.
	call bank_init			; (fills the hole before crctbls exactly)

	ld hl, #mbusrx_buf
	ld (mbusrx_rp), hl
	ld (mbusrx_wp), hl

	ld hl, #mbustx_buf
	ld (mbustx_rp), hl
	ld (mbustx_wp), hl

	out (WD), a

	ld a, #0xFF
	ld (dark), a
	ld (ad_batt), a
	ld (nosir), a

	ld hl, #packet
	ld (pkt_ptr), hl		; rewind packet pointer

	jp start_continue

;======================================================================
;
;  Some unfortunate tables need page alignment.
;  Grouped here.
;

	slack_at_this_xxx_hole = crctbls - .

	ALIGN(8, 0xFF)
crctbls:
crctbl_hi:
	.db HI(    0), HI( 4489), HI( 8978), HI(12955)
	.db HI(17956), HI(22445), HI(25910), HI(29887)
	.db HI(35912), HI(40385), HI(44890), HI(48851)
	.db HI(51820), HI(56293), HI(59774), HI(63735)
	.db HI( 4225), HI(  264), HI(13203), HI( 8730)
	.db HI(22181), HI(18220), HI(30135), HI(25662)
	.db HI(40137), HI(36160), HI(49115), HI(44626)
	.db HI(56045), HI(52068), HI(63999), HI(59510)
	.db HI( 8450), HI(12427), HI(  528), HI( 5017)
	.db HI(26406), HI(30383), HI(17460), HI(21949)
	.db HI(44362), HI(48323), HI(36440), HI(40913)
	.db HI(60270), HI(64231), HI(51324), HI(55797)
	.db HI(12675), HI( 8202), HI( 4753), HI(  792)
	.db HI(30631), HI(26158), HI(21685), HI(17724)
	.db HI(48587), HI(44098), HI(40665), HI(36688)
	.db HI(64495), HI(60006), HI(55549), HI(51572)
	.db HI(16900), HI(21389), HI(24854), HI(28831)
	.db HI( 1056), HI( 5545), HI(10034), HI(14011)
	.db HI(52812), HI(57285), HI(60766), HI(64727)
	.db HI(34920), HI(39393), HI(43898), HI(47859)
	.db HI(21125), HI(17164), HI(29079), HI(24606)
	.db HI( 5281), HI( 1320), HI(14259), HI( 9786)
	.db HI(57037), HI(53060), HI(64991), HI(60502)
	.db HI(39145), HI(35168), HI(48123), HI(43634)
	.db HI(25350), HI(29327), HI(16404), HI(20893)
	.db HI( 9506), HI(13483), HI( 1584), HI( 6073)
	.db HI(61262), HI(65223), HI(52316), HI(56789)
	.db HI(43370), HI(47331), HI(35448), HI(39921)
	.db HI(29575), HI(25102), HI(20629), HI(16668)
	.db HI(13731), HI( 9258), HI( 5809), HI( 1848)
	.db HI(65487), HI(60998), HI(56541), HI(52564)
	.db HI(47595), HI(43106), HI(39673), HI(35696)
	.db HI(33800), HI(38273), HI(42778), HI(46739)
	.db HI(49708), HI(54181), HI(57662), HI(61623)
	.db HI( 2112), HI( 6601), HI(11090), HI(15067)
	.db HI(20068), HI(24557), HI(28022), HI(31999)
	.db HI(38025), HI(34048), HI(47003), HI(42514)
	.db HI(53933), HI(49956), HI(61887), HI(57398)
	.db HI( 6337), HI( 2376), HI(15315), HI(10842)
	.db HI(24293), HI(20332), HI(32247), HI(27774)
	.db HI(42250), HI(46211), HI(34328), HI(38801)
	.db HI(58158), HI(62119), HI(49212), HI(53685)
	.db HI(10562), HI(14539), HI( 2640), HI( 7129)
	.db HI(28518), HI(32495), HI(19572), HI(24061)
	.db HI(46475), HI(41986), HI(38553), HI(34576)
	.db HI(62383), HI(57894), HI(53437), HI(49460)
	.db HI(14787), HI(10314), HI( 6865), HI( 2904)
	.db HI(32743), HI(28270), HI(23797), HI(19836)
	.db HI(50700), HI(55173), HI(58654), HI(62615)
	.db HI(32808), HI(37281), HI(41786), HI(45747)
	.db HI(19012), HI(23501), HI(26966), HI(30943)
	.db HI( 3168), HI( 7657), HI(12146), HI(16123)
	.db HI(54925), HI(50948), HI(62879), HI(58390)
	.db HI(37033), HI(33056), HI(46011), HI(41522)
	.db HI(23237), HI(19276), HI(31191), HI(26718)
	.db HI( 7393), HI( 3432), HI(16371), HI(11898)
	.db HI(59150), HI(63111), HI(50204), HI(54677)
	.db HI(41258), HI(45219), HI(33336), HI(37809)
	.db HI(27462), HI(31439), HI(18516), HI(23005)
	.db HI(11618), HI(15595), HI( 3696), HI( 8185)
	.db HI(63375), HI(58886), HI(54429), HI(50452)
	.db HI(45483), HI(40994), HI(37561), HI(33584)
	.db HI(31687), HI(27214), HI(22741), HI(18780)
	.db HI(15843), HI(11370), HI( 7921), HI( 3960)
crctbl_lo:
	.db LO(    0), LO( 4489), LO( 8978), LO(12955)
	.db LO(17956), LO(22445), LO(25910), LO(29887)
	.db LO(35912), LO(40385), LO(44890), LO(48851)
	.db LO(51820), LO(56293), LO(59774), LO(63735)
	.db LO( 4225), LO(  264), LO(13203), LO( 8730)
	.db LO(22181), LO(18220), LO(30135), LO(25662)
	.db LO(40137), LO(36160), LO(49115), LO(44626)
	.db LO(56045), LO(52068), LO(63999), LO(59510)
	.db LO( 8450), LO(12427), LO(  528), LO( 5017)
	.db LO(26406), LO(30383), LO(17460), LO(21949)
	.db LO(44362), LO(48323), LO(36440), LO(40913)
	.db LO(60270), LO(64231), LO(51324), LO(55797)
	.db LO(12675), LO( 8202), LO( 4753), LO(  792)
	.db LO(30631), LO(26158), LO(21685), LO(17724)
	.db LO(48587), LO(44098), LO(40665), LO(36688)
	.db LO(64495), LO(60006), LO(55549), LO(51572)
	.db LO(16900), LO(21389), LO(24854), LO(28831)
	.db LO( 1056), LO( 5545), LO(10034), LO(14011)
	.db LO(52812), LO(57285), LO(60766), LO(64727)
	.db LO(34920), LO(39393), LO(43898), LO(47859)
	.db LO(21125), LO(17164), LO(29079), LO(24606)
	.db LO( 5281), LO( 1320), LO(14259), LO( 9786)
	.db LO(57037), LO(53060), LO(64991), LO(60502)
	.db LO(39145), LO(35168), LO(48123), LO(43634)
	.db LO(25350), LO(29327), LO(16404), LO(20893)
	.db LO( 9506), LO(13483), LO( 1584), LO( 6073)
	.db LO(61262), LO(65223), LO(52316), LO(56789)
	.db LO(43370), LO(47331), LO(35448), LO(39921)
	.db LO(29575), LO(25102), LO(20629), LO(16668)
	.db LO(13731), LO( 9258), LO( 5809), LO( 1848)
	.db LO(65487), LO(60998), LO(56541), LO(52564)
	.db LO(47595), LO(43106), LO(39673), LO(35696)
	.db LO(33800), LO(38273), LO(42778), LO(46739)
	.db LO(49708), LO(54181), LO(57662), LO(61623)
	.db LO( 2112), LO( 6601), LO(11090), LO(15067)
	.db LO(20068), LO(24557), LO(28022), LO(31999)
	.db LO(38025), LO(34048), LO(47003), LO(42514)
	.db LO(53933), LO(49956), LO(61887), LO(57398)
	.db LO( 6337), LO( 2376), LO(15315), LO(10842)
	.db LO(24293), LO(20332), LO(32247), LO(27774)
	.db LO(42250), LO(46211), LO(34328), LO(38801)
	.db LO(58158), LO(62119), LO(49212), LO(53685)
	.db LO(10562), LO(14539), LO( 2640), LO( 7129)
	.db LO(28518), LO(32495), LO(19572), LO(24061)
	.db LO(46475), LO(41986), LO(38553), LO(34576)
	.db LO(62383), LO(57894), LO(53437), LO(49460)
	.db LO(14787), LO(10314), LO( 6865), LO( 2904)
	.db LO(32743), LO(28270), LO(23797), LO(19836)
	.db LO(50700), LO(55173), LO(58654), LO(62615)
	.db LO(32808), LO(37281), LO(41786), LO(45747)
	.db LO(19012), LO(23501), LO(26966), LO(30943)
	.db LO( 3168), LO( 7657), LO(12146), LO(16123)
	.db LO(54925), LO(50948), LO(62879), LO(58390)
	.db LO(37033), LO(33056), LO(46011), LO(41522)
	.db LO(23237), LO(19276), LO(31191), LO(26718)
	.db LO( 7393), LO( 3432), LO(16371), LO(11898)
	.db LO(59150), LO(63111), LO(50204), LO(54677)
	.db LO(41258), LO(45219), LO(33336), LO(37809)
	.db LO(27462), LO(31439), LO(18516), LO(23005)
	.db LO(11618), LO(15595), LO( 3696), LO(8185)
	.db LO(63375), LO(58886), LO(54429), LO(50452)
	.db LO(45483), LO(40994), LO(37561), LO(33584)
	.db LO(31687), LO(27214), LO(22741), LO(18780)
	.db LO(15843), LO(11370), LO( 7921), LO(3960)

;======================================================================

	ALIGN(8, 0xFF)
sinetab:          ; XXX calculate_sinetab() should mirror rest from 1/4 of a circle

	.db   +0,   +3,   +6,   +9,  +12,  +15,  +18,  +21
	.db  +24,  +27,  +30,  +33,  +36,  +39,  +42,  +45
	.db  +48,  +51,  +54,  +57,  +59,  +62,  +65,  +67
	.db  +70,  +73,  +75,  +78,  +80,  +82,  +85,  +87
	.db  +89,  +91,  +94,  +96,  +98, +100, +102, +103
	.db +105, +107, +108, +110, +112, +113, +114, +116
	.db +117, +118, +119, +120, +121, +122, +123, +123
	.db +124, +125, +125, +126, +126, +126, +126, +126
	.db +127, +126, +126, +126, +126, +126, +125, +125
	.db +124, +123, +123, +122, +121, +120, +119, +118
	.db +117, +116, +114, +113, +112, +110, +108, +107
	.db +105, +103, +102, +100,  +98,  +96,  +94,  +91
	.db  +89,  +87,  +85,  +82,  +80,  +78,  +75,  +73
	.db  +70,  +67,  +65,  +62,  +59,  +57,  +54,  +51
	.db  +48,  +45,  +42,  +39,  +36,  +33,  +30,  +27
	.db  +24,  +21,  +18,  +15,  +12,   +9,   +6,   +3
	.db   +0,   -3,   -6,   -9,  -12,  -15,  -18,  -21
	.db  -24,  -27,  -30,  -33,  -36,  -39,  -42,  -45
	.db  -48,  -51,  -54,  -57,  -59,  -62,  -65,  -67
	.db  -70,  -73,  -75,  -78,  -80,  -82,  -85,  -87
	.db  -89,  -91,  -94,  -96,  -98, -100, -102, -103
	.db -105, -107, -108, -110, -112, -113, -114, -116
	.db -117, -118, -119, -120, -121, -122, -123, -123
	.db -124, -125, -125, -126, -126, -126, -126, -126
	.db -127, -126, -126, -126, -126, -126, -125, -125
	.db -124, -123, -123, -122, -121, -120, -119, -118
	.db -117, -116, -114, -113, -112, -110, -108, -107
	.db -105, -103, -102, -100,  -98,  -96,  -94,  -91
	.db  -89,  -87,  -85,  -82,  -80,  -78,  -75,  -73
	.db  -70,  -67,  -65,  -62,  -59,  -57,  -54,  -51
	.db  -48,  -45,  -42,  -39,  -36,  -33,  -30,  -27
	.db  -24,  -21,  -18,  -15,  -12,   -9,   -6,   -3

;======================================================================
	ALIGN(8, 0xFF)
cu53an_font:

	.db	0x5f	; 0 	0 1 2 3   4 - 6
	.db	0x0c	; 1 	- - 2 3   - - -
	.db	0x7a	; 2 	- 1 - 3   4 5 6
	.db	0x7c	; 3 	- - 2 3   4 5 6
	.db	0x2d	; 4 	0 - 2 3   - 5 -
	.db	0x75	; 5 	0 - 2 -   4 5 6
	.db	0x77	; 6 	0 1 2 -   4 5 6
	.db	0x1c	; 7 	- - 2 3   4 - -
	.db	0x7f	; 8 	0 1 2 3   4 5 6
	.db	0x7d	; 9 	0 - 2 3   4 5 6
	.db	0x3f	; A 	0 1 2 3   4 5 -
	.db	0x67	; b 	0 1 2 -   - 5 6
	.db	0x53	; C 	0 1 - -   4 - 6
	.db	0x6e	; d 	- 1 2 3   - 5 6
	.db	0x73	; E 	0 1 - -   4 5 6
	.db	0x33	; F 	0 1 - -   4 5 -

	.db	0x57	; G 	0 1 2 -   4 - 6

	.org cu53an_font + ' '

	.db	0x00	;   	- - - -   - - -
	.db	0x79	; ! 	0 - - 3   4 5 6
	.db	0x09	; " 	0 - - 3   - - -
	.db	0x66	; # 	- 1 2 -   - 5 6
	.db	0x25	; $ 	0 - 2 -   - 5 -
	.db	0x05	; % 	0 - 2 -   - - -
	.db	0x6a	; & 	- 1 - 3   - 5 6
	.db	0x08	; ' 	- - - 3   - - -
	.db	0x0c	; ( 	- - 2 3   - - -
	.db	0x03	; ) 	0 1 - -   - - -
	.db	0x70	; * 	- - - -   4 5 6
	.db	0x23	; + 	0 1 - -   - 5 -
	.db	0x02	; , 	- 1 - -   - - -
	.db	0x20	; - 	- - - -   - 5 -
	.db	0x02	; . 	- 1 - -   - - -
	.db	0x2a	; / 	- 1 - 3   - 5 -
	.db	0x5f	; 0 	0 1 2 3   4 - 6
	.db	0x0c	; 1 	- - 2 3   - - -
	.db	0x7a	; 2 	- 1 - 3   4 5 6
	.db	0x7c	; 3 	- - 2 3   4 5 6
	.db	0x2d	; 4 	0 - 2 3   - 5 -
	.db	0x75	; 5 	0 - 2 -   4 5 6
	.db	0x77	; 6 	0 1 2 -   4 5 6
	.db	0x1c	; 7 	- - 2 3   4 - -
	.db	0x7f	; 8 	0 1 2 3   4 5 6
	.db	0x7d	; 9 	0 - 2 3   4 5 6
	.db	0x50	; : 	- - - -   4 - 6
	.db	0x48	; ; 	- - - 3   - - 6
	.db	0x2c	; < 	- - 2 3   - 5 -
	.db	0x60	; = 	- - - -   - 5 6
	.db	0x23	; > 	0 1 - -   - 5 -
	.db	0x3a	; ? 	- 1 - 3   4 5 -
	.db	0x7e	; @ 	- 1 2 3   4 5 6
	.db	0x3f	; A 	0 1 2 3   4 5 -
	.db	0x67	; b 	0 1 2 -   - 5 6
	.db	0x53	; C 	0 1 - -   4 - 6
	.db	0x6e	; d 	- 1 2 3   - 5 6
	.db	0x73	; E 	0 1 - -   4 5 6
	.db	0x33	; F 	0 1 - -   4 5 -
	.db	0x57	; G 	0 1 2 -   4 - 6
	.db	0x2f	; H		0 1 2 3   - 5 -
	.db	0x0c	; I 	- - 2 3   - - -
	.db	0x4e	; J 	- 1 2 3   - - 6
	.db	0x23	; K 	0 1 - -   - 5 -
	.db	0x43	; L		0 1 - -   - - 6
	.db	0x1f	; M		0 1 2 3   4 - -
	.db	0x26	; N		- 1 2 -   - 5 -
	.db	0x5f	; O 	0 1 2 3   4 - 6
	.db	0x3b	; P 	0 1 - 3   4 5 -
	.db	0x3d	; Q 	0 - 2 3   4 5 -
	.db	0x1b	; R		0 1 - 3   4 - -
	.db	0x75	; S 	0 - 2 -   4 5 6
	.db	0x13	; T		0 1 - -   4 - -
	.db	0x4f	; U 	0 1 2 3   - - 6
	.db	0x6f	; V
	.db	0x56	; W
	.db	0x70	; X		- - - -   4 5 6
	.db	0x6d	; Y 	0 - 2 3   - 5 6
	.db	0x7a	; Z 	- 1 - 3   4 5 6
	.db	0x53	; [ 	0 1 - -   4 - 6
	.db	0x25	; \ 	0 - 2 -   - 5 -
	.db	0x5c	; ] 	- - 2 3   4 - 6
	.db	0x10	; ^ 	- - - -   4 - -
	.db	0x40	; _ 	- - - -   - - 6
	.db	0x01	; ` 	0 - - -   - - -
	.db	0x26	; a 	- 1 2 -   - 5 -
	.db	0x67	; b 	0 1 2 -   - 5 6
	.db	0x62	; c 	- 1 - -   - 5 6
	.db	0x6e	; d 	- 1 2 3   - 5 6
	.db	0x62	; e 	- 1 - -   - 5 6
	.db	0x33	; f 	0 1 - -   4 5 -
	.db	0x7d	; g 	0 - 2 3   4 5 6
	.db	0x27	; h		0 1 2 -   - 5 -
	.db	0x04	; i 	- - 2 -   - - -
	.db	0x44	; j 	- - 2 -   - - 6
	.db	0x23	; k 
	.db	0x42	; l		- 1 - -   - - 6
	.db	0x1F	; m
	.db	0x26	; n		- 1 2 -   - 5 -
	.db	0x66	; o 	- 1 2 -   - 5 6
	.db	0x3b	; p 	0 1 - 3   4 5 -
	.db	0x3d	; q 	0 - 2 3   4 5 -
	.db	0x22	; r		- 1 - -   - 5 -
	.db	0x75	; s 	0 - 2 -   4 5 6
	.db	0x63	; t		0 1 - -   - 5 6
	.db	0x46	; u 	- 1 2 -   - - 6
	.db	0x6F	; v
	.db	0x56	; w
	.db	0x70	; x
	.db	0x2d	; y 	0 - 2 3   - 5 -
	.db	0x7A	; z 	- - - -   - 5 6
	.db	0x62	; { 	- 1 - -   - 5 6
	.db	0x02	; | 	- 1 - -   - - -
	.db	0x64	; } 	- - 2 -   - 5 6
	.db	0x10	; ~ 	- - - -   4 - -
	.db	0x00	; ^? 	- 1 - 3   4 5 6

	ASSERT_EQ((. - cu53an_font), 128)

;======================================================================

	; must be inside page

dtmf_8870_tab:
	.db 0xD, 1,2,3,4,5,6,7,8,9, 0x0, '*', '#', 0xA, 0xB, 0xC

	ASSERT_EQ(HI(.), HI(dtmf_8870_tab))

;======================================================================

	; must be inside page

res_set_stubs:          ; 4 bytes each (one extra for convenience)
	res 0, (hl)
	ret
	nop
	set 0, (hl)
	ret
	nop
	res 1, (hl)
	ret
	nop
	set 1, (hl)
	ret
	nop
	res 2, (hl)
	ret
	nop
	set 2, (hl)
	ret
	nop
	res 3, (hl)
	ret
	nop
	set 3, (hl)
	ret
	nop
	res 4, (hl)
	ret
	nop
	set 4, (hl)
	ret
	nop
	res 5, (hl)
	ret
	nop
	set 5, (hl)
	ret
	nop
	res 6, (hl)
	ret
	nop
	set 6, (hl)
	ret
	nop
	res 7, (hl)
	ret
	nop
	set 7, (hl)
	ret
	nop

	ASSERT_EQ(HI(.), HI(res_set_stubs))

;======================================================================

	; good place for tables that can not cross page boundary

;======================================================================

start_continue:

	ld hl, #cu_handler_unknown
	ld (cu_handler), hl

	ld a, #HI(gps_history)
	ld (gps_hist_page), a      ; trick in sioa_rca()

	ld a, #-1
	ld (key), a
	ld (lastkey), a
	ld (lastdigit), a

	call load_nvdata

	out (WD), a

	call init_modem
#if 0
	call init_fx614
#endif
	call init_ctcss

	out (WD), a

	ld b, #2
	ld c, #0
	ld d, #0			; delay 2 * 256 * 256
1:
	out (WD), a
	nop
	nop
	nop
	nop
	dec d
	jr nz, 1b
	dec c
	jr nz, 1b
	dec b
	jr nz, 1b		; Give time for LCD to reset itself !

	in a, (TMR+TMRCTRL)		; dummy read to raise PIO B5 (remove int)
	out (WD), a

	;----------------------------------------------
	;  Check some input pins at bootup

	in a, (PIO+BDATA)
	and #PB_EXIN1
	jr nz, 1f
1:

	ld a, #WR0_RESET_ESCINT
	out (SIO+BCTRL), a
	in a, (SIO+BCTRL)
	ld (sio_bctrl_mirror), a
	ld (sio_bctrl_local), a

	and #SB_LOCAL		; inverted...
	jr z, 1f			; go if LOCAL idle high, bit inverted
	ld a, #1
	ld (local_mode), a
1:

	;----------------------------------------------
	;
	;  Load generic serial controls

	call shift_external_serial_A
	call shift_external_serial_B

	;----------------------------------------------
	;
	;  Flag for powerdown - have we booted up fully.

	ld a, #HI(intvec)
	ld i, a
	im 2

	jp main

;======================================================================
;
;
;  Remember, E register keeps live values in "other" registerset,
;  decremented and systick called every 20th 1969 Hz interrupt.
;  D is live too.

; cost: 10T + 4T + 14T = 28T

#define doreti   pop af @ ei @ reti

;----------------------------------------------------------------------
;
;  SIO interrupts
;

siob_tbe:
	push af
	push hl

	ld hl, #mbustx_cnt       ; if continuous bytes are sent, this way
	dec (hl)                ; is faster than ld a, []; dec a; ld [], a
	jr z, 1f                ; end transmission

	ld hl, (mbustx_rp)
	ld a, (hl)
	inc l
	ld (mbustx_rp), hl

	out (SIO+BDATA), a

	ld a, #25
	ld (mbus_timer), a		; keep transmit timer on

	pop hl
	doreti
1:
	ld a, #WR0_RESET_TXINT
	out (SIO+BCTRL), a

	pop hl
	doreti

siob_rca:
	push af
	in a, (SIO+BDATA)      ; as soon as possible
	push hl
	ld h, a                ; keep here for a while

	ld a, (mbus_timer)
	or a
	jr nz, 2f              ; ignore

	ld a, h                ; moving around
	ld hl, #mbusrx_cnt
	inc (hl)
	jr z, 1f               ; no space available

	ld hl, (mbusrx_wp)
	ld (hl), a
	inc l
	ld (mbusrx_wp), hl     ; stash it

	pop hl
	doreti
1:
	dec (hl)               ; adjust count back.
2:
	pop hl                 ; forget the byte
	doreti


; SIOB external/status - /PTT, NETFREE and /LOCAL might have changed.
;                           NETFREE aka DMIDLE
;
; mirror of register kept in [sio_bctrl_mirror].
; PTT is polled.
; LOCAL is maybe polled, and handled here, too.
; NETFREE could be polled, or handled here

siob_esc:
	push af                          ; 11T
	push hl                          ; 11T

	in a, (SIO+BCTRL)                ; 11T
	ld hl, (sio_bctrl_mirror)        ; 16T
	ld (sio_bctrl_mirror), a         ; 13T
#if 0
	xor l                            ;  4T
	and #SB_LOCAL                     ;  7T
	call nz, fx614_bit_edge          ; 10/17T    XXX might just call blindly
#endif

	ld a, #WR0_RESET_ESCINT           ;  7T finished
	out (SIO+BCTRL), a               ; 11T

	pop hl                           ; 10T
	doreti                           ; 28T

;
;	SIO B special receive condition
;
siob_src:
	push af
	in a, (SIO+BDATA)         ; junk it

	ld a, #WR0_ERROR_RESET
	out (SIO+BCTRL), a        ; silent service

	doreti

;
;  Sending asciz strings to GPS
;
sioa_tbe:
	push af
	push hl

	ld hl, (gps_upload_ptr)
	ld a, (hl)
	or a
	jr z, 1f

	inc hl
	ld (gps_upload_ptr), hl

	out (SIO+ADATA), a

	pop hl
	doreti
1:
	ld a, #WR0_RESET_TXINT
	out (SIO+ACTRL), a

	pop hl
	doreti

;
;  NMEA input
;
sioa_rca:
	push af
	in a, (SIO+ADATA)      ; as soon as possible
	push hl

	ld hl, (gps_hist_idx)  ; 16
	ld (hl), a             ;  7 stash it
	inc l                  ;  4
	ld (gps_hist_idx), hl  ; 16 only L changed ever

	pop hl
	doreti

;
;  SIO A ext/status change - CU53_DA or CU58AF_INT, HK, Modem and timer OUT2
;
;  Also uncommitted SYNC_A comes here.
;
sioa_esc:
	push af
	push hl

	call cu_handler_stub
	call modem_handler

	in a, (TMR+TMRCTRL)		; dummy read to raise PIO B5 (remove int)

	ld a, #WR0_RESET_ESCINT
	out (SIO+ACTRL), a

	pop hl
	doreti


cu_handler_stub:           ; handlers ret to our caller.

	ld hl, (cu_handler)    ; 16T
	jp (hl)                ;  4T   = 20T extra vs. plain call

cu_handler_unknown:

	ret                 ; does nothing.

;
;  CU53 and CU58AF behave differently.
;
;  CU53 raises DA on make, and drops it on break.
;  CU58AF drops /INT each time a button makes or breaks.
;  'keydown' flags a pressed key, and is also used for debouncing.
;  When it increments to 10 in systick() the data is fetched from CU.
;  With CU53 the break is detected here, but CU58AF has to fetch
;  nil data with i2c. 'keydown' is restarted from 1 on each i2c /INT.
;
cu_handler_cu53:

	in a, (SIO+ACTRL)   ; /CTS inverts the input...
	and #SA_DA
	jr z, 1f            ; go if DA high
	xor a
	ld (key_timer), a
	ld (keydown), a     ; clear these
	ld a, (lastdigit)   ; was it a quick press of dual purpose key ?
	cp #-1
	ret z               ; no.
	ld (key), a         ; it was. do the digit.
	ld a, #-1
	ld (lastdigit), a   ; clear "queue"
	ret
1:
	ld a, (keydown)
	or a
	ret nz              ; nothing if already seen it
	inc a               ; 0++ == 1
	ld (keydown), a		; start debouncing
	ret

cu_handler_cu58af:

	in a, (SIO+ACTRL)   ; /CTS inverts the input...
	and #SA_DA
	ret z               ; skip if /INT high. We only look for drops.
	ld a, #1
	ld (keydown), a     ; start debouncing
	ret


modem_handler:

	in a, (MDM + MDMCTRL)
	and #MDM_SYNC | MDM_RXRDY
	ret z                     ; no sync nor data

	cp #MDM_SYNC
	jr z, 1f                  ; sync only (never both simultaneously ?!?!?)
	and #MDM_RXRDY
	ret z                     ; no data anyway

	in a, (MDM + MDMDATA)

	ld hl, (pkt_ptr)
	ld (hl), a
	inc hl
	ld (pkt_ptr), hl

	ld a, l
	cp #LO(packet + 2)
	jr z, 2f

	cp #LO(packet + SHORT_PACLEN)
	jp z, check_short_packet
	cp #LO(packet + LONG_PACLEN)
	jp z, check_long_packet

	ret
1:
	ld hl, #packet                ; at SYNC
	ld (pkt_ptr), hl             ; rewind packet pointer

	jp mute_fsk_at_sync_maybe
2:
	ld a, #MDM_RXENB | MDM_RXFMT  ; got 2 bytes of the packet now
	out (MDM + MDMCTRL), a

	jp mute_fsk_at_tag_maybe

;
;	SIO A special receive condition
;
sioa_src:
	push af

	in a, (SIO+ADATA)

	ld a, #WR0_ERROR_RESET
	out (SIO+ACTRL), a      ; silent service

	doreti

;----------------------------------------------------------------------
;
;  PIO interrupts
;

;   Should not get this now, as monitormask is empty...

piob_int:
	push af

	doreti

;	Change in A0, 1968.75 Hz square - systick and D/A read every now and then

ad_list:
	.db AD_IN7,  AD_TP4,  AD_RSSI, AD_SQL
	.db AD_BATT, AD_RSSI, AD_SQL,  AD_TPC
	.db AD_RSSI, AD_SQL,  AD_FPM,  AD_RSSI
	.db AD_SQL,  AD_RPM,  AD_RSSI, AD_SQL
	.db AD_IN7             ; one duplicated to handle wrap in end

	ASSERT_EQ(HI(.), HI(ad_list))  ; ad_list[] must not cross page


;   XXX inc [hl]
;   XXX call pe, signed_overflow_happened

; ctcss decoder with lowpass filter and slicer on "DTMF-ROM-multiboard"

ctcss_dec_entry:

	; step dds and get cycle quadrant bits to H

	ld bc, (ctcss_dec_phinc) ; 20
	ld hl, (ctcss_dec_phacc) ; 16
	add hl, bc               ; 11 step on the sine
	ld (ctcss_dec_phacc), hl ; 16 keep track of phase

	ld bc, (ctcss_dec_src)   ; 20 0x80xx, or a RAM zero while banked
	ld a, (bc)               ;  7 A.0 is slicer status, "sample"
	ld b, #0x80              ;  7 mask for the and below
	rrca                     ;  4 sample to A.7
	and b                    ;  4 A.6 zeroed with the lucky mask in B reg
	xor h                    ;  4 merge quadrant bits from H.7 and H.6
	add a, a                    ;  4 0xC0 into carry and sign (quick rl a)
	jp c, 2f                 ; 10
	jp m, 1f                 ; 10
	ld hl, (ctcss_dec_sin)   ; 16 Case 3
	dec hl                   ;  6
	ld (ctcss_dec_sin), hl   ; 16
	ld hl, (ctcss_dec_cos)   ; 16
	dec hl                   ;  6
	ld (ctcss_dec_cos), hl   ; 16
	jp ctcss_dec_ret         ; 10
1:
	ld hl, (ctcss_dec_sin)   ; Case 2
	dec hl
	ld (ctcss_dec_sin), hl
	ld hl, (ctcss_dec_cos)
	inc hl
	ld (ctcss_dec_cos), hl
	jp ctcss_dec_ret
2:
	jp m, 1f
	ld hl, (ctcss_dec_sin)   ; Case 0
	inc hl
	ld (ctcss_dec_sin), hl
	ld hl, (ctcss_dec_cos)
	inc hl
	ld (ctcss_dec_cos), hl
	jp ctcss_dec_ret
1:
	ld hl, (ctcss_dec_sin)   ; Case 1
	inc hl
	ld (ctcss_dec_sin), hl
	ld hl, (ctcss_dec_cos)
	dec hl
	ld (ctcss_dec_cos), hl
	jp ctcss_dec_ret


pioa_int_during_ctcss:

	ex af, af'                    ;  4 replaces the one in standard interrupt
	exx                      ;  4 replaces the one in standard interrupt, too.

	ld hl, (ctcss_enc_jump)  ; 16 order of enc and dec does not matter
	jp (hl)                  ;  4 ... both run in constant time

; ctcss encoder with RFC D/A converter

ctcss_enc_entry:

	ld bc, (ctcss_enc_phinc)
	ld hl, (ctcss_enc_phacc)
	add hl, bc
	ld (ctcss_enc_phacc), hl
	ld l, h
	ld h, #HI(ctcss_sintab)
	ld a, (hl)
	out (DA_RFC), a

ctcss_enc_skip:

	ld hl, (ctcss_dec_jump)  ; 16
	jp (hl)                  ;  4

pioa_int:

	ex af, af'                    ;  4  interrupt entry when no ctcss
	exx                      ;  4

ctcss_dec_ret:
ctcss_dec_skip:

	dec e
	jr z, systick     ;    100 Hz this
	dec d
	jr z, adc_reader  ;    500 Hz this

	ex af, af'                    ;  4
	exx                      ;  4
	ei
	reti

adc_reader:
	ld hl, #ad_select
	ld a, (hl)          ; index into ad_list[]
	inc (hl)            ; bump for next time
	and #15              ; stay inside ad_list[]
	add a, #LO(ad_list) + 1 ; from index into pointer over _next_ entry
	ld l, a
	ld h, #HI(ad_list)   ; over entry in ad_list[]
	ld c, (hl)          ; next conversion start
	dec l
	ld l, (hl)          ; previous conversion
	ld h, #HI(ad_bytes)  ; H over ad_bytes[] page
	ini                 ; read and store previous conversion - B changes !
	out (c), a          ; once to settle analog mux
	ld d, #4             ; every fourth time. also separate out insns a bit.
	out (c), a          ; start of conversion

	ex af, af'
	exx
	ei
	reti

systick:
	out (WD), a				; keep watchdog happy.

	;----------------------------
	;  Hook interest
	;
	ld hl, (pioa_data)      ; old bits to L
	in a, (PIO+ADATA)
	ld (pioa_data), a       ; save PIO ADATA, check CCIR decode again at end
	xor l					; extract change
	and #PA_HOOK
	jp z, 9f				; not changed

	; Change in hook here

	ld a, (squelch_open)
	or a
	call nz, audioc_on      ; in case repsitting has it not in sync

	ld a, (pioa_data)
	and #PA_HOOK
	ld a, #1
	jr z, 1f
	ld a, #2
1:
	ld (script_req), a       ; execute onhook/offhook-scripts later

	ld a, (cfg_light_seconds) ; light up ?
	or a
	jp z, 9f                ; 0 seconds lights on.

	call cu_lights_on
	ld hl, #sir
	set DPYSIR, (hl)		; Update CU later
9:

	;-------------------------

	ld a, (scan_on)             ; scan_timer counts ticks, possibly scan_timer_secs times 100 ticks.
	or a
	jp z, 1f                 ; not scanning
	ld a, (scan_timer)
	or a
	jp z, 1f                 ; timer not running
	dec a
	ld (scan_timer), a        ; ticks--
	jp nz, 1f                 ; if ticks not down to 0
	ld a, (scan_timer_secs)
	or a
	jr z, 1f                  ; repeat so many secs
	dec a
	ld (scan_timer_secs), a
	jr z, 1f                   ; seconds down to 0, stay 0/0
	ld a, #100
	ld (scan_timer), a         ; prep ticks for another second
1:
	;-------------------------

	ld a, (mt_timer)
	or a
	jp z, 1f
	ld a, (output_0)
	out (OUT0), a              ; XXX check this
	ld a, (mt_timer)
	dec a
	ld (mt_timer), a
	call z, stop_marker_tone
1:

	;
	;  Decrement MBUS activity timer
	;
	ld a, (mbus_timer)
	or a
	jp z, 1f
	dec a
	ld (mbus_timer), a
1:
	;
	;  ccir timer
	;
	ld a, (ccir_tx_timer)
	or a
	jp z, 1f
	dec a
	ld (ccir_tx_timer), a
1:
	;
	;  One second trail after end of xmit
	;
	ld a, (txtail_timer)
	or a
	jp z, 1f				; Not counting anymore
	ld a, (txon)
	or a
	jr nz, 1f				; Still xmit
	ld a, (txtail_timer)
	dec a
	ld (txtail_timer), a	; One 10msec less of tail
1:
	;
	;  See if keypad has data coming and debouncing
	;  allows it to be fetched
	;
	ld a, (keydown)
	or a
	jp z, 9f			; not key down
	inc a
	jr z, 1f			; been a long time, 256 softicks
	ld (keydown), a
	cp #10
	jr nz, 1f			; not at debounce-position
	ld hl, #sir
	set KEYSIR, (hl)	; go get it.
1:
	ld a, (key_timer)   ;  Typematic ?
	or a
	jp z, 9f
	dec a
	ld (key_timer), a

	call z, typematic
9:

	;	S meter and squelch control, tone decoders

	ld a, (txtail_timer)
	cp #90
	jp nc, 9f				; Skip if tx during last 100 msec
	ld a, (mton)
	or a
	jp nz, 9f				; Skip if tone on.

	call ctcss_dec_periodic
	call squelch
	call rssi_disp
	call ccir_decoder
	call dtmf_decoder
9:

	;--------------------

	; REPEATER fasttimo

	ld a, (cfg_function)
	dec a                          ; if 1
	call z, repeater_step_10msec

	;--------------------

	ld a, (sec100)
	inc a
	cp #100
	jp c, 1f		; less than full second.

	ld a, (seconds)
	inc a
	cp #60
	jp c, 2f		; less than full minute
	ld a, (minutes)
	inc a
	cp #60
	jp c, 3f
	ld a, (hours)
	inc a			; overflows to 0...
	ld (hours), a
	call once_per_hour
	xor a
3:
	ld (minutes), a
	call once_per_minute
	xor a
2:
	ld (seconds), a
	call once_per_second
	xor a
1:
	ld (sec100), a

	;--------------------

	ld e, #20	; 1969 / 100 hard ticks to next
	ld d, #3     ; fondle ADC every now and then.
	exx

	;  softlevel

	ld a, (nosir)
	or a
	jr nz, 1f		; Cannot do it now.
	ld a, (sir)
	or a
	jr nz, 2f		; there are sirs
1:
	ex af, af'
8:
	ei
	reti
2:
	bit INSIR, a
	jr nz, 1b		; already here

	set INSIR, a
	ld (sir), a		; note sir starting

	ex af, af'

	push af
	push bc
	push de
	push hl
	push ix
	push iy			; sir runs with normal regset

	call 8b
	call dosir
	di

	ld a, (sir)
	res INSIR, a
	ld (sir), a

	pop iy
	pop ix
	pop hl
	pop de
	pop bc
	pop af

	ei
	ret

dosir:

	ld hl, #sir
	bit KEYSIR, (hl)
	jr z, 1f
	res KEYSIR, (hl)
	call keypad
1:
	ld hl, #sir
	bit DPYSIR, (hl)
	jr z, 1f
	res DPYSIR, (hl)
	call display
	ld a, #1
	ld (drawn), a
1:
	ld hl, #sir
	bit DTMFSIR, (hl)
	jr z, 1f
	res DTMFSIR, (hl)
	ld a, (cu_is_alfa)
	or a
	call nz, i2c_dtmf
1:

	ret

;----------------------------------------------------------------------


;======================================================================

update_gpio12:

	; EXAL, EXIN2 and /RXON update

	ld a, (cfg_gpio1_state)         ; ____ ___a
	and #1
	rrca                            ; a___ ____
	rrca                            ; _a__ ____
			ASSERT_EQ(PB_EXAL, 0x40)
	ld h, a

	ld a, (cfg_gpio2_state)         ; ____ __cb
	and #1
	rlca                            ; ____ __b_
	rlca                            ; ____ _b__
	rlca                            ; ____ b___
	rlca                            ; ___b ____
			ASSERT_EQ(PB_RXOFF, 0x10)
	or h                            ; _a_b ____
	out (PIO+BDATA), a

	ld a, (cfg_gpio2_state)         ; third bit is open collector like EXIN1
	and #2
	jp nz, release_EXIN2
	jp pull_down_EXIN2

pulse_gpio1:

	; EXAL -> 1 -> 0 without disturbing EXIN2

	ld a, (cfg_gpio2_state)         ; ____ __cb do not touch this
	and #1
	rlca                            ; ____ __b_
	rlca                            ; ____ _b__
	rlca                            ; ____ b___
	rlca                            ; ___b ____
			ASSERT_EQ(PB_RXOFF, 0x10)

	or #PB_EXAL                      ; _a_b ____
	out (PIO+BDATA), a

	nop
	nop
	nop
	nop
	nop

	and #~PB_EXAL                    ; _a_b ____
	out (PIO+BDATA), a

	xor a
	ld (cfg_gpio1_state), a         ; always ends up as zero when this command is used

	ret

;======================================================================

; 0 = dsp, 1 = -TMR0, 2 = +TMR0
; NZ = detecting

read_ctcss_detect:

	ld a, (cfg_ctcss_input_method)
	dec a              ; funny 3-way test
	jp m, 2f           ; sign if method was 0
	in a, (PIO+BDATA)  ; does not affect Z flag from dec a
	jr z, 1f           ; zero if method was 1 = positive logic
	xor #PB_TMR0        ; method 2, invert bit for negative logic
1:
	and #PB_TMR0        ; isolate bit
	ret                ; NZ if pin was "active"
2:
	ld a, (ctcss_dec_status)
	or a
	ret                ; NZ if status "1"

read_squelcher_value:
	ld a, (squelch_tightening)
	ld b, a

	ld a, (cfg_squelch_source)	; +SQL, -SQL or +RSSI
	sub #1
	jr z, 2f                    ; src=1 -SQL
	jr c, 1f                    ; src=0 +SQL

	ld a, (ad_rssi)             ; src=2 +RSSI
	sub b
	ret nc
	xor a
	ret
1:
	ld a, (ad_sql)
	sub b             ; I'm positive Benjamin will not accept this :)
	ret nc
	xor a
	ret
2:
	ld a, (ad_sql)
	cpl
	sub b
	ret nc
	xor a
	ret

;----------------------------------------------------------------------

; _x = x for the firmware symbols the C modules use (tools/cglue.py)
#include "cglue.inc"

squelch_is_closed:
	ld a, #0
	ld (squelch_open), a
	ld (repeater_sitters_special), a
	ld a, (cfg_squelch_head)
	ld (squelch_delay), a
	ret

squelch_is_open:
	ld a, #1
	ld (squelch_open), a
	ld a, (cfg_squelch_tail)
	ld (squelch_delay), a
	ld a, #0
	ld (idle_timer), a
	ret

audioc_on:
	ld a, (output_0)
	or #O0_AUDIOC
	ld (output_0), a
	out (OUT0), a
	ret

audioc_off:
	ld a, (output_0)
	and #~O0_AUDIOC
	ld (output_0), a
	out (OUT0), a
	ret

start_repeater_sitters_special:
	ld a, (cfg_repeater_sitters_special) ; 0 or seconds of audio passed thru.
	neg                                  ; 0->0, 1->255, ...
	                                  ; count up until overflow, then cut audio
	ld (repeater_sitters_special), a     ; 0 or counter value
	ret

;
;  Cut audio during TX (maybe)
;

tx_cut_local_audio:
	ld a, (cfg_function)
	or a
	jr z, 1f                ; function is 0 = "Std", continue close audio and disable squelch
	dec a
	ret nz                  ; function is not 1 = "rPtr" but "Slave", keep audio with no regard to tx

	ld a, (cfg_repeater_wierd_simplex)
	or a
	ret z                   ; Normal "rPtr", keep audio
1:
	call close_squelch_really

	ld a, (output_0)
	and #~ O0_AUDIOC
and #~ O0_CCIRC
	ld (output_0), a
	out (OUT0), a           ; cut audio

	ld a, #100
	ld (txtail_timer), a	; shall count 1 second after tx ends
	ret

;---------------------

mic_off_ccir_off:
	di
	ld a, (output_0)
	and #~O0_CCIRC
	or #O0_MICM
	jr 1f

mic_on:
	di
	call silence_timer1
	ld a, (output_0)
	and #~(O0_CCIRC | O0_MICM)	; No tones, no mic mute
	jr 1f

mic_off:
	di
	ld a, (output_0)
	or #O0_MICM
	jr 1f

ccir_on:
	di
	ld a, (output_0)
	or #O0_CCIRC
	jr 1f

ccir_off:
	di
	call silence_timer1
	ld a, (output_0)
	and #~O0_CCIRC
	jr 1f

mtc_on:
	di
	ld a, (output_0)
	or #O0_MTC
	jr 1f

mtc_off:
	di
	call silence_timer1
	ld a, (output_0)
	and #~O0_MTC
1:
	ld (output_0), a
	out (OUT0), a
	ei
	ret

;----------------------------------------------------------------------
; from systick.
; peak rssi during an over
; smoothing rssi display

rssi_disp:

	ld a, (ad_rssi)
	ld b, a

	ld hl, #repeater_sig
	cp (hl)                 ; ad_rssi - repeater_sig
	jr c, 1f                ; if currently lower
	ld (hl), a              ; remember peak
1:
	ld a, (srssi)
	cp b					; smoothed - rssi
	jr c, 1f				; go if raising
	ld a, (rssi_timer)
	dec a
	jr nz, 2f				; go if still timing
1:
	ld a, #1
	ld (redraw_req), a
	ld a, b
	ld (srssi), a
	ld a, #50			; one second
2:
	ld (rssi_timer), a
	ret

;----------------------------------------------------------------------
;
;	CCIR decoder called 100 times a second from systick if tx is off
;
ccir_decoder:
	ld a, (ccir_tonetime)
	ld d, a               ; duration to d
	inc a
	jr z, 1f
	ld (ccir_tonetime), a ; length of serie 10 msec longer
1:
	ld a, (pioa_data)
	and #PA_CCIR           ; CCIR bits from the top of systick
	ld b, a
	in a, (PIO+ADATA)
	and #PA_CCIR           ; current bits
	cp b
	ret nz                ; CCIR bits are changing

	cp #0xF0               ; restart duration if notone
	jr nz, 1f
	xor a
	ld (ccir_tonetime), a
1:

	ld a, (ccir_prevdata) ; old ccir bits
	cp b
	ret z                 ; same bits as old
	ld a, b
	ld (ccir_prevdata), a ; remember these new bits

	; 'inc l' is used a lot below, to walk in the 256-byte ringbuffer

	ld h, #HI(ccir_history)           ; KEPT VALID A LONG TIME
	ld a, (ccir_hist_idx)
	ld l, a
	inc a
	ld (ccir_hist_idx), a ; idx points to next free slot

	ld a, b               ; new bits
	cp #0xF0
	jr z, 1f              ; tone F

	; NEW TONE

	cp #0xE0
	jr nz, 2f                ; not repeat
	dec l
	ld a, (hl)               ; peek previous chr
	inc l
	cp #' '
	jr nz, 3f                ; repeat with previous tone
	ld a, #0xE0               ; huh ? starts with repeat
2:
	rra
	rra
	rra
	rra
	ASSERT_EQ(PA_CCIR, 0xf0)
	and #0xF
3:
	ld (hl), a
	ret
1:
	; NOTONE

	ld (hl), #' '

	ld a, (cfg_ccir_minlen)  ; accept only N csec or longer series
	cp d                     ; minimum_time - duration
	jr c, 1f
	ld a, (ccir_toneptr)
	ld (ccir_hist_idx), a    ; next tone will overwrite this bad one
	ret
1:
	; okay decode

	call ccir_ok_serie

	ld a, (ccir_hist_idx)
	ld (ccir_toneptr), a     ; next serie starts here (after blank)
	dec a
	ld (ccir_hist_finger), a ; reposition peeking finger also (over blank)
	ret

ccir_ok_serie:

	; check ours

	ld de, #cfg_ccir_1
	call compare_ccir_serie
	jp z, ccir_match
	ld de, #cfg_ccir_2
	call compare_ccir_serie
	jp z, ccir_match
	ld de, #cfg_ccir_3
	call compare_ccir_serie
	jp z, ccir_match

	ld de, #cfg_repeater_suspend_ccir_cmd
	call compare_ccir_serie
	jp z, repeater_toggle_suspend

	ld de, #repeater_cfg_ccir_cmd_pfx
	call compare_ccir_prefix
	jp z, ccir_repeater_cmd              ; cmd in A

	ld de, #cfg_gpio1_ccir_pulse_cmd
	call compare_ccir_serie
	jp z, gpio1_pulse_command

	ld de, #cfg_gpio1_ccir_cmd_pfx
	call compare_ccir_prefix
	jp z, gpio1_command              ; cmd in A

	ld de, #cfg_gpio2_ccir_cmd_pfx
	call compare_ccir_prefix
	jp z, gpio2_command              ; cmd in A

	ret

compare_ccir_serie:
	ld a, (ccir_toneptr)
	ld l, a
	jr compare_tone_serie

compare_dtmf_serie:
	ld a, (dtmf_toneptr)
	ld l, a
	jr compare_tone_serie

compare_tone_serie:
	ld a, (de)
	cp (hl)
	jr nz, 1f
	inc de
	inc l
	ld a, (de)
	cp (hl)
	jr nz, 1f
	inc de
	inc l
	ld a, (de)
	cp (hl)
	jr nz, 1f
	inc de
	inc l
	ld a, (de)
	cp (hl)
	jr nz, 1f
	inc de
	inc l
	ld a, (de)
	cp (hl)
	jr nz, 1f
	inc de
	inc l
	ld a, (de)
	cp (hl)
	jr nz, 1f
	inc de
	inc l
	ld a, (de)
	cp (hl)
	jr nz, 1f
	inc de
	inc l
	ld a, (de)
	cp (hl)
	jr nz, 1f
	inc de
	inc l
	ld a, #' '
	cp (hl)    ; heard one must also end
	ret
1:
	cp #EOS     ; if mismatch, both strings must be at end
	ret nz     ; cfg continues
	ld a, #' '  ; cfg ends, heard one must also
	cp (hl)
	ret

	; return Z if prefix match, A = command byte

compare_ccir_prefix:
	ld a, (ccir_toneptr)
	ld l, a
	jr compare_tone_prefix

compare_dtmf_prefix:
	ld a, (dtmf_toneptr)
	ld l, a
	jr compare_tone_prefix

compare_tone_prefix:
	ld a, (de)
	cp (hl)
	jr nz, 2f
	inc de
	inc l   ; first one must be valid
	ld a, (de)
	cp (hl)
	jr nz, 1f
	inc de
	inc l
	ld a, (de)
	cp (hl)
	jr nz, 1f
	inc de
	inc l
	ld a, (de)
	cp (hl)
	jr nz, 1f
	inc de
	inc l
	ld a, (de)
	cp (hl)
	jr nz, 1f
	inc de
	inc l
	ld a, (de)
	cp (hl)
	jr nz, 1f
	inc de
	inc l
	ld a, (de)
	cp (hl)
	jr nz, 1f
	inc de
	inc l
	ld a, (de)
	cp (hl)
	jr nz, 1f
	inc de
	inc l

	; prefix was full 8 characters. Z condition from above cp.

	ld a, (hl)
	ret         ; Z = match, A has command
1:
	cp #EOS     ; if mismatch, cfg must be at end.
2:
	ret nz     ; cfg continues, heard was too short, return NZ

	ld a, (hl) ; cfg ends, heard one must NOT end, but have single tone left.
	cp #' '
	jr nz, 1f    ; Z if heard has blank (end of sequence)
	ld a, #'#'
	ret        ; Z, prefix match fully, no explicit command == command #
1:
	cp a       ; command digit ok, set Z condition.
	ret


ccir_match:
	ld a, #2
	ld (ding_req), a
	call start_call_timer
	ret

start_call_timer:
	ld (call_dpyed), a
	ld a, #0
	ld (call_timer_sec), a
	ld (call_timer_min), a
	ld (call_timer_hour), a
	ret

ccir_decoder_init:
	ld hl, #ccir_history
	ld a, #' '
1:
	ld (hl), a
	inc l
	jr nz, 1b
	ret

;======================================================================

dtmf_decoder_init:
	ld hl, #dtmf_history
	ld a, #' '
1:
	ld (hl), a
	inc l
	jr nz, 1b
	xor a
	ld (dtmf_prevdata), a ; start from notone
	ret

dtmf_decoder:
	ld a, (cur_bank)
	or a
	ret nz            ; multiboard not in the window: skip this sample
	ld h, #HI(0x8000)  ; address LSbyte is dont care
	ld a, (hl)        ; [0x80xx] is StD D3 D2 D1 D0 ? ? CTCSS
	cp h              ; lucky address is also mask for StD
	jr nc, 1f         ; if StD high
	xor a
	ld (dtmf_prevdata), a ; no StD, allow dtmf_idletime to grow
	ret
1:
	and #0xF8
	ld b, a         ; b is StD Q4...1 X X X

	ld a, #1
	ld (dtmf_idletime), a ; rewind dtmf notone timer

	ld a, (dtmf_prevdata)
	cp b
	ret z           ; same as old

	ld a, b
	ld (dtmf_prevdata), a ; remember as old
	rra
	rra
	rra             ; 0 0 0 StD Q4 Q3 Q2 Q1
	and #0x0F

	ld hl, #dtmf_8870_tab
	ASSERT_LT(LO(dtmf_8870_tab), 240) ; L wont carry
	add a, l
	ld l, a
	ld b, (hl)        ; map into digit or code

	ld h, #HI(dtmf_history)
	ld a, (dtmf_hist_idx)
	ld l, a
	inc a
	ld (dtmf_hist_idx), a ; idx points to next free slot now
	ld (hl), b       ; stash digit/code

	ret

dtmf_decoder_timeout:

	ld h, #HI(dtmf_history)
	ld a, (dtmf_toneptr)
	ld b, a

	ld a, (dtmf_hist_idx)
	ld l, a
	ld (dtmf_hist_finger), a ; finger points to blank after codes
	inc a
	ld (dtmf_hist_idx), a ; idx points to next free slot now
	ld (dtmf_toneptr), a  ; ptr also

	ld (hl), #' '          ; stash digit/code

	ld l, b
	call dtmf_commands
	ret

;======================================================================

pull_down_EXIN1:
	ld hl, #piob_mode
	res PB_BIT_EXIN1, (hl) ; i/o selection, 1 for input, 0 for output
	jr 1f

release_EXIN1:
	ld hl, #piob_mode
	set PB_BIT_EXIN1, (hl) ; i/o selection, 1 for input, 0 for output
	jr 1f

pull_down_EXIN2:
	ld hl, #piob_mode
	res PB_BIT_EXIN2, (hl) ; i/o selection, 1 for input, 0 for output
	jr 1f

release_EXIN2:
	ld hl, #piob_mode
	set PB_BIT_EXIN2, (hl) ; i/o selection, 1 for input, 0 for output
	jr 1f

pull_down_DCU:
	ld hl, #piob_mode
	res PB_BIT_DCU, (hl)   ; i/o selection, 1 for input, 0 for output
	jr 1f

release_DCU:
	ld hl, #piob_mode
	set PB_BIT_DCU, (hl)   ; i/o selection, 1 for input, 0 for output
1:
	ld a, #0xCF			   ; operating mode 3
	out (PIO+BCTRL), a
	ld a, (hl)
	out (PIO+BCTRL), a
	ret

;======================================================================

main:
	ei

	call probe_cu58af

	call ccir_decoder_init
	call dtmf_decoder_init
	call enable_modem

	call set_vola
#ifdef BANK_TEST
	call bank_test		; before anything runs from bank 1
	jp nz, bank_test_stop
#endif
	call far_init_menu
	call init_LPF
	call zero_txpwr

	call cu_now_known
1:
	call is_key_down
	jr nz, 1b			; wait release
	call is_ptt_pressed
	jr nz, 1b			; wait release

	call halt_txsynth
	call set_channel_step
	call changed_frequency_duplex_okay
	call cu_manipulated
	call light_on_led
	call resync_squelch_if_forced
	call repeater_init
	call far_update_gpio12_foo

	call gps_configure     ; once and ...

	call redraw
	call redraw
1:
	ld a, (seconds)
	or a
	jr z, 1b               ; ================ BOOTUP DELAY 1 SECOND =======

	call gps_configure     ; again.

	ld a, (scan_on)
	or a
	jr z, 1f
	xor a
	ld (scan_on), a
	call scanner_start
1:

	call ctcss_dec_startstop

#ifdef BANK_TEST
	call bank_test
#endif

mainloop:
	jp _mainloop		; c/mainloop.c: the loop and its checks

;======================================================================

gps_configure:

	ld a, (cfg_gps_config)
	cp #4                                ; 9600Std was 4 until AiSin went
	jr nz, 1f                            ; (2026-10-01): NV from before
	dec a
	ld (cfg_gps_config), a
1:
	dec a                                ; if 1
	jr z, gps_configure_SiRF_generic
	dec a                                ; if 2
	jr z, gps_configure_SiRF_tailored
	dec a                                ; if 3 9600 gps riku
	jr z, gps_configure_std_9600

;        ld a, 4            ! restore SIO A into 4800 riku
;        out [SIO+ACTRL], a
;        ld a, WR4_1STOPBIT | WR4_X16_CLK
;        out [SIO+ACTRL], a

	ret

	;
	;  GPS Configuration for standard 9600 nmea, add OH1E
	;
gps_configure_std_9600:

	di

        ld a, #4            ; SET SIO A into 9600 by riku
        out (SIO+ACTRL), a
        ld a, #WR4_1STOPBIT | WR4_X16_CLK  ; Set proper settings for serial line
        out (SIO+ACTRL), a   		  ; write out the bitstream

	ei		   ; ?
	ret


	;
	;  32 bytes sent at 38400 baud
	;  Shorts are MSByte first.
	;
gps_init_block_SiRF_size = 32

gps_init_block_SiRF_generic:

	.db 0xA0, 0xA2 ; Start Sequence
	.db 0x00, 0x18 ; Payload Length - 24 bytes

	.db 0x81       ; Message ID - Switch To NMEA
	.db 0x02       ; Mode 2 - what is this ?
	.db 0x01, 0x01 ; GGA interval and checksum flag
	.db 0x00, 0x01 ; GGL interval and checksum flag
	.db 0x05, 0x01 ; GSA interval and checksum flag
	.db 0x01, 0x01 ; GSV interval and checksum flag
	.db 0x02, 0x01 ; RMC interval and checksum flag
	.db 0x00, 0x01 ; VTG interval and checksum flag
	.db 0x00, 0x01 ; MSS interval and checksum flag
	.db 0x00, 0x01 ; Unused Field
	.db 0x00, 0x01 ; Unused Field
	.db 0x00, 0x01 ; Unused Field
	.db 0x12, 0xC0 ; Baud Rate - 4800 baud

    .db 0x01, 0x68 ; Message Checksum - 15bit sum of payload (not 16bit)
    .db 0xB0, 0xB3 ; End Sequence

gps_init_block_SiRF_tailored:

	.db 0xA0, 0xA2 ; Start Sequence
	.db 0x00, 0x18 ; Payload Length - 24 bytes

	.db 0x81       ; Message ID - Switch To NMEA
	.db 0x02       ; Mode 2 - what is this ?
	.db 0x00, 0x01 ; GGA interval and checksum flag
	.db 0x00, 0x01 ; GGL interval and checksum flag
	.db 0x00, 0x01 ; GSA interval and checksum flag
	.db 0x00, 0x01 ; GSV interval and checksum flag
	.db 0x01, 0x01 ; RMC interval and checksum flag - only this every second
	.db 0x00, 0x01 ; VTG interval and checksum flag
	.db 0x00, 0x01 ; MSS interval and checksum flag
	.db 0x00, 0x01 ; Unused Field
	.db 0x00, 0x01 ; Unused Field
	.db 0x00, 0x01 ; Unused Field
	.db 0x12, 0xC0 ; Baud Rate - 4800 baud

    .db 0x01, 0x60 ; Message Checksum - 15bit sum of payload (not 16bit)
    .db 0xB0, 0xB3 ; End Sequence

	; 38400 baud equals 26.0xxx microsec per bit
	; 4032000 / 38400 = 105T on P8N
	; 8064000 / 38400 = 210T on P8E
	;
	; D and E registers for 4T access, equalizing the 'jr c' branches below.
	; 'jr c' brances are not quite equal on P8N, but 12 vs. 7+4.
	; 0-bits are more important, area is counted as 11T.
	; * marks CB or ED prefix, one additional T on P8E.
	; x marks padding

gps_configure_SiRF_generic:
	ld ix, #gps_init_block_SiRF_generic
	jr 1f

gps_configure_SiRF_tailored:
	ld ix, #gps_init_block_SiRF_tailored

1:
	ld l, #gps_init_block_SiRF_size

	ld d, #WR5_8BIT_TX | WR5_RTS | WR5_DTR | WR5_TX_ENB
	ld e, #WR5_SEND_BREAK

	di                 ; =================================================

	ld a, #4            ; crispy BRK twiddling needs this TXCLK change
	out (SIO+ACTRL), a
	ld a, #WR4_1STOPBIT | WR4_X1_CLK
	out (SIO+ACTRL), a

3:
	ld b, #1+8+2        ; start + data + stop. stop at end always clears BRK
	and a              ; clear CY = startbit, will be first
	ld c, (ix)         ; 8 databits
	inc ix             ; p++

	out (WD), a        ; P8N   P8E ====== each byte atomically ========
2:
	ld a, #5            ;  7T    8T WR5 pointer
	out (SIO+ACTRL), a ; 11T   12T point at WR5

	ld a, d            ;  4T    5T
	jr c, 1f           ; 12/7T 13/8T these two lines are
	or e               ;    4T    5T 11T on P8E (XXX) and 13T on P8E (exact)
1:
	out (SIO+ACTRL), a ; 11T   12T updated

	ld a, (cpu_is_P8E) ; 13Tx  14Tx burn some cycles for
	or a               ;  4Tx   5Tx total loop time of 1/38400 seconds
	jp z, 1f           ; 10Tx  11Tx
	ex (sp), hl        ;       20Tx
	ex (sp), hl        ;       20Tx even number of these dummies :)
	ex (sp), hl        ;       20Tx
	ex (sp), hl        ;       20Tx even number of these dummies :)
	ld a, d            ;        5Tx
	ld a, d            ;        5Tx
1:
	ld a, i           ;  9Tx  11Tx*   ...end of padding.

	scf                ;  4T    5T stopbits filled in from left
	rr c               ;  8T   10T* bits sent from right - LSbit first
	djnz 2b            ; 13T   14T bitloop

	; Total              96T  109T without Tx ====== byte sent ==========

	dec l
	jp nz, 3b          ; byteloop

	ld a, #4            ; restore SIO A into 4800
	out (SIO+ACTRL), a
	ld a, #WR4_1STOPBIT | WR4_X32_CLK
	out (SIO+ACTRL), a

	ei                 ; =================================================

	ret

;----------------------------------------------------


; GPS sentence processing: c/gps.c, bank 2.
gpsc_sentence:			; c/mainloop.c: A = length
	call bank2_call
	.dw _gps_process_sentence
	ASSERT_EQ(gps_sentence_size, 100)
	ASSERT_EQ(LONG_PACLEN, 15)
	ASSERT_EQ(SIZE_STR, 8)


gpio1_pulse_command:

	ld a, #0xFE
	ld (repeater_req), a

	jp pulse_gpio1

gpio1_command:
	and #0x0F         ; '1' and 1 no different

	cp #2
	ret nc           ; 0 and 1 are valid

	ld (cfg_gpio1_state), a

	ld a, #0xFE
	ld (repeater_req), a

	jp update_gpio12

gpio2_command:
	and #0x0F         ; '1' and 1 no different

	cp #4
	ret nc           ; 0,1,2 and 3 are valid

	ld (cfg_gpio2_state), a

	ld a, #0xFE
	ld (repeater_req), a

	jp update_gpio12

;----------------------------------------------------------------------


;----------------------------------------------------------------------

marker_300hz_1s:		; c/timers.c battcheck, c/ptt.c tx_error: 300 Hz, 1 s
	ld hl, #MT_300HZ
	ld d, #100
	jp start_marker_tone

;======================================================================


;======================================================================


is_key_down:
	ld a, (keydown)
	or a
	ret nz               ; NZ key down
	call clear_key
	cp a
	ret                  ; Z not

waitkey:
1:
	ld a, (key_time)
	cp #255
	call z, feedback_let_go_the_darn_button
	call redraw
	call is_key_down
	jr nz, 1b
	ret

is_ptt_pressed:                  ; NZ if either ptt pressed. A trashed

	ld a, (sio_bctrl_mirror)
	and #SB_PTT
	ret nz                       ; /CTSB is 1 if /PTT

	ld a, (cu58af_buttons)
	and #CU58AF_TANGENT
	ret                          ; 1 if alpha-ptt pressed

;----------------------------------------------------------------------

cu_manipulated:
	xor a
	ld (ign_apo_timer), a
	ld (idle_timer), a
	ld (call_dpyed), a
	ld (display_buffer_time), a
	ld (locator_dpyed), a
	call cu_call_off
	call cu_lights_on
	ret

;----------------------------------------------------------------------


;----------------------------------------------------------------------


;----------------------------------------------------------------------

set_vola:
	xor a
1:
	ld hl, #volume
	add a, (hl)

set_vola_a:
	cp #10
	jr z, 1f		; 9 -> 10
	jr c, 2f		; 0 -> -1
	xor a
	jr 2f
1:
	ld a, #9
2:
	ld (volume), a
	cp #0
	jr z, 1f
	cp #1
	jr z, 2f
	sub #2				; 9 - 2 -> 7
	and #7
	ld b, a
	di
	ld a, (output_0)
	and #~O0_VOLUME
	and #~O0_INH
	or b
	ld (output_0), a
	out (OUT0), a
	ld hl, #sir
	set DTMFSIR, (hl)
	ei
	ret
1:
	di
	ld a, (output_0)
	and #~O0_VOLUME
	or #O0_INH
	ld (output_0), a
	out (OUT0), a
	ld hl, #sir
	set DTMFSIR, (hl)
	ei
	ret
2:
	di
	ld a, (output_0)
	and #~O0_VOLUME
	and #~O0_INH
	ld (output_0), a
	out (OUT0), a
	ld hl, #sir
	set DTMFSIR, (hl)
	ei
	ret

;----------------------------------------------------------------------


;----------------------------------------------------------------------

clear_buffer:
	push af
	xor a
	ld (digidx), a
	pop af
	ret

clear_key:
	push af
	ld a, #-1
	ld (key), a
	pop af
	ret



;======================================================================
;

;----------------------------------------------------------------------

load_num_tmp_rejects:

	ld a, (cfg_num_tmp_rejects)
	or a
	jr z, 1f                ; 0 = max
	cp #NUM_TMP_REJECTS
	ret c                   ; less than max allowed
1:
	ld a, #NUM_TMP_REJECTS   ; array has only this many available
	ret

;
; Decay temporary rejects
;
unreject_timer:
	ld hl, #tmp_rejects
	call load_num_tmp_rejects
	ld b, a
2:
	inc hl
	inc hl
	inc hl        ; over SIZE_FREQ
	ld a, (hl)
	sub #1
	jr c, 1f      ; was 0, stay 0 (inactive reject)
	cp #254
	jr z, 1f      ; was 255, stay 255 (semi-permanent reject)
	ld (hl), a    ; 1...254: step down
1:
	inc hl        ; over timer byte
	djnz 2b
	ret


;======================================================================
; 
;  FSK stuff

fskcheck:
	ld a, (packet_rdy)
	or a
	ret z
	call far_packet_for_whom
	xor a
	ld (packet_rdy), a		; Ignores quick successive packets
	ret

init_modem:
	;
	;  Initialize NMT modem
	;

	ld a, #0x04
	out (MDM + MDMCTRL), a		; Write 04 to control register

	ld hl, #10000
1:
	out (WD), a

	dec hl
	ld a, h
	or l
	jr nz, 1b					; Wait at least 1 bit.

	ld a, #0x00
	out (MDM + MDMCTRL), a		; Write zeros to control register

	ret

re_enable_modem:

	ld hl, #packet
	ld (pkt_ptr), hl		; rewind packet pointer

	ld a, #MDM_XXX
	out (MDM + MDMCTRL), a  ; disable modem

	; fallthru

enable_modem: ;  Enable modem receiver

	ld a, #MDM_RXENB
	out (MDM + MDMCTRL), a
	ret

;----------------------------------------------------------------------

get_next_cfg_6bits:

	ld a, (hl)
	inc hl

	cp #EOS
	jr nz, 1f
	ld a, #' '
	jr 2f          ; pad short strings with blanks
1:
	cp #16
	jr nc, 2f      ; already ascii
	cp #10
	jr nc, 1f
	add a, #'0'
	jr 2f          ; 0 ... 9 into '0' ... '9'
1:
	add a, #'A' - 10   ; 0xA ... 0xF into 'A' ... 'F'. This has gotten silly.
2:
	sub #' '        ; into 6 bits.
	and #0x3F       ; paranoia
	ret

store_next_6bits:

	and #0x3F       ; required.
	add a, #' '
	ld (de), a
	inc de
	ret

; FSK packet dispatch, remote config and MPRS sending: c/fsk.c, bank 2.
	FAR(far_packet_for_whom, bank2_call, _packet_for_whom)
	FAR(far_send_remote_config_packets, bank2_call, _send_remote_config_packets)
	FAR(far_send_mprs_report_packet_maybe, bank2_call, _send_mprs_report_packet_maybe)
	FAR(far_send_mprs_report_packet, bank2_call, _send_mprs_report_packet)
	FAR(far_send_call_packet, bank2_call, _send_call_packet)
	ASSERT_EQ(SHORT_PACLEN, 8)

;  c/fsk.c shims: register interfaces as --sdcccall 1 passes them
mbus_putchar:			; A: MBUS putchar takes C
	ld c, a
	jp putchar
fsk_send:			; A: send_packet_buffer takes the length in B
	ld b, a
	jp send_packet_buffer
tx_on_failed:		; A = 0xFF if tx_on returned carry
	call tx_on
	sbc a, a
	ret
mprs_timer_not_yet:		; A = 0xFF if check_for_mprs_timer says not yet
	call check_for_mprs_timer
	sbc a, a
	ret
fsk_menu_ptr:			; DE = value pointer of the current menu record
	call bank1_call
	.dw _menu_value_ptr
fsk_remote_config_execute:	; HL = ptr, DE = data, as c/menu.c takes them
	call bank1_call
	.dw _remote_config_execute

mute_fsk_at_sync_maybe:
	ld a, (cfg_fsk_silencer)
	dec a                         ; if 1
	jr z, 1f
	ret                           ; not at ALL

mute_fsk_at_tag_maybe:
	ld a, (cfg_fsk_silencer)
	cp #2
	jr z, 1f
	ret                           ; not at PrbEG
1:
	ld a, (squelch_open)
	or a
	ret z                         ; squelch was already closed (???)
	ld a, (squelch_forced)
	or a
	ret nz                        ; squelch is forced open.

	call close_squelch_really

	; make sure squelch stays closed until the frame ends and then some

	ld a, (squelch_delay)
	cp #20                    ; 200 msec
	ret nc                   ; not less than that already
	ld a, #20
	ld (squelch_delay), a    ; stretch it
	ret

	; following called from mainline fsk_check

mute_fsk_at_mprs_end_maybe:
	ld a, (cfg_fsk_silencer)
	cp #3
	jr z, 1f
	ret                           ; not at PrEnd
1:
	ld a, (squelch_open)
	or a
	ret z                         ; squelch was already closed (???)

	jp close_squelch              ; all of frame has been received,
	                              ; no need to diddle with squelch open delay


; MPRS/APRS/MIC-E packets and locator maths: c/aprs.c, bank 2 (called
; there by c/fsk.c and c/gps.c).
aprs_crc:			; c/aprs.c: A = length, DE -> data; DE = A | C << 8
	push de
	pop ix
	ld b, a
	call calc_ax25_crc
	ld e, a
	ld d, c
	ret
gps_upload_start:		; c/aprs.c: HL -> the sentence (one store: the SIO
	ld (gps_upload_ptr), hl	; interrupt sends it)
	ld a, #'$'
	out (SIO+ADATA), a
	ret

; Config packet filling and the call packet lives in bank 1 (search "BANK 1").

;----------------------------------------------------------------------
;
;  crc = crchi ^ crc16_table[crclo ^ c]
;
#define INIT_CRC ld a, #0xFF @ ld b, a

#define ADD_CRC(n) \
	ld h, #HI(crctbls) @     \
	xor (ix + (n)) @         \
	ld l, a @                        \
	ld a, b @                        \
	ld b, (hl) @                     \
	inc h @                          \
	xor (hl) @


	; buffer at IX, length B (must be 1 or more).
	; result to A and C.
	; IX incremented just past data, B zeroed.
	; F, HL and B trashed.

calc_ax25_crc:

	ld a, #0xFF
	ld c, a            ; iv FFFF

calc_ax25_crc_continue:

	ld h, #HI(crctbls)
	ASSERT_EQ(LO(crctbls), 0)
1:
	xor (ix)
	inc ix
	ld l, a
	ld a, c
	ld c, (hl)
	inc h              ; the other table
	xor (hl)
	dec h              ; back to the first table
	djnz 1b

	ret



	; af hl allowed to changed

check_short_packet:
	push bc
	push de
	push ix

	ld ix, #packet
	INIT_CRC

	ADD_CRC(0)
	ADD_CRC(1)
	ADD_CRC(2)
	ADD_CRC(3)
	ADD_CRC(4)
	ADD_CRC(5)

	cpl
	cp (ix + 7)
	jr nz, 1f
	ld a, b
	cpl
	cp (ix + 6)
	jr nz, 1f

	ld a, #MDM_RXENB
	out (MDM + MDMCTRL), a

	ld hl, #packet
	ld (pkt_ptr), hl		; its short, rewind packet pointer

	ld b, #6
	call check_packet
1:
	pop ix
	pop de
	pop bc
	ret

check_long_packet:
	push bc
	push de
	push ix

	ld a, (packet+0)
	cp #0xEC
	INIT_CRC
	jr nz, 1f
	ld ix, #cfg_remote_passwd
	ADD_CRC(0)
	ADD_CRC(1)
	ADD_CRC(2)
	ADD_CRC(3)
	ADD_CRC(4)
	ADD_CRC(5)
	ADD_CRC(6)
	ADD_CRC(7)
1:
	ld ix, #packet

	ADD_CRC(0)
	ADD_CRC(1)
	ADD_CRC(2)
	ADD_CRC(3)
	ADD_CRC(4)
	ADD_CRC(5)
	ADD_CRC(6)
	ADD_CRC(7)
	ADD_CRC(8)
	ADD_CRC(9)
	ADD_CRC(10)
	ADD_CRC(11)
	ADD_CRC(12)

	cpl
	cp (ix + 14)
	jr nz, 1f
	ld a, b
	cpl
	cp (ix + 13)
	jr nz, 1f

	ld b, #13
	call check_packet
1:
	pop ix
	pop de
	pop bc

	ld hl, #packet
	ld (pkt_ptr), hl		; short or long, rewind packet pointer

	ld a, #MDM_RXENB
	out (MDM + MDMCTRL), a

	ret

check_packet:

	ld a, (fsk_hist_idx)
	ld (packet_good), a
	ld l, a
	ld h, #HI(fsk_history)
1:
	ld a, (ix+0)
	rra
	rra
	rra
	rra
	and #0xF
	ld (hl), a
	inc l

	ld a, (ix+0)
	and #0xF
	ld (hl), a
	inc l

	inc ix
	djnz 1b

	ld (hl), #' '
	ld a, l
	ld (fsk_hist_finger), a  ; reposition viewing also, over blank
	inc a
	ld (fsk_hist_idx), a     ; insert point after blank
	ld a, #1
	ld (packet_rdy), a
	ld a, (srssi)
	ld (packet_rssi), a
	ret

send_packet_buffer:

	push bc                     ; length in b

	ld hl, #nosir
	set 0, (hl)

	ld a, #MDM_TXENB
	out (MDM + MDMCTRL), a

	ld hl, #packet_header
	ld b, #packet_header_size
	call send_some_data

	ld hl, #outpacket
	pop bc
	call send_some_data

	ld hl, #nosir
	res 0, (hl)

	call mdm_delay
1:
	in a, (MDM + MDMCTRL)
	and #MDM_TXIDL
	jr z, 1b

	ld hl, #packet
	ld (pkt_ptr), hl		; rewind packet pointer

	ld a, #MDM_RXENB
	out (MDM + MDMCTRL), a

	ret

packet_header:
	.db 0b10101010    ; 8 syncbits XXX 16 should be enough.
	.db 0b10101010    ; 8 syncbits
	.db 0b10101010    ; 8 syncbits, total 24. total was 40 earlier.
	.db 0b11000100
	.db 0b11010111
packet_header_size = . - packet_header

send_some_data:
1:
	call mdm_delay
	in a, (MDM + MDMCTRL)
	and #MDM_TXRDY
	jr z, 1b
	ld a, (hl)
	inc hl
	out (MDM + MDMDATA), a
	djnz 1b
	ret

mdm_delay:
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	ret

;======================================================================


;======================================================================



;----------------------------------------------------------------------


;----------------------------------------------------------------------

	;
	;  return carry, if mprs_report_timer says 'not yet'
	;
check_for_mprs_timer:

	ld de, (cfg_mprs_seconds)
	ld a, e
	or d                        ; Not configured is 0x0000
	sub #1
	ret c                       ; CY = not yet

	ld hl, (mprs_report_timer)
	and a
	sbc hl, de
	ret                         ; timer at or above threshold = no carry

;  c/ptt.c shims
ptt_1750_tone:
	ld hl, #MT_1750HZ
ptt_tone_count:			; HL = 8254 counter 1 count
	di
	xor a
	ld (mt_timer), a
	ld a, l
	out (TMR + 1), a
	ld a, h
	out (TMR + 1), a
	ei
	ret
ptt_tx_band_step:		; the TX band's channel step into the synth set-up
	call locate_tx_band	; into IX
	ld a, (ix+9)		; logical channel step designator
	call channel_step_parms
	ld (tx_refdiv), hl
	ld (tx_bstep_cfg), bc
	ret
	ASSERT_EQ(SB_LOCAL, 0x10)

;----------------------------------------------------------------------

ptt_ccir_xmit:

	call redraw

	di
	ld a, (output_0)
	push af
	and #~O0_VOLUME
	ld (output_0), a
	out (OUT0), a
	ei

	call mic_off_ccir_off

	ld a, #20                 ; 10 ms systicks, 200 ms silence before ccir
	call ccir_tx_timer_wait

	call mtc_on
	call ccir_on

	call ccir_from_digbuf_or_setup

	call ccir_off
	call mtc_off

	call silence_timer1
	call ccir_tx_timer_wait_100msec ; add one 100msec of silence for sure

	di
	pop af
	ld (output_0), a
	out (OUT0), a
	ei					; restored port 0

	ret

;
; singledigit CCIRs indirect to setup shortcuts
;
ccir_from_digbuf_or_setup:
	ld a, (digidx)             ; length of digit buffer
	dec a                      ; is it 1 ?
	jr nz, ccir_from_digbuf    ; no, send the digits in buffer

	ld d, a                    ; clear D in preparation of index add

	ld a, (digbuf+0)
	cp #10
	jr nc, ccir_from_digbuf    ; only 0 ... 9 can be shortcuts

	rlca                       ; 2 times
	rlca                       ; 4 times
	rlca
	ASSERT_EQ(SIZE_STR, 8)
	        ASSERT_LT(9 * 8, 256)
	ld e, a
	ld ix, #cfg_shortcut_0      ; base offset of indirect strings
	add ix, de
	ld b, #SIZE_STR             ; length limit
	jr 1f                      ; skip over to action

	; JUMPOVER

ccir_from_digbuf:
	ld ix, #digbuf       ; Start of digits
	ld a, (digidx)
	ld b, a             ; Digit count
1:
	ld c, #EOS           ; No prev digit
2:
	ld a, (ix)          ; Pick a digit
	inc ix
	cp #EOS
	ret z               ; Setup has EOS and limit, digbuf only count
	cp c                ; Same as previous digit ?
	jr nz, 1f
	ld a, #0xE           ; Yes, send E
1:
	ld c, a             ; Remember the sent digit
	rlca                ; two bytes per record in table
	ld e, a
	ld d, #0             ; MSB of hl offset
	ld hl, #ccirtbl
	add hl, de          ; point

	di                  ; change the tone
	ld a, (hl)
	inc hl
	out (TMR + 1), a
	ld a, (hl)
	out (TMR + 1), a
	ei

	call ccir_tx_timer_wait_100msec

	djnz 2b				; foreach digit

	ret

ccir_tx_timer_wait_100msec:

	ld a, #10			; 10 ms systicks

ccir_tx_timer_wait:

	ld (ccir_tx_timer), a
1:
	ld a, (ccir_tx_timer)
	or a
	jr nz, 1b

	ret

; For the repeater/CW code in bank 1: the same waits with bank 0 selected.

	FAR(b0_ccir_tx_timer_wait, bank0_call, ccir_tx_timer_wait)

	FAR(b0_cw_wait_tone, bank0_call, cw_wait_tone)

; Wait for the marker tone (or pause) to end: Z.  NZ = carrier came up
; while repeater_cw_sendit_all is 0, i.e. the sequence must be pre-empted.
; Destroys A, F.

cw_wait_tone:
	ld a, (repeater_cw_sendit_all)      ; 0=pre-empt if carrier
	or a
	jr nz, 1f

	ld a, (squelch_open)                ; repeater_check_carrier: NZ if carrier
	or a
	ret nz
1:
	ld a, (mt_timer)
	or a
	jr nz, cw_wait_tone
	ret                                 ; Z

;----------------------------------------------------------------------

;  CW timing from the configuration (fixed ROM: the repeater code in bank 1,
;  and c/rptr.c in bank 2, call them).
;
; ______________________________________________  46 slots aka dit-times
; X XXX XXX X __X XXX __X XXX X __X X   X X X __ 
; P             A       R         I     S
; 46 slots / 5 chrs;  9.2  slots/chr.
; N chrs/min; N chrs / 60 sec
; 60 / ( 9.2 * N )  sec/slot
; 100 ticks/sec
; 652/N  ticks/slot

cw_calc_delays:

	; slot duration in ticks
	; 652 ticks / sec
	;  40 CPM : 16 ticks / slot
	; 200 CPM :  3 ticks / slot

	ld a, (cfg_cw_speed)
	cp #40
	jr nc, 1f
	ld a, #40              ; be reasonable, we'd be here until next week
1:
	ld c, a
	imm_ahl(652)          ; see above for maths. CPM into slept ticks
	call div248_full
	ld a, l
	ld (cw_slot_ticks), a

	; timer count for pitch

	ld a, (cfg_cw_pitch)   ; 10 Hz units 00...2550 (cSEC in fact)
	ld c, a
	imm_ahl(403200)        ; timer CLK / 10
	call div248_full
	ld (cw_pitch_cnt), hl

	ret

cw_calc_blip:              ; C-reg has 10 Hz units 00...2550 (cSEC in fact)

	imm_ahl(403200)        ; timer CLK / 10
	call div248_full       ; /= C-reg
	ld (cw_pitch_cnt), hl

	ret

;----------------------------------------------------------------------

step_txpwr_up:
	ld a, (cfg_txpwr)
	add a, #26
	jr nc, 1f
	sbc a, a              ; quicker ld a, FF
1:
	ld (cfg_txpwr), a
	call update_txpwr
	jp redraw

step_txpwr_down:
	ld a, (cfg_txpwr)
	sub #26
	jr nc, 1f
	xor a
1:
	ld (cfg_txpwr), a
	call update_txpwr
	jp redraw

;======================================================================
;
;	Powerdown
;

powerdown_now:

	di
	ld a, #O1_TXOFF
	out (OUT1), a

	ld a, (cfg_function)
	or a
	jr nz, 1f                ; Not Std Function -> keep power relay on

	ld a, #PB_PWROFF
	out (PIO+BDATA), a       ; B0, EXAL /RXON low OFF high.
1:
	halt
	jr powerdown_now

;----------------------------------------------------------------------
;
;	MBUS putchar, character in c
;

putchar:
	ld hl, #mbustx_cnt
1:
	ld a, (hl)
	inc a
	jr z, 1b				; wait until not full
	di
	ld a, (hl)
	inc (hl)
	or a
	jr z, putchar_start		; tx not active, go start it
	ld hl, (mbustx_wp)
	ld (hl), c
	inc l
	ld (mbustx_wp), hl
	ei
	ret
putchar_start:
	ld a, c
	out (SIO+BDATA), a
	ld a, #25
	ld (mbus_timer), a
	ei
	ret

iputc:
	push af
	ld a, (mbustx_cnt)
	inc a
	jr z, 1f				; full
	ld (mbustx_cnt), a
	dec a
	jr z, 2f				; tx not active, go start it
	pop af
	push hl
	ld hl, (mbustx_wp)
	ld (hl), a
	inc l
	ld (mbustx_wp), hl
	pop hl
	ret
1:
	pop af
	ret
2:
	pop af
	out (SIO+BDATA), a
	ld a, #25
	ld (mbus_timer), a
	ret


getchar:
	ld hl, #mbusrx_cnt
	ld a, (hl)
	or a
	jr z, getchar
	di
	dec (hl)
	ld hl, (mbusrx_rp)
	ld a, (hl)
	inc l
	ld (mbusrx_rp), hl
	ei
	ret

;======================================================================

slight_delay:
	nop
	nop
	nop
	nop
	nop
	ret

keypad:

	ld a, (cu_is_alfa)
	or a
	jp z, 1f

	call keypad_cu58af
	ret z

	push af
	xor a
	ld (key_timer), a
	ld (key_time), a
	call cu_manipulated
	call blip
	pop af

	jp 2f
1:

	xor a					; CU53AN then
	ld (key_timer), a
	ld (key_time), a

	call cu_manipulated
	call blip

	;
	;	strobe the data into shifter
	;
	LD_A_OUT2(O2_LCD1)
	out (OUT2), a
	call slight_delay

	LD_A_OUT2(O2_KEYPAD)
	out (OUT2), a
	call slight_delay

	LD_A_OUT2(O2_KEYPAD|O2_CLK)
	out (OUT2), a
	call slight_delay

	LD_A_OUT2(O2_KEYPAD)
	out (OUT2), a
	call slight_delay

	LD_A_OUT2(O2_LCD1)
	out (OUT2), a
	call slight_delay
	call slight_delay

	in a, (PIO+BDATA)		; from LDR
	and #PB_DCU
	ld (dark), a

	;
	;	shift 5 keycode bits to l
	;
	ld (out2_last), a	; bus idle state, for set_bank
	ld c, #0		; collect bits here
	ld b, #5		; this many
1:
	LD_A_OUT2(O2_LCD1|O2_CLK)
	out (OUT2), a
	call slight_delay

	LD_A_OUT2(O2_LCD1)
	out (OUT2), a
	call slight_delay
	call slight_delay

	in a, (PIO+BDATA)
	and #PB_DCU
	sub #1
	rl c
	djnz 1b

	ld hl, #keytbl_cu53an ; table
	add hl, bc           ; b is already 0 from djnz
	ld a, (hl)			 ; map code to character

2:

	; common again for CU53 and CU58

	ld (lastkey), a

	cp #'*'
	jr z, 1f			; * does not repeat
	cp #'B'
	jr z, 1f            ; thingy does not either
	jr 2f
1:
	ld (key), a
	ret
2:
	cp #10				; digit ?
	jr nc, 1f
						; Yes, downtime determines 0..9 or function.
	ld (lastdigit), a

	call is_ptt_pressed
	ld a, (lastdigit)
	jr nz, 1b			; PTT down, digits are DTMF. No repeat

	ld a, (menu_active)
	or a
	ld a, (lastdigit)
	jr nz, 5f           ; digits in menu

	cp #1
	jr z, 2f
	cp #4
	jr z, 2f

	cp #7
	jr z, 3f
	cp #8
	jr z, 3f
	cp #9
	jr z, 3f
	cp #0
	jr z, 3f
4:
	ld a, #255			; 2356 memory/freq adjust
	ld (key_blips), a
	ld a, #50
	ld (key_timer), a
	ld a, #33
	ld (key_speed), a
	ret
5:
	ld a, #255			; digits in menu, scroll letters
	ld (key_blips), a
	ld a, #50
	ld (key_timer), a
	ld a, #66
	ld (key_speed), a
	ret
3:
	ld a, #2				; 7890 default buttons
	ld (key_blips), a
	ld a, #50
	ld (key_timer), a
	ld a, #100
	ld (key_speed), a
	ret
2:
	ld a, #8				; 14 squelch adjust
	ld (key_speed), a
	ld a, #50
	ld (key_timer), a
	ld a, #1
	ld (key_blips), a
	ret
1:
	ld (key), a

	cp #'+'
	jr z, 1f
	cp #'-'
	jr z, 1f

	cp #'S'
	jr z, 2f
	cp #'R'
	jr z, 2f

	ld a, #100
	ld (key_timer), a
	ld a, #100
	ld (key_speed), a
	ld a, #4
	ld (key_blips), a
	ret					; Not digit nor +/-
2:
	ld a, #100
	ld (key_timer), a
	ld a, #100
	ld (key_speed), a
	ld a, #3
	ld (key_blips), a
	ret
1:
	ld a, #50
	ld (key_timer), a
	ld a, #20
	ld (key_speed), a
	ld a, #255
	ld (key_blips), a
	ret

typematic:
	ld a, (key_speed)
	ld (key_timer), a
	ld a, (key_time)
	inc a
	jr z, 1f
	ld (key_time), a
1:
	ld a, (key_blips)
	or a
	jr z, 1f
	dec a
	ld (key_blips), a
	call blip
1:
	ld a, (lastkey)
	cp #10
	jr nc, 1f
	or #0x80			; Repeating digit is a function.
1:
	ld (key), a
	ld a, #-1
	ld (lastdigit), a
	ret

;======================================================================
;
;  4032000 / N = LPF CLK     LP_3600HZ = 4032000 / 3600 / 100
;  4032000 / N = Hz * 100
;  4032000 / (Hz * 100) = N
;  40320 / Hz = N            Hz 2000....5000
;   2016 / (Hz / 20) = N     Hz/20 0...255

init_LPF:
	ld c, #20                 ; /= 20, scale Hz
	xor a
	ld hl, (cfg_lpf_hz)      ; binary Hz in AHL
	ld (lpf_hz_now), hl
	call div248              ; Hz/20 in L (5100/20 = 255, max Hz)

	ld c, l                  ; /= (Hz/20)
	xor a
	ld hl, #2016
	call div248_full         ; Hz/20 reaches 128 from 2560 Hz (v3_Z: div248,
				 ; so 3600 Hz loaded 8, a 5 kHz cutoff, and 5100 Hz 0)

	ld a, #TMR_0 | TMR_BOTH | TMR_SQWAVE
	out (TMR + TMRCTRL), a
	ld a, l
	out (TMR + 0), a
	ld a, h
	out (TMR + 0), a
	ret

update_LPF:
	ld ix, #cfg_lpf_hz
	ld a, (lpf_hz_now + 0)
	cp (ix+0)
	jr nz, init_LPF
	ld a, (lpf_hz_now + 1)
	cp (ix+1)
	jr nz, init_LPF
	ret

;-------------------
;  marker and tx tones

init_timer1:
	ld a, #TMR_1 | TMR_BOTH | TMR_SQWAVE
	out (TMR + TMRCTRL), a
	; and ...
silence_timer1:
	ld a, #0x04
	out (TMR + 1), a	; But it leaks anyway, highest possible
	ld a, #0x00
	out (TMR + 1), a	; tone causes the least harm... brrh.
	ret

blip:                                  ; from keypad 
	ld a, (cfg_key_blip_pitch)
	or a
	ret z

	push hl
	push de
	call blip_hz
	ld d, #3                       ; length in ticks
	call start_marker_tone
	pop de
	pop hl
	ret

serv_blip:                              ; from closing squelch
	ld a, (cfg_serv_blip_pitch)
	or a
	ret z

	push hl
	push de
	call blip_hz
	ld d, #3                       ; length in ticks
	call start_marker_tone
	pop de
	pop hl
	ret

bleep:
	push hl
	ld hl, #MT_300HZ
	ld d, #100
	call start_marker_tone

	pop hl
	ret

blip_hz:                    ; input A = 1, 2, ..., set HL to MT_xxxHZ

	ld hl, #MT_500HZ
	dec a                   ; --1
	ret z                   ;    == 0
	ld hl, #MT_1000HZ
	dec a
	ret z
	ld hl, #MT_1500HZ
	dec a
	ret z
	ld hl, #MT_2000HZ
	dec a
	ret z
	ld hl, #MT_2500HZ
	dec a
	ret z
	ld hl, #MT_3000HZ
	dec a
	ret z
	ld hl, #MT_3500HZ
	dec a
	ret z

	ld hl, #MT_500HZ      ; out of range
	ret

ding:

	push bc

	di
	call stop_marker_tone
	ld a, (output_0)
	push af
	and #~O0_AUDIOC
	out (OUT0), a
	and #~O0_INH
	out (OUT0), a
	or   #O0_VOLUME
	out (OUT0), a
	ld (output_0), a
	ld a, #1
	ld (mton), a
	ei

	ld b, #5
2:
	push hl
	ld hl, #MT_1200HZ
	ld d, #5
	call start_marker_tone
	pop hl
1:
	ld a, (mt_timer)
	or a
	jr nz, 1b

	push hl
	ld hl, #MT_1400HZ
	ld d, #5
	call start_marker_tone
	pop hl
1:
	ld a, (mt_timer)
	or a
	jr nz, 1b

	djnz 2b

	di
	pop af
	ld (output_0), a
	out (OUT0), a
	xor a
	ld (mton), a
	ei

	pop bc

	call open_selective
	ret

;
;  Duration in 10ms in d, pitch in hl
;
start_marker_tone:

	xor a
	ld (mt_timer), a

	ld a, l
	out (TMR + 1), a
	ld a, h
	out (TMR + 1), a	; pitch

	ld hl, #output_0
	set O0_MTCBIT, (hl)

	ld a, d
	ld (mt_timer), a	; duration in 10ms units

	ret

stop_marker_tone:

	xor a
	ld (mt_timer), a

	ld a, (output_0)
	and #~O0_MTC
	ld (output_0), a
	out (OUT0), a		; Cut tone from local audio

	call silence_timer1

	ret

;======================================================================

resync_squelch_if_forced:
	di
	ld a, (squelch_forced)
	or a
	call nz, audioc_on
	ei
	ret

force_squelch:
	di
	ld a, #1
	ld (squelch_forced), a
	call audioc_on
	ei
	ret

unforce_squelch:
	di
	ld a, (squelch_open)
	or a
	call z, audioc_off
	xor a
	ld (squelch_forced), a
	ei
	ret

open_selective:              ; must not trash B
	di
	ld a, (squelch_muted)
	bit 1, a                 ; selective was on ?
	jr z, 1f
	and #~2                   ; bit1 selective muting
	ld (squelch_muted), a
	jr nz, 1f                ; mute had other bits active
	ld a, (squelch_open)
	or a
	call nz, audioc_on
1:
	ei
	ret

restore_squelch_scanner:
	di
	ld a, (squelch_muted)
	and #~1                   ; bit0 scanner muting
	ld (squelch_muted), a
	jr nz, 1f                ; mute did not get all zero
	ld a, (squelch_open)
	or a
	call nz, audioc_on
1:
	ei
	ret

mute_squelch_scanner:
	di
	ld a, (squelch_muted)
	or #1
	ld (squelch_muted), a
	call audioc_off                 ; XXX and squelch_is_closed ?
	ei
	ret

mute_squelch_selective:
	di
	ld a, (squelch_muted)
	or #2
	ld (squelch_muted), a
	call audioc_off
	ei
	ret

close_squelch:
	ld a, (squelch_forced)
	or a
	ret nz						; Manually forced open.

	di
	call close_squelch_really
	ei
	ret

close_squelch_really:
	call cu_serv_off
	call release_EXIN1
	call squelch_is_closed
	call audioc_off
	ret

;======================================================================
;
;	Build up display buffer
;

;     PVQQSS
;   MM_-FFFFFF
;
;     PV_QQ_SS
;    MM-FFFFFF

force_redraw:
	xor a
	ld (drawn), a
	call redraw
1:
	ld a, (drawn)
	or a
	jr z, 1b
	ret

redraw:

	xor a
	ld (dpx_ind_flags), a

	call draw_upper_row
	call draw_lower_row
	call draw_dpx_ind
	call draw_ctcss_and_mute_and_gps_ind

	ld hl, #sir
	set DPYSIR, (hl)

	ret

;----------------------------------------------------------------------

light_on_led:
	ld hl, #indicators
	ld a, (cu_is_alfa)
	or a
	jr nz, 1f
	set CU53AN_BIT_ON, (hl)
	ret
1:
	set CU58AF_BIT_ON, (hl)
	ret

dim_transmit_led:
	ld hl, #indicators
	ld a, (cu_is_alfa)
	or a
	jr nz, 1f
	res CU53AN_BIT_ROAM, (hl)
	ret
1:
	res CU58AF_BIT_ROAM, (hl)
	ret

light_transmit_led:
	ld hl, #indicators
	ld a, (cu_is_alfa)
	or a
	jr nz, 1f
	set CU53AN_BIT_ROAM, (hl)
	ret
1:
	set CU58AF_BIT_ROAM, (hl)
	ret

cu_lights_on_from_squelch:            ; XXX differentiate from cu manip
	ld a, (cfg_light_sql)
	or a
	ret z

	; FALLTHRU

cu_lights_on:
	xor a
	ld (lights_timer), a
	ld a, (cfg_light_seconds)
	or a
	ret z
	ld hl, #indicators
	ld a, (cu_is_alfa)
	or a
	jr nz, 1f
	set CU53AN_BIT_LCDLIGHT, (hl)	; lit the lights.
	set CU53AN_BIT_KEYLIGHT, (hl)
	ret
1:
	set CU58AF_BIT_LCDLIGHT, (hl)	; lit the lights.
	set CU58AF_BIT_KEYLIGHT, (hl)
	ret

	; XXX this has a race

cu_lights_off:
	ld hl, #indicators
	ld a, (cu_is_alfa)
	or a
	ld a, (hl)
	jr nz, 1f
	res CU53AN_BIT_LCDLIGHT, (hl)	; lit the lights.
	res CU53AN_BIT_KEYLIGHT, (hl)
	bit CU53AN_BIT_KEYLIGHT, a
	ret z
	jr redraw
1:
	res CU58AF_BIT_LCDLIGHT, (hl)	; lit the lights.
	res CU58AF_BIT_KEYLIGHT, (hl)
	bit CU58AF_BIT_KEYLIGHT, a
	ret z
	jp redraw

cu_serv_on:
	ld hl, #indicators
	ld a, (cu_is_alfa)
	or a
	jr nz, 1f
	set CU53AN_BIT_SERV, (hl)
	ret
1:
	set CU58AF_BIT_SERV, (hl)
	ret

cu_serv_off:
	ld hl, #indicators
	ld a, (cu_is_alfa)
	or a
	jr nz, 1f
	res CU53AN_BIT_SERV, (hl)
	ret
1:
	res CU58AF_BIT_SERV, (hl)
	ret

cu_call_on:
	ld hl, #indicators
	ld a, (cu_is_alfa)
	or a
	jr nz, 1f
	set CU53AN_BIT_CALL, (hl)
	ret
1:
	set CU58AF_BIT_CALL, (hl)
	ret

cu_call_off:
	ld hl, #indicators
	ld a, (cu_is_alfa)
	or a
	jr nz, 1f
	res CU53AN_BIT_CALL, (hl)
	ret
1:
	res CU58AF_BIT_CALL, (hl)
	ret

	ASSERT_EQ(CU53AN_SEG_V_U, 0x43)
	ASSERT_EQ(CU53AN_SEG_PHONE, 0x47)
	ASSERT_EQ(CU53AN_SEG_V_D, 0x53)
	ASSERT_EQ(CU53AN_SEG_PHONE_NO, 0x5B)
	ASSERT_EQ(CU53AN_SEG_MAST, 0x5F)
	ASSERT_EQ(CU53AN_SEG_STAR, 0x6B)
	ASSERT_EQ(CU53AN_SEG_KEY, 0x73)
	ASSERT_EQ(CU53AN_SEG_BOOK, 0x77)
	ASSERT_EQ(CU58AF_SEG_ARROW0, 28)
	ASSERT_EQ(CU58AF_SEG_ARROW1, 29)


draw_scanner_icon:
	ld a, (cu_is_alfa)
	or a
	jr nz, 1f
	segset_hl(CU53AN_SEG_CAR_U)
	ret
1:
	segset_hl(CU58AF_SEG_CAR)
	ret

clear_scanner_icon:
	ld a, (cu_is_alfa)
	or a
	jr nz, 1f
	segres_hl(CU53AN_SEG_CAR_U)
	ret
1:
	segres_hl(CU58AF_SEG_CAR)
	ret

draw_upper_colons:
	ld a, (cu_is_alfa)
	or a
	ret nz
	segset_hl(CU53AN_SEG_COLON_UL)
	segset_hl(CU53AN_SEG_COLON_UR)
	ret

clear_upper_colons:
	ld a, (cu_is_alfa)
	or a
	ret nz
	segres_hl(CU53AN_SEG_COLON_UL)
	segres_hl(CU53AN_SEG_COLON_UR)
	ret

draw_lower_colon:
	ld a, (cu_is_alfa)
	or a
	ret nz
	segset_hl(CU53AN_SEG_COLON_D)
	ret

clear_lower_colon:
	ld a, (cu_is_alfa)
	or a
	ret nz
	segres_hl(CU53AN_SEG_COLON_D)
	ret

draw_clock_icon:
	ld a, (cu_is_alfa)
	or a
	jr nz, 1f
	segset_hl(CU53AN_SEG_CLOCK)
	ret
1:
	segset_hl(CU58AF_SEG_EXP)
	ret

clear_clock_icon:
	ld a, (cu_is_alfa)
	or a
	jr nz, 1f
	segres_hl(CU53AN_SEG_CLOCK)
	ret
1:
	segres_hl(CU58AF_SEG_EXP)
	ret


;----------------------------------------------------------------------


;----------------------------------------------------------------------

no_feedback:
	ld iy, #0
	push iy
2:
	pop iy
	ld (adj_feedback), iy
	ret

feedback_reject:
	call 2b
	.ascii " rEJECtEd "

feedback_cleared:
	call 2b
	.ascii "  CLEArEd "

feedback_default:
	call 2b
	.ascii "  dEFAULt "

feedback_stored:
	call 2b
	.ascii "   StorEd "

feedback_shift_neg:
	call 2b
	.ascii "SHIFt NEG "

feedback_shift_pos:
	call 2b
	.ascii "SHIFt POS "

feedback_split:
	call 2b
	.ascii "SPLIt     "

feedback_let_go_the_darn_button:
	call 2b
	.ascii "ALLrIGHt  "

feedback_lobatt:
	call 2b
	.ascii " Lo batt  "

feedback_hold:
	call 2b
	.ascii " Hold It  "

feedback_ready:
	call 2b
	.ascii " rEAdY    "

feedback_loading:
	call 2b
	.ascii " LoAdinG  "

feedback_error:
	call 2b
	.ascii " Error    "



;----------------------------------------------------------------------

; CY set means lit, NC means unlit segment
; A contains BBBBBbbb byte and bit offsets

segment_onoff_XXX:

	ld a, (de)          ; position from display indirection map
	inc de
	rr c                ; font pattern in bits 6...0, do next

segment_onoff:

	ld h, a             ; save 5 MSbits for a while
	rla                 ; suck in carry next to bit selector
	and #0x0F            ; three bits for bit, one for res/set
	add a, a
	add a, a               ; 4 bytes per stub
	add a, #LO(res_set_stubs)
	ld l, a             ; table does not cross pages
	ld a, h             ; remember the 5 MSbits
	ld h, #HI(res_set_stubs)
	push hl             ; one jump ready to go at stack top
	rra
	rra
	rra                 ; byte offset right justified
	and #0x1F            ; 5 bits of it
	ld l, a
	ld h, #HI(segments)
	ASSERT_EQ(LO(segments), 0)
	ret                 ; jump !


;----------------------------------------------------------------------

display:

	ld a, (cu_is_alfa)
	or a
	jp nz, display_cu58af

display_cu53an:

	ld hl, #segments

	LD_A_OUT2(O2_LCD2)
	out (OUT2), a

	LD_A_OUT2(O2_LCD1)	; start 1st half of LCD1
	call display_group
	call display_bit_zero

	LD_A_OUT2(O2_LCD2)	; start 1st half of LCD2
	call display_group
	call display_bit_zero

	LD_A_OUT2(O2_LCD1)	; start 2nd half of LCD1
	call display_group
	call display_bit_one

	LD_A_OUT2(O2_LCD2)	; start 2nd half of LCD2
	call display_group
	call display_bit_one

	LD_A_OUT2(O2_LCD1)	; unselect LATCH
	out (OUT2), a

	ld hl, #indicators
	call display_byte

	LD_A_OUT2(O2_LATCH)	; select LATCH
	out (OUT2), a
	LD_A_OUT2(O2_LCD1)	; unselect LATCH
	out (OUT2), a
	ld (out2_last), a	; bus idle state, for set_bank

	ret

display_group:
	out (OUT2), a

	call display_bit_zero
	call display_byte
	call display_byte
	call display_byte
	call display_byte
	ret

	;
	;	4032000 Hz pclk
	;	0.24 us T-state
	;
display_byte:
	ld c, (hl)
	inc hl
	ld b, #8
1:
	srl c
	call display_bit
	djnz 1b
	ret

display_bit:
	jr nc, display_bit_zero
display_bit_one:
	or #O2_DP
display_bit_zero:
	or #O2_CLK
	out (OUT2), a		; data & clock set	11 T	2.7 us
	and #~O2_CLK
	out (OUT2), a		; clock edge		2.7 us
	and #~O2_DP
	out (OUT2), a		; clear data		2.7 us

	ret

;======================================================================
;
;  CU58AF things

cu_now_known:
	ld a, (cu_is_alfa)
	or a
	ld hl, #cu_handler_cu53
	jr z, 1f
	ld hl, #cu_handler_cu58af
1:
	ld (cu_handler), hl

	xor a
	ld (nosir), a
	ret

probe_cu58af:

    ; flush /INT from CU58AF, DA floats; no effect on CU53, DA low

	call cu58af_init
	call cu58af_init

	in a, (SIO+ACTRL)
	and #SA_DA			; inverted...
	jr nz, 1f			; go if DA low, idle state DA low vs. /INT high

	ld a, #1
	ld (cu_is_alfa), a
	ld a, #0
	ld (indicators), a
1:
	ret


step_audio_dst:

	ld a, (audio_dst)
	inc a
	cp #3
	jr c, 1f
	xor a              ; 0, 1 and 2 possible
1:
	ld (audio_dst), a

	jp set_vola

pcf3312_map:
	.db 'S', 0x1A  ; STO  A
	.db 'R', 0x1B  ; RCL  B
	.db 'C', 0x1C  ; CL   C
	.db 'E', 0x1D  ; ENT  D
	.db '*', 0x1E  ; *    *
	.db '#', 0x1F  ; #    #

pcf3312_map_size = (. - pcf3312_map) / 2

	.db 0x3F  ; 1760 Hz from button

dtmf_cu58af:

	cp #10
	jr c, 2f       ; digits not mapped

	ld hl, #pcf3312_map
	ld b,  #pcf3312_map_size
1:
	cp (hl)
	inc hl               ; INC HL keeps Z flag
	jr z, 1f
	inc hl
	djnz 1b
1:
	ld a, (hl)
2:
	or #0x10              ; mapped or not, 0x10 is set
	jr 1f

stop_dtmf_tone:
	ld a, (dtmf_code)
	or a
	ret z             ; no tone on (on CU58AF)
	xor a
1:
	ld (dtmf_code), a
	ld hl, #sir
	set DTMFSIR, (hl)
	ret

i2c_dtmf_tone:

	ld a, #CU58AF_AUDIOCTRL | CU58AF_EARCTRL | CU58AF_VOL_MIN | CU58AF_DTMFCTRL
	ld c, #CU58AF_CTRL
	call i2c_send_a

	ld a, (dtmf_code)
	ld c, #CU58AF_DTMF
	call i2c_send_a

	ret

i2c_dtmf:

	ld a, (dtmf_code)
	or a
	jr nz, i2c_dtmf_tone

	xor a				; End tone
	ld c, #CU58AF_DTMF
	call i2c_send_a

	ASSERT_EQ(CU58AF_VOL_MASK, 0xE0)

	ld a, (volume)	; 0..9
	cp #0
	jr z, 2f		; no at all
	sub #1			; 0..8
	cp #7
	jr c, 1f
	ld a, #7			; 0..7
1:
	and #7	; -----210
	rrc a	; 0-----21
	rrc a	; 10-----2
	rrc a	; 210-----

	ld b, a			; volume bits in position

	ld a, (audio_dst)
	cp #1
	jr nz, 1f
	di
	ld a, (output_0)
	or #O0_INH
	ld (output_0), a
	out (OUT0), a
	ei
	ld a, #CU58AF_NSPKRCTRL
	jr 2f
1:
	cp #2
	jr nz, 1f
	di
	ld a, (output_0)
	or #O0_INH
	ld (output_0), a
	out (OUT0), a
	ei
	ld a, #CU58AF_EARCTRL
	jr 2f
1:
	di
	ld a, (output_0)
	and #~O0_INH
	ld (output_0), a
	out (OUT0), a
	ei
	xor a
2:
	xor #CU58AF_NSPKRCTRL
	or #CU58AF_AUDIOCTRL | CU58AF_MICCTRL
	or b
	ld c, #CU58AF_CTRL
	call i2c_send_a

	ret

;
;  before 'ei'
;
cu58af_init:

	ld c, #CU58AF_LED
	ld b, #CU58AF_LED_ON | CU58AF_KBRLIGHT | CU58AF_LCDLIGHT
	call i2c_send

	xor a
	ld (dtmf_code), a
	call i2c_dtmf

	ld c, #CU58AF_COLBTN
	ld b, #0xFF		; All inputs
	call i2c_send

	ld c, #CU58AF_ROW
	ld b, #0
	call i2c_send

	;
	;  LCD needs more attention
	;
	call i2c_start

	ld c, #CU58AF_LCD ; /WR as required.
	call i2c_wrbyte
	ld c, #0b11001100 ; C, normal mode, enabled, 1/2 bias, 4 backplanes
	call i2c_wrbyte
	ld c, #0b10000000 ; C, data pointer rewind
	call i2c_wrbyte
	ld c, #0b11100000 ; C, device select 0
	call i2c_wrbyte
	ld c, #0b11111000 ; C, bank select 0
	call i2c_wrbyte
	ld c, #0b01110000 ; /C, blink off
	call i2c_wrbyte

	ld b, #40
1:
	ld c, #0xFF
	call i2c_wrbyte
	djnz 1b

	call i2c_stop

	ld c, #CU58AF_COLBTN
	call i2c_recv
	ld c, #CU58AF_ROW
	call i2c_recv			; Flush /int
	ld c, #CU58AF_COLBTN
	call i2c_recv
	ld c, #CU58AF_ROW
	call i2c_recv			; Flush /int

	ret

keypad_cu58af:

	;  Read columns (and buttons)

	ld c, #CU58AF_COLBTN
	call i2c_recv

	ld c, a                    ; buttons now
	ld a, (cu58af_buttons)     ; buttons previously
	xor c                      ; changes
	and c                      ; changes which were from 0 to 1
	ld b, c                    ; remember them too
	and #CU58AF_SPEAKER
	jr z, 1f                   ; speaker button was not just pressed
	ld hl, #key
	ld (hl), #'K'               ; not too nicely
1:
	ld a, c
	ld (cu58af_buttons), a     ; current state

	and #CU58AF_COL_MASK
	jr nz, 2f                  ; an active column exists

	di                         ; no columns pressed currently
	ld a, (lastdigit)
	cp #-1
	jr z, 1f
	ld (key), a                ; quick press of a digit.
	ld a, #-1
	ld (lastdigit), a          ; clear this
1:
	xor a                      ; Z=NOKEY for return
	ld (keydown), a
	ld (key_timer), a
	ei
	ret                        ; done.
2:
	xor b                      ; new press ?
	ret z                      ; already active. done

	;  New press now.
	;  rows to inputs

	ld c, #CU58AF_ROW
	ld b, #0xFF
	call i2c_send

	;  columns to outputs (low)

	ld c, #CU58AF_COLBTN
	ld b, #~CU58AF_COL_MASK
	call i2c_send

	;  Read rows (8 lines)

	ld c, #CU58AF_ROW
	call i2c_recv

	push af                    ; remember rowmask. colmask in [cu58af_buttons]

	;  columns back to inputs (high)

	ld c, #CU58AF_COLBTN
	ld b, #0xFF
	call i2c_send

	;  rows back to outputs (low)

	ld c, #CU58AF_ROW
	ld b, #0
	call i2c_send

	ld c, #CU58AF_COLBTN
	call i2c_recv	                ; Flush int from changes

	pop af                     ; rowmask
	ld c, #-1
	scf                        ; in case no active row, this ends the loop
1:
	inc c                      ; row number to C
	rra
	jr nc, 1b

	ASSERT_EQ(CU58AF_COL_MASK, 7) ; 3 keys (columns) in row. 0x7F row bits

	ld a, (cu58af_buttons)     ; junk and colmask
	and #CU58AF_COL_MASK        ; colmask 1, 2 or 4, NC
	rra                        ; column number 0, 1 or 2, NC from above

	add a, c
	add a, c
	add a, c                      ; plus 3 * row number
	ld c, a
	ld b, #0
	ld hl, #keytbl_cu58af
	add hl, bc

	ld a, (hl)                 ; map code to character
	cp #'Z'
	ret

;
;  Update LCD and LEDs
;
display_cu58af:

	ld hl, #indicators
	ld c, #CU58AF_LED
	ld b, (hl)
	call i2c_send

	call i2c_start

	ld c, #CU58AF_LCD ; /WR as required.
	call i2c_wrbyte
	ld c, #0b10000000 ; C, data pointer rewind
	call i2c_wrbyte
	ld c, #0b01100000 ; /C, device select 0
	call i2c_wrbyte

	ld hl, #segments
	ld b, #40
1:
	ld c, (hl)
	inc hl
	call i2c_wrbyte
	djnz 1b

	call i2c_stop

	ret

;
;  SDA into carry
;

i2c_getbit:
	in a, (PIO+BDATA)
	and #PB_DCU
	sub #1
	jp i2c_delay

;
;  Pull or release SDA wrt carry. NOT INTERRUPT PROTECTED.
;

i2c_putbit:
	jp c, i2c_sda_high



i2c_sda_low:
	push hl
	di
	call pull_down_DCU
	ei
	pop hl
	jp i2c_delay

i2c_sda_high:
	push hl
	di
	call release_DCU
	ei
	pop hl
	jp i2c_delay

i2c_scl_low:
	LD_A_OUT2(0)
	out (OUT2), a
	jp i2c_delay

i2c_scl_high:
	LD_A_OUT2(O2_CLK)
	out (OUT2), a
	jp i2c_delay

;
;  Call/return implicit delay should be enough...
;
i2c_delay:

	out (WD), a
	out (WD), a		; some delay anyway (v3_Z had three; the third went
				; to pay for the bank bits in i2c_scl_*: SCL high
				; stays ~11 us on a P8E, I2C needs 4 us)
#if 0
	push af
	ld a, #20		; delay. We run blind.
1:
	dec a
	jr nz, 1b
	pop af
#endif
	ret

;======================================================================
;
;  ROM banking (notes/hybrid-plan.md).  A bank is a 16 KB page mapped at
;  0x8000-0xBFFF:
;    0  power-on state: the EPROM1 socket (the DTMF/CTCSS multiboard when
;       fitted), OUT2 bits 3..0 = 1000
;    1  EPROM0 chip 0xC000-0xFFFF (OUT2 RS|RA14), on P8E and P8N
;    2  EPROM0 chip 0x8000-0xBFFF (OUT2 RS), on P8E and P8N
;  Banked code runs from mainline only.  The interrupt code keeps the bank
;  bits in its OUT2 writes (out2_bank) and does not read the multiboard
;  while a bank is selected (dtmf_decoder, ctcss_dec_src).
;
;  These are the helpers SDCC's banked-call trampolines use; call banked
;  code with
;	ld e, #bank
;	ld hl, #function
;	call ___sdcc_bcall_ehl		; (SDCC library)
;  which passes BC, D, IX, IY in and A, DE, HL back, and destroys BC.
;
;  get_bank: A = current bank; keeps the other registers.
;  set_bank: select bank A (0..NUM_BANKS-1); destroys A and F only.

NUM_BANKS = 3
	.globl ___sdcc_bcall_ehl	; link the trampoline from the SDCC library

bank_bits_p8e:	.db O2_XXX, O2_XXX | O2_RS | O2_RA14, O2_XXX | O2_RS
bank_bits_p8n:	.db O2_XXX, O2_XXX | O2_RS | O2_RA14, O2_XXX | O2_RS

bank_init:
	ld a, #O2_XXX			; bank 0 (cur_bank is 0), as set at reset
	ld (out2_bank), a
	ld (out2_last), a
	ld hl, #0x8000			; multiboard visible
	ld (ctcss_dec_src), hl
	ret

get_bank:
	ld a, (cur_bank)
	ret

set_bank:
	push hl
	push de
	ld e, a
	ld d, #0
	ld hl, #bank_bits_p8n
	ld a, (cpu_is_P8E)
	or a
	jr z, 1f
	ld hl, #bank_bits_p8e
1:
	add hl, de
	ld d, (hl)		; D = OUT2 bank bits
	ld a, e
	or a
	jr z, 2f
	; to a code bank: stop the multiboard readers first
	ld (cur_bank), a
	ld hl, #ctcss_idle_sample
	ld (ctcss_dec_src), hl
	call out2_set_bank
	pop de
	pop hl
	ret
2:
	; back to bank 0: switch first, then let the readers look again
	call out2_set_bank
	xor a
	ld (cur_bank), a
	ld hl, #0x8000
	ld (ctcss_dec_src), hl
	pop de
	pop hl
	ret

;----------------------------------------------------------------------
;
;  Assembler calls into a bank go through a fixed-ROM stub,
;  FAR(far_fn, bank1_call, fn) (bank 2: bank2_call; bank0_call runs a wait
;  with bank 0 selected).
;  All registers pass to fn and back unchanged (flags too); the previous
;  bank is restored after fn returns, so calls nest.  The RAM temporaries
;  are only live until fn starts; interrupts never call bank code.
;
;  bank0_call is the same with bank 0 selected: banked code uses it (via a
;  stub in fixed ROM) for long waits, so that the multiboard readers
;  (DTMF, CTCSS DSP decoder) see the multiboard meanwhile.

bank0_call:			; stack: [&.dw fn] [caller]
	ld (bank_hl), hl
	ld hl, #0
	jr 1f

bank2_call:			; stack: [&.dw fn] [caller]
	ld (bank_hl), hl
	ld hl, #2
	jr 1f

bank1_call:			; stack: [&.dw fn] [caller]
	ld (bank_hl), hl
	ld hl, #1
1:
	ld (bank_to), hl
	pop hl
	push af
	ld a, (hl)
	inc hl
	ld h, (hl)
	ld l, a
	ld (bank_fn), hl
	pop hl
	ld (bank_af), hl	; caller's AF
	ld a, (cur_bank)
	push af			; [old bank] [caller]
	ld a, (bank_to)
	call set_bank
	ld hl, #bank1_back
	push hl
	ld hl, (bank_fn)
	push hl			; [fn] [bank1_back] [old bank] [caller]
	ld hl, (bank_af)
	push hl
	pop af
	ld hl, (bank_hl)
	ret			; to fn

bank1_back:			; [old bank] [caller]
	ex (sp), hl
	push af
	ld a, h
	call set_bank
	pop af
	pop hl
	ret

#ifdef BANK_TEST
;----------------------------------------------------------------------
;
;  Bench test of the ROM window on a real board (make banktest, 64 KB
;  EPROM image).  Bank 1 must show EPROM0 chip 0xC000-0xFFFF: its 16-bit
;  byte sum must equal bank1_sum (patched in by ihx2bin.py), and
;  bank_test_ping there must return 0xA5.  Then the same for bank 2
;  (EPROM0 chip 0x8000-0xBFFF): bank2_sum, and bank_test_ping2 called
;  through bank2_call must return 0x5A.  The result stays on the lower row:
;	"b1b2 PASS "	both windows read and code runs in both
;	"b1 ssss 00"	bank 1's sum was ssss (make banktest prints what the
;			pages sum to; 0xC000 would be an erased page)
;	"b1 CA11 vv"	sum fine, but the routine returned vv
;	"b2 ssss 00"	bank 1 fine, bank 2's sum was ssss
;	"b2 CA11 vv"	bank 2's sum fine, its routine returned vv
;
bank_test:
	ld a, #1
	call bank_test_sum
	ld hl, (bank1_sum)
	and a
	sbc hl, de
	ex de, hl		; HL = sum read
	jr nz, 3f		; A = 0
	ld e, #1
	ld hl, #bank_test_ping
	call ___sdcc_bcall_ehl	; the routine in bank 1
	cp #0xA5
	ld hl, #0xCA11
	jr nz, 3f
	; bank 1 fine: bank 2 = EPROM0 chip 0x8000
	ld a, #2
	call bank_test_sum
	ld hl, (bank2_sum)
	and a
	sbc hl, de		; Z: as expected
	ex de, hl		; HL = sum read (flags kept)
	jr nz, 5f		; A = 0
	call far2_bank_test_ping2	; through bank2_call
	cp #0x5A
	ld hl, #0xCA11
	jr nz, 5f
	ld hl, #bank_test_pass
	jr 4f
5:
	ld bc, #bank_test_b2
	jr 6f
3:
	ld bc, #bank_test_b1
6:
	push af			; value
	push hl			; where
	ld l, c
	ld h, b
	ld de, #bank_test_msg
	ld bc, #3
	ldir
	pop hl
	ld a, h
	call bank_test_hex
	ld a, l
	call bank_test_hex
	ld a, #' '
	ld (de), a
	inc de
	pop af
	call bank_test_hex
	ld hl, #bank_test_msg
	or #1			; NZ: failed
4:
	ld (adj_feedback), hl
	ld hl, #sir
	set DPYSIR, (hl)
	ret			; Z: passed

	FAR(far2_bank_test_ping2, bank2_call, bank_test_ping2)

bank_test_sum:			; DE = 16-bit byte sum of bank A's window
	call set_bank
	ld hl, #0x8000
	ld de, #0
1:
	out (WD), a
	ld a, e
	add a, (hl)
	ld e, a
	jr nc, 2f
	inc d
2:
	inc hl
	ld a, h
	cp #0xC0
	jr nz, 1b
	xor a
	jp set_bank

	; the window is wrong: nothing from bank 1 may run, just show why
bank_test_stop:
	call cu_now_known
1:
	call redraw
	jr 1b

bank1_sum:	.dw 0	; set by ihx2bin.py --bank1-sum
bank2_sum:	.dw 0	; set by ihx2bin.py --bank2-sum

bank_test_hex:		; A as two hex digits to (DE)+
	push af
	rrca
	rrca
	rrca
	rrca
	call 1f
	pop af
1:
	and #0x0F
	add a, #'0'
	cp #'9' + 1
	jr c, 2f
	add a, #'A' - '9' - 1
2:
	ld (de), a
	inc de
	ret

bank_test_pass:	.ascii "b1b2 PASS "
bank_test_b1:	.ascii "b1 "
bank_test_b2:	.ascii "b2 "
#endif

	; OUT2 = bus state | D.  An interrupt between the two writes uses the
	; new bits already, which is harmless: we run from fixed ROM.
out2_set_bank:
	ld a, d
	ld (out2_bank), a
	ld a, (out2_last)
	and #~O2_BANK
	or d
	out (OUT2), a
	ld (out2_last), a
	ret

i2c_sendbit:
	sla c				; MSB of C (reg) into C (carry). Hmpfth...
	call i2c_putbit
	call i2c_scl_high
	call i2c_scl_low
	ret

i2c_recvbit:
	call i2c_scl_high
	call i2c_getbit
	rl c
	call i2c_scl_low
	ret

;
;  I2C byte write from reg c
;
i2c_wrbyte:

	call i2c_sendbit
	call i2c_sendbit
	call i2c_sendbit
	call i2c_sendbit

	call i2c_sendbit
	call i2c_sendbit
	call i2c_sendbit
	call i2c_sendbit

	call i2c_sda_high
	call i2c_scl_high
	call i2c_getbit		; ack ?
	push af
	call i2c_scl_low
	pop af				; Return carry clear if acknowledged.
	ret

;
;  I2C byte read to reg c. One and only one byte at a time.
;
i2c_rdbyte:

	call i2c_sda_high

	call i2c_recvbit
	call i2c_recvbit
	call i2c_recvbit
	call i2c_recvbit

	call i2c_recvbit
	call i2c_recvbit
	call i2c_recvbit
	call i2c_recvbit

	ret

i2c_start:

	call i2c_sda_high
	call i2c_scl_high

	call i2c_sda_low	; start ...
	call i2c_scl_low	; ... condition.

	ret

i2c_stop:

	call i2c_scl_low
	call i2c_sda_low

	call i2c_scl_high	; stop ...
	ld (out2_last), a	; bus state for set_bank: SCL stays high until the
				; next transaction, which always ends here too
	call i2c_sda_high	; ... condition.

	ret

i2c_send_a:
	ld b, a

i2c_send:

	res 0, c		; /WR

	call i2c_start

	call i2c_wrbyte	; Send address from C
	ld c, b
	call i2c_wrbyte	; Send data from B

	call i2c_stop

	ret

i2c_recv:

	set 0, c		; RD

	call i2c_start

	call i2c_wrbyte	; Send address from C
	call i2c_rdbyte	; Get data to C

	call i2c_stop

	ld a, c			; Return in A
	ret

;======================================================================
;
;	25 kHz
;	 512, 12800 /  512  quot 25 rem 0, /= 25 shift 0
;
;	20 kHz
;	 640, 12800 /  640  quot 20 rem 0, /= 20 shift 0
;
;	15 kHz
;	 853, 12800 /  853  quot 15 rem 0, /= 15 shift 0    NOT EXACT XXX
;
;	12.5 kHz
;	1024, 12800 / 1024  quot 12 rem 512
;	      12800 /  512  quot 25 rem 0, /= 25 shift 1
;
;	10 kHz
;	1280, 12800 / 1280  quot 10 rem 0, /= 10 shift 0
;
;	6.25 kHz
;	2048, 12800 / 2048  quot  6 rem 512
;	      12800 / 1024  quot 12 rem 512
;	      12800 /  512  quot 25 rem 0, /= 25 shift 2
;
;	3.125 kHz
;	4096, 12800 / 4096  quot  3 rem 512
;	      12800 / 2048  quot  6 rem 512
;	      12800 / 1024  quot 12 rem 512
;	      12800 /  512  quot 25 rem 0, /= 25 shift 3
;
;	5 kHz
;	2560, 12800 / 2560  quot  5 rem 0, 5 too small, use /= 10 shift 1
;


locate_tx_band:

	ld ix, #cfg_band1_start
	ld b, #num_bandrecs
1:
	load_ahl(tx_freq)
	ld e, (ix+0)
	ld d, (ix+1)
	ld c, (ix+2)
	and a
	sbc hl, de
	sbc a, c                    ; current - start
	jr c, 2f                 ; current < start, try next
	load_ahl(tx_freq)
	ld e, (ix+3)
	ld d, (ix+4)
	ld c, (ix+5)
	and a
	sbc hl, de
	sbc a, c                    ; current - end
	jr c, 3f                 ; current < end, found !
2:
	ld de, #size_bandrec
	add ix, de
	djnz 1b

	; none of the bands, we now point into defaults for "other, b is 0
3:
	ret


determine_tx_div_split:

	load_ahl(tx_freq)
	ld bc, (tx_bstep_cfg)
	call freq2div
	save_ahl(tx_divisor)
	ld bc, (tx_bstep_cfg)
	call div2freq
	save_ahl(tx_freq)         ; and back in aligned
	ret

determine_rx_div:

	load_ahl(rx_freq)
	ld bc, (rx_bstep_cfg)
	call freq2div             ; linear NA
	save_ahl(rx_divisor)      ; without I/F
	ld bc, (rx_bstep_cfg)
	call div2freq
	save_ahl(rx_freq)         ; without I/F

	ld a, (cfg_inj_below)
	or a
	jr nz, 1f

	load_ahl(cfg_if_freq)
	ld bc, (rx_bstep_cfg)
	call freq2div             ; linear NA
	add_ahl_de(rx_divisor)
	save_ahl(rx_divisor)      ; with vco
	ret
1:
	load_ahl(cfg_if_freq)
	ld bc, (rx_bstep_cfg)
	call freq2div             ; linear NA
	save_ahl(if_tmp)
	load_ahl(rx_divisor)
	sub_ahl_de(if_tmp)
	save_ahl(rx_divisor)      ; with vco
	ret

get_scan_tail:
	ld a, (band_sctail)
	ret
get_scan_patience:
	ld a, (band_sclisten)
	ret


	; set duplex shift temporarily

	ASSERT_EQ(DPX_DUPLEX, 1)
	ASSERT_EQ(DPX_SPLIT, 3)


; Some contortions to handle stepping up _TO_ a slice end


set_channel_step:

	ld a, (band_step)
	call channel_step_parms

	ld (rx_bstep_cfg), bc
	ld (tx_bstep_cfg), bc  ; XXX no need to force same stepping tx/rx
	ld (rx_refdiv), hl
	ld (tx_refdiv), hl

	ld (band_step_hz), de
	ret

	; A has logical channel step designator

channel_step_parms:

	ld hl, #TCXO / 25 * 2  ; phys 12.5
	ld bc, #25 | (1 << 8)

	ld de, #25             ; user visible 25, 12.5 phys.
	cp #STEP_25
	ret z

	ld de, #12             ; user visible 12.5, 12.5 phys
	cp #STEP_12
	ret z

	ld hl, #TCXO / 10      ; phys 10
	ld bc, #10

	ld de, #20             ; user visible 20, 10 phys
	cp #STEP_20
	ret z

	ld de, #10             ; user visible 10, 10 phys
	cp #STEP_10
	ret z

	ld hl, #TCXO / 15      ; phys 15
	ld bc, #15

	ld de, #15             ; user visible 15, 15 phys.
	cp #STEP_15
	ret z

	ld hl, #TCXO / 25 * 4
	ld bc, #25 | (2 << 8)    ; 25/4
	ld de, #6
	cp #STEP_6
	ret z

	ld hl, #TCXO / 25 * 2
	ld bc, #25 | (1 << 8)    ; 25/2
	ld de, #25

	ret


	; AHL has divisor, BC has step config

div2freq:

	call mul248         ; AHL * C -> CYAHL
	inc b
	jr 2f
1:
	rr a
	rr h
	rr l
	and a
2:
	djnz 1b

	ret

	;
	;	freq / 25 * 2 = linear divisor
	;	AHL has freq in Hz, BC has step config
	;

freq2div:

	call div248         ; AHL / C -> HL,A
	ld e, #0				; MSb
	inc b
	jr 2f
1:
	scf					; remainder * 2 + 1
	rl a				; 
	cp c				; compare with divider
	jr c, 3f
	sub c
3:
	ccf
	rl l				; and shift in
	rl h
	rl e
2:
	djnz 1b

	; divisor almost there, check last remainder 
	rl a
	cp c
	jr c, 3f
	inc l
	jr nz, 3f
	inc h
	jr nz, 3f
	inc e
3:
	call check_and_clamp_divisor  ; EHL -> AHL
	ret

check_and_clamp_divisor:
	ld a, (cfg_synth_card)
	cp #S8D
	ld a, e       ; get 3rd byte of divisor
	jr nz, 1f     ; go if RC58 or RB58 case
	cp #2          ; RD58 case
	ret c         ; ok, E was 0/1, AHL now 0/1HL
	imm_ahl(0x1FFFF)
	ret
1:
	or a
	ret z         ; ok, E was 0, AHL now 0HL, RC58 and RB58 case
	imm_ahl(0xFFFF)
	ret


halt_txsynth:
	ld a, (synth_ctrl)
	set 2, a                ; cut supply, prediv & pll
	res 3, a                ; cut supply, vco and amps
	ld (synth_ctrl), a
	jr load_synth_ctrl

enable_txsynth:
	ld a, (synth_ctrl)
	res 2, a                ; supply on, prediv & pll
	set 3, a                ; supply on, vco and amps
	ld (synth_ctrl), a
	jr load_synth_ctrl

synth_dev_and_ctrl_into_c:
	rlca
	rlca
	rlca
	rlca
	and #0xF0
	ld c, a
	ld a, (synth_ctrl)
	and #0x0F
	or c
	ld c, a
	ret

load_synth_ctrl:
	ld a, (cfg_deviation_fone)
	call synth_dev_and_ctrl_into_c

	ld a, #O1_TXOFF
	out (OUT1), a

	ld b, #8
	call send_to_synth

	or #O1_SCE
	call strobe_to_synth
	ret

change_to_signalling_deviation:
	ld a, (cfg_deviation_sign)
	call synth_dev_and_ctrl_into_c

	ld a, (txon)
	or a
	ld a, #O1_TXOFF
	jr z, 1f
	xor a
1:
	out (OUT1), a

	ld b, #8
	call send_to_synth

	or #O1_SCE
	call strobe_to_synth
	ret

load_txsynth:

	; Control register, tx vco band A/B  and txsynth ON bits

	call enable_txsynth

	; Channel spacing - R

	ld a, #O1_TXOFF
	out (OUT1), a

	ld hl, (tx_refdiv)
	ld c, h
	ld b, #8			; has excess bits... they overflow ok
	call send_to_synth
	ld c, l
	ld b, #8
	call send_to_synth

	call one_to_synth	; single "1" bit - to R register

	or #O1_STE
	call strobe_to_synth

	; Divisor

	load_ahl(tx_divisor)
	ld e, a

	ld d, #O1_STE
	call send_NA_to_synth

	ret

load_rxsynth:

	; Control register, rx vco band A/B

	call load_synth_ctrl

	; Channel spacing - R

	ld a, #O1_TXOFF
	out (OUT1), a

	ld hl, (rx_refdiv)	; channel spacing
	ld c, h
	ld b, #8			; has excess bits... they overflow ok
	call send_to_synth
	ld c, l
	ld b, #8
	call send_to_synth

	call one_to_synth	; single "1" bit - to R register

	or #O1_SRE
	call strobe_to_synth

	; Divisor

	load_ahl(rx_divisor)
	ld e, a

	ld d, #O1_SRE
	call send_NA_to_synth

	ret

;----------------------------------------------------------------------

	;
	;  10 bits of N, 7 bits of A, single zerobit to selector
	;
	;  RD58  NNNNNNNNNNAAAAAAA
	;        GFEDCBA9876543210 effective bit numbers
	;        EHHHHHHHHLLLLLLLL
	;
	;  RB58S
	;  RC58  NNNNNNNNNN0AAAAAA
	;        FEDCBA9876 543210 effective bit numbers
	;        HHHHHHHHLL LLLLLL
	;        
	;  NA in EHL register triple

send_NA_to_synth:
	ld a, (cfg_synth_card)
	cp #S8D
	jp nz, send_NA_64_to_synth   ; RB58 or RC58

	; RD58 default synthesizer S8D, fall thru to

send_NA_128_to_synth:

	; A used thru routine

	ld a, #O1_TXOFF
	out (OUT1), a

	; MSbit of N

	ld c, e
	rrc c				; Align lowest bit for MSb first shifting just 1 bit
	ld b, #1
	call send_to_synth	; send MSb (lowest of e)

	; Rest of NA

	ld c, h
	ld b, #8
	call send_to_synth
	ld c, l
	ld b, #8
	call send_to_synth

	call zero_to_synth	; single "0" bit - to A/N registers

	or d
	call strobe_to_synth	; which synth

	ret

send_NA_64_to_synth:

	; A used thru routine

	ld a, #O1_TXOFF
	out (OUT1), a

	; NA

	ld c, h
	ld b, #8
	call send_to_synth
	ld c, l
	ld b, #2
	call send_to_synth
	call zero_to_synth	; pad for 64/65 prescaler, instead of linear 128/129
	ld b, #6
	call send_to_synth

	call zero_to_synth	; single "0" bit - to A/N registers

	or d
	call strobe_to_synth	; which synth

	ret


strobe_to_synth:

	out (OUT1), a
	and #~(O1_SCE | O1_STE | O1_SRE | O1_SD)
	out (OUT1), a
	ret

send_to_synth:
2:
	rl c
	jr c, 1f
	call zero_to_synth
	djnz 2b
	ret
1:
	call one_to_synth
	djnz 2b
	ret

zero_to_synth:

	and #~O1_SD
	out (OUT1), a
	or #O1_CLK
	out (OUT1), a
	and #~(O1_CLK)
	out (OUT1), a

	ret

one_to_synth:

	or #O1_SD
	out (OUT1), a
	or #O1_CLK
	out (OUT1), a
	and #~(O1_CLK)
	out (OUT1), a

	ret

;----------------------------------------------------------------------

shift_external_serial_A:

	ld hl, (cfg_external_serial_A)
	ld b, #16
	ld c, #O1_RAS
	jr 1f

	; JUMP THRU

shift_external_serial_B:

	ld hl, (cfg_external_serial_B)
	ld a, l
	or h
	ret z                   ; 0 = not in use.

	ld b, #16
	ld c, #O1_TPS
1:

	ld a, #O1_TXOFF
2:
	and #~O1_SD
	sla l
	rl h                    ; HL to the left, hibit to CY
	jr nc, 1f
	or #O1_SD
1:
	out (OUT1), a           ; SD changes
	nop
	or #O1_CLK
	out (OUT1), a           ; CLK rises
	nop
	and #~O1_CLK
	out (OUT1), a           ; CLK drops

	djnz 2b                 ; all 16 bits

	nop
	nop
	push af                 ; remember byte without strobe
	or c
	out (OUT1), a           ; load pulse rises, about 1 usec
	nop
	nop
	pop af
	out (OUT1), a           ; load pulse drops

	and #~O1_SD
	out (OUT1), a           ; SD returned 0 just for fun

	ret

;======================================================================

;
;  Key up TX
;
real_txpwr:
	push hl
	ld a, (cfg_txpwr)
	ld hl, #txpwr_increment
	add a, (hl)
	jr nc, 1f
	sbc a, a                    ; FF to A
1:
	pop hl
	ret                      ; A has real tx power (still just a byte)

update_txpwr_if_tx:
	ld a, (txon)
	or a
	ret z

	; FALLTHRU

update_txpwr:
	call real_txpwr
	out (DA_TXPWR), a
	ret

zero_txpwr:
	xor a
	out (DA_TXPWR), a
	ret

tx_on:
	call scanner_stop

	ld a, (tx_is_legal)
	sub #1
	ret c                           ; outside band

	; fallthru

tx_on_legal_or_not:

	ld a, (cfg_tx_tot_minutes)      ; TOT=0 means no TX anywhere
	sub #1
	ret c

	call update_LPF

	di
	xor a
	ld (tx_tot_timer), a
	inc a
	ld (txon), a

	call stop_marker_tone
	call tx_cut_local_audio
	ei

	ld a, #O1_TXOFF
	out (OUT1), a
	call zero_txpwr
	call load_txsynth

	; wait synthesizer - XXX sloppy

	ld a, (cfg_pll_delay)
1:
	sub #1
	jr c, 1f
	halt                       ; 1 / 1986.75Hz really - half a millisec
	jr 1b
1:

	; /TXON and TPC=pwr

	xor a
	out (OUT1), a
	call update_txpwr

	call light_transmit_led
	and a					; return carry clear
	ret


tx_off:
	call ctcss_off                ; XXX potentially CTCSS-less tail of some msec

	ld a, #O1_TXOFF
	out (OUT1), a
	call zero_txpwr

	xor a
	ld (txon), a

	call halt_txsynth

#if 0
	xor a
	ld (alert_timer), a
#endif

	call dim_transmit_led
	call resync_squelch_if_forced
	ret

;======================================================================

	; this needs no align
keytbl_cu53an:
	.db 'Z','Z','Z','Z','Z','Z','Z','Z'
	.db 'Z','Z','Z','Z','+','-','?','B'
	.db 'E','*', 0,'#','R', 7, 8, 9
	.db 'S', 4, 5, 6,'C', 1, 2, 3

	; this needs no align
keytbl_cu58af:
	.db 'Z','Z','B', 4, 2, 1, 5, 6
	.db  3, 7, 8, 9,'*', 0,'#','-'
	.db 'C','E','+','S','R','Z','Z','Z'
	.db 'Z','Z','Z','Z','Z','Z','Z','Z'
	.db 'Z','Z','Z','Z','Z','Z','Z','Z'

	; this needs no align
ccirtbl:
	.dw MT_CALCHZ(1981) ; 0
	.dw MT_CALCHZ(1124) ; 1
	.dw MT_CALCHZ(1197) ; 2
	.dw MT_CALCHZ(1275) ; 3
	.dw MT_CALCHZ(1358) ; 4
	.dw MT_CALCHZ(1446) ; 5
	.dw MT_CALCHZ(1540) ; 6
	.dw MT_CALCHZ(1640) ; 7
	.dw MT_CALCHZ(1747) ; 8
	.dw MT_CALCHZ(1860) ; 9
	.dw MT_CALCHZ(2400) ; A
	.dw MT_CALCHZ( 930) ; B
	.dw MT_CALCHZ(2247) ; C
	.dw MT_CALCHZ( 991) ; D
	.dw MT_CALCHZ(2110) ; E
	.dw 4               ; F

;
;  -----       3
;  |\|/|   6 2 E F B
;  -- --     5   A
;  |/|\|   4 0 1 D 9
;  -----       C

	; this needs no align
cu58af_font:

	        ; FEDCBA9876543210
	.dw	0b1001101001011001	; 0
	.dw	0b0100000000000010	; 1
	.dw	0b0001110000111000	; 2
	.dw	0b0001111000101000	; 3
	.dw	0b0000111001100000	; 4
	.dw	0b0001011001101000	; 5
	.dw	0b0001011001111000	; 6
	.dw	0b0000101000001000	; 7
	.dw	0b0001111001111000	; 8
	.dw	0b0001111001101000	; 9
	.dw	0b0000111001111000	; A
	.dw	0b1011000001111000	; B
	.dw	0b0001000001011000	; C
	.dw	0b0101101000001010	; D
	.dw	0b0001010001111000	; E
	.dw	0b0000010001111000	; F
	        ; FEDCBA9876543210

	.dw	0b0001011001011000	; G
	        ; FEDCBA9876543210

	.org cu58af_font + 2*' '

	        ; FEDCBA9876543210
	.dw	0b0000000000000000	;   	- - - -   - - -
	.dw	0b1001000110001100	; ! 	- - 2 3   - - -
	.dw	0b0100000111000000	; " 	0 - - 3   - - -
	.dw	0b0001011110110000	; # 	- 1 2 -   - 5 6
	.dw	0b0101011111101010	; $ 	0 - 2 -   - 5 -
	.dw	0b1000001111000001	; % 	0 - 2 -   - - -
	.dw	0b1011000110001101	; & 	- 1 - 3   - 5 6
	.dw	0b0000000111000000	; ' 	- - - 3   - - -
	.dw	0b1010000110000000	; ( 	- - 2 3   - - -
	.dw	0b0000000110000101	; ) 	0 1 - -   - - -
	.dw	0b1110010110100111	; * 	- - - -   4 5 6
	.dw	0b0100010110100010	; + 	0 1 - -   - 5 -
	.dw	0b0000000110000001	; , 	- 1 - -   - - -
	.dw	0b0000010110100000	; - 	- - - -   - 5 -
	.dw	0b0000000110010000	; . 	- 1 - -   - - -
	.dw	0b1000000110000001	; / 	- 1 - 3   - 5 -
	.dw	0b1001101001011001	; 0
	.dw	0b0100000000000010	; 1
	.dw	0b0001110000111000	; 2
	.dw	0b0001111000101000	; 3
	.dw	0b0000111001100000	; 4
	.dw	0b0001011001101000	; 5
	.dw	0b0001011001111000	; 6
	.dw	0b0000101000001000	; 7
	.dw	0b0001111001111000	; 8
	.dw	0b0001111001101000	; 9
	.dw	0b0000000111010000	; : 	- - - -   4 - 6
	.dw	0b0100000110000001	; ; 	- - - 3   - - 6
	.dw	0b1010000110000000	; < 	- - 2 3   - 5 -
	.dw	0b0001010110100000	; = 	- - - -   - 5 6
	.dw	0b0000000110000101	; > 	0 1 - -   - 5 -
	.dw	0b1000000110001010	; ? 	- 1 - 3   4 5 -
	.dw	0b0101110111011000	; @ 	- 1 2 3   4 5 6
	        ; FEDCBA9876543210
	.dw	0b0000111001111000	; A
	.dw	0b1011000001111000	; B
	.dw	0b0001000001011000	; C
	.dw	0b0101101000001010	; D
	.dw	0b0001010001111000	; E
	.dw	0b0000010001111000	; F
	.dw	0b0001011001011000	; G
	.dw	0b0000111111110000	; H		0 1 2 3   - 5 -
	.dw	0b0101000110001010	; I 	- - 2 3   - - -
	.dw	0b0001101110010000	; J 	- 1 2 3   - - 6
	.dw	0b1010000111110000	; K 	- 1 2 3   - - 6
	.dw	0b0001000111010000	; L		0 1 - -   - - 6
	.dw	0b1000101111010100	; M		0 1 2 3   4 - -
	.dw	0b0010101111010100	; N		- 1 2 -   - 5 -
	.dw	0b0001101111011000	; O 	0 1 2 3   4 - 6
	.dw	0b0000110111111000	; P 	0 1 - 3   4 5 -
	.dw	0b0011101111011000	; Q 	0 - 2 3   4 5 -
	.dw	0b0010110111111000	; R		0 1 - 3   4 - -
	.dw	0b0011000110001100	; S 	0 - 2 -   4 5 6
	.dw	0b0100000110001010	; T		0 1 - -   4 - -
	.dw	0b0001101111010000	; U 	0 1 2 3   - - 6
	.dw	0b1000000111010001	; V 	0 1 2 3   - - 6
	.dw	0b0010101111010001	; W 	0 1 2 3   - - 6
	.dw	0b1010000110000101	; X		- - - -   4 5 6
	.dw	0b1000000110000110	; Y 	0 - 2 3   - 5 6
	.dw	0b1001000110001001	; Z 	- 1 - 3   4 5 6
	.dw	0b0000000110000000	; [ 	0 1 - -   4 - 6
	        ; FEDCBA9876543210
	.dw	0b0010000110000100	; \ 	0 - 2 -   - 5 -
	.dw	0b0000000110000000	; ] 	- - 2 3   4 - 6
	.dw	0b0000000110000000	; ^ 	- - - -   4 - -
	.dw	0b0001000110000000	; _ 	- - - -   - - 6
	.dw	0b0000000110000100	; ` 	0 - - -   - - -

	.dw	0b0000111001111000	; a
	.dw	0b1011000001111000	; b
	.dw	0b0001000001011000	; c
	.dw	0b0101101000001010	; D
	.dw	0b0001010001111000	; E
	.dw	0b0000010001111000	; F
	.dw	0b0001011001011000	; G
	.dw	0b0000111111110000	; H		0 1 2 3   - 5 -
	.dw	0b0101000110001010	; I 	- - 2 3   - - -
	.dw	0b0001101110010000	; J 	- 1 2 3   - - 6
	.dw	0b1010000111110000	; K 	- 1 2 3   - - 6
	.dw	0b0001000111010000	; L		0 1 - -   - - 6
	.dw	0b1000101111010100	; M		0 1 2 3   4 - -
	.dw	0b0010101111010100	; N		- 1 2 -   - 5 -
	.dw	0b0001101111011000	; O 	0 1 2 3   4 - 6
	.dw	0b0000110111111000	; P 	0 1 - 3   4 5 -
	.dw	0b0011101111011000	; Q 	0 - 2 3   4 5 -
	.dw	0b0010110111111000	; R		0 1 - 3   4 - -
	.dw	0b0011000110001100	; S 	0 - 2 -   4 5 6
	.dw	0b0100000110001010	; T		0 1 - -   4 - -
	.dw	0b0001101111010000	; U 	0 1 2 3   - - 6
	.dw	0b1000000111010001	; V 	0 1 2 3   - - 6
	.dw	0b0010101111010001	; W 	0 1 2 3   - - 6
	.dw	0b1010000110000101	; X		- - - -   4 5 6
	.dw	0b1000000110000110	; Y 	0 - 2 3   - 5 6
	.dw	0b1001000110001001	; Z 	- 1 - 3   4 5 6

	.dw	0b0000000110000000	; { 	- 1 - -   - 5 6
	.dw	0b0100000110000010	; | 	- 1 - -   - - -
	.dw	0b0000000110000000	; } 	- - 2 -   - 5 6
	.dw	0b0000000110001000	; ~ 	- - - -   4 - -
	.dw	0b0000000110000000	; ^? 	- 1 - 3   4 5 6

	ASSERT_EQ((. - cu58af_font), (2 * 128))

;=========================================================================

knots_to_kmh:
	push hl
	ld bc, #-138         ; 138 knots = 256 km/h
	add hl, bc          ; is HL over 138 ?
	pop hl
	jr c, 1f            ; overflow at 255 km/h

	; 237 / 128 = 1.851562 and 256 - 16 - 2 - 1 = 237

	push hl             ; -1

	add hl, hl          ; 2 times         256 * 137 is 35k, fits ok
	push hl             ; -2              no need to check overflows here
	add hl, hl          ; 4 times
	add hl, hl          ; 8 times
	add hl, hl          ; 16 times
	push hl             ; -16
	add hl, hl          ; 32 times
	add hl, hl          ; 64 times 
	add hl, hl          ; 128 times
	add hl, hl          ; 256 times       carry is clear

	pop bc
	sbc hl, bc          ; 256 - 16        carry stays clear in these
	pop bc
	sbc hl, bc          ; 256 - 16 - 2
	pop bc
	sbc hl, bc          ; 256 - 16 - 2 - 1

	ld a, h             ; seven MSbits of result
	rl l                ; LSbit of result to CY
	rla                 ; MSbits into position and LSbit insertion
	ret
1:
	sbc a, a               ; 255 and CY set - CY was set at jr location above
	ret


;=================================================================

tab_fx465:              ; Hz and D5...D0
	.db  67, 0x3F
	.db  69, 0x39
	.db  71, 0x1F
	.db  74, 0x3E
	.db  77, 0x0F
	.db  79, 0x3D
	.db  82, 0x1E
	.db  85, 0x3C
	.db  88, 0x0E
	.db  91, 0x3B
	.db  94, 0x1D
	.db  97, 0x3A
	.db 100, 0x0D
	.db 103, 0x1C
	.db 107, 0x0C
	.db 110, 0x1B
	.db 114, 0x0B
	.db 118, 0x1A
	.db 123, 0x0A
	.db 127, 0x19
	.db 131, 0x09
	.db 136, 0x18
	.db 141, 0x08
	.db 146, 0x17
	.db 151, 0x07
	.db 156, 0x16
	.db 159, 0x31
	.db 162, 0x06
	.db 167, 0x15
	.db 173, 0x05
	.db 179, 0x14
	.db 183, 0x32
	.db 186, 0x04
	.db 189, 0x33
	.db 192, 0x13
	.db 196, 0x34
	.db 199, 0x35
	.db 203, 0x03
	.db 206, 0x36
	.db 210, 0x12
	.db 218, 0x02
	.db 225, 0x11
	.db 229, 0x37
	.db 233, 0x01
	.db 241, 0x10
	.db 250, 0x00
	.db 254, 0x38

	.db 255  ; end marker


;======================================================================
;
; OUT2 emits CTCSS square wave.
;
; This needs a rewire of the timer CLK2 from the same place as
; CLK0 and CLK1, 4.032 MHz. Otherwise the tones are just too wrong.
; After the rewire the result is very accurate.
;
; Please cut the CLK2 wire into "keskeytyskytkenta" too.

get_ctcss_tx_hz:

	ld a, (mem_flags)
	and #MEM_VALID

	ld a, (cfg_ctcss_tx_hz)
	ret z                  ; not on memory
	ld a, (mem_ctcss_tx_hz)
	ret                    ; on memory


get_ctcss_rx_hz:

	ld a, (mem_flags)
	and #MEM_VALID

	ld a, (cfg_ctcss_rx_hz)
	ret z                  ; not on memory
	ld a, (mem_ctcss_rx_hz)
	ret                    ; on memory


ctcss_off:
	call ctcss_off_nohang

	ld a, (cfg_ctcss_hang)    ; msec
	or a
	ret z                     ; none
1:
	halt          ; XXX gross !
	halt          ; XXX and not quite millisecond units in cfg parameter.
	dec a
	jr nz, 1b

	ret


ctcss_off_nohang:

	xor a
	ld (ctcss_is_on), a   ; clear the flag

	; 12 cycles of ctcss in systicks is 1200 / Hz.

	ld a, (cfg_ctcss_output_method)
	dec a                         ; if 1
	jp z, ctcss_generator_off     ; RFC DAC method - off
	dec a                         ; if 2
	jr z, ctcss_fx465_off         ; addon FX465 method - off

	; and else, default, plain and simple i8253 generator off

	ld a, #TMR_2 | TMR_LSB | TMR_INTTC
	out (TMR + TMRCTRL), a
	ld a, #1
	out (TMR + 2), a     ; low for one clock, then rise and stay

	ret

ctcss_fx465_off:

	; FX465 generator off (into RX mode)

	call get_ctcss_rx_hz
	jp ctcss_fx465_rx


ctcss_maybe:

	call get_ctcss_tx_hz
	or a
	jr z, ctcss_off_nohang     ; tx hz is zero means off.

	ld c, a               ; keep here for a while
	ld (ctcss_is_on), a   ; also a flag, nz or not. now nz

	; ctcss is wanted, but how ?

	ld a, (cfg_ctcss_output_method)
	dec a                         ; if 1
	jp z, ctcss_generator_on      ; RFC DAC method
	dec a                         ; if 2
	jp z, ctcss_fx465_on          ; addon FX465 method (past the tables)

	; and else, default, plain and simple i8253 generator on
	; CTCSS proper frequency OH5NXO/OH1E

        ld hl, #ctcss_counter_counts ; constant table
        ld b, #0                     ; BC holds the CTCSS setting
        add hl, bc
        add hl, bc                  ; index by words

        ld a, #TMR_2 | TMR_BOTH | TMR_SQWAVE
        out (TMR + TMRCTRL), a      ; control register

        ld c, #TMR + 2               ; count register
        outi                        ; out [c], [hl++]; b--
        outi                        ; and msbyte
	ret

#define CTCSS_TONES \
        CTCSS_RECORD(670) \
	CTCSS_RECORD(693) \
	CTCSS_RECORD(719) \
        CTCSS_RECORD(744) \
	CTCSS_RECORD(770) \
	CTCSS_RECORD(797) \
        CTCSS_RECORD(825) \
	CTCSS_RECORD(854) \
	CTCSS_RECORD(885) \
        CTCSS_RECORD(915) \
	CTCSS_RECORD(948) \
	CTCSS_RECORD(974) \
        CTCSS_RECORD(1000) \
	CTCSS_RECORD(1035) \
	CTCSS_RECORD(1072) \
        CTCSS_RECORD(1109) \
	CTCSS_RECORD(1148) \
	CTCSS_RECORD(1188) \
        CTCSS_RECORD(1230) \
	CTCSS_RECORD(1273) \
	CTCSS_RECORD(1318) \
        CTCSS_RECORD(1365) \
	CTCSS_RECORD(1413) \
	CTCSS_RECORD(1462) \
        CTCSS_RECORD(1514) \
	CTCSS_RECORD(1567) \
	CTCSS_RECORD(1622) \
        CTCSS_RECORD(1679) \
	CTCSS_RECORD(1738) \
	CTCSS_RECORD(1799) \
        CTCSS_RECORD(1862) \
	CTCSS_RECORD(1928) \
	CTCSS_RECORD(2035) \
        CTCSS_RECORD(2066) \
	CTCSS_RECORD(2107) \
	CTCSS_RECORD(2181) \
        CTCSS_RECORD(2257) \
	CTCSS_RECORD(2291) \
	CTCSS_RECORD(2336) \
        CTCSS_RECORD(2418) \
	CTCSS_RECORD(2503) \
	CTCSS_RECORD(2541)

#undef  CTCSS_RECORD
#define CTCSS_RECORD(dHz) .dw (4032000 * 10) / (dHz) @

ctcss_counter_counts:
        .dw 0        ; unused, setting "oFF"
        CTCSS_TONES

;  The TX tone setting (GE:CtCSSt, a TAB) is an index into the list above;
;  the RFC DAC DDS and the FX465 want Hz.  v3_Z passed them the index
;  (97.4 Hz played as 12 Hz).  Rounded Hz: the FX465 table takes Hz or Hz-1.

#undef  CTCSS_RECORD
#define CTCSS_RECORD(dHz) .db ((dHz) + 5) / 10 @

ctcss_tone_hz:
        .db 0        ; "oFF"
        CTCSS_TONES
ctcss_tones = . - ctcss_tone_hz

get_ctcss_tx_tone_hz:		; A = Hz of the TX tone setting, 0 = off
	call get_ctcss_tx_hz
	cp #ctcss_tones
	jr c, 1f
	xor a                   ; past the list: off
1:
	push hl
	ld hl, #ctcss_tone_hz
	add a, l
	ld l, a
	adc a, h
	sub l
	ld h, a
	ld a, (hl)
	pop hl
	ret


	; FX465 generator on XXX this check is now redundant, with method tab

ctcss_fx465_on:

	ld a, (cfg_function)
	or a
	ret nz                 ; cannot tx with FX465 in duplex functions.

	call get_ctcss_tx_tone_hz ; the setting is an index, FX465 wants Hz
	jr ctcss_fx465_tx


;----------------------------------------------------------------------

ctcss_fx465_tx:

	ld d, #0               ; /TX
	jr load_fx465

ctcss_fx465_rx:

	ld d, #1               ; RX
	jr load_fx465


load_fx465:

	ld e, #0x30            ; default to NOTONE
	or a
	jr z, 2f              ; Hz=0, no tone

	ld c, a
	ld hl, #tab_fx465
1:
	ld a, c               ; our Hz
	sub (hl)
	jr c, 2f              ; Hz in table is greater, not there.

	jr z, 1f              ; Hz found in table
	dec a
	jr z, 1f              ; Hz - 1 found in table, take it.
	inc hl
	inc hl                ; over Hz and data, into next row
	jr 1b
1:
	inc hl
	ld e, (hl)            ; pick the data
2:
	rr d                  ; CY has RX/TX
	rl e                  ; shift RX/TX from bottom to data
	sla e                 ; shift in PTL=0

	; E has databyte for fx465

	ld b, #8               ; D5...D0 and RXTX and PTL - 8 bits

	ld a, (txon)
	or a
	ld a, #O1_TXOFF
	jr z, 2f
	xor a
2:
	and #~O1_SD
	sla e
	jr nc, 1f
	or #O1_SD
1:
	out (OUT1), a         ; SD changes
	nop
	or #O1_CLK
	out (OUT1), a         ; CLK up
	nop
	and #~O1_CLK
	out (OUT1), a         ; CLK down
	djnz 2b               ; more bits ?

	or #O1_TPS
	out (OUT1), a         ; Load /
	nop
	and #~O1_TPS
	out (OUT1), a         ; Latch \ and finally
	nop
	and #~O1_SD
	out (OUT1), a         ; done.

	ret


;----------------------------------------------------------------------
;
;  input: tone frequency in rounded Hz, 64...255, in A
;  output: phase increment for 1968.75 Hz interrupt in HL

ctcss_hz_to_phase_inc:

	ld b, a          ; Hz

	xor a
	ld l, a
	ld h, a          ; AHL zeroed
	ld c, a
	ld de, #8522      ; XXX 65536 / 1968.75 * 256 scale for accuracy
1:
	add hl, de
	adc a, c
	djnz 1b          ; slow multiply AHL = B * CDE

	rl l             ; round at 0.5
	ld l, h
	ld h, a          ; undo scale with /= 256
	ret nc
	inc hl           ; round at 0.5
	ret


;
;  H points to aligned page
;  A has gain, max 127, peak value of sine
;  C has DC component to center the result
;  gain is limited so that result fits in unsigned byte

calculate_sintab:

	; first some dancing

	or a                      ; zero gain ?
	jr nz, 1f
	ld a, #127                 ; XXX 0 means default, try max amplitude
1:
	ld b, a                   ; requested gain, sine peak

	ld a, c                   ; how it is centered ?
	cp #128                    ; positive and negative peaks must fit
	jr c, 1f                  ; limited below DC, if DC less than 128
	neg                       ; limited above DC else
1:
	cp b                      ; possible - requested
	jr nc, 1f                 ; no carry if possible, B is ok
	ld b, a                   ; limit it
1:

	; gain has been checked, do translate the sine

	ld l, #0                   ; index in sin tables, both aligned
2:
	push hl                   ; remember destination page
	ld h, #HI(sinetab)         ; values in sinetab are -127...+127
	ld e, (hl)                ; signed bytes, never -128

	ld a, e                   ; sign extend E to DE
	rla                       ; hibit to carry
	sbc a, a                     ; FF if negative value, 0 if positive or 0
	ld d, a                   ; 16 bit signed value -127...+127 in DE

	ld hl, #0                  ; multiply accumulator
	ld a, b                   ; remember multiplier between rounds
1:
	add hl, de
	djnz 1b                   ; *= gain
	add hl, hl                ; /= 128 rescale, result in H
	rl l                      ; rounding to carry

	ld b, a                   ; reset the multiplier for next round
	ld a, c                   ; DC centering
	adc a, h                     ; add AC component (with rounding from CY)

	pop hl                    ; get back destination page
	ld (hl), a
	inc l
	jr nz, 2b                 ; do them all until index wraps at 256

	ret

ctcss_revector:

	ld a, #LO(pioa_base_during_ctcss)
	out (PIO+ACTRL), a        ; let it rip

	ret

ctcss_generator_on:
ctcss_enc_start:

	;  ctcss_sintab[] = sinetab[] * cfg_ctcss_generator_gain
	;  centered at rfc
	;  gain is limited at such value, that sine does not distort
	;  XXX simplex could merrily skip most of this
	;  XXX rfc cannot be 0 or 255, which it never is, in practice

	ld h, #HI(ctcss_sintab)    ; put the multiplied sine into here

	ld a, (rfc)               ; average of sine must be == RFC
	ld c, a                   ; center result here

	ld a, (cfg_ctcss_generator_gain)

	call calculate_sintab     ; multiplier in A, center in C

	call get_ctcss_tx_tone_hz ; the setting is an index, the DDS wants Hz
	call ctcss_hz_to_phase_inc
	ld (ctcss_enc_phinc), hl

	ld hl, #0
	ld (ctcss_enc_phacc), hl

	ld hl, #ctcss_enc_entry
	ld (ctcss_enc_jump), hl

	jr ctcss_revector

ctcss_generator_off:
ctcss_enc_stop:

	ld hl, #ctcss_enc_skip
	ld (ctcss_enc_jump), hl

	ld a, (rfc)
	out (DA_RFC), a

	ret

ctcss_dec_start:

	call get_ctcss_rx_hz
	call ctcss_hz_to_phase_inc
	ld (ctcss_dec_phinc), hl

	ld hl, #0
	ld (ctcss_dec_phacc), hl

	ld hl, #ctcss_dec_entry
	ld (ctcss_dec_jump), hl

	jr ctcss_revector

init_ctcss:

	ld hl, #ctcss_enc_skip
	ld (ctcss_enc_jump), hl

	; fall thru

ctcss_dec_stop:

	ld hl, #ctcss_dec_skip
	ld (ctcss_dec_jump), hl

	ret

; need to activate software ctcss decoder ?

ctcss_dec_startstop:

	ld a, (cfg_squelch_ctcss) ; are we using ctcss for squelch ?
	or a
	jr z, 1f                  ; ... skip if not.
	call get_ctcss_rx_hz
	or a
	jr z, 1f                  ; ... skip if CTCSS Hz is 0 meaning OFF
	ld a, (cfg_ctcss_input_method)
	or a
	jr nz, 1f                 ; ... skip if method is not dsp
	jr ctcss_dec_start
1:
	jr ctcss_dec_stop


; from systick, see what has happened in tone correlation process

ctcss_dec_periodic:

	ld hl, #ctcss_dec_cnt
	dec (hl)
	ret nz

	ld (hl), #12     ; 120msec; accus fit in -240 ... +240

	; get absolute values of accus

	ld hl, (ctcss_dec_sin)
	ld a, l
	inc h
	jr nz, 1f       ; skip if positive
	neg
1:
	ld b, a         ; abs(sinacc) in B

	ld hl, (ctcss_dec_cos)
	ld a, l
	inc h
	jr nz, 1f
	neg
1:
	ld c, a         ; abs(cosacc) in C and A

	ld hl, #0
	ld (ctcss_dec_sin), hl   ; reset accus
	ld (ctcss_dec_cos), hl

	; pythagoras approximation: larger + smaller / 2. max error about 14%

	cp b            ; 4 see which is smaller
	jr nc, 1f       ; 7/12 go if A=C is already larger or equal
	ld a, b         ; 4 A is now the larger one
	ld b, c         ; 4 and B the smaller one
1:
	srl b           ; 8 unsigned halve
	add a, b           ; 4 A has magnitude
	jr nc, 1f
	sbc a, a           ; clamp at 255 (paranoia)
1:

	ld (ctcss_dec_fit), a    ; store it for perusal

	ld hl, #cfg_ctcss_dec_threshold
	cp (hl)                  ; if detect, carry is clear
	sbc a, a                    ; if detect, 0, else FF
	cpl                      ; flip
	ld (ctcss_dec_status), a ; store 0 if decode

	ret

;======================================================================
;
;  RXD from TCM3105 or FX614 wired to SIO B SYNC input.
;  Side-effects of /LOCAL should be disconnected.
;  Modemchip hardwired for receive.
;  i8254 Timer 2 rewired, 4.032 MHz to CLK2. Now same as CLK0 and CLK1.
;  Side-effects of timer OUT2 should be disconnected too.
;
;  Timer 2   1 / 4032000 = 248 nsec
;  afsk      1 / 1200    = 833 msec
;
;  1 bits count  3360 0x0D20  0 only
;  2 bits count  6720 0x1A40  10
;  3 bits count 10080 0x2760  110
;  4 bits count 13440 0x3480  1110
;  5 bits count 16800 0x41A0  11110
;  6 bits count 20160 0x4EC0  111110     stuffing.
;  7 bits count 23520 0x5BE0  1111110    that is a flag.
;  8 bits count 26880 0x6900  1111111... and this an abort.
;
;  Only the MSByte of the 16 bit count is used.
;
;  Experiments with speaker audio:
;  TCM3105: peak at 1 bittime long pulses.
;  XR2211 with recommended passive components: peak at 0.5 bittime,
;  over 2kHz ints will be tough to take. It could be built to give pulses
;  only when in lock. Should help a lot.
;
;  Most pulses will be around 1 bittime long. Very few will be more than
;  5 bittimes long. The 1-bit case is optimised. Very long falsing pulses
;  from speech etc will not overload cpu anyway.
;

	; man over board, space is tight
#if 0

fx614_bit_edge:               ;  AF and HL trashed.

	in a, (TMR + 2)           ; 11T get the count
	ld h, a                   ;  4T
	xor a                     ;  4T start downcount again
	out (TMR + 2), a          ; 11T good to have constant lag to this point.
	sub h                     ;  4T got the negate for free ! so nice.

	ld hl, (fx614_bufptr)     ; 16T abort() needs H, too.

	sub #0x06                  ;  7T trim by half the length of a single "0".
	jp c, fx614_abort         ; 10T go, if noise. very common case.

	; A.7 must be zero now, if any bit insertion is going to happen.
	; This fact is used below, before the last bitshift.

	cp #0x0D                   ;  7T      "0"
	jp c, 1f                  ; 10T               quite common case.
	cp #0x1A                   ;  7T      "10"
	jp c, 2f                  ; 10T               common case.
	cp #0x27                   ;  7T      "110"
	jr c, 3f                  ;  7T/13T           not so common anymore.
	cp #0x34                   ;  7T      "1110"
	jr c, 4f                  ;  7T/13T
	cp #0x41                   ;  7T      "11110"
	jr c, 5f                  ;  7T/13T
	cp #0x4E                   ;  7T      "11111"  rare cases.
	jr nc, fx614_flag_maybe   ;  7T/13T
	cpl                       ;  4T      Trick the last shift into onebit.
5:
	rr (hl)
	call nc, 8f      ; CY set at jump. "refill" if marker spills out.
4:
	rr (hl)
	call nc, 8f      ; CY set at jump or line above
3:
	rr (hl)
	call nc, 8f      ; 15T + 10T/17T
2:
	rr (hl)
	call nc, 8f
1:
	rla                       ;  4T last bit from A.7
	rr (hl)
	call nc, 8f

	ld (fx614_bufptr), hl     ; 16T keep track of it.
	ret                       ; 10T

	ASSERT_EQ(LO(fx614_buffer), 0)    ; max packet length is 256
8:
	inc l                     ;  4T overflows catched by crc only
	ld (hl), #0x7F             ; 10T reset marker of empty slot.
	scf                       ;  4T for any remaining rotates
	ret                       ; 10T CY clear at entering, SET at return.

fx614_flag_maybe:

	cp #0x5B                   ;  7T length of 6 ones
	jr nc, fx614_abort        ;  7T/13T go, if abort.

	; process any packet and flow thru to clean it up.

	ld a, l                   ;  4T LSByte of pointer is the length
	cp #7 + 7 + 1 + 2          ;  7T dst src control "" crc
	jp c, fx614_abort         ; 10T too short to be a valid ax.25 packet

	push ix                   ; 11T ?
	push bc                   ; 11T

	dec l
	dec l                     ; trim off crc from length
	push hl                   ; remember end of data
	ld b, l                   ; calc() argument

	ld l, #0                   ; buffer address
	push hl
	pop ix                    ; calc() argument

	call calc_ax25_crc        ; lotsa T XXX
	xor (ix + 0)              ; notice the MSByte/LSByte difference
	jr nz, 1f
	ld a, c
	xor (ix + 1)
	jr nz, 1f

	ld hl, #fx614_rxcnt
	inc (hl)
1:
	pop hl                    ; buffer page in H, length in L

	pop bc
	pop ix

	; flip buffers (change H) if packet is okay in current buffer

fx614_abort:                  ; ought to be quick if (yes) called from noise.

	ld l, #0                   ;  7T stay in the same buffer, just rewind to 0.
	ld (hl), #0x7F             ; 10T marker for 8 bits of empty storage here.
	ld (fx614_bufptr), hl     ; 16T remember it.

	ret                       ; 10T


;  Must be called before interrupts are enabled

init_fx614:

	ld hl, #fx614_buffer
	ld (hl), #0x7F             ; after 8 bits shifted in, CY will go clear
	ld (fx614_bufptr), hl     ; rewound.

	ld a, (cfg_fx614_exist)
	or a
	ret z                     ; only if wanted

	ld a, #TMR_2 | TMR_MSB | TMR_INTTC
	out (TMR + TMRCTRL), a

	xor a
	out (TMR + 2), a

	; XXX special siob_esc for this and not cases.

	; XXX of scissors
#endif

	ret

;======================================================================

negate_ahl:
	ld b, a
	ld a, l
	cpl
	add a, #1
	ld l, a
	ld a, h
	cpl
	adc a, #0
	ld h, a
	ld a, b
	cpl
	adc a, #0
	ret

	;
	;  Calculate binary value from unpacked string
	;  Return in CY AHL
	;
a2i:
	push bc
	push de
	push ix

	ld hl, #digidx
	ld b, (hl)      ; so many digits

	xor a
	ld (hl), a      ; digit buffer is cleared
	ld l, a         ; AHL starts from 0x000000
	ld h, a
	cp b            ; NC if Z
	jr z, 2f        ; no digits ?

	ld ix, #digbuf
1:
	add hl, hl
	rla    ; 2 times
	ld e, l
	ld d, h
	ld c, a
	add hl, hl
	rla
	add hl, hl
	rla    ; 8 times
	add hl, de
	adc a, c  ; AHL *= 10

	ld e, (ix)
	ld d, #0
	add hl, de
	adc a, d
	inc ix             ; AHL += *digptr++
	djnz 1b
2:
	pop ix
	pop de
	pop bc
	ret					; result in AHL


;	Multiply AHL by C, 1..
;	Result to CY AHL

mul248:

	push bc
	push de

	ld e, l
	ld d, h
	ld b, a
	and a			; clear carry
1:
	dec c
	jr z, 1f
	adc hl, de
	adc a, b
	jr nc, 1b
	imm_ahl(0xFFFFFF)
1:
	pop de
	pop bc

	ret

;----------------------------------------------------------------------
;
; Divide AHL by C, result left in HL, remainder in A.
;
; Origin: Trash-80 Assembly Language Subroutines, William Barden 1982.
;

div248:

	push bc

	ld b, #16	; do this 16 times.
2:
	add hl, hl	; rotate AHL one bit
	adc a, a		; position to the left.
	sub c
	jr c, 1f
	inc hl		; set lsb of hl, a bit into quotient.
	djnz 2b
	jr 3f
1:
	add a, c		; oops, should not have subtracted.
	djnz 2b
3:
	pop bc

	ret

;  div248 needs 2 * remainder + 1 < 256, i.e. C < 128 in general; this one
;  takes any C (a remainder doubled past 8 bits is always >= C).  AHL / C
;  -> HL, remainder A.  v3_Z used div248 for the CW slot and pitch counts:
;  speeds from 164 CPM gave 0-tick slots, many pitches from 1280 Hz were off.
div248_full:

	push bc

	ld b, #16
2:
	add hl, hl
	adc a, a
	jr c, 4f		; 9-bit remainder
	sub c
	jr c, 1f
3:
	inc hl
	djnz 2b
	jr 5f
4:
	sub c			; 256 + A - C < C: fits
	jr 3b
1:
	add a, c
	djnz 2b
5:
	pop bc

	ret

;======================================================================

lookup_rfc:
	call get_rfc_hl
	ld a, (hl)
	ld (rfc), a
	out (DA_RFC), a
	ret

save_rfc:
	call get_rfc_hl
	ld a, (rfc)
	ld (hl), a
	out (DA_RFC), a
	call save_nvdata
	ret

;
;  Receiver frequency is first modulo 100MHz, then modulo 1MHz.
;  Each "band" overwrite others, but, for ham bands values dont overlap
;  432..438 -> 32..38
;  144..146 -> 44..46
;   50.. 52 -> 50..52
;
get_rfc_hl:
	load_ahl(rx_freq)

	ld de, #100000 % 65536
	ld c,  #100000 / 65536
	and a                     ; clear CY
1:
	sbc hl, de
	sbc a, c
	jr nc, 1b                 ; modulo down to 0...99999
	add hl, de
	adc a, c

	ld c, #-1                  ; index [0...99]
	ld de, #1000
	and a
1:
	inc c
	sbc hl, de
	sbc a, #0
	jr nc, 1b

	ld hl, #rfctab
	ld b, #0
	add hl, bc
	ret

;======================================================================

save_nvmisc_and_restart:

	ld a, i
	or a
	jp z, 2f                     ; IV still 0 - don't mess nvram

#ifdef P8N
	ld hl, #nvstart
	LD_A_OUT2(O2_LCD1 | O2_SMEM)
	ld e, a			; normal: SMEM=1
	and #~O2_SMEM
	ld d, a			; battery RAM: SMEM=0
	ld c, #OUT2
1:
	out (WD), a

	ld a, (hl)
	out (c), d
	ld (hl), a
	out (c), e
	inc hl
	ld a, h
	cp #HI(nvend)
	jp nz, 1b
	ld a, l
	cp #LO(nvend)
	jp nz, 1b
#endif

2:
	ld sp, #1f
	retn			; restart to (IFF1 still clear)
1:
	.dw start		; retn to start

save_nvdata:

	ld a, i
	or a
	jp z, 2f                     ; IV still 0 - don't mess nvram

#ifdef P8N
	ld hl, #nvstart
	LD_A_OUT2(O2_LCD1 | O2_SMEM)
	ld e, a			; normal: SMEM=1
	and #~O2_SMEM
	ld d, a			; battery RAM: SMEM=0
	ld c, #OUT2
1:
	ld a, (hl)
	di
	out (c), d
	ld (hl), a
	out (c), e
	ei
	inc hl
	ld a, h
	cp #HI(nvend)
	jr nz, 1b
	ld a, l
	cp #LO(nvend)
	jr nz, 1b
#endif

2:
	ret

load_nvdata:

#ifdef P8N
	ld hl, #nvstart
	LD_A_OUT2(O2_LCD1 | O2_SMEM)
	ld e, a			; normal: SMEM=1
	and #~O2_SMEM
	ld d, a			; battery RAM: SMEM=0
	ld c, #OUT2
1:
	out (WD), a
	out (c), d
	ld a, (hl)
	out (c), e
	ld (hl), a
	inc hl
	ld a, h
	cp #HI(nvend)
	jr nz, 1b
	ld a, l
	cp #LO(nvend)
	jr nz, 1b
#endif

	ret

;========================================================================
;
;  Bitbang DTMF out from 8254 timer 1 (the CCIR/MARKER pin).
;
;  Z80  clock   4.032 MHz     ~248 nsec cycle
;  8254 clock 1 4.032 MHz     ~248 nsec cycle

;  A fixed time (interrupts disabled) program loop is used to create
;  a time cell of 130T times (32.2 usec).
;  There is no padding in the P8N-loop, but creating the time-bound
;  loop later will use less T-times, so it's ok
;  (looping ix=10000 will be 322 msec).
;
;  The 8254 timer is temporarily reprogrammed for mode0
;  ("interrupt on terminal count") and LSB-only r/w operations.
;  The loop has a constant execution time, no inner branches at all.
;
;  The loop calculates sin(low)+sin(high) from table, with DDS;
;  sinus table is scaled from 1...64 so sum range is 2...128 inclusive.
;
;  Using timer mode 0; the output goes low when the count is written.
;  after the count decrements to 0 the output rises.
;  The loop takes 130T times, slightly longer than any written count.
;
;  This creates about 31 kHz PWM output.
;
;  Step 1.
;    Create the tightest loop to walk the phases, sum up values,
;    trickle watchdog and load counter.
;    Count the T times and determine loop execution time.
;    This will be the PWM cell time.
;
;  Step 2:
;    Pad out a copy of the loop for P8E.
;
;  Step 3.
;    Build phase-inc-table for tones (see mkdtmfseq.c).
;    Values must be scaled so that the lowest sum (as the count)
;    keeps the timer output almost totally high,
;    and the highest sum keeps it mostly low.
;    T-time (from Z80 CLK) isn't the same as timer period
;    (from 8254 clock 1) (although they just happen to be in P8N).
;
;  See companion program mkdtmftab.c

;
; pwm 31015.38462 Hz
;
	dtmf_phase_1750 = 3698 ; 17.7 steps
	dtmf_phase_1633 = 3451 ; 19.0 steps
	dtmf_phase_1477 = 3121 ; 21.0 steps
	dtmf_phase_1336 = 2823 ; 23.2 steps
	dtmf_phase_1209 = 2555 ; 25.7 steps
	dtmf_phase_941  = 1988 ; 33.0 steps
	dtmf_phase_852  = 1800 ; 36.4 steps
	dtmf_phase_770  = 1627 ; 40.3 steps
	dtmf_phase_697  = 1473 ; 44.5 steps

dtmf_rowcol_table:

	.dw dtmf_phase_941, dtmf_phase_1336 ; 0
	.dw dtmf_phase_697, dtmf_phase_1209 ; 1
	.dw dtmf_phase_697, dtmf_phase_1336 ; 2
	.dw dtmf_phase_697, dtmf_phase_1477 ; 3
	.dw dtmf_phase_770, dtmf_phase_1209 ; 4
	.dw dtmf_phase_770, dtmf_phase_1336 ; 5
	.dw dtmf_phase_770, dtmf_phase_1477 ; 6
	.dw dtmf_phase_852, dtmf_phase_1209 ; 7
	.dw dtmf_phase_852, dtmf_phase_1336 ; 8
	.dw dtmf_phase_852, dtmf_phase_1477 ; 9
	.dw dtmf_phase_697, dtmf_phase_1633 ; A
	.dw dtmf_phase_770, dtmf_phase_1633 ; B
	.dw dtmf_phase_852, dtmf_phase_1633 ; C
	.dw dtmf_phase_941, dtmf_phase_1633 ; D
	.dw dtmf_phase_941, dtmf_phase_1209 ; * (E)
	.dw dtmf_phase_941, dtmf_phase_1477 ; # (F)

	.dw dtmf_phase_1750, dtmf_phase_1750 ; 0x10    for DEBUG

dtmf_map:
	.db 'C', 0x0A
	.db 'S', 0x0B
	.db 'R', 0x0C
	.db 'E', 0x0D
	.db '*', 0x0E
	.db '#', 0x0F

dtmf_map_size = (. - dtmf_map) / 2

	.db 0x10  ; 1750 Hz from button

dtmf_bang_tone:

	push af

	; summed sines must be > 0 and < 130
	; one sine must then be > 0 and < 65
	; center sine at 32

	ld h, #HI(dtmf_sintab)
	ld c, #32
	ld a, (cfg_dtmf_gain)

	call calculate_sintab

	pop af

	; get index in rowcol table

	cp #10
	jr c, 2f             ; if digit, no mapping

	ld hl, #dtmf_map
	ld b,  #dtmf_map_size
1:
	cp (hl)
	inc hl               ; INC HL keeps Z flag
	jr z, 1f
	inc hl
	djnz 1b
1:
	ld a, (hl)
2:

	; shift index into offset, pointer to ix

	sla a
	sla a            ; index into byte offset (4 byte records)
	ld e, a
	ld d, #0
	ld ix, #dtmf_rowcol_table        ; table[0]
	add ix, de

	; load phase increments

	ld c, (ix+0)
	ld b, (ix+1)
	push bc           ; phase_inc_1
	ld c, (ix+2)
	ld b, (ix+3)
	push bc
	pop iy            ; phase_inc_2 here for a while

	pop bc            ; phase_inc_1
	ld hl, #0          ; phase_acc_1
	ld d, #HI(dtmf_sintab)  ; sintab indexes from both DE's

	di  ; YES!

	exx
	push bc
	push de
	push hl           ; save and use another regset for another tone

	push iy
	pop bc            ; phase_inc_2
	ld hl, #0          ; phase_acc_2
	ld d, #HI(dtmf_sintab)
	exx

	; reroute tx audio, save previous state to stack

	ld a, (output_0)
	push af
	or #O0_CCIRC | O0_MICM               ; Pass tones, cut mic
	out (OUT0), a

	; temporary mode change in timer 1

	ld a, #TMR_1 | TMR_LSB | TMR_INTTC
	out (TMR + TMRCTRL), a

	ld a, (cpu_is_P8E)
	or a
	jp nz, 2f
	;
	; P8N loop, no waitstates
	;
1:  ; %%%%%%%%%%%%%%%%%%%%%%
	add hl, bc             ; 11T
	ld e, h                ;  4T
	ld a, (de)             ;  7T
	ld e, a                ;  4T
	exx                    ;  4T     bc de hl  swapped
	add hl, bc             ; 11T
	ld e, h                ;  4T
	ld a, (de)             ;  7T
	exx                    ;  4T     bc de hl  swapped
	add a, e                  ;  4T

	out (TMR + 1), a       ; 11T  70T here down
	ld a, #WR0_RESET_ESCINT ;  7T 
	out (SIO+ACTRL), a     ; 11T
	out (WD), a            ; 11T
	in a, (SIO+ACTRL)      ; 11T
	and #SA_DA              ;  7T inverted... go if DA low, idle state DA low
	jr z, 1b               ; 12T (when jumping, last one wont matter)
	                       ;----------
	; %%%%%%%%%%%%%%%%%%%%%% 130T total
	jp 3f
2:
	;
	; P8E loop, each opcode causes one extra T
	; Want to have the same time anyway (same tables for same timer hw),
	; so 130 * (1/4032000) / (1/8064000) = 260 T-times.
	;
1:  ; %%%%%%%%%%%%%%%%%%%%%%
	add hl, bc             ; 12T
	ld e, h                ;  5T
	ld a, (de)             ;  8T
	ld e, a                ;  5T
	exx                    ;  5T     bc de hl  swapped
	add hl, bc             ; 12T
	ld e, h                ;  5T
	ld a, (de)             ;  8T
	exx                    ;  5T     bc de hl  swapped back right way
	add a, e                  ;  5T  70T here up

		; burn 113T padding dummies to use same tables (don't foul a)
		out (WD), a ;  1
		out (WD), a ;  2
		out (WD), a ;  3
		out (WD), a ;  4
		out (WD), a ;  5
		out (WD), a ;  6
		out (WD), a ;  7
		out (WD), a ;  8
		out (WD), a ;  9 * 12T = 108T
		ld e, a     ;    +  5T = 113T

	out (TMR + 1), a       ; 12T  77T here down
	ld a, #WR0_RESET_ESCINT ;  8T 
	out (SIO+ACTRL), a     ; 12T
	out (WD), a            ; 12T
	in a, (SIO+ACTRL)      ; 12T
	and #SA_DA              ;  8T inverted... go if DA low, idle state DA low
	jr z, 1b               ; 13T (when jumping, last one wont matter)
	                       ;----------
	; %%%%%%%%%%%%%%%%%%%%%% 260T total

3:

	; restore timer back to normal

	call init_timer1

	pop af
	out (OUT0), a        ; Restore output switches

	ld a, #WR0_RESET_ESCINT
	out (SIO+ACTRL), a   ; Fresh value for next escint

	xor a
	ld (key_timer), a
	ld (keydown), a      ; we waited off the key
	dec a                ; ld a, -1
	ld (key), a
	ld (lastdigit), a    ; otherwise a ghost digit appears after ei

	; restore another regset

	exx
	pop hl
	pop de
	pop bc
	exx

	ei
	ret

;------------------------------------------------------------------------
;
;  LPF is not touched, assumed to be above 2200 Hz

emit_ax25_packet:        ; already stuffed bits in hl, terminates in 0xFF byte

	push hl

	; P8E limits the sine at 140T, P8N at 168T
	; center at half of that

	ld h, #HI(ax25_sintab)
	ld a, (cpu_is_P8E)
	or a
	ld c, #168 / 2
	jr z, 1f
	ld c, #140 / 2
1:
	ld a, (cfg_ax25_gain)

	call calculate_sintab

	pop hl

	di  ; YES!

	exx                      ; save another regset
	push bc
	push de
	push hl
	exx

	ld a, (output_0)         ; reroute tx audio, save previous state to stack
	push af
	or #O0_CCIRC | O0_MICM              ; Pass tones, cut mic
	out (OUT0), a

	ld a, #TMR_1 | TMR_LSB | TMR_INTTC  ; temporary mode change in timer 1
	out (TMR + TMRCTRL), a

	call emit_ax25_loop

	call init_timer1                   ; restore timer back to normal

	pop af
	out (OUT0), a                      ; Restore output switches

	exx                                ; restore another regset
	pop hl
	pop de
	pop bc
	exx

	ei
	ret

emit_ax25_loop:

	ld a, (cpu_is_P8E)
	or a
	jp nz, emit_ax25_loop_P8E

	; else fall thru to...

;  Note: if the dtmf_sintab[] is used, pwm must be around but no more 31kHz.
;  24 kHz might cause too weak modulation - needs testing - new table ?
;
;  P8N with 4.032 MHz clock - same as timer 1
;  pwm unit 168T = 24'000 Hz = about 41.7 usec
;  20 pwm units per bitcell

P8N_AX25_1200    = 3277    ; 20.0 steps
P8N_AX25_2200    = 6007    ; 10.9 steps
P8N_AX25_BITCELL = 20

emit_ax25_loop_P8N:

	ld d, #1                ; bitmask for walking over message bits.
	ld e, #P8N_AX25_BITCELL ; length of bitcell in pwm units.
	ld bc, #0               ; for stepping hl over message bits in constant time.

	exx
	ld de, #P8N_AX25_2200   ; fsk tones, another 
	push de                ; in stacktop and
	ld de, #P8N_AX25_1200   ; other in DE
	ld hl, #0               ; phacc
	ld b, #HI(ax25_sintab)  ; sin() array here
	exx
3:
	ld a, (hl)             ;      7T x
	cp #0x7F                ;      7T x  terminator ?
	jr z, 4f               ;      7T x  for time, only not-taken condition matters.
	and d                  ;      4T x  extract the bit which is next sent
	exx                    ;      4T x  flip over to dds regset
	jp z, 1f              ;;     10T x  zerobit = change in tone
	add ix, ix            ;;           15T padding
	jr 2f                 ;;           12T padding now equals the phinc flip code below
1:
	ex de, hl             ;;      4T x phinc temporarily into hl
	ex (sp), hl           ;;     19T x phincs are swapped
	ex de, hl             ;;      4T x phinc now in the right register, de
2:
	out (WD), a           ;; 11T 11T xy good dog
	add hl, de            ;; 11T 11T xy phacc += phinc
	ld c, h               ;;  4T  4T xy
	ld a, (bc)            ;;  7T  7T xy a = sin(phacc)
	out (TMR + 1), a      ;; 11T 11T xy start pwm unit <=========================
	exx                   ;;  4T  4T xy back from dds regset.

	dec e                  ;  4T  4T xy
	jp z, 1f               ; 10T 10T xy bitcell is ending.
	                       ;         else must burn some cycles to get 168T always
	add ix, ix             ; 15T     twiddling thumbs
	add ix, ix             ; 15T     twiddling thumbs
	add ix, ix             ; 15T     twiddling thumbs
	add ix, ix             ; 15T     twiddling thumbs
	add ix, ix             ; 15T     twiddling thumbs
	jp .+3                 ; 10T     twiddling thumbs
	ld a, #0                ;  7T     twiddling thumbs
	exx                    ;  4T     twiddling thumbs this exx must be done !!!
	jp 2b                  ; 10T     twiddling thumbs
1:
	ld e, #P8N_AX25_BITCELL ;      7T x another bitcell again this long.
	rlc d                  ;      8T x rotate mask up, CY when b7 flips back to b0
	adc hl, bc             ;     15T x ... increment hl when it happens.
	jp 3b                  ;     10T x merry go round
4:
	pop de             ; get rid of another phinc
	ret

;  P8E with 8.064 MHz clock - twice timer 1
;  pwm unit 280T = 28'800 Hz = about 34.7 usec
;  24 pwm units per bitcell

P8E_AX25_BITCELL = 24
P8E_AX25_1200    = 2731    ; 24.0 steps
P8E_AX25_2200    = 5006    ; 13.1 steps

emit_ax25_loop_P8E:

	ld d, #1                 ; bitmask for walking over message bits.
	ld e, #P8E_AX25_BITCELL  ; length of bitcell in pwm units.
	ld bc, #0                ; for stepping hl over message bits in constant T.

	exx
	ld de, #P8E_AX25_2200    ; fsk tones, another 
	push de                 ; in stacktop and
	ld de, #P8E_AX25_1200    ; other in DE
	ld hl, #0                ; phacc
	ld b, #HI(ax25_sintab)   ; sin() array here
	exx
3:
	ld a, (hl)             ;  8T x
	cp #0x7F                ;  8T x  terminator ?
	jr z, 4f               ;  8T x  only not-taken condition matters.
	and d                  ;  5T x  extract the bit which is next sent
	exx                    ;  5T x  flip over to dds regset
	jp z, 1f              ;; 11T x  zerobit = change in tone
	ld (junk), hl         ;;    17T padding
	jr 2f                 ;;    13T padding now equals the phinc flip code below
1:
	ex de, hl             ;;  5T x phinc temporarily into hl
	ex (sp), hl           ;; 20T x phincs are swapped XXX is T-time correct ?
	ex de, hl             ;;  5T x phinc now in the right register, de
2:
	out (WD), a           ;; 12T xy good dog (or scope)
	add hl, de            ;; 12T xy phacc += phinc
	ld c, h               ;;  5T xy
	ld a, (bc)            ;;  8T xy a = sin(phacc)
	out (TMR + 1), a      ;; 12T xy start pwm unit
	exx                   ;;  5T xy back from dds regset.

	call burn_p8e_89T      ; 89T xy loop must be 280T long.

	dec e                  ;  5T xy
	jp z, 1f               ; 11T xy bitcell is ending, go get another bit

	call burn_p8e_105T     ;   105T loop must be 280T in this branch too.

	exx                    ;     5T
	jp 2b                 ;;    11T
1:
	ld e, #P8E_AX25_BITCELL ;  8T x another bitcell again this long.

	; 1st line below has CB and 2nd has ED prefix, thus 1 more T-state

	rlc d                  ; 10T x rotate mask up, CY when b7 flips back to b0
	adc hl, bc             ; 17T x ... increment hl when it happens.
	jp 3b                  ; 11T x merry go round

4:
	pop de             ; get rid of another phinc
	ret

; call only from the regset, where BC is zero and HL points to packet bits !
; these ops were just conveniently short and timeconsuming.

burn_p8e_105T:          ;        18T     taken by CALL itself

	add a, (hl)            ;         8T     A was dead
	add a, (hl)            ;         8T     A was dead

burn_p8e_89T:           ; 18T            taken by CALL itself

	add hl, bc          ; 12T    12T     NOP, BC = 0
	add hl, bc          ; 12T    12T     NOP
	add hl, bc          ; 12T    12T     NOP
	add hl, bc          ; 12T    12T     NOP
	add hl, bc          ; 12T    12T     NOP
	ret                 ; 11T    11T
	                    ;

;========================================================================
;
;  For any wierd reasons, determine if this is P8N or P8E cpu-card.
;
;  8254 clock 1 4.032 MHz     ~248 nsec cycle, same on both.
;
;  P8N:
;    Z80  clock   4.032 MHz     ~248 nsec cycle
;  P8E:
;    Z80  clock   8.064 MHz     ~124 nsec cycle
;    BUT, each opcode fetch causes one extra T-time of wait.
;
;  This MUST BE CALLED EARLY, before initializing
;  anything much.

check_for_P8E_cpu:

	;
	;  Simplify things, program timer for LSB only,
	;  mode set for free counting N, N-1, N-2, N-3
	;

	out (WD), a

	ld a, #TMR_1 | TMR_LSB | TMR_INTTC
	out (TMR+TMRCTRL), a

	ld a, #65         ; see below
	out (TMR+1), a   ; go!

	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop ; 20 nops, 4T each without waitstates

	in a, (TMR+1)    ; not counted (11T), some error
	out (WD), a

	;
	;  timer counts 65 steps in 16.1 usec.
	;  P8N:
	;    20 * 4T = 80T = 19.8 usec
	;    timer has rolled over, bit 7 set.
	;  P8E:
	;    20 * 5T = 100T = 12.4 usec
	;    no timer rollover yet, bit 7 clear.
	;
	rlca   ; A.7 into A.0
	and #1
	xor #1
	ld (cpu_is_P8E), a

	ret

;========================================================================
;
;  REPEATER STUFF

repeater_toggle_suspend:
	ld a, (cfg_repeater_suspended)
	xor #1
	and #1
	ld (cfg_repeater_suspended), a
	ret

repeater_init:
	xor a
	ld (repeater_req), a
	ld (squelch_tightening), a
	ld (txpwr_increment), a
	ld hl, #0			; c/rptr.c: ST_BOOT_NEW
	ld (repeater_state), hl
	ret

; Repeater main state machine lives in bank 1 (search "BANK 1").
; Called on every mainloop pass.  Enter bank 1 only in repeater mode, and
; at most once per 10 ms systick: what the state machine polls (timers,
; squelch, CCIR/DTMF decoders) changes at that rate, so the pass right
; after a tick sees the same inputs as before, and bank 1 no longer takes
; about half of the idle time from the multiboard readers.
far_repeater_run:
	ld a, (cfg_function)
	dec a                       ; if 1
	jp nz, repeater_init        ; not repeater, init in case later turned on
	ld a, (sec100)
	ld hl, #repeater_tick
	cp (hl)
	ret z                       ; no systick since the last run
	ld (hl), a
	call bank2_call
	.dw _repeater_run

;  c/rptr.c shims
rptr_tone:			; A = ticks, DE = timer count
	ex de, hl
	ld d, a
	jp start_marker_tone
rptr_calc_blip:			; A = pitch (10 Hz)
	ld c, a
	jp cw_calc_blip
rptr_other_running:		; A != 0: repeater_timer_other running
	ld hl, (repeater_timer_other)
	ld a, h
	or l
	ret
rptr_id_running:
	ld hl, (repeater_timer_ID)
	ld a, h
	or l
	ret
rptr_set_other:			; HL (one store: the timer steps in interrupts)
	ld (repeater_timer_other), hl
	ret
rptr_set_id:
	ld (repeater_timer_ID), hl
	ret

;
;  received dtmf string at hl (h fixed, l wraps over)
;
dtmf_commands:

	push hl
	ld de, #cfg_gpio1_dtmf_pulse_cmd
	call compare_tone_serie      ; de and hl have strings, Z if equal
	pop hl
	jp z, gpio1_pulse_command

	push hl
	ld de, #cfg_gpio1_dtmf_cmd_pfx
	call compare_tone_prefix      ; de and hl have strings, a receives suffix
	pop hl
	jp z, gpio1_command

	push hl
	ld de, #cfg_gpio2_dtmf_cmd_pfx
	call compare_tone_prefix      ; de and hl have strings, a receives suffix
	pop hl
	jp z, gpio2_command

	push hl
	ld de, #cfg_repeater_suspend_dtmf_cmd
	call compare_tone_serie
	pop hl
	jp z, repeater_toggle_suspend

	ld a, (cfg_function)          ; rest for repeater only
	dec a                         ; if 1
	ret nz

	ld a, (hl)
	cp #'#'          ; #xxxx
	jr z, dtmf_commands_hash

	ret

dtmf_commands_hash:
	inc l
	inc l
	ld a, (hl)
	cp #' '          ; #x_
	ret nz
	dec l
	ld a, (hl)
	cp #' '
	ret z
	cp #0
	jr nz, 1f
	ld a, #0xFF               ; Yuck, 0xFF stands for '0'
1:
	ld (repeater_req), a
	ret

ccir_repeater_cmd:
	cp #0
	jr nz, 1f
	ld a, #0xFF                    ; FF == '0'
1:
	ld (repeater_req), a
	ret

;----------------------------------------------------------------------

repeater_step_1sec:

	ld hl, (repeater_timer_ID)
	ld a, h
	or l
	jr z, 1f
	dec hl
	ld (repeater_timer_ID), hl
1:
	ld hl, (repeater_timer_other)
	ld a, h
	or l
	jr z, 1f
	dec hl
	ld (repeater_timer_other), hl
1:
	ret

repeater_step_10msec:

	ld a, (repeater_timer_BLIP_state)
	dec a                                   ; if 1
	ret nz                                  ; skip if not running

	ld a, (repeater_timer_BLIP)
	sub #1                                   ; NC if timer was nonzero
	call c, 1f
	ld (repeater_timer_BLIP), a
	ret
1:
	ld a, #2
	ld (repeater_timer_BLIP_state), a   ; set it as 'triggered'
	xor a                               ; keep value at 0 (just for fun)
	ret

;----------------------------------------------------------------------
;----------------------------------------------------------------------
;
;  Repeater states
;

draw_decoder_history:
	push hl
	call clear_lower_colon
	pop hl

	ld de, #CU53AN_segs_d_digit_9
	ld b, #10                ; 10 slots to fill
	ld a, (cu_is_alfa)
	or a
	jr z, 1f
	ld de, #CU58AF_segs_d_digit_8
	ld b, #9                 ; 9 slots to fill
1:
	ld a, l
	sub b                   ; wind back last+1-ptr to print 9/10 last
	ld l, a
1:
	ld a, (hl)
	inc l
	push hl
	call dpydig
	pop hl
	djnz 1b
	ret

;----------------------------------------------------------------------

sput:
1:
	pop hl
	ld a, (hl)
	inc hl
	push hl
	or a
	ret z
	call dpydig
	jr 1b

draw_string_rightjust:
	push hl
	ld b, #7        ; number of blanks needed at the left
1:
	ld a, (hl)
	inc hl
	cp #EOS
	jr z, 1f
	djnz 1b
	jr 2f          ; no blanks at all
1:
	ld a, #' '
	call dpydig
	djnz 1b        ; blank padding
2:
	pop hl         ; refresh string
	ld b, #7
1:
	ld a, (hl)
	inc hl
	cp #EOS
	jr z, 1f
	push hl
	call dpydig
	pop hl
	djnz 1b
1:
	ret

draw_string_rightjust_scores:
	push hl
	ld b, #7        ; number of blanks needed at the left
1:
	ld a, (hl)
	inc hl
	cp #EOS
	jr z, 1f
	djnz 1b
	jr 2f          ; no blanks at all
1:
	ld a, #'_'
	call dpydig
	djnz 1b        ; _ padding
2:
	pop hl         ; refresh string
	ld b, #7
1:
	ld a, (hl)
	inc hl
	cp #EOS
	jr z, 1f
	push hl
	call dpydig
	pop hl
	djnz 1b
1:
	ret

;----------------------------------------------------------------------

dpydigzb_xxx:
	push af
	ld a, (yucko_alfa_draw_long_6_only)
	or a
	jr z, 1f
	xor a
	ld (yucko_alfa_draw_long_6_only), a
	pop af
	ret       ; barf
1:
	pop af

dpydigzb:
	or a
dpydigzb_Z_valid:
	jr z, 1f
	ld c, #0       ; seen nonzero
1:
	jr nz, dpydig
	ld a, c       ; replace initial 0's with ' '
	jr dpydig

dpyhexzb:
	push af
	rra
	rra
	rra
	rra
	and #0xF
	call dpydigzb_Z_valid
	pop af
	and #0xF
	jr dpydigzb_Z_valid

dpyval255:

	; load seeds and SUBs in pairs

	ld hl, #0xFF64   ; -1 and 100
	ld bc, #0xFF0A   ; -1 and  10
1:
	inc h		    ; hundreds
	sub l
	jr nc, 1b
	add a, l
1:
	inc b		    ; tens
	sub c
	jr nc, 1b
	add a, c

	ld c, a 	    ; ones

	ld a, h
	or a
	jr nz, 1f
	ld h, #' '
	or b
	jr nz, 1f
	ld b, #' '
1:
	ld a, h
	call dpydig     ; dpydig keeps BC
	ld a, b
	call dpydig
	ld a, c
	jr dpydig

dpyval99:

	ld bc, #0xFF0A   ; -1 and 10
1:
	inc b           ; tens
	sub c
	jr nc, 1b
	add a, c
	ld c, a         ; ones

	ld a, b
	or a
	jr nz, 1f
	ld a, #' '
1:
	call dpydig     ; keeps BC
	ld a, c
	jr dpydig

;----------------------------------------------------------------------

; scale 0...255 to 0...9
; save fraction for another round

byte_decade:
	ld l, a
	ld h, #0
	add hl, hl         ; 2 times
	ld c, l
	ld b, h
	add hl, hl
	add hl, hl
	add hl, bc         ; 8 + 2 times
	ld a, h            ; decade
	ld b, l            ; residue
	ret

dpydiv9:
	push bc
	call byte_decade
	pop bc
	jr dpydig

dpydiv99:
	push bc
	call byte_decade
	call dpydig        ; keeps B
	ld a, b
	call byte_decade   ; again with residue, next decade
	pop bc
	jr dpydig

;	digit or character in a
;	location table in de
;	de incremented to next position,
;	hl & a destroyed

dpyhex:
	push af
	rra
	rra
	rra
	rra
	call 1f
	pop af
1:
	and #0xF

	; fall thru

dpydig:
	push bc
	ld l, a
	ld a, (cu_is_alfa)
	or a
	jr nz, 1f

	ld h, #HI(cu53an_font)
	ASSERT_EQ(LO(cu53an_font), 0)
	ld c, (hl)		; what segments (0..6) are lit, what are dim

	call segment_onoff_XXX
	call segment_onoff_XXX
	call segment_onoff_XXX
	call segment_onoff_XXX

	call segment_onoff_XXX
	call segment_onoff_XXX
	call segment_onoff_XXX

	pop bc
	ret
1:
	ld bc, #cu58af_font
	ld h, #0
	add hl, hl           ; two bytes per glyph in font[]
	add hl, bc           ; offset into font[]
	ldi
	ldi                  ; [DE++] = [HL++], BC--

	pop bc
	ret

;----------------------------------------------------------------------

; 7 zeroblanked digits to [de] display bitbuf from AHL

draw_long_signed:

	bit 7, a
	jr z, draw_long ; positive

	; save cursor

	push de
	pop iy

	call negate_ahl
	call bin_bcd_AHL_DDEEHHLL

	; BCD result ok in DDEEHHLL

	ld a, d         ; 1st to go
	push hl         ; last 4 ones
	push de         ; middle two in e

	push iy
	pop de          ; cursor back

	cp #0
	ld a, #'-'       ; negative value
	jr z, 1f
	ld a, #'E'       ; sorry, must be 0NNNNNN
1:
	call dpydig     ; 1st cannot be set

	ld c, #' '       ; blank leading zeroes

	pop hl          ; middle two from e
	ld a, l
	call dpyhexzb   ; 2nd, 3rd

	pop hl          ; last 4 ones
	push hl
	ld a, h
	call dpyhexzb   ; 4th, 5th

	pop hl          ; last 4 ones
	ld a, l
	call dpyhexzb   ; 6th, 7th

	ret

draw_long:

	; save cursor

	push de
	pop iy

	call bin_bcd_AHL_DDEEHHLL

	; BCD result ok in DDEEHHLL

	ld a, d         ; 1st to go
	push hl         ; last 4 ones
	push de         ; middle two in e

	push iy
	pop de          ; cursor back

	ld c, #' '       ; zeroblanker

	call dpydigzb_xxx   ; 1st

	pop hl          ; middle two from e
	ld a, l
	call dpyhexzb   ; 2nd, 3rd

	pop hl          ; last 4 ones
	push hl
	ld a, h
	call dpyhexzb   ; 4th, 5th

	pop hl          ; last 4 ones
	ld a, l
	call dpyhexzb   ; 6th, 7th

	ret

;----------------------------------------------------------------------

draw_word:

	push de
	pop iy                     ; save cursor

	xor a                    ; HL has word, AHL now long
	call bin_bcd_AHL_DDEEHHLL

	ld a, e                    ; BCD result ok in EHHLL
	push hl

	push iy
	pop de                     ; cursor back

	ld c, #' '
	call dpydigzb

	pop hl
	push hl
	ld a, h
	call dpyhexzb

	pop hl
	ld a, l
	call dpyhexzb

	ret

;----------------------------------------------------------------------
;
;  For c/display.c: the display cursor lives in dpy_cursor instead of DE.
;  Each shim loads DE, calls the primitive (argument in A or HL as
;  --sdcccall 1 passes it) and stores the advanced cursor.

#define DPY_SHIM(name, fn) \
name: @ ld de, (dpy_cursor) @ call fn @ ld (dpy_cursor), de @ ret

	DPY_SHIM(dpy_ch, dpydig)
	DPY_SHIM(dpy_div9, dpydiv9)
	DPY_SHIM(dpy_div99, dpydiv99)
	DPY_SHIM(dpy_val99, dpyval99)
	DPY_SHIM(dpy_val255, dpyval255)
	DPY_SHIM(dpy_word, draw_word)
	DPY_SHIM(dpy_str_rj, draw_string_rightjust)
	DPY_SHIM(dpy_str_rj_scores, draw_string_rightjust_scores)
	DPY_SHIM(dpy_history, draw_decoder_history)

; c/menu.c keeps the cursor in dpy_cursor itself
dpy_menu_title:	call bank1_call
	.dw _draw_menu_title
dpy_menu_lower_row:	call bank1_call
	.dw _draw_menu_lower_row

dpy_freq:			; HL -> 24-bit value: draw_long of it
	ld e, (hl)
	inc hl
	ld d, (hl)
	inc hl
	ld a, (hl)
	ex de, hl		; AHL
	ld de, (dpy_cursor)
	call draw_long
	ld (dpy_cursor), de
	ret

dpy_freq_signed:		; HL -> 24-bit value: draw_long_signed of it
	ld e, (hl)
	inc hl
	ld d, (hl)
	inc hl
	ld a, (hl)
	ex de, hl		; AHL
	ld de, (dpy_cursor)
	call draw_long_signed
	ld (dpy_cursor), de
	ret

;  c/menu.c: a2i results as --sdcccall 1 returns them
menu_a2i:			; AHL -> HLDE (32 bits)
	call a2i
	ex de, hl
	ld l, a
	ld h, #0
	ret
menu_a2i_word:			; HL -> DE
	call a2i_word
	ex de, hl
	ret
keys_a2i:			; c/keys.c: digits -> 24 bits at HL
	push hl
	call a2i		; AHL, keeps BC/DE/IX
	ex de, hl
	pop hl
	ld (hl), e
	inc hl
	ld (hl), d
	inc hl
	ld (hl), a
	ret

;----------------------------------------------------------------------

bin_bcd_AHL_DDEEHHLL:

	; 3 bytes of binary input in AHL, to c ix

	push hl
	pop ix
	ld c, a

	; 3 and half bytes of packed BCD, result, MSNibble d, in ddeehhll

	xor a
	ld l, a
	ld h, a
	ld e, a
	ld d, a

	ld b, #24         ; 24 bits binary value
	jr 2f            ; 24 shifts
1:
	; BCD adjustment after all but last shift
	; if nibble >= 5, 3 added to nibble

#define __ADD3 \
	add a, #0x33 @ jp m, 3f @ sub #0x30 @ 3: bit 3, a @ jp nz, 3f @ sub #0x03 @ 3:

	ld a, l
	__ADD3
	ld l, a
	ld a, h
	__ADD3
	ld h, a
	ld a, e
	__ADD3
	ld e, a
	ld a, d
	__ADD3
	ld d, a

#undef __ADD3
2:
	add ix, ix      ; ix <<= 1
	rl c
	rl l            ; shift the bits 1 bit up, binary MSbit into BCD LSbit
	rl h
	rl e
	rl d
	djnz 1b

	; BCD result ok in DEEHHLL

	ret

;======================================================================

a2i_byte:
	call a2i   ; long in AHL
	or h       ; AH zero ?
	ld a, l
	ret z
	ld a, #0xFF
	ret           ; byte in A

a2i_word:
	call a2i   ; long in AHL
	or a       ; A zero ?
	ret z
	ld hl, #0xFFFF
	ret           ; word in HL

;======================================================================

#define TAB(name) 1: name: .db (1f - . - 1) / 8
#define   STR(s)           2: .ascii s @ FILL(8 - (. - 2b), 0xFF) @ ASSERT_EQ((. - 2b), 8)
#define ENDTABS          1:


#define REC(grp, name, type, ptr, arg, def, help) \
	1: .ascii grp @ ASSERT_EQ((.-1b), 2) @  \
	1: .ascii name @ ASSERT_EQ((.-1b), 6) @ \
	.dw ptr @                               \
	.dw arg @                               \
	.dw def @                               \
	.db type @                              \
	.db 'Z' @                               \
	ALIGN(4, 0)

; The setup menu engine and its tables live in bank 1 (search "BANK 1").
; Fixed code calls it through these stubs (bank1_call); menu_ptr holds
; bank 1 addresses, which fixed code only compares or passes back.

	FAR(far_init_menu, bank1_call, init_menu)
	FAR(far_update_gpio12_foo, bank1_call, update_gpio12_foo)
	FAR(far_toggle_or_position_menu, bank1_call, toggle_or_position_menu)
	FAR(far_menu_enter_or_walk, bank1_call, menu_enter_or_walk)
	FAR(far_menu_defval_or_exec, bank1_call, menu_defval_or_exec)
	FAR(far_menu_up_value, bank1_call, menu_up_value)
	FAR(far_menu_dn_value, bank1_call, menu_dn_value)
	FAR(far_menu_next_group, bank1_call, menu_next_group)
	FAR(far_menu_prev, bank1_call, menu_prev)
	FAR(far_decoder_hist_rewind, bank1_call, decoder_hist_rewind)
	FAR(far_leaved_setup, bank1_call, leaved_setup)

; read by the APRS code, so not in the bank with the other menu tables
	TAB(tab_ax25_digi)      ; must be literal as used in packet, chr by chr
		STR("nonE")
		STR("rELAY")
		STR("WIdE")
		STR("WIdE2-2")
		STR("WIdE3-3")
		STR("WIdE4-4")
		STR("WIdE5-5")
		STR("WIdE6-6")
		STR("trACE")
		STR("trACE2-2")
		STR("trACE3-3")
		STR("trACE4-4")
		STR("trACE5-5")
		STR("trACE6-6")
		STR("AriSS")
		STR("AStArS")
						AX25_DIGI_OTHER_IDX = (. - tab_ax25_digi) / 8
		STR("[othEr]")
	ENDTABS

;======================================================================
;
;  Fill holes (0 values) in rfctab.
;  It is assumed values never droop when going upwards table.
;
;  "Bresenham simplified"


;======================================================================

	.ascii "TheEnd"
	rom_cksum:
	.db 0	; ROM checksum: 256 - sum(ROM[0 .. rom_cksum - 1]), set by ihx2bin.py
rom_end:		; linked code (C modules, SDCC library) follows (tools/link.py)

	slack_at_end = 0x8000 - .

	ASSERT_LT(., 0x8000)  ; catch the moment when 32kB overflows

;== BANK 1 ============================================================
;
;  EPROM0 0xC000-0xFFFF, mapped at 0x8000 by set_bank(1).  Mainline code
;  only (never from interrupts or dosir); fixed code enters it through
;  the far_* stubs.  Code here may call fixed code freely.

	.area BANK1 (ABS)
	.org 0x8000
bank1_start:


;----------------------------------------------------------------------
;
;  SETUP GUNK MACROS

	; 1 byte          number of selections in table
	; n * 8 bytes     zero terminated strings, 8 bytes separated

offset_tag   = 0
offset_title = 2
offset_ptr   = 8
offset_arg   = 10
offset_def   = 12
offset_type  = 14

size_menurec = 16

;  c/menu.c: struct rec, the record types and constants it hard-codes
	ASSERT_EQ(offset_tag, 0)
	ASSERT_EQ(offset_title, 2)
	ASSERT_EQ(offset_ptr, 8)
	ASSERT_EQ(offset_arg, 10)
	ASSERT_EQ(offset_def, 12)
	ASSERT_EQ(offset_type, 14)
	ASSERT_EQ(size_menurec, 16)
	ASSERT_EQ(CFG_BYTE, 1)
	ASSERT_EQ(CFG_WORD, 2)
	ASSERT_EQ(CFG_FREQ, 3)
	ASSERT_EQ(CFG_TAB, 4)
	ASSERT_EQ(CFG_DYN, 5)
	ASSERT_EQ(CFG_RST, 6)
	ASSERT_EQ(CFG_STR, 7)
	ASSERT_EQ(CFG_DPX, 8)
	ASSERT_EQ(CFG_cSEC, 9)
	ASSERT_EQ(CFG_EXE, 10)
	ASSERT_EQ(S8C, 1)
	ASSERT_EQ(S8B, 2)
	ASSERT_EQ(SIZE_STR, 8)
	ASSERT_EQ(MEM_VALID, 1)
	ASSERT_EQ(DA_RFC, 0x30)
	ASSERT_EQ(EOS, 0xFF)

	ALIGN(4, 0)

;== SETUP TABLES ======================================================
;
;  note the ugliness of cSEC, e.g. defval here is 100 for 1000 msec etc

start_menu:
menu_0:
	REC("GE", "tPc   ",CFG_BYTE, cfg_txpwr,          0,               0, tx teho)
        REC("GE", "CtCSSt",CFG_TAB,  cfg_ctcss_tx_hz,    tab_ctcss_tx_hz, 0, tx ctcss taajuus - Hz)
	REC("GE", "CtCSSr",CFG_BYTE, cfg_ctcss_rx_hz,    0,               0, rx ctcss taajuus - Hz)
	REC("GE", "GPio 1",CFG_TAB,  cfg_gpio1_state,    tab_onoff,       0, EXAL pinnin tila - GPct1X + 0/1 asettaa 0/1)
	REC("GE", "GPio 2",CFG_TAB,  cfg_gpio2_state,    tab_0123,        0, /RXON EXIN2 pinnien tila - GPct2X + 0/1/2/3 asettaa 0/1)
	REC("GE", "Loud  ",CFG_TAB,  cfg_key_blip_pitch, tab_blip,        1, keyclick)
	REC("GE", "IdLE t",CFG_BYTE, cfg_idlefn_delay,   0,               0, minuutteja idle-tilaan)
	REC("GE", "IdLEFn",CFG_TAB,  cfg_idlefn,         tab_idlefn,      0, idle-toiminta)

	REC("GE", "SELC t",CFG_BYTE,  cfg_selcall_time,   0,      0, selektiivitilan kestoaika)

	REC("GE", "onHoo ",CFG_STR,  cfg_onhook_script,  0,      0, luurin lasku-toiminta (script))
	REC("GE", "oFFHoo",CFG_STR,  cfg_offhook_script, 0,      0, luurin nosto-toiminta (script))

	REC("GE", "APrS  ",CFG_TAB,  cfg_aprs_tx,        tab_onoff,      0, Real-APRS-mode - /LOCAL PTT ja mikkilinjaan mic-e tms - QSY tr:APrSFq)
	REC("GE", "rEPSit",CFG_BYTE, cfg_repeater_sitters_special,0,     0, repeater sitters special - seconds)

	REC("Pr", "CALL  ",CFG_STR,  cfg_mprs_callsign,  0,              0, kutsu MPRS-modessa - max 6 merkkiä)
	REC("Pr", "SSId  ",CFG_BYTE, cfg_mprs_ssid,      0,              0, SSID MPRS-modessa (0...15))
	REC("Pr", "ObJECt",CFG_TAB,  cfg_mprs_symbol,    tab_mprs_symbol,0, aseman symboli MPRS-modessa)
	REC("Pr", "PttSnd",CFG_TAB,  cfg_keyup_mprs,     tab_pttsnd,     0, MPRS vapautettaessa PTT - Ei/Aina/Tarvittaessa - katso SndInt)
	REC("Pr", "AutSnd",CFG_TAB,  cfg_spontaneous_mprs, tab_onoff,    0, MPRS spontaanisti - QSY tr:APrSFq)
	REC("Pr", "CutAud",CFG_TAB,  cfg_fsk_silencer,  tab_fsk_silencer, 0, audion sulku FSK:n kohdalla)
	REC("Pr", "buS Fn",CFG_TAB,  cfg_mbus_mprs,      tab_mbus_mprs,  0, MPRS releoidaan MBUS:iin tavalla X)
	REC("Pr", "dPYSEC",CFG_BYTE, cfg_remote_dpy_secs, 0,             0, MPRS tiedot pidetään näytöllä N sekuntia)
	REC("Pr", "GPSUPL",CFG_TAB,  cfg_gps_upload,     tab_gps_upload, 0, MPRS tiedot GPS:ään waypointteina)
	REC("Pr", "dStSnd",CFG_TAB,  cfg_gps_dst_send,   tab_onoff,      0, MPRS oman määränpään julkaisu)
	REC("Pr", "buS rF",CFG_TAB,  cfg_bus_rf_relay,   tab_onoff,      0, MBUS/RF relay)
	REC("Pr", "SndInt",CFG_WORD, cfg_mprs_seconds,   0,        900, MPRS lähetysintervalli - sekuntia - tiukentuu liikkeessä)
	REC("Pr", "tProto",CFG_TAB,  cfg_report_type,    tab_mprs_aprs,  0, MPRS vai APRS lähetys - VAIKUTTAA VAIN LÄHETYKSEEN)
	REC("Pr", "dGPAth",CFG_TAB,  cfg_mic_e_dest_ssid,tab_mic_e_dest_ssid,  0, MIC-E toistoreitti - vaikuttaa vain MIC-E formaatissa)
	REC("Pr", "StAtuS",CFG_TAB,  cfg_mic_e_message,  tab_mic_e_message,  0, MIC-E statustieto - vaikuttaa vain MIC-E formaatissa)
	REC("Pr", "APdiG0",CFG_TAB,  cfg_ax25_digi0,     tab_ax25_digi,  0, APRS digipeater #0 - vaikuttaa vain ascii-formaatissa)
	REC("Pr", "APdiG1",CFG_TAB,  cfg_ax25_digi1,     tab_ax25_digi,  0, APRS digipeater #1 - vaikuttaa vain ascii-formaatissa)
	REC("Pr", "APdiG2",CFG_TAB,  cfg_ax25_digi2,     tab_ax25_digi,  0, APRS digipeater #2 - vaikuttaa vain ascii-formaatissa)
	REC("Pr", "APdiG3",CFG_TAB,  cfg_ax25_digi3,     tab_ax25_digi,  0, APRS digipeater #3 - vaikuttaa vain ascii-formaatissa)
	REC("Pr", "APdiGo",CFG_STR,  cfg_ax25_digi_other,0,              0, APRS digipeater 'othEr' - aktivoidaan APdiG0..3 valintojen kautta)

	REC("Pr", "PAdbit",CFG_BYTE, cfg_ax25_padbits,  0,      0, AX.25 preamble - "TXDELAY*10" - kts. myös PH:PLLdEL)

#if 0
	REC("Pr", "r AX25",CFG_TAB,  cfg_fx614_exist,   tab_onoff,      0, AX.25 modem (like tcm3105 or fx614) is wired to /LOCAL - see elsewhere for details)
	REC("Pr", "b AX25",CFG_STR,  fx614_buffer + 16,  0,      0, palanen vikaa vastaanotettua ax.25 pakettia)
	REC("Pr", "c AX25",CFG_BYTE, fx614_rxcnt,        0,      0, oikein vastaanotettujen ax.25 pakettien lukumäärä modulo 256)
#endif

menu_1:
	REC("to", "LiGHtS",CFG_BYTE, cfg_light_seconds,  0,             255, valojen pitoaika)
	REC("to", "Lit Sq",CFG_TAB,  cfg_light_sql,      tab_onoff,       0, aukeava salpa = valot on)
	REC("to", "IGnAPO",CFG_BYTE, cfg_ign_apo_hours,  0,             255, auto sytytysvirraton: viive-sammutus - jos käytössä niin gpio2 pitää olla 2 tai 3 eli /EXIN2 on Hi-Z)
	REC("to", "tr tot",CFG_BYTE, cfg_tx_tot_minutes, 0,             255, tx aikaraja)
	REC("to", "UnrEJt",CFG_BYTE, cfg_unreject_mins,  0,               5, skannaus: automaattinen unreject)

	REC("SC", "rAtE  ",CFG_cSEC, cfg_scan_rate_kvik, 0,               2, skannaus: askellusviive msec)
	REC("SC", "SLrAtE",CFG_cSEC, cfg_scan_rate_slow, 0,               6, skannaus: hidas askellusviive msec)
	REC("SC", "SL qSy",CFG_FREQ, cfg_scan_large_qsy, 0,             100, skannaus: nopea/hidas qsy kHz)
	REC("SC", "nodAtA",CFG_TAB,  cfg_scan_skip_fsk_channels, tab_onoff, 0, skannaus: FSK-kantoaallon ohitus)

menu_2:
menu_rec_sql:
	REC("Sq", "SqL   ",CFG_DYN,  menu_sql_change,    draw_sql_dpy,  127, kohinasalvan taso)
menu_rec_sqB:
	REC("Sq", "SqL bi",CFG_DYN,  menu_sqB_change,    draw_sqB_dpy,  255, kohinasalvan tail-less taso)
	REC("Sq", "HySt  ",CFG_BYTE, cfg_squelch_hyst,   0,               4, kohinasalvan hystereesi)
	REC("Sq", "oPEn  ",CFG_cSEC, cfg_squelch_head,   0,              10, aukeamisviive)
	REC("Sq", "tAIL  ",CFG_cSEC, cfg_squelch_tail,   0,              10, sulkeutumisviive)
	REC("Sq", "SourcE",CFG_TAB,  cfg_squelch_source, tab_sqsrc,       0, salpamekanismi)
	REC("Sq", "CtCSS ",CFG_TAB,  cfg_squelch_ctcss,  tab_sql_ctcss,   0, CTCSS-salpa)

	REC("Sq", "BonGo ",CFG_TAB,  cfg_serv_blip_pitch, tab_blip,        0, piip salvan sulkeutuessa)

menu_3:
	REC("LP", "7 SqL ",CFG_BYTE, cfg_def_squelch,    0,               0, oletustaso salvalle; pitkä 7)
	REC("LP", "8 CHAn",CFG_BYTE, cfg_def_memory,     0,               0, oletusmuistipaikka; pitkä 8)
	REC("LP", "9 FrEq",CFG_FREQ, cfg_def_frequency,  0,               0, oletustaajuus; pitkä 9)
	REC("LP", "0 Loud",CFG_BYTE, cfg_def_volume,     0,               1, oletusvolume; pitkä 0)


menu_4:

	REC("b1", "StArt ",CFG_FREQ, cfg_band1_start,    0,               0, bandiviipaleen alku)
	REC("b1", "End   ",CFG_FREQ, cfg_band1_end,      0,               0, ... loppu)
	REC("b1", "duPL  ",CFG_DPX,  cfg_band1_duplex,   0,               0, viipaleella voimassaoleva erotus)
	REC("b1", "StEP  ",CFG_TAB,  cfg_band1_step,     tab_chstep,      0, ... askellus)
	REC("b1", "SCtAIL",CFG_BYTE, cfg_band1_sctail,   0,               2, skannaus: odotteluviive)
	REC("b1", "LIStEn",CFG_BYTE, cfg_band1_sclisten, 0,              15, skannaus: overin kesto; kärsivällisyys)
	REC("b1", "AutorJ",CFG_TAB,  cfg_band1_autoreject,tab_onoff,      0, skannaus: kärsivällisyyden loppu = tmp reject)

	REC("b2", "StArt ",CFG_FREQ, cfg_band2_start,    0,               0, kuten edellä)
	REC("b2", "End   ",CFG_FREQ, cfg_band2_end,      0,               0,)
	REC("b2", "duPL  ",CFG_DPX,  cfg_band2_duplex,   0,               0,)
	REC("b2", "StEP  ",CFG_TAB,  cfg_band2_step,     tab_chstep,      0,)
	REC("b2", "SCtAIL",CFG_BYTE, cfg_band2_sctail,   0,               2,)
	REC("b2", "LIStEn",CFG_BYTE, cfg_band2_sclisten, 0,              15,)
	REC("b2", "AutorJ",CFG_TAB,  cfg_band2_autoreject,tab_onoff,      0,)

	REC("b3", "StArt ",CFG_FREQ, cfg_band3_start,    0,               0, kuten edellä)
	REC("b3", "End   ",CFG_FREQ, cfg_band3_end,      0,               0,)
	REC("b3", "duPL  ",CFG_DPX,  cfg_band3_duplex,   0,               0,)
	REC("b3", "StEP  ",CFG_TAB,  cfg_band3_step,     tab_chstep,      0,)
	REC("b3", "SCtAIL",CFG_BYTE, cfg_band3_sctail,   0,               2,)
	REC("b3", "LIStEn",CFG_BYTE, cfg_band3_sclisten, 0,              15,)
	REC("b3", "AutorJ",CFG_TAB,  cfg_band3_autoreject,tab_onoff,      0,)

	REC("b4", "StArt ",CFG_FREQ, cfg_band4_start,    0,               0, kuten edellä)
	REC("b4", "End   ",CFG_FREQ, cfg_band4_end,      0,               0,)
	REC("b4", "duPL  ",CFG_DPX,  cfg_band4_duplex,   0,               0,)
	REC("b4", "StEP  ",CFG_TAB,  cfg_band4_step,     tab_chstep,      0,)
	REC("b4", "SCtAIL",CFG_BYTE, cfg_band4_sctail,   0,               2,)
	REC("b4", "LIStEn",CFG_BYTE, cfg_band4_sclisten, 0,              15,)
	REC("b4", "AutorJ",CFG_TAB,  cfg_band4_autoreject,tab_onoff,      0,)

	REC("b5", "StArt ",CFG_FREQ, cfg_band5_start,    0,               0, kuten edellä)
	REC("b5", "End   ",CFG_FREQ, cfg_band5_end,      0,               0,)
	REC("b5", "duPL  ",CFG_DPX,  cfg_band5_duplex,   0,               0,)
	REC("b5", "StEP  ",CFG_TAB,  cfg_band5_step,     tab_chstep,      0,)
	REC("b5", "SCtAIL",CFG_BYTE, cfg_band5_sctail,   0,               2,)
	REC("b5", "LIStEn",CFG_BYTE, cfg_band5_sclisten, 0,              15,)
	REC("b5", "AutorJ",CFG_TAB,  cfg_band5_autoreject,tab_onoff,      0,)

	REC("b6", "StArt ",CFG_FREQ, cfg_band6_start,    0,               0, kuten edellä)
	REC("b6", "End   ",CFG_FREQ, cfg_band6_end,      0,               0,)
	REC("b6", "duPL  ",CFG_DPX,  cfg_band6_duplex,   0,               0,)
	REC("b6", "StEP  ",CFG_TAB,  cfg_band6_step,     tab_chstep,      0,)
	REC("b6", "SCtAIL",CFG_BYTE, cfg_band6_sctail,   0,               2,)
	REC("b6", "LIStEn",CFG_BYTE, cfg_band6_sclisten, 0,              15,)
	REC("b6", "AutorJ",CFG_TAB,  cfg_band6_autoreject,tab_onoff,      0,)


	REC("bo", "duPL  ",CFG_DPX,  cfg_other_duplex,   0,               0, oletusarvot oltaessa yo)
	REC("bo", "StEP  ",CFG_TAB,  cfg_other_step,     tab_chstep,      0, viipaleiden ulkopuolella)
	REC("bo", "SCtAIL",CFG_BYTE, cfg_other_sctail,   0,               2,)
	REC("bo", "LIStEn",CFG_BYTE, cfg_other_sclisten, 0,              15,)
	REC("bo", "AutorJ",CFG_TAB,  cfg_other_autoreject,tab_onoff,      0,)

menu_5:
	REC("rJ", "n tEmP",CFG_BYTE, cfg_num_tmp_rejects, 0,              0, temp rejektien lukumäärä 0=max 20)

	REC("rJ", "rEJ  0",CFG_FREQ, cfg_reject_0,       0,               0, fixed reject-taajuus)
	REC("rJ", "rEJ  1",CFG_FREQ, cfg_reject_1,       0,               0, ... 20 kpl)
	REC("rJ", "rEJ  2",CFG_FREQ, cfg_reject_2,       0,               0,)
	REC("rJ", "rEJ  3",CFG_FREQ, cfg_reject_3,       0,               0,)
	REC("rJ", "rEJ  4",CFG_FREQ, cfg_reject_4,       0,               0,)
	REC("rJ", "rEJ  5",CFG_FREQ, cfg_reject_5,       0,               0,)
	REC("rJ", "rEJ  6",CFG_FREQ, cfg_reject_6,       0,               0,)
	REC("rJ", "rEJ  7",CFG_FREQ, cfg_reject_7,       0,               0,)
	REC("rJ", "rEJ  8",CFG_FREQ, cfg_reject_8,       0,               0,)
	REC("rJ", "rEJ  9",CFG_FREQ, cfg_reject_9,       0,               0,)
	REC("rJ", "rEJ 10",CFG_FREQ, cfg_reject_10,      0,               0,)
	REC("rJ", "rEJ 11",CFG_FREQ, cfg_reject_11,      0,               0,)
	REC("rJ", "rEJ 12",CFG_FREQ, cfg_reject_12,      0,               0,)
	REC("rJ", "rEJ 13",CFG_FREQ, cfg_reject_13,      0,               0,)
	REC("rJ", "rEJ 14",CFG_FREQ, cfg_reject_14,      0,               0,)
	REC("rJ", "rEJ 15",CFG_FREQ, cfg_reject_15,      0,               0,)
	REC("rJ", "rEJ 16",CFG_FREQ, cfg_reject_16,      0,               0,)
	REC("rJ", "rEJ 17",CFG_FREQ, cfg_reject_17,      0,               0,)
	REC("rJ", "rEJ 18",CFG_FREQ, cfg_reject_18,      0,               0,)
	REC("rJ", "rEJ 19",CFG_FREQ, cfg_reject_19,      0,               0,)

	REC("Sh", "ShCut0",CFG_STR,  cfg_shortcut_0,     0,               0, pikavalintoja signaloinnille)
	REC("Sh", "ShCut1",CFG_STR,  cfg_shortcut_1,     0,               0,)
	REC("Sh", "ShCut2",CFG_STR,  cfg_shortcut_2,     0,               0,)
	REC("Sh", "ShCut3",CFG_STR,  cfg_shortcut_3,     0,               0,)
	REC("Sh", "ShCut4",CFG_STR,  cfg_shortcut_4,     0,               0,)
	REC("Sh", "ShCut5",CFG_STR,  cfg_shortcut_5,     0,               0,)
	REC("Sh", "ShCut6",CFG_STR,  cfg_shortcut_6,     0,               0,)
	REC("Sh", "ShCut7",CFG_STR,  cfg_shortcut_7,     0,               0,)
	REC("Sh", "ShCut8",CFG_STR,  cfg_shortcut_8,     0,               0,)
	REC("Sh", "ShCut9",CFG_STR,  cfg_shortcut_9,     0,               0,)

menu_6:
	REC("dH", "ccir H",CFG_DYN,  ccir_hist_walk,     draw_ccir_hist,  0, heard-listoja: ccir)
	REC("dH", "dtmf H",CFG_DYN,  dtmf_hist_walk,     draw_dtmf_hist,  0, dtmf)
	REC("dH", "FSK  H",CFG_DYN,  fsk_hist_walk,      draw_fsk_hist,   0, ja fsk)
	REC("dH", "GPS  H",CFG_DYN,  gps_hist_walk,      draw_gps_hist,   0, ja NMEA)
	REC("dH", "APr  0",CFG_STR,  remote_display_buffer, 0,            0, Viimeisin MPRS ...)
	REC("dH", "Sqr  0",CFG_STR,  locator_display_buffer, 0,           0, ... tästä ruudusta)
	REC("dH", "diSt 0",CFG_STR,  distance_bearing,   0,               0, ... etäisyys ja suunta)

	REC("AL", "id   1",CFG_STR,  cfg_mycall_1,       0,               0, fsk-omatunnus)
	REC("AL", "id   2",CFG_STR,  cfg_mycall_2,       0,               0, ...)
	REC("AL", "id   3",CFG_STR,  cfg_mycall_3,       0,               0, ... 3 kpl)
	REC("AL", "ccir 1",CFG_STR,  cfg_ccir_1,         0,               0, ccir-omatunnus)
	REC("AL", "ccir 2",CFG_STR,  cfg_ccir_2,         0,               0, ...)
	REC("AL", "ccir 3",CFG_STR,  cfg_ccir_3,         0,               0, ... 3 kpl)
	REC("AL", "dtnf 1",CFG_STR,  cfg_dtmf_1,         0,               0, dtmf-omatunnus)
	REC("AL", "dtnf 2",CFG_STR,  cfg_dtmf_2,         0,               0, ...)
	REC("AL", "dtnf 3",CFG_STR,  cfg_dtmf_3,         0,               0, ... 3 kpl)
	REC("AL", "PEPA  ",CFG_STR,  cfg_pepa_on,        0,               0, OFF)
	REC("AL", "PEPAoF",CFG_STR,  cfg_pepa_off,       0,               0, OFF)
	REC("AL", "Loud  ",CFG_BYTE, cfg_alert_vol,      0,               7, hälytysääni volume)
	REC("AL", "cirdur",CFG_cSEC, cfg_ccir_minlen,    0,              20, ccir min kestoaika)
	REC("AL", "dtfdur",CFG_BYTE, cfg_dtmf_holdtime,  0,               5, dtmf hold aika)

	REC("io", "GPct1c",CFG_STR,  cfg_gpio1_ccir_cmd_pfx, 0,           0, control gpio1-pin=EXAL - ccir prefix)
	REC("io", "GPct1d",CFG_STR,  cfg_gpio1_dtmf_cmd_pfx, 0,           0, control gpio1-pin=EXAL - dtmf prefix)
	REC("io", "GPct2c",CFG_STR,  cfg_gpio2_ccir_cmd_pfx, 0,           0, control gpio2-pins=(/RXON EXIN2) - ccir pfx)
	REC("io", "GPct2d",CFG_STR,  cfg_gpio2_dtmf_cmd_pfx, 0,           0, control gpio2-pins=(/RXON EXIN2) - dtmf pfx)
	REC("io", "GPULSc",CFG_STR,  cfg_gpio1_ccir_pulse_cmd, 0,         0, pulse gpio1-pin=EXAL - ccir command)
	REC("io", "GPULSd",CFG_STR,  cfg_gpio1_dtmf_pulse_cmd, 0,         0, pulse gpio1-pin=EXAL - dtmf command)

menu_7:
	REC("Fn", "Func  ",CFG_TAB,  cfg_function,       tab_func,        0, rigin toimintamode (Std!))

	REC("rP", "id   t",CFG_WORD, repeater_cfg_TID,   0,             600, kutsunlähetysintervalli; sec)
	REC("rP", "OPEn t",CFG_WORD, repeater_cfg_TOPEN, 0,              15, kantoaaltoaika; 0 sec: tx pois heti)
	REC("rP", "HOG  t",CFG_WORD, repeater_cfg_THOG,  0,             300, pyörtymisaika; max 65535 sec: 18+ tuntia)
	REC("rP", "CLOS t",CFG_WORD, repeater_cfg_TCLS,  0,              30, valmiusaika; 0 sec: ei valmiusaikaa)
	REC("rP", "dEAd t",CFG_WORD, repeater_cfg_TDEAD, 0,              60, karenssiaika; 0 sec: ei viivyttelyä)
	REC("rP", "bLiP t",CFG_cSEC, repeater_cfg_TBLIP, 0,              50, välibongon viive; msec)
	REC("rP", "SqIncr",CFG_BYTE, repeater_cfg_sqincr,0,               8, salvan kiristysarvo)
	REC("rP", "trIncr",CFG_BYTE, repeater_cfg_txincr,0,               8, tehon nostoarvo)
	REC("rP", "SPEEd ",CFG_BYTE, cfg_cw_speed,       0,             120, cw nopeus mrk/min)
	REC("rP", "PItCH ",CFG_cSEC, cfg_cw_pitch,       0,             140, cw äänenkorkeus)
	REC("rP", "AF Src",CFG_TAB,  repeater_cfg_afsrc, tab_rep_mic,   140, audion kytkentätapa)
	REC("rP", "ACCESS",CFG_TAB,  repeater_cfg_access_method,tab_rep_access, 0, avaustapa)
	REC("rP", "tonE t",CFG_WORD, repeater_cfg_TBEEPMAX,  0,           5, maksimiaika avausäänelle)
	REC("rP", "id G1 ",CFG_STR,  repeater_cfg_id_greet1, 0,           0, identifikaatio; tervehdysviesti)
	REC("rP", "id G2 ",CFG_STR,  repeater_cfg_id_greet2, 0,           0, ...)
	REC("rP", "id G3 ",CFG_STR,  repeater_cfg_id_greet3, 0,           0, ... 3 osainen)
	REC("rP", "id t1 ",CFG_STR,  repeater_cfg_id_during1, 0,          0, identifikaatio; qson aikana)
	REC("rP", "id t2 ",CFG_STR,  repeater_cfg_id_during2, 0,          0, ...)
	REC("rP", "id t3 ",CFG_STR,  repeater_cfg_id_during3, 0,          0, ... 3 osainen)
	REC("rP", "id b1 ",CFG_STR,  repeater_cfg_id_bye1,   0,           0, identifikaatio; sulkeutuessa)
	REC("rP", "id b2 ",CFG_STR,  repeater_cfg_id_bye2,   0,           0, ...)
	REC("rP", "id b3 ",CFG_STR,  repeater_cfg_id_bye3,   0,           0, ... 3 osainen)

	REC("rP", "id Hot",CFG_STR,  repeater_cfg_msg_hot_alert, 0,       0, cw viesti kun lämpötila nousee; TP4 below rP:Hot)
	REC("rP", "idCoLd",CFG_STR,  repeater_cfg_msg_cold_alert, 0,      0, cw viesti kun lämpötila laskee; TP4 above rP:Cold)
	REC("rP", "id Ant",CFG_STR,  repeater_cfg_msg_ant_bad,    0,      0, cw viesti kun palaava teho nousee)
	REC("rP", "id HOG",CFG_STR,  repeater_cfg_msg_hog,        0,      0, cw viesti pyörryttäessä)

	REC("rP", "bLIP  ",CFG_STR,  repeater_cfg_blip,  0,               0, cw välibongo)
	REC("rP", "bLIP L",CFG_STR,  repeater_cfg_blip_link,  0,          0, cw välibongo linkki-ptt:n takia)
	REC("rP", "bLIGP1",CFG_STR,  repeater_cfg_blip_gpio_001, 0,       0, cw välibongo GPio2+1 = 00 1)
	REC("rP", "bLIGP2",CFG_STR,  repeater_cfg_blip_gpio_010, 0,       0, cw välibongo GPio2+1 = 01 0)
	REC("rP", "bLIGP3",CFG_STR,  repeater_cfg_blip_gpio_011, 0,       0, cw välibongo GPio2+1 = 01 1)
	REC("rP", "bLIGP4",CFG_STR,  repeater_cfg_blip_gpio_100, 0,       0, cw välibongo GPio2+1 = 10 0)
	REC("rP", "bLIGP5",CFG_STR,  repeater_cfg_blip_gpio_101, 0,       0, cw välibongo GPio2+1 = 10 1)
	REC("rP", "bLIGP6",CFG_STR,  repeater_cfg_blip_gpio_110, 0,       0, cw välibongo GPio2+1 = 11 0)
	REC("rP", "bLIGP7",CFG_STR,  repeater_cfg_blip_gpio_111, 0,       0, cw välibongo GPio2+1 = 11 1)
	REC("rP", "PItCHb",CFG_cSEC, cfg_cw_pitch_blip,  0,             140, välibongon äänenkorkeus)
	REC("rP", "PItCHL",CFG_cSEC, cfg_cw_pitch_blip_link,  0,        140, linkki-ptt-bongon äänenkorkeus)
	REC("rP", "PItCHG",CFG_cSEC, cfg_cw_pitch_blip_gpio,  0,        140, gpio-bongon äänenkorkeus)
	REC("rP", "Hot  L",CFG_BYTE, cfg_temperature_limit_hot,  0,       0, lämpötilan raja-arvo)
	REC("rP", "CoLd L",CFG_BYTE, cfg_temperature_limit_cold, 0,     255, lämpötilan raja-arvo)
	REC("rP", "AntbAd",CFG_BYTE, cfg_rpm_limit,      0,               0, palaavan tehon raja-arvo)
	REC("rP", "rEMOtE",CFG_WORD, cfg_remote_id,      0,               0, kaukokäytön osoite (0!))
	REC("rP", "PASS C",CFG_STR,  cfg_remote_passwd,  0,               0, kaukokäytön salasana)

	REC("rP", "ccirPF",CFG_STR,  repeater_cfg_ccir_cmd_pfx, 0,        0, ruutukomentojen ccir-prefiksi)

	REC("rP", "S1rSSi", CFG_BYTE, cfg_rssi_S1, 0, 0, S1 signaalitason RSSI-arvo)
	REC("rP", "S9rSSi", CFG_BYTE, cfg_rssi_S9, 0, 0, S9 signaalitason RSSI-arvo)

	REC("rP", "CtCOut", CFG_TAB, cfg_ctcss_output_when, tab_ctcss_out, 0, tx ctcss milloin)

	REC("rP", "SUSP c", CFG_STR, cfg_repeater_suspend_ccir_cmd, 0, 0, ccir sammutuskoodi)
	REC("rP", "SUSP d", CFG_STR, cfg_repeater_suspend_dtmf_cmd, 0, 0, dtmf sammutuskoodi)
	REC("rP", "SUSPnd", CFG_TAB, cfg_repeater_suspended, tab_onoff, 0, sammutustila)

	REC("rP", "HidE 9", CFG_TAB, cfg_repeater_cmd_9_hidden, tab_pass_hide, 0, #9 sallittu)
	REC("rP", "SIMPLE", CFG_TAB, cfg_repeater_wierd_simplex, tab_onoff, 0, toistimen omituinen simplex-mode)
	REC("rP", "BLIPS ", CFG_TAB, repeater_cfg_musical_blips, tab_cw_notes, 0, välibongot cw vai nuotit)
	REC("rP", "BrSSiS", CFG_TAB, repeater_cfg_rssi_bongos, tab_onoff, 0, rssi välibongot käytössä - #5 dtmf toggle)
	REC("rP", "rSSi 1", CFG_BYTE, repeater_cfg_rssi_A, 0,             0, RSSI A raja-arvo)
	REC("rP", "BrSSi1", CFG_STR,  repeater_cfg_blip_rssi_A, 0,        0, RSSI A raja-arvon bongo)
	REC("rP", "rSSi 2", CFG_BYTE, repeater_cfg_rssi_B, 0,             0, RSSI B raja-arvo)
	REC("rP", "BrSSi2", CFG_STR,  repeater_cfg_blip_rssi_B, 0,        0, RSSI B raja-arvon bongo)
	REC("rP", "rSSi 3", CFG_BYTE, repeater_cfg_rssi_C, 0,             0, RSSI C raja-arvo)
	REC("rP", "BrSSi3", CFG_STR,  repeater_cfg_blip_rssi_C, 0,        0, RSSI C raja-arvon bongo)
	REC("rP", "Pr id ", CFG_BYTE, repeater_cfg_mprs_id, 0,        0, MPRS paketti eri tilanteissa: 1=greet 2=during 4=bye 8=raport)

	REC("tr", "tr Lo ",CFG_FREQ, cfg_tx_band_start,  0,               0, alempi tx raja)
	REC("tr", "tr Hi ",CFG_FREQ, cfg_tx_band_end,    0,               0, ylempi tx raja)
	REC("tr", "tSPot0",CFG_FREQ, cfg_tx_oob_0,       0,               0, rajojen ulkopuolinen sallittu)
	REC("tr", "tSPot1",CFG_FREQ, cfg_tx_oob_1,       0,               0, tx taajuus ...)
	REC("tr", "tSPot2",CFG_FREQ, cfg_tx_oob_2,       0,               0, ...)
	REC("tr", "tSPot3",CFG_FREQ, cfg_tx_oob_3,       0,               0, ...)
	REC("tr", "tSPot4",CFG_FREQ, cfg_tx_oob_4,       0,               0, ... 5 kpl)
	REC("tr", "APrSFq",CFG_FREQ, cfg_aprs_tx_freq,   0,               0, Real-APRS lähetystaajuus)

menu_8:
	REC("PH", "SynCrd",CFG_TAB,  cfg_synth_card,     tab_synth_card,  0, RF-osan tyyppi)
	REC("PH", "3diGit",CFG_STR,  cfg_implied,        0,               0, implied MHz (3 ensimmäistä numeroa))
	REC("PH", "IFFrEq",CFG_FREQ, cfg_if_freq,        0,               0, rx välitaajuus)
	REC("PH", "LO InJ",CFG_TAB,  cfg_inj_below,      tab_above_below, 0, injektion puoli)
	REC("PH", "r CEnt",CFG_FREQ, cfg_rx_vco_center,  0,               0, rx vcon keskitaajuus)
	REC("PH", "t CEnt",CFG_FREQ, cfg_tx_vco_center,  0,               0, tx vcon keskitaajuus)
	REC("PH", "LPFILt",CFG_WORD, cfg_lpf_hz,         0,            3600, tx audion alipäästö)
	REC("PH", "FonE d",CFG_BYTE, cfg_deviation_fone, 0,              15, puhedeviaation säätö - 0 ... 15)
	REC("PH", "SiG dE",CFG_BYTE, cfg_deviation_sign, 0,               7, signalointideviaation säätö - 0 ... 15)
tune_tone_position:
	REC("PH", "t tunE",CFG_WORD, cfg_txtune_hz,      0,               0, tx testisignaalia)
	REC("PH", "PLLdEL",CFG_BYTE, cfg_pll_delay,      0,               0, txpll käynnistysviive - karkeasti msec - PLL stabiiliksi)

	REC("PH", "tr oFF", CFG_FREQ, cfg_tx_mix_freq,       0, 0, tx mikseri)
	REC("PH", "t mult", CFG_BYTE, cfg_tx_vco_multiplier, 0, 0, tx kertoja)
	REC("PH", "r mult", CFG_BYTE, cfg_rx_vco_multiplier, 0, 0, rx kertoja)
	REC("PH", "CtCdEc", CFG_TAB,  cfg_ctcss_input_method, tab_ctcss_input_method, 0, ctcss-detektori: ROM1 /TMR0 TMR0)
	REC("PH", "CtCtHr", CFG_BYTE, cfg_ctcss_dec_threshold, 0,      100, ctcss-softadekooderin raja-arvo)
	REC("PH", "CtCGEn", CFG_TAB,  cfg_ctcss_output_method, tab_ctcss_output_method, 0, ctcss:n luontitapa - huomaa: kaikki vaativat modifikaatioita)
	REC("PH", "CtHAnG", CFG_BYTE, cfg_ctcss_hang,    0,               0, hang-aika overin lopussa ilman ctcss-ääntä - msec)
	REC("PH", "CtGAin", CFG_BYTE, cfg_ctcss_generator_gain, 0,      127, rfc-dac ctcss-generaattorin gain - mahduttava rfc:n ja abs(-rfc):n rajoihin)
	REC("PH", "dtGAin", CFG_BYTE, cfg_dtmf_gain, 0,       31, dtmf-generaattorin gain - oltava 1...31)
	REC("PH", "PrGAin", CFG_BYTE, cfg_ax25_gain, 0,       63, ax.25-generaattorin gain - P8N 1...70 P8E 1...84)
	REC("PH", "SErCtA", CFG_WORD, cfg_external_serial_A, 0,           0, 16bit shiftreg SD CLK RAS - MSbit first - positive 1usec pulses)
	REC("PH", "SErCtB", CFG_WORD, cfg_external_serial_B, 0,           0, 16bit shiftreg SD CLK TPS - MSbit first - positive 1usec pulses)
	REC("PH", "GPSCFG", CFG_TAB,  cfg_gps_config,    tab_gps_config,  0, GPS-konfiguraatio - Std = geneerinen NMEA- 9600Std -OH1E)

	REC("dF", "CFGGEt",CFG_RST,  all_config_get,     0,               0, KAIKKIEN asetusten ylikirjoitus MBUS-karvasta)
	REC("dF", "CFGSnd",CFG_RST,  all_config_send,    0,               0, asetusten lähetys MBUS-karvaan)
	REC("dF", "ALLrSt",CFG_RST,  disaster,           0,               0, asetusten nollaus)
	REC("dF", "CH rSt",CFG_RST,  wipe_memories,      0,               0, muistien nollaus)
	REC("dF", "SAnE  ",CFG_RST,  sane_defaults,      0,               0, monien asetusten oletusasetus)
	REC("dF", "rFcrSt",CFG_RST,  wipe_rfctab,        0,               0, rx säätöarvojen nollaus)
	REC("dF", "rFcFIL",CFG_RST,  rfc_fill_blanks,    0,               0, rx säätöarvojen interpolointi)
	REC("dF", "rEboot",CFG_RST,  do_reboot,          0,               0, lämmin käynnistys)

	REC("dF", "EntLen",CFG_BYTE, cfg_enter_time,     0,               0, setupnapin turva-aika)

menu_9:
	REC("St", "SoFt  ",CFG_STR,  version,            0,               0, softaversio)
	REC("St", "AdrSSI",CFG_BYTE, ad_rssi,            0,               0, RSSI arvo)
	REC("St", "Ad SqL",CFG_BYTE, ad_sql,             0,               0, SQL arvo)
	REC("St", "AdbAtt",CFG_BYTE, ad_batt,            0,             255, jännite) ; HA!
	REC("St", "Ad tPc",CFG_BYTE, ad_tpc,             0,               0, tx power control)
	REC("St", "Ad For",CFG_BYTE, ad_fpm,             0,               0, forward power)
	REC("St", "Ad rEF",CFG_BYTE, ad_rpm,             0,               0, reflected power)
	REC("St", "Ad tP4",CFG_BYTE, ad_tp4,             0,               0, TP4 mittapiste)
	REC("St", "Ad in7",CFG_BYTE, ad_in7,             0,               0, IN7 mittapiste)
	REC("St", "ctcFit",CFG_BYTE, ctcss_dec_fit,      0,               0, ctcss korrelaatio - isompi parempi)

	REC("St", "USEcnt",CFG_FREQ, repeater_cfg_open_counter,  0,       0, avauskerrat)
	REC("St", "USEhrS",CFG_FREQ, transmitter_hours,  0,               0, käyttötunnit)
	REC("GP", "utc   ",CFG_STR,  gps_utc,            0,               0, HHMMSS)
	REC("GP", "dAtE  ",CFG_STR,  gps_date,           0,               0, YYMMDD)
	REC("GP", "LAt   ",CFG_STR,  cfg_gps_latitude,   0,               0, DDDMMmmN/S)
	REC("GP", "Lon   ",CFG_STR,  cfg_gps_longitude,  0,               0, DDDMMmmE/W)
	REC("GP", "SPEEd ",CFG_BYTE, gps_speed,          0,               0, speed - km/h - 255 = overflow)
	REC("GP", "knotS ",CFG_WORD, gps_knots,          0,               0, knots - solmua)
	REC("GP", "CourSE",CFG_WORD, gps_course,         0,               0, course - degrees)
	REC("GP", "GridSq",CFG_STR,  cfg_gps_locator,    0,               0, Maidenhead)
	REC("GP", "StAtuS",CFG_STR,  gps_status,         0,               0, vastaanoton laatu - sisältö laitekohtainen)

	REC("rF", "rFc   ",CFG_DYN,  menu_rfc_change,    draw_rfc_dpy,    0, rx säätöarvon asetus vfo MHz:lla)
end_menu:

	ASSERT_GT(end_menu + 255 * size_menurec, start_menu) ; safety for overflow calc
	ASSERT_LT(end_menu + 255 * size_menurec, 0x10000)

num_menu = (end_menu - start_menu) / size_menurec

	TAB(tab_rep_access)
		STR("tonES")
		STR("CArr")
		STR("nonE")
	TAB(tab_ctcss_out)
		STR("oFF")      ; 0
		STR("trAnS")    ; 1
		STR("SIGnAL")   ; 2
		STR("CtCSSi")   ; 3
		STR("cuSt")     ; 4  "CUSTOM" --- signal, and when id'ing
	TAB(tab_rep_mic)
		STR("MICnot")
		STR("MIC")
		STR("thru")
	TAB(tab_func)
		STR("Std")
		STR("rPtr")
		STR("SLAvE")
	TAB(tab_onoff)
		STR("oFF")
		STR("on")
	TAB(tab_posneg)
		STR("POS")
		STR("nEG")
	TAB(tab_sqsrc)
		STR("SqL")
		STR("SqLnot")
		STR("rSSI")
	TAB(tab_chstep)
		STR("25")
		STR("20")
		STR("15")
		STR("12_5")
		STR("10")
#ifdef ALLOW_6_25_kHz
		STR("6_25")
#endif
	TAB(tab_synth_card)
		STR("S8d")
		STR("S8c")
		STR("S8b")
	TAB(tab_idlefn)
		STR("oFF")
		STR("SCAn")
		STR("CHAn")
	TAB(tab_blip)
		STR("0")
		STR("500")
		STR("1000")
		STR("1500")
		STR("2000")
		STR("2500")
		STR("3000")
		STR("3500")
	TAB(tab_above_below)
		STR("AboUE")
		STR("bELou")
	TAB(tab_pass_hide)
		STR("PASS")
		STR("HidE")
	TAB(tab_mbus_mprs)
		STR("oFF")
		STR("tnc")
		STR("KISS")
		STR("3rd P")
		STR("LoGGEr")
	TAB(tab_mprs_symbol)
		STR("PUPPY")
		STR("CAr")
		STR("VAn")
		STR("SHIP")
		STR("bASE")
		STR("CArE")
		STR("Ant")
		STR("FLAG")
		STR("[0]")
		STR("[1]")
		STR("[2]")
		STR("[3]")
		STR("[4]")
		STR("[5]")
		STR("[6]")
		STR("[SSId]")
	TAB(tab_gps_upload)
		STR("oFF")
		STR("GPWPL")
		STR("MAGELL")
	TAB(tab_sql_ctcss)
		STR("oFF")
		STR("And")
	TAB(tab_0123)
		STR("oFF")
		STR("1")
		STR("2")
		STR("3")
	TAB(tab_cw_notes)
		STR("norSE")     ; eh-hehe
		STR("notES")
	TAB(tab_pttsnd)
		STR("oFF")
		STR("ALL")
		STR("on d")
	TAB(tab_mprs_aprs)
		STR("ProPr")    ; 0
		STR("APrS")     ; 1
		STR("MIC-E")    ; 2
	TAB(tab_fsk_silencer)
		STR("oFF")
		STR("ALL")
		STR("PrbEG")
		STR("PrEnd")
	TAB(tab_mic_e_message)
		STR("oFF dt") ;  0   0 000 Off Duty
		STR("En rtE") ;  1   0 001 En Route
		STR("In Svc") ;  2   0 010 In Service
		STR("rEturn") ;  3   0 011 Returning
		STR("CottEd") ;  4   0 100 Committed
		STR("SPEc")   ;  5   0 101 Special
		STR("Prio")   ;  6   0 110 Priority
		STR("-HELP-") ;  7   0 111 Emergency
		STR("CuSt 0") ;  8   1 000 Custom-0
		STR("CuSt 1") ;  9   1 001 Custom-1
		STR("CuSt 2") ; 10   1 010 Custom-2
		STR("CuSt 3") ; 11   1 011 Custom-3
		STR("CuSt 4") ; 12   1 100 Custom-4
		STR("CuSt 5") ; 13   1 101 Custom-5
		STR("CuSt 6") ; 14   1 110 Custom-6
	TAB(tab_mic_e_dest_ssid)
		STR("nonE")   ; 0
		STR("WidE-1") ; 1
		STR("WidE-2") ; 2
		STR("WidE-3") ; 3
		STR("WidE-4") ; 4
		STR("WidE-5") ; 5
		STR("WidE-6") ; 6
		STR("WidE-7") ; 7
		STR("north")  ; 8
		STR("South")  ; 9
		STR("EASt")   ; 10
		STR("WEst")   ; 11
		STR("n WidE") ; 12
		STR("S WidE") ; 13
		STR("E WidE") ; 14
		STR("W WidE") ; 15
	TAB(tab_ctcss_output_method)
		STR("i8254")  ; 0
		STR("rFcdAc") ; 0
		STR("Fx465")  ; 0
	TAB(tab_ctcss_input_method)
		STR("dSP")    ; 0
		STR("-Piob5") ; 1
		STR("Piob5")  ; 2
	TAB(tab_gps_config)
		STR("Std")
		STR("SirF")
		STR("SirFt")
		STR("9600Std")
#undef  CTCSS_RECORD
#define CTCSS_RECORD(dHz) STR("dHz") @
	TAB(tab_ctcss_tx_hz)
        	STR("oFF")
        	CTCSS_TONES

	ENDTABS

menu_quickspots:
	.dw menu_0
	.dw menu_1
	.dw menu_2
	.dw menu_3
	.dw menu_4
	.dw menu_5
	.dw menu_6
	.dw menu_7
	.dw menu_8
	.dw menu_9

;== SETUP DEFAULTS wrt BAND ===========================================

#define X(_f) .db LO(_f), LO((_f) >> 8), LO((_f) >> 16) @

	; IMPLIED
	; 1st I/F
	; VCO A/B rx
	; VCO A/B tx
	; TX LIMITS
	; BAND1:   start end duplex step
	; BAND2:   start end duplex step
	; OTHER:             duplex step

defaults_70cm:
	.db 4,3,3, EOS, EOS, EOS
	X( 86512)
	X(450000)
	X(450000)
	X(432000) X(438000)
	X(433400) X(433600) X(    0) .db STEP_25
	X(434600) X(435000) X(-1600) .db STEP_25
	                    X(-1600) .db STEP_25

defaults_2m:
	.db 1,4,5, EOS, EOS, EOS
	X( 21400)
	X(150000)
	X(150000)
	X(144000) X(146000)
	X(145200) X(145600) X(   0) .db STEP_25
	X(145600) X(145800) X(-600) .db STEP_25
	                    X(-600) .db STEP_25

defaults_6m:
	.db 0,5,1, EOS, EOS, EOS
	X( 45000)
	X( 60000)
	X( 60000)
	X( 50000) X( 52000)
	X( 51490) X( 51610) X(   0) .db STEP_20
	X( 51810) X( 51970) X(-600) .db STEP_20
	                    X(-600) .db STEP_20

#undef X


;----- GPS sentence processing (was fixed ROM) -----


;======================================================================

; execute [script_req] if it is nonzero.


;----- MPRS/APRS/MIC-E packets and locator maths (was fixed ROM) -----

;----- Repeater main state machine (was fixed ROM) -----

;======================================================================

; hl points to first blank after some characters to view

#ifdef BANK_TEST
bank_test_ping:
	ld a, #0xA5
	ret
#endif

bank1_end:
	ASSERT_LE(., 0xC000)
	slack_in_bank1 = 0xC000 - .

;== BANK 2 ============================================================
;
;  EPROM0 0x8000-0xBFFF, mapped at 0x8000 by set_bank(2); the same rules
;  as bank 1, entered through FAR stubs with bank2_call.  Linked at the
;  virtual address 0x28000 (bank 1 has the window addresses): labels here
;  are 0x28000 + offset, and every 16-bit use of them (ld, jp, .dw, >> 8,
;  & 0xFF) gets the window address; tools/ihx2bin.py puts the area at
;  file 0x8000.  C code with #pragma bank 2 (area _CODE_2) is linked
;  right after bank2_end (tools/link.py), C with #pragma bank 1 (_CODE_1)
;  after bank1_end.

	.area BANK2 (ABS)
	.org 0x28000
bank2_start:

#ifdef BANK_TEST
bank_test_ping2:
	ld a, #0x5A
	ret
#endif

bank2_end:
	ASSERT_LE(., 0x2C000)


;======================================================================

1:
	.area RAM (ABS)

	.org 0xC000		; start of RAM

;======================================================================
;
;	Variables
;

;----------------------------------------------------------------------
nvstart:					;------------------------------------------

audio_dst:       BYTE
volume:          BYTE ; reversed order of these two 25.8.2000

squelch_forced:  BYTE
scan_on:         BYTE
scan_mask:       WORD

mem_flags:       BYTE
mem_idx:         BYTE

rx_freq:         FREQ
tx_freq:         FREQ

duplex_state:    BYTE
duplex_shift:    FREQ
band:            BYTE
band_step:       BYTE
band_step_hz:    WORD
band_sctail:     BYTE
band_sclisten:   BYTE

vip_freq:        FREQ

mem_ctcss_rx_hz: BYTE     ; cfg_ctcss_*_hz
mem_ctcss_tx_hz: BYTE     ; brothers

band_autoreject: BYTE

				.ds 94 ; carve out future nv variables from here

ASSERT_EQ(., 0xC07C)    ; keep below unchanged, just append stuff to cfg_xxx

;-----------
VIP_COUNT = 10
vip_list:	BUF(SIZE_FREQ * VIP_COUNT)

;-----------
;  RFC values fold over every 100 MHz, each 1 MHz has separate value
;
rfctab:     .ds 100
end_rfctab:

;-----------
;  12 bytes per memory:
;
;    @0     3 bytes rx-frequency
;    @3     3 bytes tx-frequency
;    @6     1 byte  misc bits
;    @7     1 byte  ctcss hz
;    @8     4 bytes reserved
;

mem_FLAGS  = 6         ; offsets
mem_CTCSSt = 7
mem_BAND   = 8         ; XXX halfway
mem_CTCSSr = 9
mem_FOO2   = 10
mem_FOO3   = 11
mem_SIZE   = 12

MEM_VALID     = 0x01   ; flag bits
MEM_HIDDEN    = 0x02
MEM_SCANNABLE = 0x04


memories:    .ds 130 * mem_SIZE
end_memories:

;== SETUP BLOCK =======================================================

	cfg_function:          BYTE

	cfg_implied:           STRING   ; STRING

	cfg_txpwr:             BYTE     ; Transmitter power level
	cfg_alert_vol:         BYTE     ; Alert volume
	cfg_key_blip_pitch:    BYTE     ; Keyclick pitch idx
	cfg_light_seconds:     BYTE     ; seconds
	cfg_ign_apo_hours:     BYTE     ; powerdown without manipulation nor IGN
	cfg_tx_tot_minutes:    BYTE     ; powerdown if tx longer

	cfg_scan_rate_kvik:    BYTE     ; cSEC 0...2550

	cfg_squelch_source:    BYTE	   ; SQL, /SQL or RSSI
	cfg_squelch_level:     BYTE     ; between +/- half hysteresis
	cfg_squelch_BIG:       BYTE     ; REALLY STRONG SIGNAL, now sql_bi w/ RSSI
	cfg_squelch_hyst:      BYTE     ; difference of open and close levels
	cfg_squelch_head:      BYTE     ; opening "tail"
	cfg_squelch_tail:      BYTE     ; closing tail

	cfg_def_squelch:       BYTE
	cfg_def_memory:        BYTE
	cfg_def_frequency:     FREQ
	cfg_def_volume:        BYTE

	cfg_synth_card:        BYTE     ; TAB    S8x enumeration
	cfg_if_freq:           FREQ     ; 1st I/F
	cfg_rx_vco_center:     FREQ     ;
	cfg_tx_vco_center:     FREQ     ;
	; c/menu.c copies these three in one copy_default(9, cfg_if_freq)
	ASSERT_EQ(cfg_rx_vco_center - cfg_if_freq, 3)
	ASSERT_EQ(cfg_tx_vco_center - cfg_if_freq, 6)

	cfg_ctcss_tx_hz:       BYTE     ; 0..255 Hz

	cfg_lpf_hz:            WORD     ; low-pass cutoff freq

	cfg_tx_oob_0:          FREQ     ; Single spot allowed tx out-of-band

	cfg_tx_band_start:     FREQ     ; start/end pairs must be successive
	cfg_tx_band_end:       FREQ

size_bandrec = (3 * SIZE_FREQ + 3 + 2)      ; bands 1...6
	cfg_band1_start:       FREQ
	cfg_band1_end:         FREQ
	cfg_band1_duplex:      FREQ     ; CFG_DPX (includes sign)
	cfg_band1_step:        BYTE     ; TAB (STEP_xx)
	cfg_band1_sctail:      BYTE     ; seconds of lingering after LOS
	cfg_band1_sclisten:    BYTE     ; seconds of stay at one location
	cfg_band1_autoreject:  BYTE
	                      .ds 1
	cfg_band2_start:       FREQ
	cfg_band2_end:         FREQ
	cfg_band2_duplex:      FREQ
	cfg_band2_step:        BYTE     ; TAB (STEP_xx)
	cfg_band2_sctail:      BYTE     ; seconds of lingering after LOS
	cfg_band2_sclisten:    BYTE     ; seconds of stay at one location
	cfg_band2_autoreject:  BYTE
	                      .ds 1
	cfg_band3_start:       FREQ
	cfg_band3_end:         FREQ
	cfg_band3_duplex:      FREQ
	cfg_band3_step:        BYTE     ; TAB (STEP_xx)
	cfg_band3_sctail:      BYTE     ; seconds of lingering after LOS
	cfg_band3_sclisten:    BYTE     ; seconds of stay at one location
	cfg_band3_autoreject:  BYTE
	                      .ds 1
	cfg_band4_start:       FREQ
	cfg_band4_end:         FREQ
	cfg_band4_duplex:      FREQ
	cfg_band4_step:        BYTE     ; TAB (STEP_xx)
	cfg_band4_sctail:      BYTE     ; seconds of lingering after LOS
	cfg_band4_sclisten:    BYTE     ; seconds of stay at one location
	cfg_band4_autoreject:  BYTE
	                      .ds 1
	cfg_band5_start:       FREQ
	cfg_band5_end:         FREQ
	cfg_band5_duplex:      FREQ
	cfg_band5_step:        BYTE     ; TAB (STEP_xx)
	cfg_band5_sctail:      BYTE     ; seconds of lingering after LOS
	cfg_band5_sclisten:    BYTE     ; seconds of stay at one location
	cfg_band5_autoreject:  BYTE
	                      .ds 1
	cfg_band6_start:       FREQ
	cfg_band6_end:         FREQ
	cfg_band6_duplex:      FREQ
	cfg_band6_step:        BYTE     ; TAB (STEP_xx)
	cfg_band6_sctail:      BYTE     ; seconds of lingering after LOS
	cfg_band6_sclisten:    BYTE     ; seconds of stay at one location
	cfg_band6_autoreject:  BYTE
	                      .ds 1
num_bandrecs = 6
	cfg_other_start:       FREQ     ; unused, now "other" looks ...
	cfg_other_end:         FREQ     ; ... like previous bandrecords
	cfg_other_duplex:      FREQ     ; CFG_DPX (includes sign)
	; c/freq.c hard-codes the band record layout
	ASSERT_EQ(num_bandrecs, 6)
	ASSERT_EQ(size_bandrec, 14)
	ASSERT_EQ(cfg_band1_duplex - cfg_band1_start, 6)
	ASSERT_EQ(cfg_band1_step - cfg_band1_start, 9)
	ASSERT_EQ(cfg_band1_autoreject - cfg_band1_start, 12)
	ASSERT_EQ(cfg_other_duplex - cfg_band1_start, 6 * 14 + 6)
	ASSERT_EQ(DPX_SPLIT, 3)
	cfg_other_step:        BYTE     ; TAB (STEP_xx)
	cfg_other_sctail:      BYTE     ; seconds of lingering after LOS
	cfg_other_sclisten:    BYTE     ; seconds of stay at one location
	cfg_other_autoreject:  BYTE
	                      .ds 1

	cfg_reject_0:          FREQ
	cfg_reject_1:          FREQ
	cfg_reject_2:          FREQ
	cfg_reject_3:          FREQ
	cfg_reject_4:          FREQ
	cfg_reject_5:          FREQ
	cfg_reject_6:          FREQ
	cfg_reject_7:          FREQ
	cfg_reject_8:          FREQ
	cfg_reject_9:          FREQ

	unused_cfg_act_onhook:        STRING ; command strings
	unused_cfg_act_offhook:       STRING

	cfg_shortcut_0:        STRING
	cfg_shortcut_1:        STRING
	cfg_shortcut_2:        STRING
	cfg_shortcut_3:        STRING
	cfg_shortcut_4:        STRING
	cfg_shortcut_5:        STRING
	cfg_shortcut_6:        STRING
	cfg_shortcut_7:        STRING
	cfg_shortcut_8:        STRING
	cfg_shortcut_9:        STRING

	cfg_mycall_1:          STRING
	cfg_mycall_2:          STRING
	cfg_mycall_3:          STRING
	cfg_ccir_1:            STRING
	cfg_ccir_2:            STRING
	cfg_ccir_3:            STRING
	cfg_dtmf_1:            STRING
	cfg_dtmf_2:            STRING
	cfg_dtmf_3:            STRING

	cfg_pepa_on:           STRING
	cfg_pepa_off:          STRING

	cfg_ccir_minlen:       BYTE    ; cSEC, minimum accepted length of ccir series
	cfg_dtmf_holdtime:     BYTE    ; SEC, idle before dtmf sequence complete

	cfg_reject_10:         FREQ
	cfg_reject_11:         FREQ
	cfg_reject_12:         FREQ
	cfg_reject_13:         FREQ
	cfg_reject_14:         FREQ
	cfg_reject_15:         FREQ
	cfg_reject_16:         FREQ
	cfg_reject_17:         FREQ
	cfg_reject_18:         FREQ
	cfg_reject_19:         FREQ

	repeater_cfg_TOPEN:     WORD
	repeater_cfg_TID:       WORD
	repeater_cfg_THOG:      WORD
	repeater_cfg_TCLS:      WORD
	repeater_cfg_TDEAD:     WORD

	cfg_cw_speed:           BYTE
	cfg_cw_pitch:           BYTE    ; cSEC

	repeater_cfg_id_greet1:       STRING
	repeater_cfg_id_greet2:       STRING
	repeater_cfg_id_greet3:       STRING

	repeater_cfg_blip:      STRING

	cfg_overtemp_limit_xxx:     BYTE       ; unused
	cfg_rpm_limit:          BYTE

	repeater_cfg_afsrc:     BYTE   ; 0: AF routed when /MIC=+5V  1: v.v.
	repeater_cfg_access_method: BYTE ; tab

	cfg_remote_id:          WORD
	cfg_remote_xxxxxxxxx:   STRING                 ; XXX available to use

	cfg_light_sql:          BYTE   ; 0=off, 1=on

	repeater_cfg_id_during1:       STRING
	repeater_cfg_id_during2:       STRING
	repeater_cfg_id_during3:       STRING

	repeater_cfg_id_bye1:       STRING
	repeater_cfg_id_bye2:       STRING
	repeater_cfg_id_bye3:       STRING

	cfg_remote_fooy:        STRING     ; keep these ...
	cfg_remote_passwd:      STRING
	cfg_remote_passwd_size = . - cfg_remote_passwd     ; ... together

	repeater_cfg_TBEEPMAX:  WORD

	repeater_cfg_sqincr:    BYTE       ; squelch tightening delta value
	repeater_cfg_txincr:    BYTE       ; txpwr rised delta value

	cfg_txtune_hz:     WORD

	cfg_voice_id:           BYTE       ; onoff AVAILABLE, UNUSED
	cfg_idlefn_delay:       BYTE       ; minutes
	cfg_idlefn:             BYTE       ; tab

	cfg_unreject_mins:      BYTE       ;

	cfg_scan_skip_fsk_channels: BYTE

	cfg_tx_oob_1:          FREQ     ; Single spot allowed tx out-of-band
	cfg_tx_oob_2:          FREQ     ; Single spot allowed tx out-of-band
	cfg_tx_oob_3:          FREQ     ; Single spot allowed tx out-of-band
	cfg_tx_oob_4:          FREQ     ; Single spot allowed tx out-of-band

	cfg_inj_below:         BYTE    ; rx lo inj below if nz

	repeater_cfg_blip_link: STRING   ; blip if repeater sees PTT activity
	cfg_cw_pitch_blip:           BYTE    ; cSEC
	cfg_cw_pitch_blip_link:      BYTE    ; cSEC

	repeater_cfg_msg_hot_alert:       STRING
	repeater_cfg_msg_ant_bad:          STRING

	repeater_cfg_open_counter: FREQ
	transmitter_hours:         FREQ
	transmitter_hours_second_counter: WORD

	cfg_tx_mix_freq:       FREQ     ; TX mixer LO
	cfg_rx_vco_multiplier: BYTE     ; RX and TX multipliers
	cfg_tx_vco_multiplier: BYTE     ; 

	cfg_rssi_S1: BYTE
	cfg_rssi_S9: BYTE

	cfg_ctcss_input_method:   BYTE  ; tab
	cfg_ctcss_output_when:    BYTE  ; tab

	cfg_onhook_script:     STRING
	cfg_offhook_script:    STRING

	cfg_selcall_time: BYTE

	repeater_cfg_ccir_cmd_pfx: STRING

	cfg_aprs_tx:           BYTE ; off/on
	cfg_aprs_tx_freq:      FREQ
	cfg_mprs_callsign:     STRING

	cfg_num_tmp_rejects:   BYTE

	repeater_cfg_msg_hog:          STRING

	cfg_serv_blip_pitch:    BYTE     ; local välibongo

	cfg_enter_time:         BYTE     ; how many seconds must ENT be down

	cfg_gpio1_state:         BYTE
	cfg_gpio1_ccir_cmd_pfx:  STRING
	cfg_gpio1_dtmf_cmd_pfx:  STRING

	cfg_repeater_suspended:        BYTE
	cfg_repeater_suspend_ccir_cmd: STRING
	cfg_repeater_suspend_dtmf_cmd: STRING

	cfg_repeater_cmd_9_hidden: BYTE

	repeater_cfg_TBLIP:      BYTE

	cfg_repeater_wierd_simplex:     BYTE

	cfg_scan_rate_slow:   BYTE     ; cSEC 0...2550
	cfg_scan_large_qsy:   FREQ

	cfg_repeater_sitters_special:  BYTE

	cfg_keyup_mprs:     BYTE
	cfg_mbus_mprs:      BYTE

	; Following must be together
	cfg_gps_latitude:      STRING	; degrees3 minutes2 decim_minutes2 N/S
	cfg_gps_longitude:     STRING	; degrees3 minutes2 decim_minutes2 E/W

	cfg_gps_locator:       STRING	; KP41bb

	cfg_gpio2_state:         BYTE
	available_string_foo_0: STRING   ; XXX
	available_string_foo_1: STRING   ; XXX
	available_string_foo_2: STRING   ; XXX

	cfg_squelch_ctcss:     BYTE ; on/and/or/only
	cfg_mprs_symbol:       BYTE
	cfg_mprs_ssid:         BYTE
	cfg_fsk_silencer:      BYTE ; tab
	cfg_remote_dpy_secs:   BYTE ; seconds

	cfg_gps_upload:        BYTE ; tab
	cfg_gps_dst_send:      BYTE ; tab on/off

	cfg_gpio2_ccir_cmd_pfx:  STRING
	cfg_gpio2_dtmf_cmd_pfx:  STRING

	repeater_cfg_blip_gpio_001: STRING   ; blips when any of GPio1 and/or GPio2 are active
	repeater_cfg_blip_gpio_010: STRING   ; MUST be consecutive
	repeater_cfg_blip_gpio_011: STRING
	repeater_cfg_blip_gpio_100: STRING
	repeater_cfg_blip_gpio_101: STRING
	repeater_cfg_blip_gpio_110: STRING
	repeater_cfg_blip_gpio_111: STRING

	cfg_external_serial_A:       WORD
	cfg_external_serial_B:       WORD

	cfg_cw_pitch_blip_gpio:      BYTE    ; cSEC

	repeater_cfg_musical_blips:  BYTE ; cw/notes

	repeater_cfg_rssi_A:       BYTE
	repeater_cfg_blip_rssi_A:  STRING  ; bongo when rssi >= A
	repeater_cfg_rssi_B:       BYTE
	repeater_cfg_blip_rssi_B:  STRING  ; bongo when rssi >= B
	repeater_cfg_rssi_C:       BYTE
	repeater_cfg_blip_rssi_C:  STRING  ; bongo when rssi >= C

	repeater_cfg_rssi_bongos:  BYTE ; off on

	cfg_ctcss_rx_hz:       BYTE     ; 0..255 Hz
	cfg_deviation_fone:    BYTE     ; 0...15
	cfg_deviation_sign:    BYTE     ; 0...15

	cfg_bus_rf_relay:     BYTE     ; off on

	repeater_cfg_mprs_id:  BYTE    ; bitmap

	cfg_mprs_seconds:   WORD
	cfg_spontaneous_mprs:   BYTE
	cfg_report_type:   BYTE

	cfg_ax25_1200:     WORD      ; free
	cfg_ax25_2200:     WORD      ; free
	cfg_ax25_debug:     BYTE     ; free

	cfg_ax25_digi0:    BYTE    ; these must be contiguous
	cfg_ax25_digi1:    BYTE
	cfg_ax25_digi2:    BYTE
	cfg_ax25_digi3:    BYTE    ; this is now used

	cfg_ax25_padbits:   BYTE
	cfg_pll_delay:      BYTE

	cfg_mic_e_message:  BYTE
	cfg_mic_e_dest_ssid:  BYTE

	cfg_ax25_digi_other:  STRING  ; [othEr] in table

	cfg_ctcss_output_method:    BYTE  ; tab
	cfg_ctcss_generator_gain:   BYTE  ;
	cfg_ctcss_hang:             BYTE  ; ~ msec

	cfg_gpio1_ccir_pulse_cmd:  STRING
	cfg_gpio1_dtmf_pulse_cmd:  STRING

	cfg_gps_config:            BYTE ; tab Std, ...

	cfg_fx614_exist:           BYTE ; tab on off

	cfg_ctcss_dec_threshold:   BYTE ; 0..120

	cfg_dtmf_gain:   BYTE  ;
	cfg_ax25_gain:   BYTE  ;

	cfg_temperature_limit_cold:	BYTE
	cfg_temperature_limit_hot:	BYTE

	repeater_cfg_msg_cold_alert:       STRING

;== END SETUP BLOCK ===================================================

chk_size_nvdata = . - nvstart
	ASSERT_LT(chk_size_nvdata, (4 * 1024))

	.org nvstart + 4 * 1024
nvend:						;------------------------------------------

;----------------------------------------------------------------------

output_0:	BYTE
output_1:	BYTE

mbusrx_rp:	WORD
mbusrx_wp:	WORD

mbustx_rp:	WORD
mbustx_wp:	WORD

synth_ctrl:  BYTE    ; synth control register
rx_refdiv:   WORD
tx_refdiv:   WORD
rx_divisor:	BUF(3)
tx_divisor:	BUF(3)	; 17 bits NA

cpu_is_P8E:  BYTE

;======================================================================

_bss:                    ; zeroed variables

rx_bstep_cfg:	BUF(2)	; 2 and 25 for frequency/divisor math
tx_bstep_cfg:	BUF(2)	; 2 and 25 for frequency/divisor math

mbustx_cnt:	BYTE
mbusrx_cnt:	BYTE

mbus_timer:	BYTE		; timer for MBUS transmit

rssi_timer:		BYTE
mt_timer:		BYTE
key_timer:		BYTE
key_speed:		BYTE
key_blips:		BYTE

idle_timer:      BYTE    ; Minutes idle squelch and CU
alert_timer:		BYTE	; Seconds between alerts
lights_timer:	BYTE	; Seconds since last CU manipulation
txtail_timer:	BYTE	; to delay squelch pop after tx and
						; battery check wrt voltage drop on tx
tx_tot_timer:	BYTE	; Catch stuck PTT, 0...255 minutes
ign_apo_timer:   BYTE    ; powerdown after IGN clear this long
ccir_tx_timer:	BYTE	; for 100ms tone (10 ticks)
scan_timer:		BYTE    ; csec part...
scan_timer_secs: BYTE    ; ... second part.
scan_patience:	BYTE	; slower timer for "patience"

squelch_muted:	BYTE	; NZ if scanner unstable etc
scanner_state:	WORD
scan_paused:     BYTE    ; NZ if scanner paused on channel

squelch_tightening: BYTE ; normally 0, subtracted from "squelcher value"
txpwr_increment:    BYTE ; normally 0

scan_slicecnt:   BYTE
scan_slices:     BUF(num_bandrecs * 2 * SIZE_FREQ)

NUM_TMP_REJECTS = 20
reject_idx:		BYTE
tmp_rejects:		BUF((SIZE_FREQ + 1) * NUM_TMP_REJECTS) ; freq(3) + timer(1)
;  c/scan.c hard-codes these
	ASSERT_EQ(NUM_TMP_REJECTS, 20)
	ASSERT_EQ(mem_SIZE, 12)
	ASSERT_EQ(mem_FLAGS, 6)
	ASSERT_EQ(MEM_VALID, 0x01)
	ASSERT_EQ(MEM_SCANNABLE, 0x04)
	ASSERT_EQ(num_bandrecs, 6)
	ASSERT_EQ(MDM + MDMCTRL, 0xA3)
	ASSERT_EQ(MDM_DCD, 0x04)
	ASSERT_EQ(cfg_reject_9 + 3 - cfg_reject_0, 30)
	ASSERT_EQ(cfg_reject_19 + 3 - cfg_reject_10, 30)
;  c/keys.c hard-codes these too
	ASSERT_EQ(end_memories - memories, 130 * 12)
	ASSERT_EQ(mem_CTCSSt, 7)
	ASSERT_EQ(mem_BAND, 8)
	ASSERT_EQ(mem_CTCSSr, 9)
	ASSERT_EQ(mem_FOO2, 10)
	ASSERT_EQ(mem_FOO3, 11)
	ASSERT_EQ(MEM_HIDDEN, 0x02)
	ASSERT_EQ(VIP_COUNT, 10)

adj_feedback:	WORD
call_dpyed:      BYTE
dpx_ind_flags:   BYTE

sir:			BYTE
KEYSIR  = 0
DPYSIR  = 1
DTMFSIR = 2
INSIR   = 7
nosir:		BYTE	; Mainline needs full attention

lastdigit:	BYTE
lastkey:		BYTE
key:			BYTE
dark:		BYTE
key_time:	BYTE

pttdn:		BYTE
keydown:		BYTE

digidx:		BYTE
digbuf:		BUF(16)

squelch_prev_ones:    WORD   ; previous sqls (10 and 20 msec before)
squelch_delay:   BYTE   ; dragging "timer" for squelch head/tail
squelch_open:	BYTE   ; 1/0 state

mton:		BYTE

tx_is_legal: BYTE   ; NZ if ok to tx
txon:		BYTE
rfc:			BYTE
srssi:		BYTE

yucko_alfa_draw_long_6_only: BYTE

sec100:		BYTE		; "uptime"
seconds:		BYTE
minutes:		BYTE
hours:		BYTE

redraw_req:	BYTE
drawn:       BYTE

vip_idx:		BYTE

piob_mode:       BYTE  ; PIO B mode, ones inputs
pioa_data:		BYTE
last_columns:	BYTE  ; XXX free
dtmf_code:		BYTE
cu58af_buttons:  BYTE

local_mode:	BYTE	; NZ if /LOCAL grounded
cu_is_alfa:	BYTE	; NZ if CU58AF detected
cu_handler:  WORD    ; pointer to function handling CU DA or /INT

ccir_prevdata:    BYTE  ; unshifted raw bits from PIO PA
ccir_hist_finger: BYTE  ; peeking offset
ccir_hist_idx:    BYTE  ; insert point
ccir_tonetime:    BYTE  ; length in centiseconds
ccir_toneptr:     BYTE  ; start of current serie

dtmf_prevdata:    BYTE  ; unshifted raw bits from [DTMF]
dtmf_hist_finger: BYTE  ; peeking offset
dtmf_hist_idx:    BYTE  ; insert point
dtmf_idletime:    BYTE  ; note when no dtmf tones for some time
dtmf_toneptr:     BYTE  ; pending codes

packet:           BUF(16) ; buffer to collect input frame
pkt_ptr:          WORD   ; in above buffer
fsk_hist_finger:  BYTE   ; peeking offset
fsk_hist_idx:     BYTE   ; insert point
packet_good:      BYTE   ; index in history, to check "ours"
packet_rdy:       BYTE


menu_active: BYTE           ; 
menu_ptr:    WORD

lpf_hz_now:  WORD   ; catch change in setup

gps_hist_finger:   BYTE
gps_hist_idx:      BYTE
gps_hist_page:     BYTE     ; must follow gps_hist_idx !
gps_hist_rp:       BYTE

cw_slot_ticks:    BYTE
cw_pitch_cnt:     WORD

remote_display_buffer:   BUF(16)     ; longer than 8
display_buffer_time:     BYTE

idlefn_flag: BYTE

if_tmp:     FREQ

sio_bctrl_mirror:   BYTE
sio_bctrl_local:    BYTE

ding_req:    BYTE
script_req:  BYTE

rx_freq_previous:   FREQ
last_qsy_kHz:       FREQ
scan_settling_time: BYTE

call_timer_hour: BYTE
call_timer_min:  BYTE
call_timer_sec:  BYTE

repeater_state:         WORD  ; jump pointer
repeater_timer_other:   WORD        ; second timers
repeater_timer_ID:      WORD

repeater_timer_BLIP:       BYTE          ; 10msec timer
repeater_timer_BLIP_state: BYTE

repeater_ptt_seen:       BYTE
repeater_cw_sendit_all:  BYTE
repeater_cw_jmpbuf:      WORD

repeater_sitters_special: BYTE
repeater_is_suspended:    BYTE

gps_utc:           STRING    ; HHMMSS__
gps_date:          STRING    ; DDMMYY__
gps_speed:         BYTE      ; binary km/h
gps_course:        WORD      ; binary degrees


ad_bytes:                ; this must be aligned LO(ad_bytes) == AD
ad_rssi:		BYTE         ; 0
ad_sql:		BYTE         ; 1
ad_batt:		BYTE         ; 2
ad_tpc:      BYTE         ; 3
ad_fpm:      BYTE         ; 4
ad_rpm:      BYTE         ; 5
ad_tp4:      BYTE         ; 6
ad_in7:      BYTE         ; 7
ad_select:	BYTE     ; 0...15 index in ad_list[]

ASSERT_EQ(LO(ad_bytes), AD)    ; ioaddr must equal memaddr offset, silly optim

repeater_req:           BYTE  ; #x DTMF commands
repeater_sig:           BYTE  ; peak rssi during an over
last_sqtail:            BYTE  ; 1 if last sq close had tail

mprs_packed_packet:     BUF(6 + 3 + 3)
locator_display_buffer: STRING
locator_dpyed:          BYTE

gps_sentence_len:  BYTE
gps_latlon_tmp:         BUF(3 + 3)

gps_upload_ptr:         WORD

packet_rssi: BYTE

my_coord_tmp_6bytes:    BUF(6)
mprs_qrb_dir_bits:      BYTE
distance_bearing:       STRING

mprs_report_timer:      WORD

gps_knots:        WORD
gps_sentence:           BUF(100)
gps_sentence_size = . - gps_sentence

SHORT_PACLEN = 8
LONG_PACLEN  = 15

ctcss_enc_jump:         WORD
ctcss_enc_phinc:        WORD
ctcss_enc_phacc:        WORD

ctcss_dec_jump:         WORD
ctcss_dec_phinc:        WORD
ctcss_dec_phacc:        WORD

fx614_bufptr:           WORD    ; pointer to fx614_buffer[]

	slack_at_this_yyy_hole = ccir_history - .

	ALIGN(8, 0) ; ------------------------

ccir_history: BUF(256)    ; page aligned
dtmf_history: BUF(256)    ; page aligned
fsk_history:  BUF(256)    ; page aligned
gps_history:  BUF(256)    ; page aligned
#if 0
fx614_buffer: BUF(256)    ; page aligned
#endif

mbusrx_buf:	 BUF(256)    ; page aligned
mbustx_buf:	 BUF(256)    ; page aligned
ctcss_sintab: BUF(256)    ; page aligned
ax25_sintab:  BUF(256)    ; page aligned
dtmf_sintab:  BUF(256)    ; page aligned

segments:	BUF(64)      ; page aligned, space for either AN or AF cu.
indicators:	BYTE         ; LEDs.

	; rest need no align

ctcss_dec_sin:          WORD
ctcss_dec_cos:          WORD
ctcss_dec_fit:          BYTE     ; how good the correlation is
ctcss_dec_status:       BYTE     ; 0 if no decode
ctcss_dec_cnt:          BYTE     ; how many systicks between reloads

ctcss_is_on:            BYTE     ; nz when on
ctcss_custom_flag:      BYTE     ; nz if cw_epilog must ctcss_off

outpacket:	BUF(16)

mbus_mprs_buffer:       BUF(64) ; make sure there is room in here

aprs_packet_out: BUF(7 + 7 + 4 * 7 + 2 + 80)
aprs_packet_out_size = . - aprs_packet_out     ; make sure these have room
aprs_bits_out:   BUF(32 + 1 + aprs_packet_out_size * 6 / 5 + 6 + 2)

gps_reported_speed:     BYTE
gps_status:             STRING
gps_valid_seconds:      BYTE     ; seconds downcounter from "good" nmea


fx614_rxcnt:           BYTE ; XXX debug only

junk:		WORD

cur_bank:	BYTE	; set_bank: bank in the 0x8000 window
out2_bank:	BYTE	; its OUT2 bits (O2_BANK)
out2_last:	BYTE	; last handset bus state written to OUT2
ctcss_dec_src:	WORD	; CTCSS DSP decoder sample address
ctcss_idle_sample: BYTE	; stays 0: "no signal" while banked
bank_hl:	WORD	; bank1_call temporaries
bank_to:	WORD	; target bank (low byte)
repeater_tick:	BYTE	; sec100 at the last far_repeater_run
dpy_cursor:	WORD	; c/display.c: display cursor (DE in the assembler)
bank_fn:	WORD
bank_af:	WORD
#ifdef BANK_TEST
bank_test_msg:	BUF(10)
#endif

C_BSS_SIZE = 256
c_bss:	.ds C_BSS_SIZE	; the C modules' _DATA area is linked here (tools/link.py)
c_bss_end:

_end:
cfg_image_buffer:		; all_config_get receives the NV image here (up to the stack)

chk_size_stack = 0x10000 - _end
slack_for_stack = chk_size_stack

	ASSERT_GT(chk_size_stack, (4 * 1024))

