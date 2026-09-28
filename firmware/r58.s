; sdasz80 source, built by cpp + tools/asmpp.py + sdasz80 (notes/toolchain.md).
; Converted from the as80 source by tools/as80tosdas.py.
; HI/LO, ALIGN/FILL, ASSERT_*: firmware/asm.h
#include "asm.h"

#ifdef C_MODULES
/* routines replaced by C (c/*.c); C symbols carry a leading underscore */
#define squelch			_squelch
#define append_short_packet_crc	_append_short_packet_crc
#define append_long_packet_crc	_append_long_packet_crc
#define append_secret_packet_crc	_append_secret_packet_crc
#define once_per_second		_once_per_second
#define once_per_minute		_once_per_minute
#define once_per_hour		_once_per_hour
#define battcheck		_battcheck
#define keycheck		_keycheck
#define dokey_not_menu		_dokey_not_menu
#define handle_key_during_tx	_handle_key_during_tx
#define draw_upper_row		_draw_upper_row
#define draw_lower_row		_draw_lower_row
#define changed_frequency		_changed_frequency
#define changed_frequency_duplex_okay		_changed_frequency_duplex_okay
#define temporary_change_rx_freq		_temporary_change_rx_freq
#define locate_band		_locate_band
#define set_duplex_from_tx_rx		_set_duplex_from_tx_rx
#define step_duplex_state		_step_duplex_state
#define step_channel_up		_step_channel_up
#define step_channel_down		_step_channel_down
#define update_tx_vco_band		_update_tx_vco_band
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
#define scanner_run		_scanner_run
#define scanner_stop		_scanner_stop
#define toggle_scan_mask		_toggle_scan_mask
#define add_reject		_add_reject
#define clear_rejects		_clear_rejects
#endif

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

#ifndef C_MODULES
once_per_second:

	ld a, (gps_valid_seconds)
	or a
	jr z, 1f
	dec a
	ld (gps_valid_seconds), a
1:

	ld hl, (mprs_report_timer)
	ld a, (gps_speed)               ; this one in km/h
	rra
	rra
	and #0x3F
	inc a                           ; 128 km/h => 33, still => 1
	ld e, a
	ld d, #0
	add hl, de
	jr nc, 1f
	ld hl, #0xFFFF
1:
	ld (mprs_report_timer), hl

	ld a, (txon)
	or a
	jr z, 1f

	; transmitter hours counter

	ld hl, (transmitter_hours_second_counter)
	inc hl
	ld (transmitter_hours_second_counter), hl
	ld a, l
	cp #LO(3600)
	jr nz, 1f
	ld a, h
	cp #HI(3600)
	jr nz, 1f

	ld hl, #0
	ld (transmitter_hours_second_counter), hl

	ld hl, #transmitter_hours
	inc (hl)
	jr nz, 1f
	inc hl
	inc (hl)
	jr nz, 1f
	inc hl
	inc (hl)              ; about 2000 years. not likely to overflow.
1:

	;
	;  repeater sitting
	;
	ld a, (pioa_data)
	and #PA_HOOK
	jr z, 1f                             ; handset off cradle, disabled, skip
	ld hl, #repeater_sitters_special
	ld a, (hl)
	or a
	jr z, 1f                             ; not counting, skip
	inc (hl)
	call z, audioc_off                   ; stealthly disable audio if overflow
1:

	;
	;  Alert timer
	;
	ld a, (alert_timer)
	or a
	jr z, 1f
	dec a
	ld (alert_timer), a
1:
	;
	;  slower scanner timer
	;
	ld a, (scan_on)
	or a
	jr z, 1f
	ld a, (scan_patience)
	or a
	jr z, 1f
	dec a
	ld (scan_patience), a
1:
	;
	;  _INCREMENT_ timer for handset lights
	;
	ld a, (keydown)
	or a
	jr nz, 1f				; not if button still pressed
	ld a, (lights_timer)
	inc a
	jr z, 1f                ; walk and stay at 255 seconds
	ld (lights_timer), a
1:

	;  any pending DTMF codes buffered ?

	ld a, (dtmf_idletime)
	or a
	jr z, 1f
	inc a
	ld hl, #cfg_dtmf_holdtime
	cp (hl)
	jr c, 2f
	call dtmf_decoder_timeout
	xor a
2:
	ld (dtmf_idletime), a
1:

	; REPEATER timers

	ld a, (cfg_function)
	dec a                          ; if 1
	call z, repeater_step_1sec

	; DisplayData Buffer

	ld a, (display_buffer_time)
	or a
	jr z, 1f
	dec a
	ld (display_buffer_time), a
	jr nz, 1f
	ld (locator_dpyed), a
	ld a, #1
	ld (redraw_req), a
1:


	; call timer ?

	ld a, (call_dpyed)
	or a
	jr z, 1f

	ld a, (call_timer_sec)
	inc a
	cp #60
	jr c, 2f
		ld a, (call_timer_min)
		inc a
		cp #60
		jr c, 3f
			ld a, (call_timer_hour)
			inc a
			cp #99
			jr c, 4f
				ld a, #99
			4:
			ld (call_timer_hour), a
			xor a
		3:
		ld (call_timer_min), a
		xor a
	2:
	ld (call_timer_sec), a
1:
	; done

	ret

;----------------------------------------------------------------------

once_per_minute:

	; TOT overrun ?

	ld a, (txon)
	or a
	jr z, 1f
	; tx_tot_timer counts the minute boundaries since TX on, so TX lasts
	; N..N+1 minutes before a TOT of N powers down.  (v3_Z compared before
	; counting and allowed N+1..N+2.)  255 = no limit.
	ld a, (cfg_tx_tot_minutes)
	cp #255
	jr z, 1f
	ld hl, #tx_tot_timer
	inc (hl)
	cp (hl)                        ; carry if more minutes than allowed
	jp c, powerdown_now
1:

	;  When idle_timer passes over cfg_idlefn_delay,
	;  restart scan or do other things

	ld a, (scan_on)
	or a
	jr nz, 1f       ; no idle timer if scanner already on
	ld a, (squelch_open)
	or a
	jr nz, 1f       ; no idle timer if squelch open
	ld a, (key)
	cp #-1
	jr nz, 1f       ; no idle timer if key pending
	ld a, (digidx)
	or a
	jr nz, 1f       ; no idle timer if digit buffer pending
	ld a, (menu_active)
	or a
	jr nz, 1f       ; no idle timer if in setup
	call is_ptt_pressed
	jr nz, 1f       ; no idle timer if PTT

	ld hl, #idle_timer
	ld a, (hl)
	inc a
	jr z, 1f        ; stay at 255 minutes

	ld (hl), a     ; bump idle_timer

	ld a, (cfg_idlefn_delay)
	or a
	jr z, 1f       ; delay=0 == no autoscan

	cp (hl)                       ; cfg - timer
	jr nz, 1f       ; jump if not at exact point

	ld a, #1
	ld (idlefn_flag), a
1:
	;
	;  Decay temporary reject timers
	;
	call unreject_timer

	ret

;----------------------------------------------------------------------

once_per_hour:

	; APO overrun ?

	in a, (PIO+BDATA)
	and #PB_EXIN2              ; aka /IGN
	jr z, 1f                  ; /IGN still grounded
	ld a, (cfg_ign_apo_hours)
	ld hl, #ign_apo_timer
	cp (hl)                        ; if cfg is 255, never carry
	jp c, powerdown_now
	inc (hl)
1:

	call re_enable_modem
	ret

#endif /* C_MODULES */

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

#ifdef C_MODULES
; _x = x for the firmware symbols the C modules use (tools/cglue.py)
#include "cglue.inc"
#else
squelch:

#if 0
	call read_squelcher_value  ; current sql

	ld bc, (squelch_prev_ones)
	ld d, c                    ; d has sql 20 msec ago
	ld c, b
	ld b, a                    ; b has sql now
	ld (squelch_prev_ones), bc
#else
	ld a, (ad_rssi)
	ld bc, (squelch_prev_ones)
	ld d, c                    ; d has rssi 20 msec ago
	ld c, b
	ld b, a                    ; b has rssi now
	ld (squelch_prev_ones), bc

	call read_squelcher_value  ; current sql
	ld b, a                    ; b has sql now
#endif

	ld a, (cfg_squelch_hyst)
	srl a
	ld c, a                    ; c has half hysteresis


	ld a, (squelch_open)       ; previous state
	or a
	jr nz, 9f

	;  squelch was closed --------------------------------

	ld a, (cfg_squelch_level)
	add a, c                        ; a has open limit
	jr nc, 1f
	sbc a, a                        ; quicker ld a, 0xFF
1:
	cp b						 ; open_limit - sql
	jp nc, squelch_is_closed     ; if open_limit >= sql, stay closed

	;  sql now rised above open limit

	ld a, (squelch_delay)
	or a
	jr z, 1f
	dec a
	ld (squelch_delay), a        ; still dragging to open
	ret nz
1:
	ld a, (cfg_squelch_ctcss) ; are we using ctcss for squelch ?
	or a
	jr z, 1f                  ; ... skip if not.
	call get_ctcss_rx_hz
	or a
	jr z, 1f                  ; ... skip if CTCSS Hz is 0 meaning OFF
	call read_ctcss_detect
	ret z                     ; do not open until also CTCSS detected.
1:

	; opening delay expired, open and prep delay for tail

	call cu_serv_on
	call cu_lights_on_from_squelch
	call pull_down_EXIN1
	call squelch_is_open
	ld hl, #sir
	set DPYSIR, (hl)

	call start_repeater_sitters_special

	ld a, (squelch_muted)
	or a
	ret nz					; Scanner etc forced no audio.

	jr audioc_on

	;  squelch was open ---------------------------------
9:

	ld a, (cfg_squelch_ctcss) ; are we using ctcss for squelch ?
	or a
	jr z, 1f                  ; ... skip if not.
	call get_ctcss_rx_hz
	or a
	jr z, 1f                  ; ... skip if CTCSS Hz is 0 meaning OFF.
	call read_ctcss_detect
	jr nz, 1f                 ; if CTCSS detected, continue check SQL.

	ld b, #0                   ; ... else make it close now, SQL forced to 0.
1:

	ld a, (cfg_squelch_level)
	sub c
	ld c, a
	jr nc, 1f
	ld c, #0                         ; c has close limit
1:
	ld a, b                         ; a has sql
	cp c							; sql - close_limit
	jr nc, squelch_is_open     		; if sql >= close_limit, stay open

	;  sql now below close limit, tail delay ?

	ld c, #0                     ; assume no tail

	ld a, (cfg_squelch_BIG)
	cp d                       ; monster_threshold - value_20_msec_ago
	jr c, 1f                   ; last value was above MONSTER, tail-less

	ld c, #1                  ; close action has tail

	ld a, (squelch_delay)
	or a
	jr z, 1f
	dec a
	ld (squelch_delay), a        ; still dragging
	ret nz
1:
	ld a, c
	ld (last_sqtail), a      ; remember how squelch closed

	; closing delay expired, close and prep delay for opening delay

	call cu_serv_off
	call release_EXIN1
	call squelch_is_closed
	ld hl, #sir
	set DPYSIR, (hl)

	call serv_blip            ; possible local blip from closing squelch

	ld a, (squelch_forced)
	or a
	ret nz						; Manually forced open.

	jr audioc_off

#endif /* C_MODULES */

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
	call redrawcheck
	call battcheck
	call pttcheck
	call aprs_ptt_check
	call keycheck
	call fskcheck
	call ccircheck
	call dim_lights_if_idle
	call idlefn_check
	call script_check
	call scanner_run
	call far_repeater_run
	call gps_check

	ld a, (cfg_bus_rf_relay)
	or a
	call nz, bus_rf_relay             ; only if configured

	ld a, (cfg_spontaneous_mprs)
	or a
	call nz, spontaneous_mprs_check   ; only if configured

	; halt
	; jr mainloop
	jr mainloop

;======================================================================

bus_rf_relay:

	ld a, (mbusrx_cnt)
	cp #12
	ret c

	ld de, #outpacket
	ld a, #0x50
	ld (de), a
	inc de

	ld b, #12
1:
	call getchar
	ld (de), a
	inc de
	djnz 1b

	call append_long_packet_crc

	ld b, #LONG_PACLEN
	jp send_packet_buffer

;======================================================================

gps_configure:

	ld a, (cfg_gps_config)

	dec a                                ; if 1
	jr z, gps_configure_SiRF_generic
	dec a                                ; if 2
	jr z, gps_configure_SiRF_tailored
	dec a                                ; if 3
	jr z, gps_configure_aisin_seiki
	dec a                                ; if4 9600 gps riku
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
	;  Aisin-Seiki talks proprietary data in 9600 baud, 8 data, even parity
	;
gps_configure_aisin_seiki:

	di

	ld a, #4            ; WR4
	out (SIO+ACTRL), a
	ld a, #WR4_1STOPBIT | WR4_X16_CLK | WR4_PARITY_ENB | WR4_PARITY_EVEN
	out (SIO+ACTRL), a

	ei

	; no nmea option. proprietary data is handled on-the-fly later

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

gps_check:

	ld a, (gps_hist_rp)        ; our removal idx
	ld e, a
	ld a, (gps_hist_idx)       ; insertion idx
	cp e
	ret z                      ; empty

	ld d, #HI(gps_history)      ; picking from here


	ld a, (cfg_gps_config)
	cp #3
	jr z, gps_check_aisin_seiki


	ld a, (gps_sentence_len)
	ld c, a                    ; length of sentence
	ld b, #0
	ld hl, #gps_sentence
	add hl, bc                 ; storing into here

	ex de, hl                  ; just for fun, normal assignment of src/dest
1:
	ld a, c
	cp #gps_sentence_size
	jr nc, 3f                  ; too long sentence, not likely. just rewind

	ld a, (hl)                 ; ++ at the loop bottom

	cp #'$'
	jr z, 3f                   ; $ (not stored), go rewind.

	cp #0x0A
	jr z, 2f                   ; ends in CR LF, process, then rewind.

	ld (de), a
	inc de
	inc c
	jr 4f
2:
	push hl
	ld a, c                    ; check for obvious junk, shorter than N chars.
	cp #10
	call nc, far_gps_process_sentence
	pop hl
3:
	ld c, #0
	ld de, #gps_sentence        ; rewind
4:
	ld a, (gps_hist_idx)       ; meanwhile... insertion idx
	inc l                      ; stay in page buffer
	cp l                       ; 
	jr nz, 1b                  ; keep on loopin

	ld a, l
	ld (gps_hist_rp), a        ; update removal idx
	ld a, c
	ld (gps_sentence_len), a   ; update sentence length

	ret

	;
	; There will be 44+50+11+11 bytes every second,
	; namely the CACA, CBCB, C3C3 and C4C4 messages.
	; So the 256 byte ringbuffer will not overrun easily.
	;
	; CA CA [40 bytes] cksum 0D is the block which interests us.
	; cksum is complement of 8-bit sum of CA CA (any tag) and payload bytes.
	;
gps_check_aisin_seiki:         ; DE points to first new gps data byte

1:
	ld a, (de)
	inc e                      ; stay in page buffer
	cp #0x0D
	call z, far_gps_process_aisin_seiki

	ld a, (gps_hist_idx)
	cp e
	jr nz, 1b

	ld a, e
	ld (gps_hist_rp), a        ; update removal idx

	ret

; GPS sentence processing lives in bank 1 (search "BANK 1"), with
; C_MODULES in c/gps.c, bank 2.
#ifdef C_MODULES
far_gps_process_aisin_seiki:	; DE -> after a 0x0D in gps_history, kept
	push de
	ld a, e
	call 1f
	pop de
	ret
1:
	call bank2_call
	.dw _gps_process_aisin_seiki
far_gps_process_sentence:	; C = length
	ld a, c
	call bank2_call
	.dw _gps_process_sentence
gps_latlon:			; c/gps.c: HL -> 1/256", DE -> DDDMMmm
	push hl
	pop iy
	push de
	pop ix
	jp aisin_seiki_parse_latlon
#else
far_gps_process_aisin_seiki:	call bank1_call
	.dw gps_process_aisin_seiki
far_gps_process_sentence:	call bank1_call
	.dw gps_process_sentence
#endif

script_check:

	ld a, (script_req)
	or a
	ret z

	call open_selective            ; before script (so it can (re)start mute)

	; reset flag

	ld hl, #script_req
	ld a, (hl)
	ld (hl), #0

	; SIZE_STR bytes from HL

	ld b, #SIZE_STR
	dec a                        ; if 1
	ld hl, #cfg_onhook_script
	jr z, 1f
	dec a                        ; if 2
	ret nz                       ; did not recognize it, ignore.
	ld hl, #cfg_offhook_script
1:
	ld a, (hl)
	inc hl              ; next character
	cp #EOS
	jr z, 1f               ; End of string character
	push hl
	push bc

	ld c, a                ; chr in C

	xor a
	ld (key_time), a         ; this gives only quick simple presses
	ld (keydown), a
	dec a                    ; ld a, -1
	ld (key), a

	ld a, c                ; the C version takes the key in A
	call dokey_not_menu     ; process the character

	pop bc
	pop hl
	djnz 1b             ; 8 characters max
1:
	ret

;======================================================================

dim_lights_if_idle:
	ld a, (cfg_light_seconds)
	ld hl, #lights_timer
	cp (hl)                 ; setting - idleseconds
	call c, cu_lights_off   ; dim if idle longer than configured time
	ret

;----------------------------------------------------------------------

ccircheck:
	ld a, (ding_req)
	or a
	ret z
	xor a
	ld (ding_req), a

	call ding
	ret

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

idlefn_check:
	ld a, (idlefn_flag)
	or a
	ret z

	xor a
	ld (idlefn_flag), a

	ld a, (cfg_idlefn)

	dec a                  ; if 1
	jp z, scanner_start
	dec a                  ; if 2
	jp z, def_memo

	ret

;----------------------------------------------------------------------

#ifdef C_MODULES
alert_tone_1s:			; for c/timers.c battcheck: 300 Hz for 1 s
	ld hl, #MT_300HZ
	ld d, #100
	jp start_marker_tone
#else
; Battery dangerously low.
; Twiddle here for a moment, waiting voltage to revive, return back then.
; After a couple of seconds turn off power relay.

battcheck_lobatt:

	call feedback_lobatt
	call force_redraw

	ld a, (seconds)
	add a, #5                   ; 5 seconds twiddling at powerwait
	cp #60
	jr c, 1f
	sub #60
1:
	ld b, a            ; save, couple of seconds into future, modulo minutes

1:
	ld a, (seconds)
	cp b
	jp z, powerdown_now        ; timeout. OFF!

	ld a, (ad_batt)
	cp #100 * 256 / 156	       ; 10V
	jr c, 1b                   ; loop if below.

	; whoa, battery reanimation

	call clear_clock_icon
	call no_feedback

	jp redraw                  ; returns to caller of battcheck()


battcheck:

	ld a, (txtail_timer)	; did xmit lately ?
	or a
	ld a, (ad_batt)
	jr z, 2f
	cp  #80 * 256 / 156	       ; 8V
	jr c, battcheck_lobatt

	cp  #90 * 256 / 156	        ; 9V, was 11.2V, 184
	jr c, 1f
	call clear_clock_icon
	ret
2:
	cp  #90 * 256 / 156	           ; 9V, was 10.2V, 167
	jr c, battcheck_lobatt

	cp #100 * 256 / 156	       ; 10V, was 11.2V, 184
	jr c, 1f
	call clear_clock_icon
	ret

1:
	call draw_clock_icon

	ld a, (alert_timer)
	or a
	ret nz

	ld a, #60
	ld (alert_timer), a	; every 60 sec

	ld hl, #MT_300HZ
	ld d, #100				; one second alert tone
	call start_marker_tone

	ret

#endif /* C_MODULES */

;======================================================================

redrawcheck:

	ld a, (redraw_req)
	or a
	ret z

	xor a
	ld (redraw_req), a

	jp redraw

;======================================================================

#ifndef C_MODULES
keycheck:

	ld a, (key)
	cp #-1
	ret z

	ld c, a
	call clear_key
	call dokey
	call no_feedback
	call open_selective
	jp redraw

#endif /* C_MODULES */

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

#ifndef C_MODULES
dokey:				; whatever we call will do ret

	ld a, (menu_active)
	or a
	jp nz, menu_input

	; fallthru

dokey_not_menu:

	ld a, c
	cp #10
	jp c, insdig_or_scan_toggle

	cp #'T'
	jp z, mute_squelch_selective

	cp #'#'
	jp z, execute
	cp #'C'
	jp z, backspace
	cp #0xC
	jp z, backspace
	cp #'E'
	jp z, far_toggle_or_position_menu
	cp #0xE
	jp z, far_toggle_or_position_menu
	cp #'*'
	jp z, beep_or_fsk_send
	cp #'+'
	jp z, up_vola
	cp #'-'
	jp z, dn_vola
	cp #'B'
	jp z, monitor_audio
	cp #0xB
	jp z, monitor_audio

	cp #0x81
	jp z, up_sqlv
	cp #0x84
	jp z, dn_sqlv
	cp #0x87
	jp z, def_sqlv

	cp #0x82
	jp z, up_memo
	cp #0x85
	jp z, dn_memo
	cp #0x88
	jp z, def_memo

	cp #0x83
	jp z, up_freq
	cp #0x86
	jp z, dn_freq
	cp #0x89
	jp z, def_freq

	cp #0x80
	jp z, def_vola

	cp #'S'
	jp z, scanner_key

	cp #'R'
	jp z, duplex_key

	cp #'K'
	jp z, step_audio_dst

	ret

menu_input:

	ld a, c
	cp #10
	jp c, insdig

	cp #'C'
	jp z, backspace
	cp #0xC
	jp z, backspace
	cp #'E'
	jp z, far_toggle_or_position_menu
	cp #0xE
	jp z, far_toggle_or_position_menu
	cp #'#'
	jp z, far_menu_enter_or_walk
	cp #'*'
	jp z, far_menu_defval_or_exec
	cp #'+'
	jp z, far_menu_up_value
	cp #'-'
	jp z, far_menu_dn_value
	cp #'B'
	jp z, monitor_audio
	cp #0xB
	jp z, monitor_audio

	cp #0x81   ; alphanumeric input with long digit presses
	jp z, insdig_alpha
	cp #0x82
	jp z, insdig_alpha
	cp #0x83
	jp z, insdig_alpha
	cp #0x84
	jp z, insdig_alpha
	cp #0x85
	jp z, insdig_alpha
	cp #0x86
	jp z, insdig_alpha
	cp #0x87
	jp z, insdig_alpha
	cp #0x88
	jp z, insdig_alpha
	cp #0x89
	jp z, insdig_alpha
	cp #0x80
	jp z, insdig_punct

	cp #'S'
	jp z, far_menu_next_group

	cp #'R'
	jp z, far_menu_prev

	cp #'K'
	jp z, step_audio_dst

	ret

#endif /* C_MODULES */

;----------------------------------------------------------------------

#ifndef C_MODULES
handle_key_during_tx:

	call clear_key

	; volume buttons step xmit power when transmitting

	cp #'+'
	jp z, step_txpwr_up
	cp #'-'
	jp z, step_txpwr_down

	; other buttons emit DTMF

	ld c, a
	ld a, (cu_is_alfa)
	or a
	ld a, c
	jp nz, dtmf_cu58af

	jp dtmf_bang_tone

#endif /* C_MODULES */

;----------------------------------------------------------------------

execute:
	ld a, (scan_on)
	or a
	jp nz, scanner_stop	; Just stop it, nothing else
	call 1f
	call save_nvdata
	ret
1:
	ld a, (key_time)
	or a
	jp nz, save_memory		; long press starting, go handle memories

	call is_key_down
	jr nz, 1b

	ld a, (digidx)
	cp #0
	jp z, next_vip          ; just #, no digits
	cp #3
	jp c, go_mem			; 1...2 digits
	cp #5
	call c, fill_implied	; if 3 or 4 digits, fix to abs.

	call a2i
	save_ahl(rx_freq)
	call leave_memories
	call remember_vip
	call changed_frequency
	ret

;----------------------------------------------------------------------

monitor_audio:

	ld a, (scan_on)
	or a
	jp nz, scanner_stop              ; thingy just stops scanner, if scanning.

	; possibly enter repeater input

	load_ahl(rx_freq)
	push af
	push hl
	call compare_tx_rx_freq
	push af                 ; Remember to re-swap rx/tx if needed
	jr z, 1f				; Simplex. No channel change

	load_ahl(tx_freq)
	save_ahl(rx_freq)
	call temporary_change_rx_freq
1:
	ld a, (squelch_forced)     ; remember which way it was
	ld c, a
	call force_squelch         ; anyways it is open when button down

	; wait button release, note if over 1 sec down.

	ld b, #0                 ; assume "quick"
1:
	push bc
	call redraw
	pop bc
	ld a, (keydown)
	cp #20
	jr c, 2f
	ld b, #1                 ; no, "long" after 200 msec
2:
	call is_key_down
	jr nz, 1b

	; close squelch if long press, toggle if short. We opened it above, so
	; close squelch if long press _or_ it was already forced

	ld a, b            ; NZ if long
	or c               ; NZ if forced already
	call nz, unforce_squelch

	; restore frequency if changed

	pop af
	pop hl
	pop bc
	jr z, 1f				; Simplex. No channel change
	ld a, b
	save_ahl(rx_freq)
	call temporary_change_rx_freq
1:
	ret


up_freq:
	call leave_memories
	call clear_buffer
	call scanner_stop
	jp step_channel_up

dn_freq:
	call leave_memories
	call clear_buffer
	call scanner_stop
	jp step_channel_down


def_sqlv:
	call clear_buffer
	call feedback_default
	call redraw
1:
	ld a, (key_time)
	cp #2
	jr nc, 1f			; set default
	call is_key_down
	jr nz, 1b

	ld a, (cfg_def_squelch)
	ld (cfg_squelch_level), a

	call unforce_squelch	; Adjusting opened sq removes hard open.
	ret
1:
	ld a, (cfg_squelch_level)
	ld (cfg_def_squelch), a

	call feedback_stored
	call waitkey
	ret

up_sqlv:
	call clear_buffer

	ld a, (cfg_squelch_level)
	add a, #1
	sbc a, #0
	ld (cfg_squelch_level), a
	call unforce_squelch	; Adjusting opened sq removes hard open.
	ret

dn_sqlv:
	call clear_buffer

	ld a, (cfg_squelch_level)
	sub #1
	adc a, #0
	ld (cfg_squelch_level), a
	call unforce_squelch	; Adjusting opened sq removes hard open.
	ret

up_vola:
	ld a, #1
	jr 1f
dn_vola:
	ld a, #-1
	jr 1f
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

fill_implied:

	; 3 or 4 digits, use implied for initial part of frequency

	ld de, #digbuf + 5
	ld hl, #digbuf + 2
	ld bc, #6
	ld a, (digidx)
	cp #3
	jr z, 1f
	inc hl
	ldd
1:
	ldd
	ldd
	ldd
	ld hl, #cfg_implied
	ld de, #digbuf
	ldir                ; 2 or 3 count in bc
	ld a, #6
	ld (digidx), a      ; abs. freq now

	ret

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

insdig_or_scan_toggle:
	ld e, a
	ld a, (scan_on)
	or a
	ld a, e
	jp nz, toggle_scan_mask

	; FALL THRU

insdig:
	ld e, a
	ld a, (digidx)
	cp #16
	jr nc, 1f
	ld hl, #digbuf
	ld b, #0
	ld c, a
	add hl, bc
	inc a
	ld (hl), e
	ld (digidx), a
1:
	call scanner_stop
	ret

backspace:
	call far_decoder_hist_rewind

	xor a
	ld (vip_idx), a

	call scanner_stop

	ld a, (keydown)
	cp #20
	jr nc, 1f
	ld a, (digidx)
	sub #1                 ; initial CL press, erase one
	adc a, #0
	ld (digidx), a
	ret
1:
	xor a				; Brute force clear all if repeating CL
	ld (digidx), a
	ret

alpha_punct:
	.db '/', '-', '?', '#'
	.db '$', '=', '.', 0
alpha_tab:
	.db 0xA, 0xB, 0xC, 1
	.db 0xD, 0xE, 0xF, 2
	.db 'G', 'H', 'I', 3
	.db 'J', 'K', 'L', 4
	.db 'M', 'N', 'O', 5
	.db 'P', 'Q', 'R', 6
	.db 'S', 'T', 'U', 7
	.db 'V', 'W', 'X', 8
	.db ' ', 'Y', 'Z', 9

insdig_punct:
	ld hl, #alpha_punct
	ld a, (key_time)
	sub #1
	and #7
	ld e, a
	ld d, #0
	add hl, de
	jr 1f

	; JMPOVER

insdig_alpha:
	and #0xF
	sub #1           ; table starts from 1
	add a, a    ; *= 2
	add a, a    ; *= 4
	ld e, a
	ld d, #0
	ld hl, #alpha_tab
	add hl, de
	ld a, (key_time)
	sub #1
	and #3
	ld e, a
	add hl, de
1:
	ld e, (hl)

	ld hl, #digbuf
	ld a, (digidx)
	ld b, #0
	ld c, a
	add hl, bc
	cp #16
	ret nc        ; forget if buffer full
	ld a, (digidx)
	cp #0
	jr z, 1f      ; impossible, digidx 0 but rnot first alpha XXX
	ld a, (key_time)
	cp #1
	jr z, 1f      ; go if first alpha

	dec hl        ; else overwrite current char
	ld (hl), e
	ret
1:
	ld (hl), e
	ld a, (digidx)
	inc a
	ld (digidx), a
	ret

;----------------------------------------------------------------------

duplex_key:
	ld a, (digidx)
	cp #2
	jp c, step_duplex_state  ; too few digits, simplex/duplex/reverse
1:
	call redraw
	ld a, (key_time)
	cp #1
	jr nc, 1f
	call is_key_down
	jr nz, 1b
	jp step_duplex_state     ; quick press, simplex/duplex/reverse
1:
	call feedback_shift_neg
1:
	call redraw
	ld a, (key_time)
	cp #2
	jr nc, 1f
	call is_key_down
	jr nz, 1b
	jp set_duplex_shift_neg ; longer press, temp. duplex shift override
1:
	call feedback_shift_pos
1:
	call redraw
	ld a, (key_time)
	cp #3
	jr nc, 1f
	call is_key_down
	jr nz, 1b
	jp set_duplex_shift_pos ; longer press, temp. duplex shift override
1:
	call feedback_split
	call waitkey
	jp set_tx_freq     ; even longer press, temp. tx freq override


beep_or_fsk_send:
	ld a, (digidx)
	or a
	jp nz, far_send_call_packet

	jp beep1750               ; No digits, repeater beep

;----------------------------------------------------------------------

scanner_key:
1:
	call redraw
	ld a, (key_time)
	cp #1
	jr nc, 1f
	call is_key_down
	jr nz, 1b
	jp scanner_start
1:
	call feedback_reject
1:
	call redraw
	ld a, (key_time)
	cp #2
	jr nc, 1f
	call is_key_down
	jr nz, 1b
	jp add_reject
1:
	call feedback_cleared
	call waitkey
	jp clear_rejects

;----------------------------------------------------------------------

def_vola:
	call clear_buffer

	call feedback_default
	call waitkey

	ld a, (cfg_def_volume)
	jp set_vola_a

def_memo:
	call clear_buffer
	call scanner_stop

	call feedback_default
	call waitkey

	ld a, (cfg_def_memory)
	jp go_mem_a

def_freq:
	call clear_buffer
	call scanner_stop

	call feedback_default
	call waitkey

	call leave_memories
	load_ahl(cfg_def_frequency)
	save_ahl(rx_freq)
	jp changed_frequency

	; tx_freq - rx_freq into ahl and CY and Z

compare_tx_rx_freq:
	load_ahl(tx_freq)
	sub_ahl_de(rx_freq)     ; tx - rx
	ret c                   ; CY set, Z clear
	ld e, a                 ; result in ahl
	or l
	or h
	ld a, e
	ret                     ; CY clear, Z valid

;======================================================================
;
;  Push current memory/frequency
;  into vip_list, forgetting oldest record.
;  Duplicates raise into head of list.
;
remember_vip:

	ld ix, #vip_list
	ld b, #VIP_COUNT

	load_ahl(rx_freq)
	save_ahl(vip_freq)
	ex de, hl
	ld c, a
	ld a, (mem_flags)
	and #MEM_VALID
	jr z, 1f  ; on "vfo"
	ld a, (mem_idx)
	ld e, a   ; on memories
	ld d, #0
	ld c, #0
1:
	; Push CDE to vips
2:
	ld l, (ix+0)      ; next in list
	ld h, (ix+1)
	ld a, (ix+2)
	ld (ix+0), e      ; replaced by new
	ld (ix+1), d
	ld (ix+2), c
	ld e, l           ; flip for next round
	ld d, h
	ld c, a
	ld a, (vip_list+0)
	cp e
	jr nz, 1f
	ld a, (vip_list+1)
	cp d
	jr nz, 1f
	ld a, (vip_list+2)
	cp c
	jr nz, 1f
	ret               ; overwrote duplicate, leave rest.
1:
	inc ix
	inc ix
	inc ix
	djnz 2b
	ret

back_to_last_vip:
	xor a
	ld (vip_idx), a

	; FALL THRU

next_vip:

	ld a, (vip_idx)
	ld c, a
	inc a
	cp #VIP_COUNT
	jr c, 1f
	xor a
1:
	ld (vip_idx), a

	ld hl, #vip_list
	ld b, #0
	add hl, bc
	add hl, bc
	add hl, bc

	push hl
	pop ix

	load_ahl_ix_0
	or h
	jr nz, 1f     ; larger than 255, must be frequency
	ld a, l
	jp go_mem_a   ; a memory else
1:
	load_ahl_ix_0
	save_ahl(rx_freq)
	call leave_memories
	jp changed_frequency

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

#ifndef C_MODULES	/* c/scan.c: rejects, scan masks, slices, the scan */
is_freq_rejected_temp:
	ld c, a        ; CHL has freq

	ld ix, #tmp_rejects
	call load_num_tmp_rejects
	ld b, a

2:
	ld a, (ix + 3)
	or a
	jr z, 3f         ; timer has counted reject into stale condition ?

	ld a, l
	cp (ix + 0)
	jr nz, 1f
	ld a, h
	cp (ix + 1)
	jr nz, 1f
	ld a, c
	cp (ix + 2)
	jr nz, 1f
	ret            ; Z - rejected
3:
	or #1           ; make NZ in case last one (jump c was wrongly Z)
1:
	inc ix         ; flags not harmed
	inc ix
	inc ix
	ASSERT_EQ(SIZE_FREQ, 3)
	inc ix
	djnz 2b        ; flags not harmed
	ret            ; NZ - not rejected


is_freq_rejected_perm:
	ld c, a        ; CHL has freq

	ld ix, #cfg_reject_0  ; 10 permanent in first group
	call check_ten_rejects
	ret z
	ld ix, #cfg_reject_10 ; 10 permanent in second group
	jr check_ten_rejects


check_ten_rejects:
	ld b, #10
2:
	ld a, l
	cp (ix + 0)
	jr nz, 1f
	ld a, h
	cp (ix + 1)
	jr nz, 1f
	ld a, c
	cp (ix + 2)
	jr nz, 1f
	ret            ; Z - rejected
1:
	inc ix         ; flags not harmed
	inc ix
	inc ix
	djnz 2b        ; flags not harmed
	ret            ; NZ - not rejected

;----------------------------------------------------------------------

clear_rejects:
	ld b, #NUM_TMP_REJECTS       ; all of the array
	xor a
	ld hl, #tmp_rejects
1:
	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	ld (hl), a
	inc hl
	ASSERT_EQ(SIZE_FREQ, 3)
	ld (hl), a
	inc hl
	djnz 1b
	ret

add_reject:

	; Determine the frequency to reject -- into IY

	ld iy, #rx_freq     ; reject current rx frequency
	ld a, (scan_on)
	or a
	jr z, 1f
	ld iy, #vip_freq    ; when scanning use vip[0] instead
1:

	; This frequency already in list ? Use the same slot, if so.
	; At the same time, locate the next record to become clear.

	ld ix, #tmp_rejects
	call load_num_tmp_rejects
	ld b, a

	ld c, #255                ; special timer value -- wont crawl down
1:
	ld a, (ix+0)
	cp (iy+0)
	jr nz, 2f
	ld a, (ix+1)
	cp (iy+1)		; v3_Z: (iy+0)
	jr nz, 2f
	ld a, (ix+2)
	cp (iy+2)
	jr nz, 2f
	jr add_reject_out        ; found, fill it
2:
	ld a, (ix+3)
	cp c                     ; this_timer - prev
	jr nc, 2f                ; nc if this timer older or equal prev
	push ix
	pop hl                   ; remember it
	ld c, a                  ; found an older one
2:
	inc ix
	inc ix
	inc ix
	inc ix          ; 4 byte per tmp_reject record
	djnz 1b

	ld a, c
	cp #255
	jr z, 1f           ; z if did not find any aging slot
	push hl
	pop ix
	jr add_reject_out
1:

	; Still no slot ? Just pick the next one

	call load_num_tmp_rejects
	ld b, a
	ld a, (reject_idx)
	inc a
	cp b
	jr c, 1f
	xor a
1:
	ld (reject_idx), a
	sla a
	sla a
	ASSERT_EQ(SIZE_FREQ, 3) ; and one byte of timer:  *= 4
	ld c, a
	ld b, #0
	ld ix, #tmp_rejects
	add ix, bc

	; Add reject - slot found

add_reject_out:            ; slot at IX, freq at IY
	ld a, (iy + 0)
	ld (ix + 0), a
	ld a, (iy + 1)
	ld (ix + 1), a
	ld a, (iy + 2)
	ld (ix + 2), a     ; freq stored

	ld a, (cfg_unreject_mins)
	or a
	jr nz, 1f
	ld a, #255          ; XXX 0 behaves as 255
1:
	ld (ix + 3), a     ; timer stored

	ld hl, #scan_do_step
	ld (scanner_state), hl

	ret

;----------------------------------------------------------------------
;
;  Called from mainloop, enters scanner in [scanner_state]
;  scanner_ret updates [scanner_state] for next call.

scanner_run:
	ld a, (scan_on)
	or a
	ret z
	ld hl, (scanner_state)
	push hl
	ret
scanner_ret:
	pop hl
	ld (scanner_state), hl
	ret

scanner_start:
	call unforce_squelch
	call draw_scanner_icon

	ld hl, #scan_do_step
	ld (scanner_state), hl

	call build_scan_mask
	ld a, h
	or l
	jr nz, 1f
	ld hl, #0x0003          ; if not given and no previous
1:
	ld (scan_mask), hl
	call clear_buffer
	call build_scan_slicetab ; selected band to sorted (collapsed ?) slices
	ld a, #1
	ld (scan_on), a
	ret

build_scan_mask:
	ld hl, (scan_mask)      ; previous scan mask
	ld ix, #digbuf
	ld a, (digidx)
	or a
	ret z                   ; lone STO, use previous
	ld b, a
	ld hl, #0                ; collect new mask
1:
	ld a, (ix+0)
	inc ix
	call digit_to_scan_mask ; map digit to mask bit
	ld a, h
	or d
	ld h, a
	ld a, l
	or e
	ld l, a      ; hl |= de
	djnz 1b
	ret

toggle_scan_mask:
	call 1f

	ld hl, (scan_mask)
	ld a, l
	xor e
	ld l, a
	ld a, h
	xor d
	ld h, a
	ld (scan_mask), hl

	ld hl, #scan_do_step
	ld (scanner_state), hl

	ret
1:
	ld de, #0x0040
	cp #0
	ret z      ; 0 0040 memblocks 0x

	sla e
	cp #1       ; 1 0080 memblocks 1x
	ret z

	ld de, #0x0100
	cp #2       ; 2 0100 2x
	ret z

	sla d
	cp #3       ; 3 0200 3x
	ret z

	sla d
	cp #4       ; 4 0400 4x
	ret z

	sla d
	cp #5       ; 5 0800 5x
	ret z

	sla d
	cp #6       ; 6 1000 6x
	ret z

	sla d
	cp #7       ; 7 2000 7x
	ret z

	sla d
	cp #8       ; 8 4000 8x
	ret z

	sla d
	cp #9       ; 9 8000 9x
	ret z

	ld de, #0
	ret

;----------------------------------------------------------------------

digit_to_scan_mask:
	ld de, #0x0001
	cp #1
	ret z      ; 1 0001 band 1

	sla e
	cp #2
	ret z      ; 2 0002 band 2

	sla e
	cp #3
	ret z      ; 3 0004 band 3

	sla e
	cp #4
	ret z      ; 4 0008 band 4

	sla e
	cp #5
	ret z      ; 5 0010 band 5

	sla e
	cp #6
	ret z      ; 6 0020 band 6

	ld de, #0x2000
	cp #7
	ret z      ; 7 2000 memblock 7x

	sla d
	cp #8
	ret z      ; 8 4000 memblock 8x

	sla d
	cp #9
	ret z      ; 9 8000 memblock 9x

	ld de, #0x1FC0
	cp #0
	ret z      ; 0 1FC0 memblocks 0x...6x XXX

	ret

scan_this_memblock:        ; a has mem idx, return NZ if yes

	ld hl, (scan_mask)
	cp #90
	jr c, 1f
	bit 7, h      ; 9x, bit 15
	ret
1:
	cp #80
	jr c, 1f
	bit 6, h      ; 8x, bit 14
	ret
1:
	cp #70
	jr c, 1f
	bit 5, h      ; 7x, bit 13
	ret
1:
	cp #60
	jr c, 1f
	bit 4, h      ; 6x, bit 12
	ret
1:
	cp #50
	jr c, 1f
	bit 3, h      ; 5x, bit 11
	ret
1:
	cp #40
	jr c, 1f
	bit 2, h      ; 4x, bit 10
	ret
1:
	cp #30
	jr c, 1f
	bit 1, h      ; 3x, bit 9
	ret
1:
	cp #20
	jr c, 1f
	bit 0, h      ; 2x, bit 8
	ret
1:
	cp #10
	jr c, 1f
	bit 7, l      ; 1x, bit 7
	ret
1:
	bit 6, l      ; 0x, bit 6
	ret

;----------------------------------------------------------------------

;
;  Pick scanned bands and sort by start freq into scan_slices.
;  List might have overlaps or touching edges.
;
build_scan_slicetab:

	; copy scanned bands into runtime list from config -------------------

	ld iy, #cfg_band1_start  ; from config
	ld ix, #scan_slices      ; to scratch
	ld h, #0                 ; # of taken bands
	ld l, #1                 ; mask to check if band scanned
	ld b, #num_bandrecs
3:
	ld a, (scan_mask)
	and l
	jr z, 2f                ; this band not scanned
	ld e, (iy+0)
	ld d, (iy+1)
	ld c, (iy+2)   ; bandX_start
	ld a, c
	or d
	or e
	jr z, 2f       ; empty band, starts with 0
	ld (ix+0), e
	ld (ix+1), d
	ld (ix+2), c
	ld e, (iy+3)
	ld d, (iy+4)
	ld c, (iy+5)   ; bandX_end
	ld (ix+3), e
	ld (ix+4), d
	ld (ix+5), c
	ld de, #SIZE_FREQ * 2
	add ix, de
	inc h
2:
	ld de, #size_bandrec    ; next band config
	add iy, de
	sla l                  ; shift mask for next band
	djnz 3b

	; sort scanlist -------------------------------

	ld a, h
	ld (scan_slicecnt), a  ; # of bands [count, 0]
	cp #2
	ret c                  ; one band or no bands at all

	dec a
	ld b, a                ; [count - 1, 1]
3:
	push bc
	ld ix, #scan_slices     ; b bubbles from the list beginning
1:
	ld e, (ix+0)
	ld d, (ix+1)
	ld c, (ix+2)           ; cde list[i] start
	ld l, (ix+6)
	ld h, (ix+7)
	ld a, (ix+8)           ; ahl list[i+1] start
	and a
	sbc hl, de
	sbc a, c
	jr nc, 2f              ; skip if correct ascending order

	; XXX also by end ?

	ld a, (ix+0)
	ld c, (ix+6)
	ld (ix+6), a
	ld (ix+0), c  ; swap [0] [6]
	ld a, (ix+1)
	ld c, (ix+7)
	ld (ix+7), a
	ld (ix+1), c
	ld a, (ix+2)
	ld c, (ix+8)
	ld (ix+8), a
	ld (ix+2), c
	ld a, (ix+3)
	ld c, (ix+9)
	ld (ix+9), a
	ld (ix+3), c
	ld a, (ix+4)
	ld c, (ix+10)
	ld (ix+10), a
	ld (ix+4), c
	ld a, (ix+5)
	ld c, (ix+11)
	ld (ix+11), a
	ld (ix+5), c  ; swap [5] [11]
2:
	ld de, #2 * SIZE_FREQ
	add ix, de
	djnz 1b                ; bubble rises
	pop bc
	djnz 3b                ; one bubble less

	ret

;----------------------------------------------------------------------

scanner_stop:
	ld a, (scan_on)
	or a
	ret z

	xor a
	ld (scan_on), a
	ld (vip_idx), a         ; re-enter most current in next_vip

	call restore_squelch_scanner
	call clear_scanner_icon
	call next_vip
	ret


scan_bad:
	call scanner_stop
	call scanner_ret
	; not reached after scanner_stop


scan_do_step_again:

	call scanner_ret ; ready to step again next check

scan_do_step:

	xor a
	ld (scan_paused), a

	call redraw
	call mute_squelch_scanner

	ld a, (mem_flags)
	or a
	jp nz, scan_next_memory

	jr scan_next_frequency

scan_do_step_maybe_reject:

	ld a, (band_autoreject)
	or a
	call nz, add_reject

	jr scan_do_step

;----------------------------------------------------------------------

scan_first_frequency:

	call scanner_ret          ; if scanner gets stuck without any channels
	                          ; allow kbd to abort
	call leave_memories
	ld a, (scan_slicecnt)
	or a
	jp z, scan_first_memory   ; no slices at all

	load_ahl(scan_slices)
	save_ahl(rx_freq)
	call changed_frequency
	jp scan_did_step_freq     ; rewind and go

scan_next_frequency:

	ld a, (scan_slicecnt)
	or a
	jp z, scan_first_memory   ; no slices to scan
	ld b, a                   ; nleft
	ld ix, #scan_slices        ; lp

	; locate slice we are in now
1:
	load_ahl(rx_freq)
	load_cde_ix_3             ; lp->end
	and a
	sbc hl, de
	sbc a, c
	jr c, 1f                  ; jump if rx_freq < lp->end
	ld de, #2 * SIZE_FREQ
	add ix, de
	djnz 1b
	jr scan_first_memory      ; passed over all slices
1:
	; orient in this slice

	load_ahl(rx_freq)
	load_cde_ix_0             ; lp->start
	and a
	sbc hl, de
	sbc a, c
	jr nc, 1f                 ; skip if rx_freq >= lp->start
	ld a, c
	ld (rx_freq+0), de        ; else skip over to this slice
	ld (rx_freq+2), a
	call changed_frequency
	jp scan_did_step_freq
1:
	push bc
	push ix
	call step_channel_up      ; in band, step one channel, rx loaded
	pop ix
	pop bc                    ; restore nleft and lp
	load_ahl(rx_freq)
	load_cde_ix_3             ; lp->end
	and a
	sbc hl, de
	sbc a, c
	jr c, scan_did_step_freq ; stayed in band, scan this freq

	; passed the slice, another there to skip over to ?

	ld a, b
	dec a
	jr z, scan_first_memory  ; nope. nleft now 0

	ld de, #2 * SIZE_FREQ
	add ix, de                ; ++lp
	load_ahl_ix_0             ; lp->start
	save_ahl(rx_freq)
	call changed_frequency
	jr scan_did_step_freq

;----------------------------------------------------------------------

scan_first_memory:

	call scanner_ret          ; if scanner gets stuck without any channels
	                          ; allow kbd to abort

	ld a, (scan_mask+1)   ; bits 0xFFC0 are memory blocks
	and #0xFF
	jr nz, 1f
	ld a, (scan_mask+0)
	and #0xC0
	jp z, scan_first_frequency ; no memoryblocks scanned
1:
	xor a                ; start from mem 00
	ld ix, #memories
	jr 1f                  ; try 00

scan_next_memory:

	ld a, (mem_idx)
	call point_ix_memory_a
	jr 2f                  ; step first, then try
1:
	cp #100
	jp nc, scan_first_frequency  ; if passing mem 99, run bands then
	call scan_this_memblock
	jr z, 2f                     ; block not in mask
	ld e, a
	ld a, (ix + mem_FLAGS)
	and #MEM_VALID | MEM_SCANNABLE
	cp  #MEM_VALID | MEM_SCANNABLE
	ld a, e
	jr nz, 2f                    ; empty or scanblocked
	call go_mem_a			     ; Ah.
	jr scan_did_step
2:
	ld de, #mem_SIZE
	add ix, de
	inc a
	jr 1b

;----------------------------------------------------------------------

; like squelch_open 1/0, but disregards hysteresis and squelch slowness

is_sql_over_level:
	call read_squelcher_value
	ld b, a
	ld a, (cfg_squelch_level)
	cp b                     ; limit - value, CY if value > limit
	ret

scan_did_step_freq:

	load_ahl(rx_freq)
	call is_freq_rejected_perm
	jp z, scan_do_step_again

scan_did_step:

	load_ahl(rx_freq)
	call is_freq_rejected_temp
	jp z, scan_do_step_again

	; step wait --------------

	ld a, (squelch_open)
	or a
	ld a, (scan_settling_time)	; Wait time
	jr z, 1f
	add a, a					; Make it double long if channel is busy.
	jr nc, 1f
	ld a, #255
1:
	di
	ld (scan_timer), a
	xor a
	ld (scan_timer_secs), a
	ei                          ; 'rate' times 10 msec
1:
	call scanner_ret

	ld a, (scan_timer)
	or a
	jr nz, 1b				; The wait.

	; after step wait, look around --------------

	ld a, (squelch_forced)
	or a
	jr nz, 2f				; Squelch manually forced open, act as if signal.

	call is_sql_over_level
	jp nc, scan_do_step		; No signal. Next.

	ld a, #1
	ld (scan_paused), a     ; allow normal display
2:
	call redraw
	call get_scan_patience
	cp #255
	jr z, 4f
		ld (scan_patience), a	; Stay N seconds with or without signal.
	4:

	ld a, (cfg_scan_skip_fsk_channels) ; XXX
	or a
	jr z, 1f

	in a, (MDM + MDMCTRL)
	and #MDM_DCD
	jp nz, scan_do_step
1:
	call scanner_ret

	call get_scan_patience
	cp #255                       ; 255 means listen forever
	jr z, 4f
		ld a, (scan_patience)
		or a
		jp z, scan_do_step_maybe_reject		; Lost patience. Next.
	4:

	call restore_squelch_scanner    ; Open audio.

	ld a, (squelch_forced)
	or a
	jr nz, 2b				; Squelch forced open. Stay forever and 15 sec more.
	ld a, (squelch_open)
	or a
	jr z, 3f				; No signal. Go wait for a while.
	call remember_vip
	jr 1b					; There is signal. Stay.
3:
	call get_scan_tail		; Stay N seconds without signal.
	cp #255
	jr z, 5f                 ; 255 means listen forever
		di
		ld (scan_timer_secs), a
		or a
		jr z, 4f                    ; no ticks if 0 seconds
			ld a, #100
		4:
		ld (scan_timer), a           ; 'secs' times 1 second (100 ticks)
		ei
	5:
2:
	call scanner_ret

	ld a, (squelch_open)
	or a
	jr nz, 1b				; Again signal. Keep listening.

	ld a, (scan_timer_secs)
	or a
	jr nz, 2b				; No signal for N seconds...

	jp scan_do_step			; ... so Next.

#endif /* C_MODULES */

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

; FSK packet dispatch, remote config and MPRS sending lives in bank 1
; (search "BANK 1"), with C_MODULES in c/fsk.c, bank 2.
#ifdef C_MODULES
far_packet_for_whom:	call bank2_call
	.dw _packet_for_whom
far_send_remote_config_packets:	call bank2_call
	.dw _send_remote_config_packets
far_send_mprs_report_packet_maybe:	call bank2_call
	.dw _send_mprs_report_packet_maybe
far_send_mprs_report_packet:	call bank2_call
	.dw _send_mprs_report_packet
far_send_mprs_report_packet_1:	call bank2_call
	.dw _send_mprs_report_packet_1
far_send_call_packet:	call bank2_call
	.dw _send_call_packet

;  c/fsk.c shims: register interfaces as --sdcccall 1 passes them
fsk_putchar:			; A: MBUS putchar takes C
	ld c, a
	jp putchar
fsk_send:			; A: send_packet_buffer takes the length in B
	ld b, a
	jp send_packet_buffer
fsk_tx_on_failed:		; A = 0xFF if tx_on returned carry
	call tx_on
	sbc a, a
	ret
fsk_mprs_not_yet:		; A = 0xFF if check_for_mprs_timer says not yet
	call check_for_mprs_timer
	sbc a, a
	ret
fsk_menu_ptr:			; DE = value pointer of the current menu record
	call bank1_call
	.dw _menu_value_ptr
fsk_remote_config_execute:	; HL = ptr, DE = data, as c/menu.c takes them
	call bank1_call
	.dw _remote_config_execute
#else
far_packet_for_whom:	call bank1_call
	.dw packet_for_whom
far_send_remote_config_packets:	call bank1_call
	.dw send_remote_config_packets
far_send_mprs_report_packet_maybe:	call bank1_call
	.dw send_mprs_report_packet_maybe
far_send_mprs_report_packet:	call bank1_call
	.dw send_mprs_report_packet
far_send_mprs_report_packet_1:	call bank1_call
	.dw send_mprs_report_packet_1
#endif

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


; MPRS/APRS/MIC-E packets and locator maths lives in bank 1 (search "BANK 1"),
; with C_MODULES in c/aprs.c, bank 2 (called there by c/fsk.c and c/gps.c).
#ifdef C_MODULES
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
#else
far_handle_mprs_packets:	call bank1_call
	.dw handle_mprs_packets
far_send_aprs_report_packet:	call bank1_call
	.dw send_aprs_report_packet
#endif

; Config packet filling and the call packet lives in bank 1 (search "BANK 1").
#ifndef C_MODULES
far_send_call_packet:	call bank1_call
	.dw send_call_packet
#endif

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

#ifndef C_MODULES
append_short_packet_crc:

	ld ix, #outpacket
	INIT_CRC

	ADD_CRC(0)
	ADD_CRC(1)
	ADD_CRC(2)
	ADD_CRC(3)
	ADD_CRC(4)
	ADD_CRC(5)

	cpl
	ld (ix + 7), a
	ld a, b
	cpl
	ld (ix + 6), a

	ret

append_secret_packet_crc:

	INIT_CRC

	ld ix, #cfg_remote_passwd

	ADD_CRC(0)
	ADD_CRC(1)
	ADD_CRC(2)
	ADD_CRC(3)
	ADD_CRC(4)
	ADD_CRC(5)
	ADD_CRC(6)
	ADD_CRC(7)
	jr 1f

	; JMPOVER

append_long_packet_crc:

	INIT_CRC
1:
	ld ix, #outpacket

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
	ld (ix + 14), a
	ld a, b
	cpl
	ld (ix + 13), a

	ret

#endif /* C_MODULES */

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

save_memory:
	ld a, (digidx)
	or a
	jr nz, 1f
	ld a, (mem_idx)
	jr 2f
1:
	call a2i_byte
2:
	cp #130
	jr c, 1f
	ld a, #99
1:

	ld (mem_idx), a

	ld a, #MEM_VALID | MEM_SCANNABLE
	ld (mem_flags), a
	call redraw
7:
	ld a, (mem_flags)
	ld b, a
	ld a, (key_time)
	cp #2
	jr c, 1f
	ld b, #MEM_VALID       ; 2-long
1:
	ld a, (key_time)
	cp #3
	jr c, 1f
	ld b, #MEM_VALID | MEM_HIDDEN  ; 3-long
1:
	ld a, (mem_flags)
	cp b
	jr z, 1f
	ld a, b
	ld (mem_flags), a
	call redraw
1:
	call is_key_down
	jr nz, 7b            ; keep waiting

	call point_ix_memory

	load_ahl(rx_freq)
	save_ahl_ix_0
	load_ahl(tx_freq)
	save_ahl_ix_3

	ld a, (mem_flags)
	ld (ix + 6), a                    ; scan/valid flags are saved

	; ld a, [cfg_ctcss_hz]
	; ld [ix + mem_CTCSS], a          ! ctcss is NOT saved here

	ld a, (band_step)
	ld (ix + mem_BAND), a             ; band step is saved, but it is not used when recalled

	ld (ix + mem_FOO2), #0
	ld (ix + mem_FOO3), #0             ; clear these

	call save_nvdata
	ret

; up down memories from "vfo", just go back to last memory

maybe_just_reenter_last:
	call clear_buffer
	call scanner_stop
	ld a, (mem_flags)
	cp #0
	ret nz                   ; NZ, already on memories
	call get_mem_flags
	and #MEM_VALID | MEM_HIDDEN
	cp  #MEM_VALID            ; Z if okay this
	ld a, (mem_idx)          ; ... last memory
	ret                      ; and Z condition

up_memo:
	call maybe_just_reenter_last
	jp z, go_mem_a
	ld e, #132
2:
	dec e
	jr z, 8f
	ld a, (mem_idx)
	inc a
	cp #130
	jr c, 1f
	xor a
1:
	ld (mem_idx), a
	call get_mem_flags
	and #MEM_VALID | MEM_HIDDEN
	cp  #MEM_VALID
	jr nz, 2b

	ld a, (mem_idx)
	jr go_mem_a
8:
	xor a
	ld (mem_flags), a
	ret

dn_memo:
	call maybe_just_reenter_last
	jr z, go_mem_a
	ld e, #132
2:
	dec e
	jr z, 8f
	ld a, (mem_idx)
	dec a
	cp #130
	jr c, 1f
	ld a, #129
1:
	ld (mem_idx), a
	call get_mem_flags
	and #MEM_VALID | MEM_HIDDEN
	cp  #MEM_VALID
	jr nz, 2b

	ld a, (mem_idx)
	jr go_mem_a
8:
	xor a
	ld (mem_flags), a
	ret

go_mem:
	call a2i_byte
	call go_mem_a
	call remember_vip
	ret

save_memory_ctcss:
	call point_ix_memory

	ld a, (mem_ctcss_tx_hz)
	ld (ix + mem_CTCSSt), a

	ld a, (mem_ctcss_rx_hz)
	ld (ix + mem_CTCSSr), a
	ret

;======================================================================

point_ix_memory:
	ld a, (mem_idx)
point_ix_memory_a:
	cp #130
	jr c, 1f
	ld a, #99
1:
	ld h, #0
	ld l, a
	add hl, hl      ; *= 2
	add hl, hl      ; *= 4
	push hl
	pop bc
	add hl, hl      ; *= 8
	add hl, bc
	ld bc, #memories
	add hl, bc
	push hl
	pop ix
	ret

go_mem_a:
	cp #130
	jr c, 1f
	ld a, #99
1:
	ld (mem_idx), a
	call point_ix_memory_a

	load_ahl_ix_0
	save_ahl(rx_freq)
	load_ahl_ix_3
	save_ahl(tx_freq)

	push ix
	call locate_band                  ; preset band_xxx variables, override below
	pop ix

	ld a, (ix + mem_FLAGS)
	or #MEM_VALID                      ; make it valid, even if the real record is cleared
	ld (mem_flags), a

	ld a, (ix + mem_CTCSSt)
	ld (mem_ctcss_tx_hz), a              ; load ctcss of memory

	ld a, (ix + mem_CTCSSr)
	ld (mem_ctcss_rx_hz), a              ; this is not (yet) used

	call set_duplex_from_tx_rx
	call set_channel_step
	jp changed_frequency_duplex_okay     ; overridden duplex rx/tx data.

get_mem_flags:
	call point_ix_memory
	ld a, (ix + mem_FLAGS)
	ret

leave_memories:
	xor a
	ld (mem_flags), a
	ret

;----------------------------------------------------------------------

pttcheck:
	call is_ptt_pressed
	ret z                  ; PTT is not pressed

	call open_selective

	ld a, #1
	ld (repeater_ptt_seen), a

	ld a, (cfg_function)
	dec a                  ; if 1
	ret z                  ; Repeater mode, ignore PTT here.

	; PTT is down, normal or slave mode.

	call cu_manipulated

	; Try to start TX, bail out if illegal

	call tx_on
	jr c, tx_error

	; Hum on, if necessary

	call ctcss_maybe

	; Pending digits in basic display

	ld a, (menu_active)     ; in menu ?
	or a
	jr nz, 1f
	ld a, (digidx)			; no, CCIR if digits, then /PTT down
	or a
	call nz, ptt_ccir_xmit
1:
	call mic_on

	call tx_tune_tone_maybe

	; Then watch PTT

	call battcheck
	call redraw
	ld a, (ad_batt)
	ld e, a
1:
	ld a, (ad_batt)
	sub e
	jr z, 2f
	cp #1
	jr z, 2f
	cp #-1
	jr z, 2f
	call battcheck
	call redraw
	ld a, (ad_batt)
	ld e, a
2:
	push de
	ld a, (menu_active)
	or a
	call nz, redraw          ; keep redrawing if in menu - status displays

	ld a, (key)			; keys pressed after /PTT ?
	cp #-1
	call nz, handle_key_during_tx

	call is_key_down
	call z, stop_dtmf_tone
	pop de

	call is_ptt_pressed
	jr nz, 1b

	; Trailing end of PTT, query/command if in menu

	call ctcss_off 		; Disabling CTCSS When sending other stuff eg. aprs without ctcss tone - OH1E

	call change_to_signalling_deviation

	ld a, (menu_active)
	or a
	call nz, far_send_remote_config_packets

	; ! Voice ID ?
	;
	; ld a, [cfg_voice_id]
	; or a
	; call nz, bang_voice_id

	; MPRS report at PTT release ?

	call far_send_mprs_report_packet_maybe

	; EOT

	call tx_off
	call stop_dtmf_tone
	call redraw

	call remember_vip

	call far_repeater_operator_ptt
	ret

tx_error:
	ld hl, #MT_300HZ
	ld d, #100
	call start_marker_tone
1:
	call waitkey
	call is_ptt_pressed
	jr nz, 1b

	ret

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

spontaneous_mprs_check:

	ld a, (txon)
	or a
	ret nz                    ; tx is on, wait

	ld a, (cfg_idlefn_delay)
	ld b, a
	ld a, (idle_timer)
	cp b
	ret c                     ; abort if not idle enough

	call check_for_mprs_timer
	ret c                     ; not yet

        ld a, (squelch_open)
        or a
        ret nz                    ; Be sure THERE IS NO traffic/squelch open, wait... - OH1E

	ld ix, #cfg_aprs_tx_freq
	ld a, (ix + 0)
	or (ix + 1)
	or (ix + 2)
	ret z                  ; Not configured

	; Committed to blurt the mprs packet

	load_ahl(tx_freq)           ; save frequency data
	push af
	push hl
	load_ahl(tx_divisor)
	push af
	push hl
	ld hl, (tx_refdiv)
	push hl
	ld hl, (tx_bstep_cfg)
	push hl

	load_ahl(cfg_aprs_tx_freq)       ; load temp freq
	save_ahl(tx_freq)

	call update_tx_vco_band

	call 1f                            ; xmit

	pop hl
	ld (tx_bstep_cfg), hl
	pop hl
	ld (tx_refdiv), hl
	pop hl
	pop af
	save_ahl(tx_divisor)
	pop hl
	pop af
	save_ahl(tx_freq)

	call update_tx_vco_band
	ret

1:
	call locate_tx_band           ; into [ix]
	ld a, (ix+9)                  ; logical channel step designator into A
	call channel_step_parms
	ld (tx_refdiv), hl
	ld (tx_bstep_cfg), bc

	call determine_tx_div_split
	call close_squelch

	call tx_on_legal_or_not      ; error ignored
	call redraw

	call far_send_mprs_report_packet

	call tx_off
	call redraw
	ret

;--- yuck, repetititition ---------------------------------------------

aprs_ptt_check:
	ld a, (cfg_aprs_tx)
	or a
	ret z                  ; Not configured

	ld a, (sio_bctrl_mirror)
	and #SB_LOCAL
	ret z                      ; /LOCAL not pulled, bit inverted

	ld a, (cfg_idlefn_delay)
	ld b, a
	ld a, (idle_timer)
	cp b
	ret c                     ; abort if not idle enough

	ld ix, #cfg_aprs_tx_freq
	ld a, (ix + 0)
	or (ix + 1)
	or (ix + 2)
	ret z                  ; Not configured

	; Committed to blurt the aprs packet

	load_ahl(tx_freq)           ; save frequency data
	push af
	push hl
	load_ahl(tx_divisor)
	push af
	push hl
	ld hl, (tx_refdiv)
	push hl
	ld hl, (tx_bstep_cfg)
	push hl

	load_ahl(cfg_aprs_tx_freq)       ; load temp freq
	save_ahl(tx_freq)

	call update_tx_vco_band

	call 1f                            ; xmit

	pop hl
	ld (tx_bstep_cfg), hl
	pop hl
	ld (tx_refdiv), hl
	pop hl
	pop af
	save_ahl(tx_divisor)
	pop hl
	pop af
	save_ahl(tx_freq)

	call update_tx_vco_band
	ret

1:
	call locate_tx_band           ; into [ix]
	ld a, (ix+9)                  ; logical channel step designator into A
	call channel_step_parms
	ld (tx_refdiv), hl
	ld (tx_bstep_cfg), bc

	call determine_tx_div_split
	call close_squelch

	call tx_on_legal_or_not      ; error ignored
	call redraw
	call mic_on                      ; MIC is on.
1:
	ld a, (sio_bctrl_mirror)
	and #SB_LOCAL
	jr nz, 1b                    ; Then watch /LOCAL here, bit inverted

	call tx_off
	call redraw
	ret

;----------------------------------------------------------------------

beep1750:

	call tx_on
	jp c, tx_error

	call battcheck

	call mic_off_ccir_off

	call change_to_signalling_deviation

	di
	xor a
	ld (mt_timer), a
	ld a, #LO(MT_1750HZ)
	out (TMR + 1), a
	ld a, #HI(MT_1750HZ)
	out (TMR + 1), a
	ei

	call ccir_on
	call waitkey

	call ccir_off
	call tx_off
	ret

tx_tune_tone_maybe:

	ld a, (menu_active)
	or a
	ret z                       ; not in menu

	ld de, (menu_ptr)
	ld a, d
	cp #HI(tune_tone_position)
	ret nz
	ld a, e
	cp #LO(tune_tone_position)
	ret nz                      ; not in "t tune" display

	ld de, (cfg_txtune_hz)
	ld a, d
	or e
	ret z                  ; 0 Hz = no tx tuning help tone

	imm_ahl(4032000)
	ld bc, #-1              ; XXX erm, -2 in fact ?
	and a
1:
	inc bc
	sbc hl, de
	sbc a, #0
	jr nc, 1b              ; 4032000 / HZ = CNT, into bc

	di
	xor a
	ld (mt_timer), a
	ld a, c
	out (TMR + 1), a
	ld a, b
	out (TMR + 1), a
	ei

	call mic_off
	call ccir_on
	ret

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

b0_ccir_tx_timer_wait:	call bank0_call
	.dw ccir_tx_timer_wait

b0_cw_wait_tone:	call bank0_call
	.dw cw_wait_tone

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
	call div248

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

draw_ctcss_and_mute_and_gps_ind:

	ld a, (cu_is_alfa)
	or a
	ret nz          ; sorry, no ctcss indicator on AF

	; CTCSS indicators ---------

	call get_ctcss_tx_hz
	or a
	jr z, 1f                    ; is the var zero ?
	segset_hl(CU53AN_SEG_MAST)
	jr 2f
1:
	segres_hl(CU53AN_SEG_MAST)
2:
	call get_ctcss_rx_hz
	or a
	jr z, 1f                    ; is the var zero ?
	segset_hl(CU53AN_SEG_PHONE_NO)
	jr 2f
1:
	segres_hl(CU53AN_SEG_PHONE_NO)
2:
	; SELECTIVE mute indicator -------------

	ld a, (squelch_muted)
	and #2                         ; bit1 is selmute
	jr z, 1f
	segset_hl(CU53AN_SEG_KEY)
	jr 2f
1:
	segres_hl(CU53AN_SEG_KEY)
2:
	; GPS "in fix" indicator ---------

	ld a, (gps_valid_seconds)
	or a
	jr z, 1f                    ; "still valid" ?
	segset_hl(CU53AN_SEG_BOOK)
	jr 2f
1:
	segres_hl(CU53AN_SEG_BOOK)
2:
	ret


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

draw_squelch_ind:
	ld a, (cu_is_alfa)
	or a
	jr nz, 1f
	ld a, (squelch_forced)
	or a
	jr nz, 2f
	segres_hl(CU53AN_SEG_STAR)
	ret
2:
	segset_hl(CU53AN_SEG_STAR)
	ret
1:
	ld a, (squelch_forced)
	or a
	ld a, #' '
	jr z, 2f
	ld a, #'*'
2:
	call dpydig
	ret

draw_dpx_ind:

	ld a, (cu_is_alfa)
	or a
	ld a, (dpx_ind_flags)
	jr nz, 3f
	bit 0, a                        ;;;;;;; CU53
	jr z, 1f
	segset_hl(CU53AN_SEG_V_D)
	jr 2f
1:
	segres_hl(CU53AN_SEG_V_D)
2:
	bit 1, a
	jr z, 1f
	segset_hl(CU53AN_SEG_V_U)
	jr 2f
1:
	segres_hl(CU53AN_SEG_V_U)
2:
	ld a, (display_buffer_time)
	or a
	jr z, 1f
	segset_hl(CU53AN_SEG_PHONE)
	jr 2f
1:
	segres_hl(CU53AN_SEG_PHONE)
2:
	ret
3:                                  ;;;;;;;; ALPHA
	bit 0, a
	jr z, 1f
	segset_hl(CU58AF_SEG_ARROW0)
	jr 2f
1:
	segres_hl(CU58AF_SEG_ARROW0)
2:
	bit 1, a
	jr z, 1f
	segset_hl(CU58AF_SEG_ARROW1)
	jr 2f
1:
	segres_hl(CU58AF_SEG_ARROW1)
2:
	ret

;----------------------------------------------------------------------

#ifndef C_MODULES
draw_upper_row:

	ld de, #CU53AN_segs_u_digit_5
	ld a, (cu_is_alfa)
	or a
	jr z, 1f
	ld de, #CU58AF_segs_u_digit_7
1:

	ld a, (menu_active)
	or a
	jp nz, far_draw_menu_title

	ld a, (call_dpyed)
	or a
	jr nz, draw_call_timer

	ld a, (locator_dpyed)
	or a
	jr nz, draw_locator_in_upper_row

	call draw_upper_colons

	; txpwr volume squelch rssi

	call real_txpwr              ; txpwr 0..255 into 0..9
	call dpydiv9

	ld a, (volume)               ; volume
	call dpydig

	ld a, (cu_is_alfa)           ;  audio whereto if alfa handset
	or a
	jr z, 2f
	ld a, (audio_dst)
	cp #1
	ld l, #'>'
	jr z, 1f
	cp #2
	ld l, #'<'
	jr z, 1f
	ld l, #' '
1:
	ld a, l
	call dpydig
2:

	ld a, (cfg_squelch_level)    ; squelch setting 0..255 into 0..99
	call dpydiv99

	call draw_squelch_ind        ; icon or a star character to cursor++

	ld a, (cfg_function)
	dec a                        ; if 1 = "rPtr"
	jr z, 1f
	ld a, (txon)                 ; srssi if rx/rptr; txpwr if normal tx
	or a
	jr z, 1f
	call real_txpwr
	jp dpydiv99                  ; upper row complete
1:
	ld a, (srssi)
	jp dpydiv99                    ; upper row complete

;----------------------------------------------------------------------

toggle_upper_colons:
	jp nz, draw_upper_colons
	jp clear_upper_colons

draw_call_timer:
	ld a, (call_timer_sec)
	and #1
	call toggle_upper_colons

	ld a, (cu_is_alfa)
	or a
	jr z, 1f

	ld a, #' '
	call dpydig
	ld a, #' '
	call dpydig
1:
	ld a, (call_timer_hour)
	call dpyval99
	ld a, (call_timer_min)
	call dpyval99
	ld a, (call_timer_sec)
	call dpyval99

	ret

draw_locator_in_upper_row:

	call clear_upper_colons

	ld a, (cu_is_alfa)
	or a
	jr z, 1f

	ld a, #' '
	call dpydig
	ld a, #' '
	call dpydig
1:
	ld a, (locator_display_buffer + 0)
	call dpydig
	ld a, (locator_display_buffer + 1)
	call dpydig
	ld a, (locator_display_buffer + 2)
	call dpydig
	ld a, (locator_display_buffer + 3)
	call dpydig
	ld a, (locator_display_buffer + 4)
	call dpydig
	ld a, (locator_display_buffer + 5)
	call dpydig

	ret

;----------------------------------------------------------------------

draw_digit_buffer:
	ld ix, #digbuf
	ld a, (digidx)
	cp #10				; positions max
	jr c, 1f
	ld a, #10
1:
	ld b, a				; to show
	neg
	add a, #10
	ld c, a				; to blank
1:
	ld a, (ix)
	inc ix
	call dpydig
	djnz 1b

	ld a, c
	or a
	ret z              ; no blanks needed
	ld b, a
	ld a, #'_'
	call dpydig
	dec b
	ret z
1:
	ld a, #' '
	call dpydig
	djnz 1b

	ret

;----------------------------------------------------------------------

draw_memory_info:

	ld a, (cfg_function)
	dec a               ; if 1
	jr nz, 1f
	ld a, #'r'           ; rP_
	call dpydig
	ld a, #'P'
	call dpydig
	ld a, #' '
	jp dpydig           ; and ret
1:
	ld a, (mem_flags)
	and #MEM_VALID
	jr nz, 1f
	ld a, #' '           ; blank out memory info digits
	call dpydig
	ld a, #' '
	call dpydig
	ld a, #' '           ; and status blanked
	jp dpydig           ; and ret
1:
	;  Active memory exists

	ld a, (mem_idx)
	call dpyval99         ; memory number, 2 digits

	ld b, #'='
	ld a, (mem_flags)
	and #MEM_HIDDEN
	jr nz, 1f             ; = if hidden set
	ld b, #'-'
	ld a, (mem_flags)
	and #MEM_SCANNABLE
	jr z, 1f              ; - if scannable clear
	ld b, #' '
1:
	ld a, b
	jp dpydig				; memory status

#endif /* C_MODULES */

set_dpx_ind_from_rx_tx_freq:
	push de
	call compare_tx_rx_freq
	pop de
	ret z                 ; tx = rx
	ld a, #2
	jr nc, 1f   ; tx above
	ld a, #1     ; tx below
1:
	ld (dpx_ind_flags), a
	ret

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


#ifndef C_MODULES
draw_adjust_feedback:
	ld b, #10
	ld a, (cu_is_alfa)
	or a
	jr z, 1f
	ld b, #9        ; sorry
1:
	ld a, (hl)
	inc hl
	cp #EOS
	jr nz, 2f
		ld a, #' '
	2:
	push hl
	call dpydig
	pop hl
	djnz 1b
	ret

draw_remote_display:
	ld hl, #remote_display_buffer

	jr draw_adjust_feedback


;----------------------------------------------------------------------
draw_scan_mask:
	ld b, #10
	ld a, (cu_is_alfa)
	or a
	jr z, 1f
	ld b, #9        ; sorry
1:
	ld hl, (scan_mask)     ; 9876543210FEDCBA bitpositions
	ld c, #0xA              ; ABC DEF 0 123 456 789 whatever fits
1:
	srl h
	rr l
	jr nc, 2f
	push bc
	push hl
	ld a, c
	call dpydig
	pop hl
	pop bc
	dec b
	ret z          ; filled screen
2:
	inc c
	ld a, c
	cp #0x10
	jr nz, 2f
	ld c, #0        ; after F comes 0
2:
	ld a, h
	or l
	jr nz, 1b      ; more bits to show
1:
	ld a, #'-'
	call dpydig    ; pad rest with ----------
	djnz 1b
	ret

;----------------------------------------------------------------------

	;  Lower left, 2 digits, lower right, 8 digits

draw_lower_row:

	ld de, #CU53AN_segs_bottom_row
	ld a, (cu_is_alfa)
	or a
	jr z, 1f
	ld de, #CU58AF_segs_bottom_row      ;  Cursor at lower left
1:

	; Clear the lower colon unless the menu row is next, which lights it
	; (v3_Z cleared it first, so a frame sent mid-redraw lost it)
	ld a, (call_dpyed)
	or a
	jr nz, 1f
	ld hl, (adj_feedback)
	ld a, h
	or l
	jr nz, 1f
	ld a, (digidx)
	or a
	jr nz, 1f
	ld a, (menu_active)
	or a
	jr nz, 2f
1:
	call clear_lower_colon
2:

	ld a, (call_dpyed)
	or a
	jp nz, draw_call_notice

	ld hl, (adj_feedback)
	ld a, h
	or l
	jp nz, draw_adjust_feedback

	ld a, (digidx)                    ; digit buffer non-empty ?
	or a
	jp nz, draw_digit_buffer

	ld a, (menu_active)
	or a
	jp nz, far_draw_menu_lower_row

	ld a, (display_buffer_time)
	or a
	jp nz, draw_remote_display

	;  Cursor still at lower left, scanner running ?

	ld a, (scan_on)
	or a
	jr z, 1f                ; not scanning, std display
	ld a, (scan_paused)
	or a
	jr nz, 1f               ; scanner paused, std display
	ld a, (squelch_forced)
	or a
	jr nz, 1f               ; squelch opened, std display

	jp draw_scan_mask       ; else show mask what are being scanned
1:

	;  Cursor still at lower left, now memory number and frequency

	call draw_memory_info

	call set_dpx_ind_from_rx_tx_freq

	ld a, (cu_is_alfa)
	ld (yucko_alfa_draw_long_6_only), a

	ld a, (txon)
	or a
	jr nz, 1f
	load_ahl(rx_freq)
	jp draw_long
1:
	load_ahl(tx_freq)
	jp draw_long


draw_call_notice:

	call sput
	.asciz "CALL"

	ld a, (cu_is_alfa)
	or a
	jr nz, 1f
	call sput
	.asciz " "
1:
	ld a, (call_dpyed)
	dec a                 ; if 1
	jr z, 1f
	dec a                 ; if 2
	jr z, 2f
	call sput
	.asciz "  ???"
	ret
1:
	ld h, #HI(fsk_history)
	ld a, (packet_good)
	inc a                     ; to source address offset
	ld l, a
	ld a, (hl)
	inc l
	push hl
	call dpydig
	pop hl
	ld a, (hl)
	inc l
	push hl
	call dpydig
	pop hl
	ld a, (hl)
	inc l
	push hl
	call dpydig
	pop hl
	ld a, (hl)
	inc l
	push hl
	call dpydig
	pop hl
	ld a, (hl)
	inc l
	push hl
	call dpydig
	pop hl
	ret
2:
	call sput
	.asciz " CCIr"
	ret

#endif /* C_MODULES */

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
;  Assembler calls into bank 1:  fn_stub:  call bank1_call / .dw fn
;  (bank 2: far2_fn:  call bank2_call / .dw fn)
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

far2_bank_test_ping2:	call bank2_call
	.dw bank_test_ping2

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

#ifndef C_MODULES
changed_frequency:
	call parameters_from_band
	call changed_frequency_duplex_okay
	ret

changed_frequency_duplex_okay:
	call temporary_change_rx_freq
	call determine_tx_div
	call set_legal_tx_flag
	ret

temporary_change_rx_freq:
	call close_squelch
	call lookup_rfc            ; input: rx_freq
	call update_vco_bands      ; input: rx_freq & tx_freq
	call determine_rx_div
	call load_rxsynth
	call determine_qsy_kHz
	ret

parameters_from_band:
	call locate_band
	call set_channel_step      ; input: bandx logical step
	ret

#endif /* C_MODULES */

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

#ifndef C_MODULES
locate_band:
	ld a, #DPX_DUPLEX
	ld (duplex_state), a     ; assume duplex

	ld ix, #cfg_band1_start
	ld b, #num_bandrecs
1:
	load_ahl(rx_freq)
	ld e, (ix+0)
	ld d, (ix+1)
	ld c, (ix+2)
	and a
	sbc hl, de
	sbc a, c                    ; current - start
	jr c, 2f                 ; current < start, try next
	load_ahl(rx_freq)
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

	ld a, #DPX_SIMPLEX
	ld (duplex_state), a     ; default to simplex outside bands
3:
	ld a, b
	or a
	jr z, 1f
	ld a, #num_bandrecs + 1
	sub b                ; b is 6....1, want 1...6, 7 - 6 = 1, 7 - 1 = 6
1:
	ld (band), a

	ld l, (ix+6)             ; offset of duplex shift
	ld h, (ix+7)
	ld a, (ix+8)
	call set_band_duplex_shift

	ld a, (ix+9)             ; rest of band parameters
	ld (band_step), a
	ld a, (ix+10)
	ld (band_sctail), a
	ld a, (ix+11)
	ld (band_sclisten), a
	ld a, (ix+12)
	ld (band_autoreject), a

	ret

	; duplex shift is set in band 1..6 only if it is "repeater band"
	; "other" shift does not imply autoduplex

set_band_duplex_shift:
	save_ahl(duplex_shift)
	or h
	or l
	ret nz                   ; band has shift

	load_ahl(cfg_other_duplex)
	save_ahl(duplex_shift)
	ld a, #DPX_SIMPLEX         ; not a duplex band, prepare with "other" shift
	ld (duplex_state), a
	ret

set_duplex_from_tx_rx:
	call compare_tx_rx_freq    ; ahl has subtract value, CY and Z also
	save_ahl(duplex_shift)
	ld a, #DPX_DUPLEX
	jr nz, 1f
	load_ahl(cfg_other_duplex)
	save_ahl(duplex_shift)
	ld a, #DPX_SIMPLEX
1:
	ld (duplex_state), a
	ret

	;-------------
	; duplex state 0: tx = rx_freq
	;              1: tx = rx_freq + duplex_shift (sign included in shift)
	;              2: tx = rx_freq - duplex_shift (sign included in shift)
	;              3: tx = tx_freq

determine_tx_div:
	ld a, (duplex_state)
	cp #DPX_DUPLEX
	jr z, 1f
	cp #DPX_REVERSE
	jr z, 2f
	cp #DPX_SPLIT
	jr z, 3f
	load_ahl(rx_freq)         ; duplex 0, tx follows rx
	save_ahl(tx_freq)
	jr 3f
1:
	load_ahl(rx_freq)         ; duplex 1, tx = rx + shift (shift neg. usually)
	add_ahl_de(duplex_shift)
	save_ahl(tx_freq)
	jr 3f
2:
	load_ahl(rx_freq)         ; duplex 2, tx = rx + shift
	sub_ahl_de(duplex_shift)
	save_ahl(tx_freq)
3:
	; fallthru

#endif /* C_MODULES */

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

#ifndef C_MODULES
set_legal_tx_flag:
	load_ahl(cfg_tx_band_start)
	sub_ahl_de(tx_freq)
	jr nc, 2f                  ; start >= vfo, illegal

	load_ahl(tx_freq)
	sub_ahl_de(cfg_tx_band_end)
	jr c, 1f                   ; vfo < end, and start < vfo, legal
2:
	load_ahl(tx_freq)
	sub_ahl_de(cfg_tx_oob_0)
	or l
	or h
	jr z, 1f                   ; vfo at "oob tx spot", legal after all
	load_ahl(tx_freq)
	sub_ahl_de(cfg_tx_oob_1)
	or l
	or h
	jr z, 1f                   ; vfo at "oob tx spot", legal after all
	load_ahl(tx_freq)
	sub_ahl_de(cfg_tx_oob_2)
	or l
	or h
	jr z, 1f                   ; vfo at "oob tx spot", legal after all
	load_ahl(tx_freq)
	sub_ahl_de(cfg_tx_oob_3)
	or l
	or h
	jr z, 1f                   ; vfo at "oob tx spot", legal after all
	load_ahl(tx_freq)
	sub_ahl_de(cfg_tx_oob_4)
	or l
	or h
	jr z, 1f                   ; vfo at "oob tx spot", legal after all

	ld a, (local_mode)         ; illegal if not local_mode 
	ld (tx_is_legal), a
	ret
1:
	ld a, #1
	ld (tx_is_legal), a
	ret

	; split and temporary shift overrides are forgotten if this is used

step_duplex_state:
	ld a, (duplex_state)
	inc a
	cp #DPX_SPLIT
	jr c, 1f
	ld a, #DPX_SIMPLEX
1:
	ld (duplex_state), a
	cp #DPX_DUPLEX
	jr z, 1f
	load_ahl(rx_freq)        ; 1 to 2 or 2 to 0, flip rx/tx
	push af
	push hl
	load_ahl(tx_freq)
	save_ahl(rx_freq)
	pop hl
	pop af
	save_ahl(tx_freq)
1:
	jp changed_frequency_duplex_okay

#endif /* C_MODULES */

	; set duplex shift temporarily

set_duplex_shift_neg:
	call a2i
	call negate_ahl
	save_ahl(duplex_shift)
	ld a, #DPX_DUPLEX
	ld (duplex_state), a
	jp changed_frequency_duplex_okay

set_duplex_shift_pos:
	call a2i
	save_ahl(duplex_shift)
	ld a, #DPX_DUPLEX
	ld (duplex_state), a
	jp changed_frequency_duplex_okay

	; set tx freq to given memory (rx of the memory)
	; or given frequency (short 3/4 digit freq ok)

set_tx_freq:
	ld a, (digidx)
	cp #3
	jr c, 1f               ; 1...2 digits
	cp #5
	call c, fill_implied   ; if 3 or 4 digits, fix to abs.
	call a2i               ; AHL freq
	jr 2f
1:
	call a2i_byte
	call point_ix_memory_a
	load_ahl_ix_0          ; use memory rx frequency as tx freq
2:
	save_ahl(tx_freq)

	ld a, #DPX_SPLIT
	ld (duplex_state), a
	jp changed_frequency_duplex_okay


; Some contortions to handle stepping up _TO_ a slice end

#ifndef C_MODULES
step_channel_up:
	ld de, (band_step_hz)
	inc de                 ; rounding up, to land on the proper slice.
	load_ahl(rx_freq)
	add hl, de
	adc a, #0
	save_ahl(rx_freq)
	jp changed_frequency


; Extra contortions to handle stepping down _FROM_ a slice start

step_channel_down:

	load_ahl(rx_freq)         ; old frequency

	ld de, #1
	and a
	sbc hl, de
	sbc a, #0
	save_ahl(rx_freq)         ; temporary new freq to old - 1

	call locate_band          ; determine which slice has the destination
	ld a, (band_step)
	call channel_step_parms   ; band_step_hz of destination slice, into DE
	dec de                    ; account for the -1 above

	load_ahl(rx_freq)         ; tmp frequency back.
	and a
	sbc hl, de                ; sub channel step - 1
	sbc a, #0
	save_ahl(rx_freq)         ; (almost) final new frequency

	jp changed_frequency


#endif /* C_MODULES */

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

#ifndef C_MODULES
determine_qsy_kHz:
	load_ahl(rx_freq)             ; current rx freq
	sub_ahl_de(rx_freq_previous)  ; -= previous rx freq
	call c, negate_ahl            ; other way around for abs value

	save_ahl(last_qsy_kHz)
	sub_ahl_de(cfg_scan_large_qsy) ; -= threshold

	ld a, (cfg_scan_rate_kvik)
	jr c, 1f                       ; threshold larger than this qsy
	ld a, (cfg_scan_rate_slow)
1:
	ld (scan_settling_time), a

	load_ahl(rx_freq)
	save_ahl(rx_freq_previous)    ; remember rx freq for next time
	ret

;======================================================================

update_vco_bands:
	call update_rx_vco_band
	call update_tx_vco_band
	ret

update_rx_vco_band:
	ld a, (synth_ctrl)
	or #0x01                 ; assume vco bit "1"
	ld c, a
	load_ahl(rx_freq)
	sub_ahl_de(cfg_rx_vco_center)
	jr c, 1f
	res 0, c                 ; "0" = high band
1:
	ld a, c
	ld (synth_ctrl), a
	ret

update_tx_vco_band:
	ld a, (synth_ctrl)
	or #0x02                 ; assume vco bit "1"
	ld c, a
	load_ahl(tx_freq)
	sub_ahl_de(cfg_tx_vco_center)
	jr c, 1f
	res 1, c                 ; "0" = high band
1:
	ld a, c
	ld (synth_ctrl), a
	ret

#endif /* C_MODULES */

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

quarter_ms_to_kmh:      ; quartermeter / second into km/h

	push hl
	ld bc, #-284         ; 284 * 0.25 m/s = 71 m/s = 256 km/h
	add hl, bc          ; is HL over 284 ?
	pop hl
	jr c, 1f            ; overflow at 255 km/h

	; 115 / 128 ~ 0.9 and 128 - 16 + 2 + 1 = 115

	push hl             ; +1

	add hl, hl          ; 2 times         128 * 285 is 36k, fits ok
	push hl             ; +2              no need to check overflows here
	add hl, hl          ; 4 times
	add hl, hl          ; 8 times
	add hl, hl          ; 16 times
	push hl             ; -16
	add hl, hl          ; 32 times
	add hl, hl          ; 64 times 
	add hl, hl          ; 128 times       j

	pop bc
	sbc hl, bc          ; 128 - 16        carry stays clear in these
	pop bc
	add hl, bc          ; 128 - 16 + 2
	pop bc
	add hl, bc          ; 128 - 16 + 2 + 1

	ld a, h             ; seven MSbits of result
	rl l                ; LSbit of result to CY
	rla                 ; MSbits into position and LSbit insertion
	ret
1:
	sbc a, a               ; 255 and CY set - CY was set from jr above
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
	jr z, ctcss_fx465_on          ; addon FX465 method

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


	; FX465 generator on XXX this check is now redundant, with method tab

ctcss_fx465_on:

	ld a, (cfg_function)
	or a
	ret nz                 ; cannot tx with FX465 in duplex functions.

	ld a, c                ; Hz still in C.
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

	call get_ctcss_tx_hz
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
#ifdef C_MODULES
	ld hl, #0			; c/rptr.c: ST_BOOT_NEW
#else
	ld hl, #repeater_boot
#endif
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
#ifdef C_MODULES
	call bank2_call
	.dw _repeater_run
far_repeater_operator_ptt:	call bank2_call
	.dw _repeater_operator_ptt

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
#else
	call bank1_call
	.dw repeater_run
far_repeater_operator_ptt:	call bank1_call
	.dw repeater_operator_ptt
#endif

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

#ifdef C_MODULES
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
	DPY_SHIM(dpy_squelch_ind, draw_squelch_ind)
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
#endif /* C_MODULES */

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

far_init_menu:	call bank1_call
	.dw init_menu
far_update_gpio12_foo:	call bank1_call
	.dw update_gpio12_foo
far_toggle_or_position_menu:	call bank1_call
	.dw toggle_or_position_menu
far_menu_enter_or_walk:	call bank1_call
	.dw menu_enter_or_walk
far_menu_defval_or_exec:	call bank1_call
	.dw menu_defval_or_exec
far_menu_up_value:	call bank1_call
	.dw menu_up_value
far_menu_dn_value:	call bank1_call
	.dw menu_dn_value
far_menu_next_group:	call bank1_call
	.dw menu_next_group
far_menu_prev:	call bank1_call
	.dw menu_prev
far_decoder_hist_rewind:	call bank1_call
	.dw decoder_hist_rewind
#ifdef C_MODULES
; c/menu.c: remote_config_execute takes the pointer in HL, the data in DE;
; load_menu_ptr is menu_value_ptr (menu_ptr's value, in DE), fsk_menu_ptr
far_remote_config_execute:	; DE = ptr, HL = data
	ex de, hl
	call bank1_call
	.dw _remote_config_execute
far_leaved_setup:	call bank1_call
	.dw leaved_setup
#else
far_remote_config_execute:	call bank1_call
	.dw remote_config_execute
far_leaved_setup:	call bank1_call
	.dw leaved_setup
far_load_menu_ptr:	call bank1_call
	.dw load_menu_ptr
#endif
far_draw_menu_title:	call bank1_call
	.dw draw_menu_title
far_draw_menu_lower_row:	call bank1_call
	.dw draw_menu_lower_row

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

rfc_fill_blanks:

	ld ix, #rfctab

	; make sure index 99 has a barrier, 0 into 255 else

	ld a, (ix+99)
	or a
	jr nz, 1f
	dec a
	ld (ix+99), a
1:
	; find holes in 1...98 range, [0] not hole, [99] barrier
1:
	ld a, (ix+1)
	or a
	call z, rfc_fill_one_hole
	inc ix
	push ix
	pop hl
	ld de, #rfctab + 98
	and a
	sbc hl, de      ; below end ?
	jr c, 1b
	ret             ; after no holes

;
;  entry:  ix+1 first of hole
;  return: ix+1 one past hole
;
rfc_fill_one_hole:
	push ix         ; x1
	pop iy
1:
	inc iy
	ld a, (iy+0)    ; y2 ?
	or a
	jr z, 1b        ; find the end of the hole, it is there always (barrier)

	ld e, (ix+0)    ; y1
	sub e           ; dy
	ld e, a         ; dy = e

	push iy         ; x2
	pop hl
	push ix
	pop bc          ; x1
	and a
	sbc hl, bc      ; x2 - x1
	ld c, l         ; dx = c

	;
	;  Fill blanks from ix+1 upto next nonblank
	;  ix+0 has last y, ix+1 is blank, new y determined,
	;  ix stepped and new y stored.
	;
	ld hl, #0            ; sum = 0
	ld d, #0
	ld b, #0             ; dx and dy as words
	jr 1f               ; start loop
3:
	inc a               ; y++
2:
	inc ix              ; x++
	ld (ix+0), a
1:
	ld a, (ix+1)
	or a
	ret nz              ; at endpoint

	ld a, c
	cp e                ; dx - dy
	ld a, (ix+0)        ; y
	jr c, 1f            ; if (dx < dy) steep way

	; slow rise way

	add hl, de          ; sum += dy
	sbc hl, bc
	jr nc, 3b           ; if (sum >= dx)
	add hl, bc
	jr 2b

	; steep rise way
1:
	inc a               ; y++
	add hl, bc          ; sum += dx
	sbc hl, de
	jr nc, 2b           ; if (sum >= dy)
	add hl, de
	jr 1b

;======================================================================

	; @IY - 4 bytes in 1/256 of a second units
	; @IX - buffer to receive DDDMMmm; degrees, minutes and centiminutes

aisin_seiki_parse_latlon:

	ld a, (iy+0)
	ld h, (iy+1)
	ld l, (iy+2)       ; dividend in AHL, max 180 * 60 * 60

	;  calculate degrees

	ld e, #0            ; EBC is divisor for the first digitloop
	ld bc, #60 * 60 * 10
	ld d, #-1
	and a
1:
	inc d
	sbc hl, bc
	sbc a, e
	jr nc, 1b
	add hl, bc         ; fix back. after this dividend fits in HL

	ld a, d
	ld d, #1
	sub #10
	jr nc, 1f          ; jump if result is 10 ... 18
	dec d              ; result was 0 ... 9
	add a, #10
1:
	ld (ix+0), d
	ld (ix+1), a       ; hundreds and tens of degrees, HL max 60 * 60 * 10

	ld bc, #60 * 60 * 1
	sub a
1:
	inc a
	sbc hl, bc
	jr nc, 1b
	add hl, bc

	dec a
	ld (ix+2), a       ; degrees now set 0 ... 180, HL max 60 * 60 * 1

	; calculate minutes

	ld bc, #60 * 10
	sub a
1:
	inc a
	sbc hl, bc
	jr nc, 1b
	add hl, bc

	dec a
	ld (ix+3), a       ; tens of minutes, HL max 60 * 10

	ld bc, #60 * 1
	sub a
1:
	inc a
	sbc hl, bc
	jr nc, 1b
	add hl, bc         ; L has seconds, 0 ... 59

	dec a
	ld (ix+4), a       ; minutes now set 0 ... 60

	; calculate centiminutes

	ld h, l            ; finally, do the fractional seconds. 
	ld l, (iy+3)       ; HL contains 256 * seconds, max 15360

	ld bc, #1536        ; 60 * 256 / 153.6 = 100
	sub a
1:
	inc a
	sbc hl, bc
	jr nc, 1b
	add hl, bc

	dec a
	ld (ix+5), a       ; tens of centiminutes
	ld (ix+6), l       ; ones of centiminutes

	ret

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

#ifndef C_MODULES	/* c/menu.c, bank 1: the engine; the records, tables and
			   band defaults below stay */
init_menu:
	ld ix, #start_menu
	ld (menu_ptr), ix
	ret

; 6 digits, title string, two more blanks with alfa

draw_menu_title:
	call clear_upper_colons

	ld ix, (menu_ptr)

	ld a, (ix+offset_title+0)
	call dpydig
	ld a, (ix+offset_title+1)
	call dpydig
	ld a, (ix+offset_title+2)
	call dpydig
	ld a, (ix+offset_title+3)
	call dpydig
	ld a, (ix+offset_title+4)
	call dpydig
	ld a, (ix+offset_title+5)
	call dpydig

	ld a, (cu_is_alfa)
	or a
	ret z

	ld a, #' '
	call dpydig
	ld a, #' '
	call dpydig
	ret

; TT:b1234567, where :b is nonexistent in CU58AF

draw_menu_lower_row:

	ld ix, (menu_ptr)
	ld a, (ix+offset_tag+0)
	call dpydig
	ld a, (ix+offset_tag+1)
	call dpydig

	ld a, (cu_is_alfa)
	or a
	jr nz, 1f
	call draw_lower_colon
	ld a, #' '
	call dpydig
1:
	ld ix, (menu_ptr)
	ld a, (ix+offset_type)
	cp #CFG_BYTE
	jp z, draw_menu_byte
	cp #CFG_WORD
	jp z, draw_menu_word
	cp #CFG_FREQ
	jp z, draw_menu_freq
	cp #CFG_TAB
	jp z, draw_menu_tab
	cp #CFG_DYN
	jp z, draw_menu_dyn
	cp #CFG_RST
	jp z, draw_menu_rst
	cp #CFG_STR
	jp z, draw_menu_str
	cp #CFG_DPX
	jp z, draw_menu_dpx
	cp #CFG_cSEC
	jr z, draw_menu_csec

	call sput
	.asciz "???????"
	ret

; return value-pointer of record ix in hl

load_menu_ptr:
	ld l, a
	ld a, (display_buffer_time)
	or a
	ld a, l
	jr z, 1f
	ld hl, #remote_display_buffer  ; if we got remote config reply, use that data
	ret
1:
	ld l, (ix+offset_ptr+0)
	ld h, (ix+offset_ptr+1)

	; is this the special case for mem/vfo ctcss_*_hz ? (yuck)

	ld a, (mem_flags)
	and #MEM_VALID
	ret z                          ; not on memories.

	ld a, (ix+offset_type)
	cp #CFG_TAB
	jr z, 2f                       ; CtCSSt is a TAB record (v3_Z: BYTE only)
	cp #CFG_BYTE
	ret nz                         ; CtCSSr a BYTE
2:

	ld a, l
	cp #LO(cfg_ctcss_tx_hz)
	jr nz, 1f
	ld a, h
	cp #HI(cfg_ctcss_tx_hz)
	jr nz, 1f                      ; not that one.

	ld hl, #mem_ctcss_tx_hz         ; this one instead.
	ret
1:
	ld a, l
	cp #LO(cfg_ctcss_rx_hz)
	ret nz
	ld a, h
	cp #HI(cfg_ctcss_rx_hz)
	ret nz                         ; not that one.

	ld hl, #mem_ctcss_rx_hz         ; this one instead.
	ret


leaved_setup:
	ld a, (mem_flags)
	and #MEM_VALID
	call nz, save_memory_ctcss     ; disgusting

	call ctcss_dec_startstop

	call save_nvdata
	ret

load_menu_arg:
	ld l, (ix+offset_arg+0)
	ld h, (ix+offset_arg+1)
	ret

draw_menu_byte:
	call sput
	.asciz "    "  ; 4 blanks, 3 zeroblanked digits
	call load_menu_ptr
	ld a, (hl)
	jp dpyval255

draw_menu_csec:
	call sput
	.asciz "   "  ; 3 blanks, 3 zeroblanked digits, fixed 0
	call load_menu_ptr
	ld a, (hl)
	or a
	jr z, 1f
	call dpyval255
	ld a, #'0'
	jp dpydig      ; NNN0
1:
	call sput
	.asciz "   0"  ; 3 blanks, fixed 0
	ret

draw_menu_word:
	call sput
	.asciz "  "    ; 2 blanks, 5 zeroblanked digits
	call load_menu_ptr
	push hl
	pop ix
	ld l, (ix+0)
	ld h, (ix+1)
	jp draw_word

draw_menu_freq:              ; 7 zeroblanked digits
	call load_menu_ptr
	push hl
	pop ix
	load_ahl_ix_0
	jp draw_long

draw_menu_dpx:               ; 7 zeroblanked digits
	call load_menu_ptr
	push hl
	pop ix
	load_ahl_ix_0
	or h
	or l
	jr z, 1f
	load_ahl_ix_0
	jp draw_long_signed
1:
	call sput
	.asciz "    oFF"
	ret

draw_menu_tab:
	call load_menu_ptr
	ld a, (hl)           ; tab index
	call load_menu_arg
	cp (hl)              ; tab size
	jr nc, 1f
	inc hl               ; point to string array
	ld c, a
	ld b, #0
	sla c
	rl b    ; 2
	sla c
	rl b    ; 4
	sla c
	rl b    ; 8
	add hl, bc
	jp draw_string_rightjust
1:
	ld hl, #1f            ; out of range value
	jp draw_string_rightjust

1:	.ascii "???"
.db EOS

draw_menu_dyn:
	call load_menu_arg
	push hl
	ret
	ret

draw_menu_rst:
	call sput
	.asciz "  666 ?"
	ret

draw_menu_str:
	call load_menu_ptr
	jp draw_string_rightjust_scores

;======================================================================

draw_rfc_dpy:
	ld a, (display_buffer_time)
	or a
	jr nz, draw_remote_dyn_dpy
	ld a, (rfc)
	call dpyval255
	ld a, #' '
	call dpydig
	ld a, (ad_rssi)
	call dpyval255
	ret

menu_rfc_change:
	cp #-1
	jr z, 1f
	cp #+1
	jr z, 1f
	call a2i_byte
	ld (rfc), a
	xor a
1:
	ld hl, #rfc
	add a, (hl)
	ld (hl), a
	out (DA_RFC), a
	call save_rfc
	ret

draw_sql_dpy:
	ld a, (display_buffer_time)
	or a
	jr nz, draw_remote_dyn_dpy
	ld a, (cfg_squelch_level)
	call dpyval255
	ld a, #' '
	call dpydig
	call read_squelcher_value
	call dpyval255
	ret

draw_sqB_dpy:
	ld a, (display_buffer_time)
	or a
	jr nz, draw_remote_dyn_dpy
	ld a, (cfg_squelch_BIG)
	call dpyval255
	ld a, #' '
	call dpydig
	ld a, (ad_rssi)         ; sql_bi w/ RSSI, not: call read_squelcher_value
	call dpyval255
	ret

menu_sql_change:
	cp #0
	jr nz, 1f
	call a2i_byte
	ld (cfg_squelch_level), a
	ret
1:
	ld hl, #cfg_squelch_level
	add a, (hl)
	ld (hl), a
	ret

menu_sqB_change:
	cp #0
	jr nz, 1f
	call a2i_byte
	ld (cfg_squelch_BIG), a
	ret
1:
	ld hl, #cfg_squelch_BIG
	add a, (hl)
	ld (hl), a
	ret

draw_remote_dyn_dpy:
	ld a, (remote_display_buffer+0)
	call dpyval255
	ld a, #' '
	call dpydig
	ld a, (remote_display_buffer+1)
	call dpyval255
	ret

;----------------------------------------------------------------------

decoder_hist_rewind:
	ld a, (ccir_hist_idx)      ; points usually past last blank
	dec a
	ld (ccir_hist_finger), a

	ld a, (dtmf_hist_idx)
	dec a
	ld (dtmf_hist_finger), a

	ld a, (fsk_hist_idx)
	dec a
	ld (fsk_hist_finger), a

	ld a, (gps_hist_idx)
	dec a
	ld (gps_hist_finger), a

	ret

ccir_hist_walk:
	ld hl, #ccir_hist_finger
	jr decoder_history_walk

dtmf_hist_walk:
	ld hl, #dtmf_hist_finger
	jr decoder_history_walk

fsk_hist_walk:
	ld hl, #fsk_hist_finger
	jr decoder_history_walk

gps_hist_walk:
	ld hl, #gps_hist_finger
	jr decoder_history_walk

decoder_history_walk:
	add a, (hl)
	ld (hl), a
	ret

;----------------------------------------------------------------------

draw_ccir_hist:
	ld hl, (ccir_hist_finger) ; current peeking offset (ld l, [infact])
	ld h, #HI(ccir_history)   ; history page
	jp draw_decoder_history

draw_dtmf_hist:
	ld hl, (dtmf_hist_finger) ; current peeking offset
	ld h, #HI(dtmf_history)   ; history page
	jp draw_decoder_history

draw_fsk_hist:
	ld hl, (fsk_hist_finger)  ; current peeking offset
	ld h, #HI(fsk_history)    ; history page
	jp draw_decoder_history

draw_gps_hist:
	ld hl, (gps_hist_finger)  ; current peeking offset
	ld h, #HI(gps_history)    ; history page
	jp draw_decoder_history

;----------------------------------------------------------------------

enter_safety_delay:          ; return CY if long enough press

	call feedback_hold
	call redraw
1:
	ld a, (key_time)
	ld b, a
	ld a, (cfg_enter_time)
	cp #10
	jr c, 2f
		ld a, #10             ; clamp the limit at 10
	2:
	sub b                    ; length_limit - current_length
	jr c, 1f                 ; if is long enough, change display
	call is_key_down
	jr nz, 1b                ; loop as long as pressed

	call clear_buffer
	call clear_key
	call no_feedback
	call redraw
	and a
	ret                      ; return no CY
1:
	call feedback_let_go_the_darn_button
	call redraw
	call waitkey
	call clear_key
	call no_feedback
	scf
	ret

toggle_or_position_menu:

	ld a, (menu_active)
	or a
	jr nz, 1f                  ; already in menu, allow short press
	ld a, (cfg_enter_time)
	or a
	jr z, 1f                   ; no safety delay in ENT

	call enter_safety_delay    ; twiddle until released
	ret nc                     ; if too short
1:

	; How many pending digits ?

	ld a, (digidx)
	or a
	jr nz, 1f              ; jump if any digits

	; Just ENT - toggle setup

	ld a, (menu_active)
	xor #1
	ld (menu_active), a
	or a
	call z, leaved_setup    ; if leaving menu
	ret
1:
	;
	; ENT with digits, single or more digits ?
	;
	ld ix, #digbuf

	cp #1                   ; just a single digit ?
	jr z, 1f
	cp #2                   ; two digits ?
	jr z, 2f

	; one and two digits here

	call a2i               ; number into AHL
	ld c, #100
	call div248            ; /= 100, result L has top, A has sub indexes
	ld b, a
	ld a, l                ; a top index, b sub index
	jr 3f
1:
	ld a, (ix + 0)         ; top index
	ld b, #0                ; subindex 0
	jr 3f
2:
	ld a, (ix + 0)         ; top index
	ld b, (ix + 1)         ; sub index
3:
	; separated now, A and B - both just 8bits

	cp #10
	jr c, 1f
	ld a, #9               ; someone _might_ alphainput these
1:
	sla a                  ; wordify index
	ld e, a
	ld d, #0
	ld ix, #menu_quickspots
	add ix, de
	ld l, (ix+0)
	ld h, (ix+1)           ; hl points into first in submenu
	push hl


	; XXX this might overflow the pointer if the setup table
	; were located in very high address. The problem is asserted.

	ld c, #size_menurec
	xor a
	ld h, a
	ld l, b               ; AHL gets sub index
	call mul248           ; turns into byte offset in submenu

	pop bc                ; submenu offset back
	add hl, bc            ; finally record pointer

	; Only check needed, overflow at end of menu. Never overflow of 16bit
	; address.

	push hl
	ld de, #end_menu
	and a
	sbc hl, de
	pop hl
	jr c, 1f
	ld hl, #end_menu - size_menurec       ; stick at last
1:
	ld (menu_ptr), hl

	ld a, #1
	ld (menu_active), a           ; menu mode forced to 1

	xor a
	ld (digidx), a
	ret



menu_enter_or_walk:
	ld a, (digidx)
	or a
	jr z, menu_next

	call menu_new_value
	xor a
	ld (digidx), a
	ret

menu_defval_or_exec:
	ld ix, (menu_ptr)
	call load_menu_ptr            ; into hl
	ld a, (ix + offset_type)
	cp #CFG_DPX
	jr z, menu_set_duplex_def      ; CFG_DPX, copy cfg_other_duplex
	cp #CFG_FREQ
	jr z, menu_set_from_vfo        ; CFG_FREQ, copy rx_freq
	cp #CFG_EXE
	jp nz, reset_menurec
	jp (hl)                        ; CFG_EXE, jump to ptr

menu_set_duplex_def:
	push hl
	pop ix
	load_ahl(cfg_other_duplex)
	save_ahl_ix_0
	ret

menu_set_from_vfo:
	push hl
	pop ix
	load_ahl(rx_freq)
	save_ahl_ix_0
	ret

menu_next_group:
	ld ix, (menu_ptr)
	ld b, (ix+offset_tag+0)
	ld c, (ix+offset_tag+1)
1:
	push bc
	call menu_next
	pop bc
	ld ix, (menu_ptr)
	ld a, (ix+offset_tag+0)
	cp b
	ret nz
	ld a, (ix+offset_tag+1)
	cp c
	ret nz
	jr 1b

menu_next:
	ld bc, #size_menurec
	jr menu_next_prev
menu_prev:
	ld bc, #-size_menurec
	jr menu_next_prev

menu_next_prev:
	ld hl, (menu_ptr)
	add hl, bc
	ld a, #HI(end_menu)
	cp h
	jr nz, 1f
	ld a, #LO(end_menu)
	cp l
	jr nz, 1f
	ld hl, #start_menu
1:
	ld a, #HI(start_menu - size_menurec)
	cp h
	jr nz, 1f
	ld a, #LO(start_menu - size_menurec)
	cp l
	jr nz, 1f
	ld hl, #end_menu - size_menurec
1:
	ld (menu_ptr), hl
	ret

	; de = ptr, hl data (wrap)

remote_config_execute:

	; special ptr ?

	ld a, d
	or a
	jr nz, 1f            ; normal varible, search menu

	ld a, e

	cp #0                    ; VERSION = 0
	ret z
	cp #1                    ; RFC = 1
	ret z

	ld ix, #menu_rec_sql
	cp #2                    ; SQL = 2
	jr z, 3f

	ld ix, #menu_rec_sqB
	cp #3                    ; SQL BI = 3
	jr z, 3f

	ret         ; no such special ptr
1:
	; where in menu is this ptr

	ld ix, #start_menu
2:
	ld a, (ix+offset_ptr+0)
	cp e
	jr nz, 1f
	ld a, (ix+offset_ptr+1)
	cp d
	jr z, 3f                  ; here
1:
	push ix
	pop bc
	ld a, c
	cp #LO(end_menu)
	jr nz, 1f
	ld a, b
	cp #HI(end_menu)
	ret z                    ; no such record. XXX later for remote pokes
1:
	ld bc, #size_menurec
	add ix, bc
	jr 2b
3:
	ld (menu_ptr), ix                        ; XXX could just preload ix

	; Act as like remote data in digbuf

	ld de, #digbuf
	ld b, #SIZE_STR
	ld c, #0
1:
	ld a, (hl)
	inc l              ; in page wrap
	sla4
	or (hl)
	inc l              ; in page wrap
	cp #EOS
	jr z, 1f
	ld (de), a
	inc de
	inc c
	dec b
	jr nz, 1b
1:
	ld a, c
	ld (digidx), a

	; GO!

	call menu_new_value
	xor a
	ld (digidx), a
	ret


menu_new_value:
	ld ix, (menu_ptr)                            ; XXX remote could skip this
	call load_menu_ptr          ; hl -> var
	ld a, (ix+offset_type)
	cp #CFG_BYTE
	jr z, menu_new_value_byte
	cp #CFG_WORD
	jr z, menu_new_value_word
	cp #CFG_FREQ
	jp z, menu_new_value_freq
	cp #CFG_TAB
	jr z, menu_new_value_tab
	cp #CFG_DYN
	jp z, menu_new_value_dyn
	cp #CFG_RST
	jp z, menu_new_value_rst
	cp #CFG_STR
	jp z, menu_new_value_str
	cp #CFG_DPX
	jp z, menu_new_value_dpx
	cp #CFG_cSEC
	jr z, menu_new_value_csec

	ret


menu_new_value_byte:
	push hl
	call a2i_byte
	pop ix
	ld (ix+0), a
	ret

menu_new_value_csec:
	push hl
	ld a, (digidx)
	dec a
	ld (digidx), a      ; 10# for millisecs, we need 1# for cSECs
	call a2i_byte
	pop ix
	ld (ix+0), a
	ret

menu_new_value_word:
	push hl
	call a2i_word
	pop ix
	ld (ix+0), l
	ld (ix+1), h

	push ix                       ; argh.... these must be generalized
	pop hl

	jr menu_word_value_changed


menu_new_value_tab:
	push hl               ; variable
	call load_menu_arg
	ld c, (hl)
	push bc               ; count of selections
	call a2i_byte
	pop bc
	cp c
	jr c, 1f
	ld a, c
	dec a
1:
	pop hl
	ld (hl), a

	jr menu_tab_value_changed

menu_word_value_changed:

	ld a, l
	cp #LO(cfg_external_serial_A)
	jr nz, 1f
	ld a, h
	cp #HI(cfg_external_serial_A)
	jr nz, 1f

	jp shift_external_serial_A      ; this ?
1:
	ld a, l
	cp #LO(cfg_external_serial_B)
	jr nz, 1f
	ld a, h
	cp #HI(cfg_external_serial_B)
	jr nz, 1f

	jp shift_external_serial_B      ; this ?
1:
	ret

menu_tab_value_changed:

	ld a, l
	cp #LO(cfg_gpio1_state)
	jr nz, 1f
	ld a, h
	cp #HI(cfg_gpio1_state)
	jr nz, 1f

	jr update_gpio12_foo
1:
	ld a, l
	cp #LO(cfg_gpio2_state)
	jr nz, 1f
	ld a, h
	cp #HI(cfg_gpio2_state)
	jr nz, 1f

	jr update_gpio12_foo
1:
	ret

update_gpio12_foo:
	di
	call update_gpio12
	ei
	ret


menu_new_value_rst:
	push hl
	ret
	ret

empty_string: .db EOS,EOS,EOS,EOS,EOS,EOS,EOS,EOS,EOS,EOS,EOS,EOS

menu_new_value_str:
	push hl
	push hl
	pop de
	ld hl, #empty_string
	ld bc, #SIZE_STR
	ldir
	pop de
	ld hl, #digbuf
	ld a, (digidx)
	or a
	ret z
	cp #SIZE_STR
	jr c, 1f
	ld a, #SIZE_STR
1:
	ld c, a
	xor a
	ld b, a
	ldir
	ret

menu_new_value_freq:
	push hl
	call a2i
	pop ix
	save_ahl_ix_0
	ret

menu_new_value_dpx:
	push hl
	call a2i
	pop ix
	ld c, (ix+2)        ; previous MSByte
	bit 7, c
	call nz, negate_ahl ; previous was negative, so...
	save_ahl_ix_0
	ret

menu_up_value:
	ld a, #+1
	jr 1f

menu_dn_value:
	ld a, #-1
1:
	push af                     ; direction in stack

	ld ix, (menu_ptr)
	call load_menu_ptr          ; hl -> var
	ld a, (ix+offset_type)
	cp #CFG_DYN
	jp z, menu_step_value_dyn
	cp #CFG_BYTE
	jr z, menu_step_value_byte
	cp #CFG_cSEC
	jr z, menu_step_value_byte
	cp #CFG_TAB
	jr z, menu_step_value_tab
	cp #CFG_WORD
	jr z, menu_step_value_word
	cp #CFG_FREQ
	jr z, menu_step_value_freq
	cp #CFG_DPX
	jr z, menu_step_value_dpx

	pop af
	ret         ; doh, +/- no effect

menu_step_value_dpx:
	pop af               ; duplex value stepped, just flip between neg/pos
	push hl
	pop ix
	load_ahl_ix_0
	call negate_ahl
	save_ahl_ix_0
	ret

menu_step_value_freq:
	call get_probable_chstep_de
	pop af
	push hl
	pop ix
	cp #+1
	load_ahl_ix_0
	jr z, 1f
	and a
	sbc hl, de
	sbc a, #0
	jr 2f
1:
	add hl, de
	adc a, #0
2:
	save_ahl_ix_0
	ret

menu_step_value_word:
	pop af
	ld bc, #1
	cp #+1
	jr z, 1f
	ld bc, #-1
1:
	push hl
	pop ix
	ld l, (ix+0)
	ld h, (ix+1)
	add hl, bc
	ld (ix+0), l
	ld (ix+1), h

	push ix
	pop hl
	jp menu_word_value_changed


menu_step_value_byte:
	pop af
	add a, (hl)
	ld (hl), a                   ; +=   +1 or -1
	ret

menu_step_value_tab:
	pop af
	add a, (hl)
	ld b, a                   ; +=   +1 or -1
	push hl                ; save ptr
	call load_menu_arg     ; for max-1
	ld a, (hl)
	ld c, a
	pop hl
	ld a, b
	cp #-1
	jr nz, 1f
	ld a, c
	dec a             ; count - 1 if down from 0
1:
	cp c
	jr c, 1f
	xor a           ; 0 if up from max
1:
	ld (hl), a

	jp menu_tab_value_changed


menu_step_value_dyn:
	pop af
	jr 1f
menu_new_value_dyn:
	xor a
1:
	push af
	ld a, h
	or l
	ret z             ; null ptr, non-editable field
	pop af
	jp (hl)

;----------------------------------------------------------------------

reset_menurec:
	ld a, (ix + offset_type)

	cp #CFG_BYTE
	jr z, reset_menurec_byte
	cp #CFG_TAB
	jr z, reset_menurec_byte
	cp #CFG_cSEC
	jr z, reset_menurec_byte

	cp #CFG_WORD
	jr z, reset_menurec_word

	cp #CFG_STR
	jr z, reset_menurec_str

	ret

reset_menurec_str:
	call load_menu_ptr
	ld (hl), #EOS
	ret

reset_menurec_byte:
	call load_menu_ptr
	ld a, (ix + offset_def)
	ld (hl), a
	ret

reset_menurec_word:
	call load_menu_ptr
	ld a, (ix + offset_def + 0)
	ld (hl), a
	inc hl
	ld a, (ix + offset_def + 1)
	ld (hl), a
	ret

#endif /* C_MODULES */

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

#ifdef C_MODULES
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
#endif

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

	REC("Pr", "CALL  ",CFG_STR,  cfg_mprs_callsign,  0,              0, kutsu MPRS-modessa - max 6 merkkiÃ¤)
	REC("Pr", "SSId  ",CFG_BYTE, cfg_mprs_ssid,      0,              0, SSID MPRS-modessa (0...15))
	REC("Pr", "ObJECt",CFG_TAB,  cfg_mprs_symbol,    tab_mprs_symbol,0, aseman symboli MPRS-modessa)
	REC("Pr", "PttSnd",CFG_TAB,  cfg_keyup_mprs,     tab_pttsnd,     0, MPRS vapautettaessa PTT - Ei/Aina/Tarvittaessa - katso SndInt)
	REC("Pr", "AutSnd",CFG_TAB,  cfg_spontaneous_mprs, tab_onoff,    0, MPRS spontaanisti - QSY tr:APrSFq)
	REC("Pr", "CutAud",CFG_TAB,  cfg_fsk_silencer,  tab_fsk_silencer, 0, audion sulku FSK:n kohdalla)
	REC("Pr", "buS Fn",CFG_TAB,  cfg_mbus_mprs,      tab_mbus_mprs,  0, MPRS releoidaan MBUS:iin tavalla X)
	REC("Pr", "dPYSEC",CFG_BYTE, cfg_remote_dpy_secs, 0,             0, MPRS tiedot pidetÃ¤Ã¤n nÃ¤ytÃ¶llÃ¤ N sekuntia)
	REC("Pr", "GPSUPL",CFG_TAB,  cfg_gps_upload,     tab_gps_upload, 0, MPRS tiedot GPS:Ã¤Ã¤n waypointteina)
	REC("Pr", "dStSnd",CFG_TAB,  cfg_gps_dst_send,   tab_onoff,      0, MPRS oman mÃ¤Ã¤rÃ¤npÃ¤Ã¤n julkaisu)
	REC("Pr", "buS rF",CFG_TAB,  cfg_bus_rf_relay,   tab_onoff,      0, MBUS/RF relay)
	REC("Pr", "SndInt",CFG_WORD, cfg_mprs_seconds,   0,        900, MPRS lÃ¤hetysintervalli - sekuntia - tiukentuu liikkeessÃ¤)
	REC("Pr", "tProto",CFG_TAB,  cfg_report_type,    tab_mprs_aprs,  0, MPRS vai APRS lÃ¤hetys - VAIKUTTAA VAIN LÃHETYKSEEN)
	REC("Pr", "dGPAth",CFG_TAB,  cfg_mic_e_dest_ssid,tab_mic_e_dest_ssid,  0, MIC-E toistoreitti - vaikuttaa vain MIC-E formaatissa)
	REC("Pr", "StAtuS",CFG_TAB,  cfg_mic_e_message,  tab_mic_e_message,  0, MIC-E statustieto - vaikuttaa vain MIC-E formaatissa)
	REC("Pr", "APdiG0",CFG_TAB,  cfg_ax25_digi0,     tab_ax25_digi,  0, APRS digipeater #0 - vaikuttaa vain ascii-formaatissa)
	REC("Pr", "APdiG1",CFG_TAB,  cfg_ax25_digi1,     tab_ax25_digi,  0, APRS digipeater #1 - vaikuttaa vain ascii-formaatissa)
	REC("Pr", "APdiG2",CFG_TAB,  cfg_ax25_digi2,     tab_ax25_digi,  0, APRS digipeater #2 - vaikuttaa vain ascii-formaatissa)
	REC("Pr", "APdiG3",CFG_TAB,  cfg_ax25_digi3,     tab_ax25_digi,  0, APRS digipeater #3 - vaikuttaa vain ascii-formaatissa)
	REC("Pr", "APdiGo",CFG_STR,  cfg_ax25_digi_other,0,              0, APRS digipeater 'othEr' - aktivoidaan APdiG0..3 valintojen kautta)

	REC("Pr", "PAdbit",CFG_BYTE, cfg_ax25_padbits,  0,      0, AX.25 preamble - "TXDELAY*10" - kts. myÃ¶s PH:PLLdEL)

#if 0
	REC("Pr", "r AX25",CFG_TAB,  cfg_fx614_exist,   tab_onoff,      0, AX.25 modem (like tcm3105 or fx614) is wired to /LOCAL - see elsewhere for details)
	REC("Pr", "b AX25",CFG_STR,  fx614_buffer + 16,  0,      0, palanen vikaa vastaanotettua ax.25 pakettia)
	REC("Pr", "c AX25",CFG_BYTE, fx614_rxcnt,        0,      0, oikein vastaanotettujen ax.25 pakettien lukumÃ¤Ã¤rÃ¤ modulo 256)
#endif

menu_1:
	REC("to", "LiGHtS",CFG_BYTE, cfg_light_seconds,  0,             255, valojen pitoaika)
	REC("to", "Lit Sq",CFG_TAB,  cfg_light_sql,      tab_onoff,       0, aukeava salpa = valot on)
	REC("to", "IGnAPO",CFG_BYTE, cfg_ign_apo_hours,  0,             255, auto sytytysvirraton: viive-sammutus - jos kÃ¤ytÃ¶ssÃ¤ niin gpio2 pitÃ¤Ã¤Â olla 2 tai 3 eli /EXIN2 on Hi-Z)
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
	REC("LP", "7 SqL ",CFG_BYTE, cfg_def_squelch,    0,               0, oletustaso salvalle; pitkÃ¤ 7)
	REC("LP", "8 CHAn",CFG_BYTE, cfg_def_memory,     0,               0, oletusmuistipaikka; pitkÃ¤ 8)
	REC("LP", "9 FrEq",CFG_FREQ, cfg_def_frequency,  0,               0, oletustaajuus; pitkÃ¤ 9)
	REC("LP", "0 Loud",CFG_BYTE, cfg_def_volume,     0,               1, oletusvolume; pitkÃ¤ 0)


menu_4:

	REC("b1", "StArt ",CFG_FREQ, cfg_band1_start,    0,               0, bandiviipaleen alku)
	REC("b1", "End   ",CFG_FREQ, cfg_band1_end,      0,               0, ... loppu)
	REC("b1", "duPL  ",CFG_DPX,  cfg_band1_duplex,   0,               0, viipaleella voimassaoleva erotus)
	REC("b1", "StEP  ",CFG_TAB,  cfg_band1_step,     tab_chstep,      0, ... askellus)
	REC("b1", "SCtAIL",CFG_BYTE, cfg_band1_sctail,   0,               2, skannaus: odotteluviive)
	REC("b1", "LIStEn",CFG_BYTE, cfg_band1_sclisten, 0,              15, skannaus: overin kesto; kÃ¤rsivÃ¤llisyys)
	REC("b1", "AutorJ",CFG_TAB,  cfg_band1_autoreject,tab_onoff,      0, skannaus: kÃ¤rsivÃ¤llisyyden loppu = tmp reject)

	REC("b2", "StArt ",CFG_FREQ, cfg_band2_start,    0,               0, kuten edellÃ¤)
	REC("b2", "End   ",CFG_FREQ, cfg_band2_end,      0,               0,)
	REC("b2", "duPL  ",CFG_DPX,  cfg_band2_duplex,   0,               0,)
	REC("b2", "StEP  ",CFG_TAB,  cfg_band2_step,     tab_chstep,      0,)
	REC("b2", "SCtAIL",CFG_BYTE, cfg_band2_sctail,   0,               2,)
	REC("b2", "LIStEn",CFG_BYTE, cfg_band2_sclisten, 0,              15,)
	REC("b2", "AutorJ",CFG_TAB,  cfg_band2_autoreject,tab_onoff,      0,)

	REC("b3", "StArt ",CFG_FREQ, cfg_band3_start,    0,               0, kuten edellÃ¤)
	REC("b3", "End   ",CFG_FREQ, cfg_band3_end,      0,               0,)
	REC("b3", "duPL  ",CFG_DPX,  cfg_band3_duplex,   0,               0,)
	REC("b3", "StEP  ",CFG_TAB,  cfg_band3_step,     tab_chstep,      0,)
	REC("b3", "SCtAIL",CFG_BYTE, cfg_band3_sctail,   0,               2,)
	REC("b3", "LIStEn",CFG_BYTE, cfg_band3_sclisten, 0,              15,)
	REC("b3", "AutorJ",CFG_TAB,  cfg_band3_autoreject,tab_onoff,      0,)

	REC("b4", "StArt ",CFG_FREQ, cfg_band4_start,    0,               0, kuten edellÃ¤)
	REC("b4", "End   ",CFG_FREQ, cfg_band4_end,      0,               0,)
	REC("b4", "duPL  ",CFG_DPX,  cfg_band4_duplex,   0,               0,)
	REC("b4", "StEP  ",CFG_TAB,  cfg_band4_step,     tab_chstep,      0,)
	REC("b4", "SCtAIL",CFG_BYTE, cfg_band4_sctail,   0,               2,)
	REC("b4", "LIStEn",CFG_BYTE, cfg_band4_sclisten, 0,              15,)
	REC("b4", "AutorJ",CFG_TAB,  cfg_band4_autoreject,tab_onoff,      0,)

	REC("b5", "StArt ",CFG_FREQ, cfg_band5_start,    0,               0, kuten edellÃ¤)
	REC("b5", "End   ",CFG_FREQ, cfg_band5_end,      0,               0,)
	REC("b5", "duPL  ",CFG_DPX,  cfg_band5_duplex,   0,               0,)
	REC("b5", "StEP  ",CFG_TAB,  cfg_band5_step,     tab_chstep,      0,)
	REC("b5", "SCtAIL",CFG_BYTE, cfg_band5_sctail,   0,               2,)
	REC("b5", "LIStEn",CFG_BYTE, cfg_band5_sclisten, 0,              15,)
	REC("b5", "AutorJ",CFG_TAB,  cfg_band5_autoreject,tab_onoff,      0,)

	REC("b6", "StArt ",CFG_FREQ, cfg_band6_start,    0,               0, kuten edellÃ¤)
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
	REC("rJ", "n tEmP",CFG_BYTE, cfg_num_tmp_rejects, 0,              0, temp rejektien lukumÃ¤Ã¤rÃ¤ 0=max 20)

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
	REC("dH", "Sqr  0",CFG_STR,  locator_display_buffer, 0,           0, ... tÃ¤stÃ¤ ruudusta)
	REC("dH", "diSt 0",CFG_STR,  distance_bearing,   0,               0, ... etÃ¤isyys ja suunta)

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
	REC("AL", "Loud  ",CFG_BYTE, cfg_alert_vol,      0,               7, hÃ¤lytysÃ¤Ã¤ni volume)
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

	REC("rP", "id   t",CFG_WORD, repeater_cfg_TID,   0,             600, kutsunlÃ¤hetysintervalli; sec)
	REC("rP", "OPEn t",CFG_WORD, repeater_cfg_TOPEN, 0,              15, kantoaaltoaika; 0 sec: tx pois heti)
	REC("rP", "HOG  t",CFG_WORD, repeater_cfg_THOG,  0,             300, pyÃ¶rtymisaika; max 65535 sec: 18+ tuntia)
	REC("rP", "CLOS t",CFG_WORD, repeater_cfg_TCLS,  0,              30, valmiusaika; 0 sec: ei valmiusaikaa)
	REC("rP", "dEAd t",CFG_WORD, repeater_cfg_TDEAD, 0,              60, karenssiaika; 0 sec: ei viivyttelyÃ¤)
	REC("rP", "bLiP t",CFG_cSEC, repeater_cfg_TBLIP, 0,              50, vÃ¤libongon viive; msec)
	REC("rP", "SqIncr",CFG_BYTE, repeater_cfg_sqincr,0,               8, salvan kiristysarvo)
	REC("rP", "trIncr",CFG_BYTE, repeater_cfg_txincr,0,               8, tehon nostoarvo)
	REC("rP", "SPEEd ",CFG_BYTE, cfg_cw_speed,       0,             120, cw nopeus mrk/min)
	REC("rP", "PItCH ",CFG_cSEC, cfg_cw_pitch,       0,             140, cw Ã¤Ã¤nenkorkeus)
	REC("rP", "AF Src",CFG_TAB,  repeater_cfg_afsrc, tab_rep_mic,   140, audion kytkentÃ¤tapa)
	REC("rP", "ACCESS",CFG_TAB,  repeater_cfg_access_method,tab_rep_access, 0, avaustapa)
	REC("rP", "tonE t",CFG_WORD, repeater_cfg_TBEEPMAX,  0,           5, maksimiaika avausÃ¤Ã¤nelle)
	REC("rP", "id G1 ",CFG_STR,  repeater_cfg_id_greet1, 0,           0, identifikaatio; tervehdysviesti)
	REC("rP", "id G2 ",CFG_STR,  repeater_cfg_id_greet2, 0,           0, ...)
	REC("rP", "id G3 ",CFG_STR,  repeater_cfg_id_greet3, 0,           0, ... 3 osainen)
	REC("rP", "id t1 ",CFG_STR,  repeater_cfg_id_during1, 0,          0, identifikaatio; qson aikana)
	REC("rP", "id t2 ",CFG_STR,  repeater_cfg_id_during2, 0,          0, ...)
	REC("rP", "id t3 ",CFG_STR,  repeater_cfg_id_during3, 0,          0, ... 3 osainen)
	REC("rP", "id b1 ",CFG_STR,  repeater_cfg_id_bye1,   0,           0, identifikaatio; sulkeutuessa)
	REC("rP", "id b2 ",CFG_STR,  repeater_cfg_id_bye2,   0,           0, ...)
	REC("rP", "id b3 ",CFG_STR,  repeater_cfg_id_bye3,   0,           0, ... 3 osainen)

	REC("rP", "id Hot",CFG_STR,  repeater_cfg_msg_hot_alert, 0,       0, cw viesti kun lÃ¤mpÃ¶tila nousee; TP4 below rP:Hot)
	REC("rP", "idCoLd",CFG_STR,  repeater_cfg_msg_cold_alert, 0,      0, cw viesti kun lÃ¤mpÃ¶tila laskee; TP4 above rP:Cold)
	REC("rP", "id Ant",CFG_STR,  repeater_cfg_msg_ant_bad,    0,      0, cw viesti kun palaava teho nousee)
	REC("rP", "id HOG",CFG_STR,  repeater_cfg_msg_hog,        0,      0, cw viesti pyÃ¶rryttÃ¤essÃ¤)

	REC("rP", "bLIP  ",CFG_STR,  repeater_cfg_blip,  0,               0, cw vÃ¤libongo)
	REC("rP", "bLIP L",CFG_STR,  repeater_cfg_blip_link,  0,          0, cw vÃ¤libongo linkki-ptt:n takia)
	REC("rP", "bLIGP1",CFG_STR,  repeater_cfg_blip_gpio_001, 0,       0, cw vÃ¤libongo GPio2+1 = 00 1)
	REC("rP", "bLIGP2",CFG_STR,  repeater_cfg_blip_gpio_010, 0,       0, cw vÃ¤libongo GPio2+1 = 01 0)
	REC("rP", "bLIGP3",CFG_STR,  repeater_cfg_blip_gpio_011, 0,       0, cw vÃ¤libongo GPio2+1 = 01 1)
	REC("rP", "bLIGP4",CFG_STR,  repeater_cfg_blip_gpio_100, 0,       0, cw vÃ¤libongo GPio2+1 = 10 0)
	REC("rP", "bLIGP5",CFG_STR,  repeater_cfg_blip_gpio_101, 0,       0, cw vÃ¤libongo GPio2+1 = 10 1)
	REC("rP", "bLIGP6",CFG_STR,  repeater_cfg_blip_gpio_110, 0,       0, cw vÃ¤libongo GPio2+1 = 11 0)
	REC("rP", "bLIGP7",CFG_STR,  repeater_cfg_blip_gpio_111, 0,       0, cw vÃ¤libongo GPio2+1 = 11 1)
	REC("rP", "PItCHb",CFG_cSEC, cfg_cw_pitch_blip,  0,             140, vÃ¤libongon Ã¤Ã¤nenkorkeus)
	REC("rP", "PItCHL",CFG_cSEC, cfg_cw_pitch_blip_link,  0,        140, linkki-ptt-bongon Ã¤Ã¤nenkorkeus)
	REC("rP", "PItCHG",CFG_cSEC, cfg_cw_pitch_blip_gpio,  0,        140, gpio-bongon Ã¤Ã¤nenkorkeus)
	REC("rP", "Hot  L",CFG_BYTE, cfg_temperature_limit_hot,  0,       0, lÃ¤mpÃ¶tilan raja-arvo)
	REC("rP", "CoLd L",CFG_BYTE, cfg_temperature_limit_cold, 0,     255, lÃ¤mpÃ¶tilan raja-arvo)
	REC("rP", "AntbAd",CFG_BYTE, cfg_rpm_limit,      0,               0, palaavan tehon raja-arvo)
	REC("rP", "rEMOtE",CFG_WORD, cfg_remote_id,      0,               0, kaukokÃ¤ytÃ¶n osoite (0!))
	REC("rP", "PASS C",CFG_STR,  cfg_remote_passwd,  0,               0, kaukokÃ¤ytÃ¶n salasana)

	REC("rP", "ccirPF",CFG_STR,  repeater_cfg_ccir_cmd_pfx, 0,        0, ruutukomentojen ccir-prefiksi)

	REC("rP", "S1rSSi", CFG_BYTE, cfg_rssi_S1, 0, 0, S1 signaalitason RSSI-arvo)
	REC("rP", "S9rSSi", CFG_BYTE, cfg_rssi_S9, 0, 0, S9 signaalitason RSSI-arvo)

	REC("rP", "CtCOut", CFG_TAB, cfg_ctcss_output_when, tab_ctcss_out, 0, tx ctcss milloin)

	REC("rP", "SUSP c", CFG_STR, cfg_repeater_suspend_ccir_cmd, 0, 0, ccir sammutuskoodi)
	REC("rP", "SUSP d", CFG_STR, cfg_repeater_suspend_dtmf_cmd, 0, 0, dtmf sammutuskoodi)
	REC("rP", "SUSPnd", CFG_TAB, cfg_repeater_suspended, tab_onoff, 0, sammutustila)

	REC("rP", "HidE 9", CFG_TAB, cfg_repeater_cmd_9_hidden, tab_pass_hide, 0, #9 sallittu)
	REC("rP", "SIMPLE", CFG_TAB, cfg_repeater_wierd_simplex, tab_onoff, 0, toistimen omituinen simplex-mode)
	REC("rP", "BLIPS ", CFG_TAB, repeater_cfg_musical_blips, tab_cw_notes, 0, vÃ¤libongot cw vai nuotit)
	REC("rP", "BrSSiS", CFG_TAB, repeater_cfg_rssi_bongos, tab_onoff, 0, rssi vÃ¤libongot kÃ¤ytÃ¶ssÃ¤ - #5 dtmf toggle)
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
	REC("tr", "APrSFq",CFG_FREQ, cfg_aprs_tx_freq,   0,               0, Real-APRS lÃ¤hetystaajuus)

menu_8:
	REC("PH", "SynCrd",CFG_TAB,  cfg_synth_card,     tab_synth_card,  0, RF-osan tyyppi)
	REC("PH", "3diGit",CFG_STR,  cfg_implied,        0,               0, implied MHz (3 ensimmÃ¤istÃ¤ numeroa))
	REC("PH", "IFFrEq",CFG_FREQ, cfg_if_freq,        0,               0, rx vÃ¤litaajuus)
	REC("PH", "LO InJ",CFG_TAB,  cfg_inj_below,      tab_above_below, 0, injektion puoli)
	REC("PH", "r CEnt",CFG_FREQ, cfg_rx_vco_center,  0,               0, rx vcon keskitaajuus)
	REC("PH", "t CEnt",CFG_FREQ, cfg_tx_vco_center,  0,               0, tx vcon keskitaajuus)
	REC("PH", "LPFILt",CFG_WORD, cfg_lpf_hz,         0,            3600, tx audion alipÃ¤Ã¤stÃ¶)
	REC("PH", "FonE d",CFG_BYTE, cfg_deviation_fone, 0,              15, puhedeviaation sÃ¤Ã¤tÃ¶ - 0 ... 15)
	REC("PH", "SiG dE",CFG_BYTE, cfg_deviation_sign, 0,               7, signalointideviaation sÃ¤Ã¤tÃ¶ - 0 ... 15)
tune_tone_position:
	REC("PH", "t tunE",CFG_WORD, cfg_txtune_hz,      0,               0, tx testisignaalia)
	REC("PH", "PLLdEL",CFG_BYTE, cfg_pll_delay,      0,               0, txpll kÃ¤ynnistysviive - karkeasti msec - PLL stabiiliksi)

	REC("PH", "tr oFF", CFG_FREQ, cfg_tx_mix_freq,       0, 0, tx mikseri)
	REC("PH", "t mult", CFG_BYTE, cfg_tx_vco_multiplier, 0, 0, tx kertoja)
	REC("PH", "r mult", CFG_BYTE, cfg_rx_vco_multiplier, 0, 0, rx kertoja)
	REC("PH", "CtCdEc", CFG_TAB,  cfg_ctcss_input_method, tab_ctcss_input_method, 0, ctcss-detektori: ROM1 /TMR0 TMR0)
	REC("PH", "CtCtHr", CFG_BYTE, cfg_ctcss_dec_threshold, 0,      100, ctcss-softadekooderin raja-arvo)
	REC("PH", "CtCGEn", CFG_TAB,  cfg_ctcss_output_method, tab_ctcss_output_method, 0, ctcss:n luontitapa - huomaa: kaikki vaativat modifikaatioita)
	REC("PH", "CtHAnG", CFG_BYTE, cfg_ctcss_hang,    0,               0, hang-aika overin lopussa ilman ctcss-Ã¤Ã¤ntÃ¤ - msec)
	REC("PH", "CtGAin", CFG_BYTE, cfg_ctcss_generator_gain, 0,      127, rfc-dac ctcss-generaattorin gain - mahduttava rfc:n ja abs(-rfc):n rajoihin)
	REC("PH", "dtGAin", CFG_BYTE, cfg_dtmf_gain, 0,       31, dtmf-generaattorin gain - oltava 1...31)
	REC("PH", "PrGAin", CFG_BYTE, cfg_ax25_gain, 0,       63, ax.25-generaattorin gain - P8N 1...70 P8E 1...84)
	REC("PH", "SErCtA", CFG_WORD, cfg_external_serial_A, 0,           0, 16bit shiftreg SD CLK RAS - MSbit first - positive 1usec pulses)
	REC("PH", "SErCtB", CFG_WORD, cfg_external_serial_B, 0,           0, 16bit shiftreg SD CLK TPS - MSbit first - positive 1usec pulses)
	REC("PH", "GPSCFG", CFG_TAB,  cfg_gps_config,    tab_gps_config,  0, GPS-konfiguraatio - Std = geneerinen NMEA- 9600Std -OH1E)

	REC("dF", "CFGGEt",CFG_RST,  all_config_get,     0,               0, KAIKKIEN asetusten ylikirjoitus MBUS-karvasta)
	REC("dF", "CFGSnd",CFG_RST,  all_config_send,    0,               0, asetusten lÃ¤hetys MBUS-karvaan)
	REC("dF", "ALLrSt",CFG_RST,  disaster,           0,               0, asetusten nollaus)
	REC("dF", "CH rSt",CFG_RST,  wipe_memories,      0,               0, muistien nollaus)
	REC("dF", "SAnE  ",CFG_RST,  sane_defaults,      0,               0, monien asetusten oletusasetus)
	REC("dF", "rFcrSt",CFG_RST,  wipe_rfctab,        0,               0, rx sÃ¤Ã¤tÃ¶arvojen nollaus)
	REC("dF", "rFcFIL",CFG_RST,  rfc_fill_blanks,    0,               0, rx sÃ¤Ã¤tÃ¶arvojen interpolointi)
	REC("dF", "rEboot",CFG_RST,  do_reboot,          0,               0, lÃ¤mmin kÃ¤ynnistys)

	REC("dF", "EntLen",CFG_BYTE, cfg_enter_time,     0,               0, setupnapin turva-aika)

menu_9:
	REC("St", "SoFt  ",CFG_STR,  version,            0,               0, softaversio)
	REC("St", "AdrSSI",CFG_BYTE, ad_rssi,            0,               0, RSSI arvo)
	REC("St", "Ad SqL",CFG_BYTE, ad_sql,             0,               0, SQL arvo)
	REC("St", "AdbAtt",CFG_BYTE, ad_batt,            0,             255, jÃ¤nnite) ; HA!
	REC("St", "Ad tPc",CFG_BYTE, ad_tpc,             0,               0, tx power control)
	REC("St", "Ad For",CFG_BYTE, ad_fpm,             0,               0, forward power)
	REC("St", "Ad rEF",CFG_BYTE, ad_rpm,             0,               0, reflected power)
	REC("St", "Ad tP4",CFG_BYTE, ad_tp4,             0,               0, TP4 mittapiste)
	REC("St", "Ad in7",CFG_BYTE, ad_in7,             0,               0, IN7 mittapiste)
	REC("St", "ctcFit",CFG_BYTE, ctcss_dec_fit,      0,               0, ctcss korrelaatio - isompi parempi)

	REC("St", "USEcnt",CFG_FREQ, repeater_cfg_open_counter,  0,       0, avauskerrat)
	REC("St", "USEhrS",CFG_FREQ, transmitter_hours,  0,               0, kÃ¤yttÃ¶tunnit)
	REC("GP", "utc   ",CFG_STR,  gps_utc,            0,               0, HHMMSS)
	REC("GP", "dAtE  ",CFG_STR,  gps_date,           0,               0, YYMMDD)
	REC("GP", "LAt   ",CFG_STR,  cfg_gps_latitude,   0,               0, DDDMMmmN/S)
	REC("GP", "Lon   ",CFG_STR,  cfg_gps_longitude,  0,               0, DDDMMmmE/W)
	REC("GP", "SPEEd ",CFG_BYTE, gps_speed,          0,               0, speed - km/h - 255 = overflow)
	REC("GP", "knotS ",CFG_WORD, gps_knots,          0,               0, knots - solmua)
	REC("GP", "CourSE",CFG_WORD, gps_course,         0,               0, course - degrees)
	REC("GP", "GridSq",CFG_STR,  cfg_gps_locator,    0,               0, Maidenhead)
	REC("GP", "StAtuS",CFG_STR,  gps_status,         0,               0, vastaanoton laatu - sisÃ¤ltÃ¶ laitekohtainen)

	REC("rF", "rFc   ",CFG_DYN,  menu_rfc_change,    draw_rfc_dpy,    0, rx sÃ¤Ã¤tÃ¶arvon asetus vfo MHz:lla)
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
		STR("AiSin")
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

#ifndef C_MODULES	/* c/menu.c, bank 1 */
set_defaults_band:
	ld a, (cfg_synth_card)
	push af
	call reset_menurecords   ; remember radio type during reset
	pop af
	ld (cfg_synth_card), a
	cp #S8B
	ld hl, #defaults_6m
	jr z, 1f
	cp #S8C
	ld hl, #defaults_2m
	jr z, 1f
	ld hl, #defaults_70cm
1:
	ldi_6(cfg_implied)
	ldi_3(cfg_if_freq)
	ldi_3(cfg_rx_vco_center)
	ldi_3(cfg_tx_vco_center)

	ldi_6(cfg_tx_band_start)    ; and end

	ldi_10(cfg_band1_start)    ; and end, duplex, step
	ldi_10(cfg_band2_start)    ; and end, duplex, step

	ldi_3(cfg_other_duplex)
	ldi_1(cfg_other_step)

	call save_nvdata
	jp powerdown_now


get_probable_chstep_de:
	ld a, (cfg_synth_card)
	ld de, #20
	cp #S8B
	ret z
	ld de, #25
	ret


reset_menurecords:
	ld ix, #start_menu
1:
	call reset_menurec
	ld de, #size_menurec
	add ix, de
	push ix
	pop de
	ld a, d
	cp #HI(end_menu)
	jr nz, 1b
	ld a, e
	cp #LO(end_menu)
	jr nz, 1b

	ret

check_for_666:
	call a2i
	sub_ahl_immde(666)
	or h
	or l
	ret

;----------------------------------------------------------------------

sane_defaults:
	call check_for_666
	ret nz
	jp set_defaults_band

disaster:
	call check_for_666
	ret nz

	ld a, (cfg_synth_card)
	ld b, a
	ld hl, #nvstart
1:
	ld (hl), #0
	inc hl
	ld a, h
	cp #HI(nvend)
	jr nz, 1b
	ld a, l
	cp #LO(nvend)
	jr nz, 1b

	ld a, b
	ld (cfg_synth_card), a

	jp set_defaults_band

all_config_send:
	call check_for_666
	ret nz

	ld de, #banner
1:
	ld a, (de)
	inc de
	cp #EOS
	jr z, 1f
	ld c, a
	call putchar          ; banner line
	jr 1b
1:


	ld c, #LO(nvend - nvstart)
	call putchar
	ld c, #HI(nvend - nvstart)
	call putchar          ; length of block in binary word



	ld de, #nvstart
	ld b, #0               ; simple checksum
1:
	ld a, (de)
	inc de

	ld c, a               ; putchar(c)

	add a, b
	ld b, a               ; keep 8-bit running sum

	call putchar          ; destroys a and hl

	ld a, d
	cp #HI(nvend)
	jr nz, 1b
	ld a, e
	cp #LO(nvend)
	jr nz, 1b

	ld a, b
	neg                   ; data+checksum == 0
	ld c, a               ; putchar sends C (v3_Z sent the last data byte again)
	call putchar

	ret


all_config_get:
	call check_for_666
	ret nz

1:
	ld a, (mbusrx_cnt)
	or a
	jr z, 1f
	call getchar          ; purge old
	jr 1b
1:
	call feedback_ready
	call force_redraw

	call getchar
	push af                ; first character of config banner

	call feedback_loading
	call force_redraw

	pop af
1:
	cp #0x0A                ; end of banner ?
	jr z, 1f

	call getchar
	jr 1b
1:

	call getchar
	cp #LO(nvend - nvstart)
	jr nz, all_config_get_failed

	call getchar
	cp #HI(nvend - nvstart)
	jr nz, all_config_get_failed

	ld de, #_end
	ld b, #0               ; simple checksum
1:
	call getchar

	ld (de), a
	inc de

	add a, b
	ld b, a

	ld a, d
	cp #HI(_end + nvend - nvstart)
	jr nz, 1b
	ld a, e
	cp #LO(_end + nvend - nvstart)
	jr nz, 1b                     ; more

	call getchar                  ; checksum byte
	add a, b
	jr nz, all_config_get_failed

	ld hl, #_end
	ld de, #nvstart
1:
	ld a, (hl)
	inc hl
	ld (de), a
	inc de

	ld a, d
	cp #HI(nvend)
	jr nz, 1b
	ld a, e
	cp #LO(nvend)
	jr nz, 1b

	call no_feedback
	call redraw

	ret

all_config_get_failed:

	call feedback_error
	call redraw
	ret


wipe_memories:
	call check_for_666
	ret nz

	ld hl, #memories
1:
	ld (hl), #0
	inc hl
	ld a, h
	cp #HI(end_memories)
	jr nz, 1b
	ld a, l
	cp #LO(end_memories)
	jr nz, 1b

	ret

wipe_rfctab:
	call check_for_666
	ret nz

	ld hl, #rfctab
1:
	ld (hl), #0
	inc hl
	ld a, h
	cp #HI(end_rfctab)
	jr nz, 1b
	ld a, l
	cp #LO(end_rfctab)
	jr nz, 1b

	ret

do_reboot:
	call check_for_666
	ret nz

	di
	jp .                  ; watchdog restart.



#endif /* C_MODULES */

;----- GPS sentence processing (was fixed ROM) -----

#ifndef C_MODULES	/* c/gps.c, bank 2 (the symbol tables: c/aprs.c) */
gps_process_aisin_seiki:

	ld a, e
	sub #44                     ; wind back to start of possible CACA-block
	ld l, a
	ld h, d                    ; HL and DE both in the gps_history page

	ld a, #0xCA
	cp (hl)
	ret nz
	inc l
	cp (hl)
	ret nz
	inc l                      ; HL into start of payload, 40 bytes

	push de

	ld b, #40                   ; 40 bytes between CACA and cksum
	ld c, #0xCA + 0xCA          ; cksum includes these two
	ld de, #gps_sentence        ; copy message into here, easier access later
1:
	ld a, (hl)
	inc l
	ld (de), a
	inc de
	add a, c
	ld c, a
	djnz 1b

	ld a, (hl)                   ; cksum is a complement
	add a, c
	call z, gps_process_aisin_seiki_CACA

	pop de

	ret

gps_process_aisin_seiki_CACA:        ; message in gps_sentence[]

	; [ 0] 1 validity
	;      0 decoded sats 0
	;      1 decoded sats 1
	;      2 decoded sats 2
	;      3 2D fix
	;      4 3D fix
	;    0x10 certain change happened, mask

	ld a, (gps_sentence + 0)

	and #~0x10   ; remove 'changed' mask
	cp #3
	ret c       ; less than 2D fix
	cp #5
	ret nc      ; more than 3D fix ??? that is antenna trouble.

	; Good. Any kind of fix is good enough for us.


	; [ 1] 4 latitude           1/256"    MSByte first
	; [ 5] 4 longitude          1/256"    MSByte first

	ld iy, #gps_sentence + 1
	ld ix, #cfg_gps_latitude
	call aisin_seiki_parse_latlon

	ld iy, #gps_sentence + 5
	ld ix, #cfg_gps_longitude
	call aisin_seiki_parse_latlon


	; From now on, IY is gps_sentence[]  - TAKE NOTE !


	ld iy, #gps_sentence


	; [ 9] 2 height             0.5m       very inaccurate anyway
	; [11] 1 error ellipse 1    2m
	; [12] 1 error ellipse 2    2m

	; [13] 2 heading            360deg/1024    values 0...3FF

	ld h, (iy + 13)
	ld l, (iy + 14)

	push hl               ;  +1      *=45 /=128 converts to degrees
	add hl, hl            ; 2
	add hl, hl            ; 4
	push hl               ;  +4
	add hl, hl            ; 8
	push hl               ;  +8
	add hl, hl            ; 16
	add hl, hl            ; 32

	pop bc
	add hl, bc
	pop bc
	add hl, bc
	pop bc
	add hl, bc            ; 45 times in HL

	rl l                  ; LSbit into CY
	ld l, h               ; 8 MSbits in L
	ld h, #0               ; H will contain only 1 MSbit
	rl h                  ; all bits properly in HL now

	ld (gps_course), hl   ; integer degrees in range 0...359

	; [15] 1 heading error      90deg/256

	; [16] 2 ground speed       1/4 m/s    end 16384 m/s = 31847 knots

	ld h, (iy + 16)
	ld l, (iy + 17)

	push hl                 ; we will make another conversion shortly

	xor a                      ; AHL has speed in 0.25 meter / second
	push hl                    ;  -1
	add hl, hl
	adc a, a          ; 2 times
	add hl, hl
	adc a, a          ; 4 times
	add hl, hl
	adc a, a          ; 8 times
	add hl, hl
	adc a, a          ; 16 times
	add hl, hl
	adc a, a          ; 32 times      cannot overflow - CY clear
	pop bc
	sbc hl, bc
	sbc a, #0                      ; 31 times in AHL
	add hl, hl                 ; shift left
	rla                        ; AHL shifted once
	add hl, hl                 ; shift left again
	rla                        ; AHL shifted twice
	ld l, h
	ld h, a                    ; divided by 64
	ld (gps_knots), hl         ; speed in knots = x * 31 / 64

	pop hl                        ; another conversion ... sigh.

	call quarter_ms_to_kmh
	ld (gps_speed), a          ; speed in km/h

	; [18] 1 ground speed error 1/4 m/s
	; [19] 1 dummy
	; [20] 1 dummy
	; [21] 1 dummy

	; [22] 6 date & time        1s  YYMMDDHHMMSS in packed bcd

	ld hl, #gps_sentence + 22

	ld de, #gps_date
	ld b, #3
1:
	call aisin_seiki_datetime_unpack ; year is % 100
	djnz 1b

	ld de, #gps_utc
	ld b, #3
1:
	call aisin_seiki_datetime_unpack
	djnz 1b

	; too bad it was not date then utc in ram. cannot
	; flip them because their address is fixed by remote cfg conventions.

	; [28] 1 HDOP               0.2
	; [29] 1 VDOP               0.2
	; [30] 1 satellite count
	; [31] 8 satellite used info

	ld hl, #gps_sentence + 31 + 4        ; 1st ... 4th is a PRN bitmap or ...
	ld de, #gps_status
	ld b, #4
1:
	call aisin_seiki_satstat_unpack     ; 5th ... 8th byte more interesting
	djnz 1b

	; [39] 1 dummy

	jp gps_information_has_been_updated ; finished.


;------------

	; These two routines are exactly the same.

aisin_seiki_datetime_unpack:            ; packed bcd to two unpacked 0 ... 9
aisin_seiki_satstat_unpack:             ; two nybbles into two hex digits 0 ... F

	ld a, (hl)
	rrca
	rrca
	rrca
	rrca
	call 1f              ; tens

	ld a, (hl)
	inc hl
1:
	and #0x0F
	ld (de), a           ; ones
	inc de

	ret

;---------------------------------------------

; length in C, kept, Z = good.

gps_checksum:

	ld hl, #gps_sentence ; $ is not saved in the buffer
	ld b, c             ; keep c, downcount b
	ld e, #0             ; checksum seed
1:
	ld a, (hl)
	inc hl
	cp #'*'
	jr z, 1f
	xor e
	ld e, a
	djnz 1b
2:
	or #1                ; NZ
	ret                 ; too short.
1:
	ld a, b
	cp #2
	jr c, 2b            ; too short.
	ld a, (hl)
	inc hl
	call hexchr_to_bin
	jr c, 2b            ; illegal character in checksum
	rla
	rla
	rla
	rla
	and #0xF0
	ld b, a
	ld a, (hl)
	inc hl
	call hexchr_to_bin
	jr c, 2b
	or b
	cp e	            ; checksum mismatch ? NZ if so
	ret


;
;  only A and some flags change here. NC = good.
;
hexchr_to_bin:
	sub #'0'          ; 3 ranges: 0-9, A-F, a-f
	ret c            ; below 0
	cp #10
	ccf
	ret nc           ; 0-9
	sub #'A' - '0'
	ret c            ; below A
	cp #6
	jr c, 1f         ; A-F
	sub #'a' - 'A'
	ret c            ; below a
	cp #6
	jr c, 1f         ; a-f
	scf              ; above f
	ret
1:
	add a, #10           ; 0xA...0xF. carry will be clear
	ret

symbol_nibble_to_primary_symbol:
	.db 'p' ;  0   rover (puppy dog)
	.db '>' ;  1   car
	.db 'v' ;  2   van
	.db 's' ;  3   ship (power boat)
	.db '-' ;  4   house
	.db '+' ;  5   red cross
	.db 'r' ;  6   antenna
	.db 'c' ;  7   orienteering marker
	.db '0' ;  8   (0)
	.db '1' ;  9   (1)
	.db '2' ;  A   (2)
	.db '3' ;  B   (3)
	.db '4' ;  C   (4)
	.db '5' ;  D   (5)
	.db '6' ;  E   (6)
	          ;  F indirect symbol:   take symbol from SSID

ssid_nibble_to_primary_symbol:
	.db '/' ;   0 Dot (indirect from MPRS symbol 15 and SSID 0)
	.db 'a' ;   1 ambulance
	.db 'U' ;   2 bus
	.db 'f' ;   3 fire truck
	.db 'b' ;   4 bicycle
	.db 'Y' ;   5 yacht
	.db 'X' ;   6 helicopter
	.db 0x27 ;   7 small aircraft
	.db 's' ;   8 ship (power boat)
	.db '>' ;   9 car
	.db '<' ;  10 motorcycle
	.db 'O' ;  11 balloon
	.db 'j' ;  12 jeep
	.db 'R' ;  13 recreational vehicle
	.db 'k' ;  14 truck
	.db 'v' ;  15 van

str_gprmc: .asciz "GPRMC,"

; length in c-reg

gps_process_sentence:

	ld hl, #gps_sentence
	ld de, #str_gprmc
	ld b, c              ; keep c, downcount b
1:
	ld a, (de)
	or a
	jr z, 2f             ; matched pattern to end
	cp (hl)
	ret nz               ; mismatch, not GPRMC
	inc hl
	inc de
	djnz 1b
	ret                  ; huh ?
2:
	call gps_checksum
	ret nz               ; corrupt
	jr gps_process_gprmc

; length in c-reg  ============================

gps_process_gprmc:

	; GPRMC,212909.00,A,4915.607,N,12310.537,W,000.0,360.0,111198,020.3,E*68
	; HHMMSS might have .NN decimal seconds.

	ld hl, #gps_sentence

	inc hl
	inc hl
	inc hl
	inc hl
	inc hl
	inc hl    ; skip tag and first comma "GPRMC,"

	; 225446     Time of fix 22:54:46 UTC ------------------------------------

	ld de, #gps_utc
	ld b, #6
1:
	ld a, (hl)
	inc hl
	sub #'0'
	ret c            ; not '0'...'9'
	ld (de), a
	inc de
	djnz 1b

	ld a, #EOS
	ld (de), a
	inc de
	ld (de), a

1:
	ld a, (hl)
	inc hl
	cp #','
	jr z, 1f          ; comma after utc, end of field.
	cp #'.'
	jr z, 1b          ; decimal point (any number of them accepted)
	sub #'0'
	ret c            ; less than digit
	cp #10
	ret nc             ; over 9
	jr 1b                     ; otherwise keep looking for comma.
1:


	; A          Navigation receiver warning A = OK, V = warning -------------

	ld a, (hl)
	inc hl
	cp #'A'
	ret nz            ; not A = OK, Navigation receiver warning

	ld a, (hl)
	inc hl
	cp #','
	ret nz            ; missing comma after A/V status

	; 4916.45,N  Latitude 49 deg. 16.45 min North ----------------------------

	ld ix, #cfg_gps_latitude

	ld bc, #0
	ld de, #0
1:
	ld a, (hl)
	inc hl
	cp #'.'
	jr z, 1f
	sub #'0'
	ret c            ; other than decimal point or numbers
	ld (ix+0), b
	ld b, c
	ld c, d
	ld d, e
	ld e, a
	jr 1b
1:
	ld (ix+1), b
	ld (ix+2), c
	ld (ix+3), d
	ld (ix+4), e

	; decimal minutes

	ld de, #0

	ld a, (hl)
	inc hl
	cp #','
	jr z, 1f
	sub #'0'
	ret c            ; other than numbers before the ending comma
	ld d, a                   ; 0.1 minutes

	ld a, (hl)
	inc hl
	cp #','
	jr z, 1f
	sub #'0'
	ret c            ; other than numbers before the ending comma
	ld e, a                   ; 0.xx minutes ready (rest is ignored)

2:
	ld a, (hl)
	inc hl
	cp #','
	jr z, 1f          ; no more decimals
	sub #'0'
	ret c            ; other than numbers before the ending comma
	jr 2b
1:
	ld (ix+5), d
	ld (ix+6), e

	ld a, (hl)
	inc hl
	ld (ix+7), a               ; N/S character

	ld a, (hl)
	inc hl
	cp #','
	ret nz            ; comma after North/South

	; 12311.12,W Longitude 123 deg. 11.12 min West ---------------------------

	ld ix, #cfg_gps_longitude

	ld bc, #0
	ld de, #0
1:
	ld a, (hl)
	inc hl
	cp #'.'
	jr z, 1f
	sub #'0'
	ret c            ; other than decimal point or numbers
	ld (ix+0), b
	ld b, c
	ld c, d
	ld d, e
	ld e, a
	jr 1b
1:
	ld (ix+1), b
	ld (ix+2), c
	ld (ix+3), d
	ld (ix+4), e

	; decimal minutes

	ld de, #0

	ld a, (hl)
	inc hl
	cp #','
	jr z, 1f
	sub #'0'
	ret c            ; other than numbers before the ending comma
	ld d, a                   ; 0.1 minutes

	ld a, (hl)
	inc hl
	cp #','
	jr z, 1f
	sub #'0'
	ret c            ; other than numbers before the ending comma
	ld e, a                   ; 0.01 minutes

2:
	ld a, (hl)
	inc hl
	cp #','
	jr z, 1f          ; no more decimals
	sub #'0'
	ret c            ; other than comma or numbers
	jr 2b
1:
	ld (ix+5), d
	ld (ix+6), e

	ld a, (hl)
	inc hl
	ld (ix+7), a               ; E/W character

	ld a, (hl)
	inc hl
	cp #','
	ret nz            ; comma after East/West

	; 000.5      Speed over ground, Knots ------------------------------------

	ld ix, #0               ; 65 kiloknots and overflow is NOT checked XXX
1:
	ld a, (hl)
	inc hl
	cp #','
	jr z, 1f
	cp #'.'
	jr z, 2f
	sub #'0'
	ret c
	add ix, ix
	push ix
	pop de
	add ix, ix
	add ix, ix
	add ix, de     ; *= 10
	ld d, #0
	ld e, a
	add ix, de     ; += ones
	jr 1b
2:
	ld a, (hl)
	inc hl
	cp #','
	jr z, 1f
	cp #'5'
	jr c, 2f
		inc ix                ; round up
	2:
		ld a, (hl)
		inc hl
		cp #','
		jr z, 1f
		sub #'0'
		ret c
		jr 2b
1:
	ld (gps_knots), ix         ; speed in knots

	push hl                ; save pointer

	push ix                ; copy ix ...
	pop hl                 ; ... to hl
	call knots_to_kmh
	ld (gps_speed), a      ; speed in km/h - limited to 255 km/h

	pop hl                 ; restore pointer

	; 054.7      Course Made Good, True --------------------------------------

	ld ix, #0
1:
	ld a, (hl)
	inc hl
	cp #','
	jr z, 1f
	cp #'.'
	jr z, 2f
	sub #'0'
	ret c
	add ix, ix
	push ix
	pop de
	add ix, ix
	add ix, ix
	add ix, de     ; *= 10
	ld d, #0
	ld e, a
	add ix, de     ; += ones
	jr 1b
2:
	ld a, (hl)
	inc hl
	cp #','
	jr z, 1f
	cp #'5'
	jr c, 2f
		inc ix                ; round up
	2:
		ld a, (hl)
		inc hl
		cp #','
		jr z, 1f
		sub #'0'
		ret c
		jr 2b
1:
	ld (gps_course), ix

	; 191194     Date of fix  19 November 1994 -------------------------------

	ld ix, #gps_date         ; yymmdd

	ld a, (hl)
	inc hl
	sub #'0'
	ret c            ; not '0'...'9'
	ld (ix+4), a
	ld a, (hl)
	inc hl
	sub #'0'
	ret c            ; not '0'...'9'
	ld (ix+5), a

	ld a, (hl)
	inc hl
	sub #'0'
	ret c            ; not '0'...'9'
	ld (ix+2), a
	ld a, (hl)
	inc hl
	sub #'0'
	ret c            ; not '0'...'9'
	ld (ix+3), a

	ld a, (hl)
	inc hl
	sub #'0'
	ret c            ; not '0'...'9'
	ld (ix+0), a
	ld a, (hl)
	inc hl
	sub #'0'
	ret c            ; not '0'...'9'
	ld (ix+1), a

	ld a, #EOS
	ld (ix+6), a
	ld (ix+7), a

	ld a, (hl)
	inc hl
	cp #','
	ret nz            ; missing comma after date

	; 020.3,E    Magnetic variation 20.3 deg East ----------------------------

	; XXX don't care about those. ------------------------------

gps_information_has_been_updated:

	call gps_own_locator  ; turn lat/lon into maidenhead grid square

	ld a, #5
	ld (gps_valid_seconds), a

	ld a, (menu_active)
	or a
	jp nz, redraw          ; redraw if in menu - in case GPSxxx display

	ret
#endif /* C_MODULES */

;======================================================================

; execute [script_req] if it is nonzero.


;----- MPRS/APRS/MIC-E packets and locator maths (was fixed ROM) -----
#ifndef C_MODULES	/* c/aprs.c, bank 2 */

handle_mprs_packets:               ; 4x-packets
	inc l
	ld a, (hl)                      ; XXX minor digit ignored for now
	inc l

	ld ix, #mprs_packed_packet
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (ix+0), a     ; callsign
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (ix+1), a
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (ix+2), a
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (ix+3), a
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (ix+4), a
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (ix+5), a

	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (ix+6), a     ; lat
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (ix+7), a
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (ix+8), a

	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (ix+9), a      ; lon
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (ix+10), a
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (ix+11), a

	call mute_fsk_at_mprs_end_maybe

	ld ix, #mprs_packed_packet
	ld de, #remote_display_buffer
	call packet_callsign_unpack

	ld a, #EOS
	ld (remote_display_buffer + 6), a     ; 6 characters are valid in packet
	ld (remote_display_buffer + 7), a
	ld (remote_display_buffer + 8), a
	ld (remote_display_buffer + 9), a     ; 10 will be displayed from buffer
	ld (remote_display_buffer + 10), a    ; barrier

	ld hl, #remote_display_buffer - 1     ; step over nonblanks to add (-NN and) EOS
1:
	inc hl
	ld a, (hl)
	cp #EOS
	jr z, 1f                        ; already ends in EOS
	cp #' '
	jr nz, 1b                       ; more valid chars

	ld (hl), #EOS                    ; only call now, HL left over end
1:

	ld a, (mprs_packed_packet + 4)
	and #0xF0                              ; SSID ?
	jr z, 1f                              ; no -NN if SSID was 0
		ld (hl), #'-'
		inc hl

		rra
		rra
		rra
		rra
		and #0xF
		cp #10
		jr c, 2f
			ld (hl), #'1'                  ; always 1x if over 9
			inc hl
			sub #10                        ; ones
	2:
		add a, #'0'
		ld (hl), a                        ; 6 + "-15" always fits buffer[10]
		inc hl

		ld (hl), #EOS
1:

	ld ix, #mprs_packed_packet + 6      ; lat/lon/symbol ?
	ld a, (ix)
	and #0x80
	jr nz, 1f                          ; skip if reserved data
		ld iy, #locator_display_buffer
		call packed_latlon_to_locator

		ld a, #EOS
		ld (locator_display_buffer + 6), a
		ld (locator_display_buffer + 7), a

		ld a, (cfg_mbus_mprs)
		or a
		call nz, mbus_mprs_call_latlon     ; blurt it out MBUS too

		ld a, (cfg_gps_upload)
		or a
		call nz, gps_mprs_call_latlon     ; blurt it out into GPS

		ld a, (cfg_remote_dpy_secs)
		ld (locator_dpyed), a

		call mprs_qrb
1:
	ld a, (cfg_remote_dpy_secs)
	ld (display_buffer_time), a
	or a
	call nz, redraw

	ret

packed_latlon_to_locator:

	ld a, (ix+0)             ; lat degrees ================================
	and #0x7F                 ; mask off reserved bit
	ld c, #'J' - 1
1:
	inc c
	sub #10                   ; 10 degrees per letter
	jr nc, 1b
	add a, #10 + '0'             ; has has degrees % 10, into ascii direct
	ld (iy+1), c
	ld (iy+3), a

	ld a, #50
	cp (ix+2)                ; one halfminute from decimal minutes maybe
	ld a, (ix+1)             ; lat minutes
	rl a                     ; turn to total halfminutes
	and #0x7F                 ; mask off remaining symbol bit
	ld c, #'A' - 1
1:
	inc c
	sub #5                    ; 5 minutes per halfminutes or letter
	jr nc, 1b
	add a, #5                    ; minor digit in the making
	ld (iy+5), c             ; minor letter ok.
	ld c, a
	sla c                    ; minor letter, now missing lsbit
	ld a, (ix+2)
	cp #50
	jr c, 1f
	sub #50                   ; delete half a minute
1:                           ; even/odd quarter ok
	cp #25
	jr c, 1f                 ; skip if even quarter
	inc c                    ; lsbit ok
1:
	ld a, c
	add a, #'0'
	ld (iy+7), a             ; minor digit ok.

	ld a, (ix+2)             ; Correction for South ?
	and #0x80
	jr z, 1f                 ; no, skip
	ld a, #'I'
	sub (iy+1)
	add a, #'J'
	ld (iy+1), a             ; 'I' - chr + 'J'
	ld a, #'9'
	sub (iy+3)
	add a, #'0'
	ld (iy+3), a             ; '9' - chr + '0'
	ld a, #'L'
	sub (iy+5)
	add a, #'M'
	ld (iy+5), a             ; 'L' - chr + 'M'
	ld a, #'9'
	sub (iy+7)
	add a, #'0'
	ld (iy+7), a             ; '9' - chr + '0'
1:

	ld a, (ix+3)             ; lon degrees ===============================
	ld c, #'J' - 1
1:
	inc c
	sub #20                   ; 20 degrees per letter
	jr nc, 1b
	add a, #20                   ; has has degrees % 20
	srl a                    ; has has degrees % 10
	push af                  ; remember carry -----------------------
	add a, #'0'                  ; into ascii
	ld (iy+0), c             ; major letter ok.
	ld (iy+2), a             ; major digit ok.

	ld a, (ix+4)             ; lon minutes
	and #0x3F                 ; mask off symbol bits
	ld c, a
	pop af                   ; even/odd degree from above
	ld a, c
	jr nc, 1f
	add a, #60                   ; 24 small squares in 2 degrees
1:
	ld c, #'A' - 1
1:
	inc c
	sub #5                    ; 5 minutes per letter
	jr nc, 1b
	add a, #5                    ; A has minutes modulo 5
	ld (iy+4), c             ; minor letter ok.
	ld c, a
	ld a, #50
	cp (ix+5)                ; lon hundredths of minutes
	rl c                     ; add lsbit.
	ld a, c
	add a, #'0'
	ld (iy+6), a             ; minor digit ok.

	sla a
	ld a, (ix+5)             ; Correction for West ?
	and #0x80
	jr z, 1f                 ; no, skip
	ld a, #'I'
	sub (iy+0)
	add a, #'J'
	ld (iy+0), a             ; 'I' - chr + 'J'
	ld a, #'9'
	sub (iy+2)
	add a, #'0'
	ld (iy+2), a             ; '9' - chr + '0'
	ld a, #'L'
	sub (iy+4)
	add a, #'M'
	ld (iy+4), a             ; 'L' - chr + 'M'
	ld a, #'9'
	sub (iy+6)
	add a, #'0'
	ld (iy+6), a             ; '9' - chr + '0'
1:

	ret


gps_own_locator:

	ld ix, #gps_latlon_tmp    ; temporarily into binary

	ld iy, #cfg_gps_latitude
	ld e, #2
	ASSERT_EQ(cfg_gps_longitude, cfg_gps_latitude + 8)
2:
	ld a, (iy)
	inc iy
	or a
	jr z, 1f
	ld a, #100
1:
	ld d, a
	ld b, #3       ; deg(rest of) and min and decimal min
1:
	ld a, (iy+0)  ; tens
	add a, a         ; 2
	ld c, a
	add a, a         ; 4
	add a, a         ; 8
	add a, c         ; 10
	add a, (iy+1)    ; ones
	add a, d         ; one loysy 1xx in longitude
	ld d, #0
	inc iy
	inc iy
	ld (ix), a
	inc ix
	djnz 1b

	ld a, (iy+0)
	inc iy
	cp #'N'
	jr z, 1f
	cp #'W'
	jr nz, 1f
	dec ix
	ld a, (ix)
	or #0x80
	ld (ix), a
	inc ix
1:
	dec e
	jr nz, 2b    ; longitude

	ld ix, #gps_latlon_tmp
	ld iy, #cfg_gps_locator        ; final location of locator string

	jp packed_latlon_to_locator


;----------------------------------------------------------------------
; input: A degrees, B minutes and C hundredths of minutes without signs.
; output: centiminutes in AHL

degmin_to_centiminutes:

	ld l, a            ; degrees from A-reg ------------------------
	ld h, #0            ; 180 max, minutes will fit HL
	add hl, hl         ; 2 times
	add hl, hl         ; 4 times
	push hl
	add hl, hl         ; 8 times
	add hl, hl         ; 16 times
	add hl, hl         ; 32 times
	add hl, hl         ; 64 times, carry clear
	pop de
	sbc hl, de         ; - 4 times, HL has degrees as minutes

	ld e, b            ; minutes from B-reg ------------------------
	ld d, #0
	add hl, de         ; HL has integer minutes
	xor a            ; extend to AHL.

	add hl, hl
	adc a, a  ; 2 times
	add hl, hl
	adc a, a  ; 4 times
	push af
	push hl
	add hl, hl
	adc a, a  ; 8 times
	add hl, hl
	adc a, a  ; 16 times
	add hl, hl
	adc a, a  ; 32 times
	push af
	push hl
	add hl, hl
	adc a, a  ; 64 times

	pop de
	add hl, de
	pop de
	adc a, d              ; + 32 times

	pop de
	add hl, de
	pop de
	adc a, d              ; + 4 times, HL has integer minutes as centiminutes

	ld b, #0            ; fractional minutes from C-reg -------------
	add hl, bc
	adc a, #0  ; AHL has full centiminutes

	ret

; input: A degrees, B minutes and C hundredths of minutes and sign-bit
; result: AHL centiminutes north from south pole (0...1'080'000)

degmin_to_centiminutes_from_south_pole:
	push bc                 ; remember hemisphere
	res 7, a                ; mask sign- etc bits off
	res 7, b
	res 6, b
	res 7, c
	call degmin_to_centiminutes  ; ABC -> AHL
	pop bc
	bit 7, c                ; south ?
	call nz, negate_ahl     ; 90 - x (else 90 + x)

	ld de, #(90 * 60 * 100) % 65536
	add hl, de
	adc    a, #(90 * 60 * 100) / 65536
	ret                     ; AHL has result

; input: A degrees, B minutes and C hundredths of minutes and sign-bit
; result: AHL signed centiminutes from greenwich (+/- 0...1'080'000)

degmin_to_centiminutes_from_meridian:
	push bc                 ; remember hemisphere
	res 7, a                ; mask sign- etc bits off
	res 7, b
	res 6, b
	res 7, c
	call degmin_to_centiminutes  ; ABC -> AHL
	pop bc
	bit 7, c                ; west ?

	call nz, negate_ahl     ; make signed, - for west.

	ret                     ; AHL has result


mul_ahl_1852:           ; 2048 - 128 - 64 - 4

	add hl, hl
	adc a, a   ;    2 times
	add hl, hl
	adc a, a   ;    4 times
	push af
	push hl
	add hl, hl
	adc a, a   ;    8 times
	add hl, hl
	adc a, a   ;   16 times
	add hl, hl
	adc a, a   ;   32 times
	add hl, hl
	adc a, a   ;   64 times
	push af
	push hl
	add hl, hl
	adc a, a   ;  128 times
	push af
	push hl
	add hl, hl
	adc a, a   ;  256 times
	add hl, hl
	adc a, a   ;  512 times
	add hl, hl
	adc a, a   ; 1024 times
	add hl, hl
	adc a, a   ; 2048 times
	pop de
	pop bc
	and a
	sbc hl, de
	sbc a, b   ; - 128 times
	pop de
	pop bc
	sbc hl, de
	sbc a, b   ; - 64 times
	pop de
	pop bc
	sbc hl, de
	sbc a, b   ; - 4 times = 1852 times.

	ret


centiminutes_to_1852_meters:

	ld c, #100
	call div248         ; HL has full minutes, A has hundredths of minutes

	push hl             ; remember full minutes for a while

	ld l, a             ; decimal minutes
	xor a
	ld h, a
	call mul_ahl_1852

	ld c, #100
	call div248         ; HL has last few meters from decimal mins.

	pop bc              ; get full minutes now
	push hl             ; save last few meters

	ld l, c
	ld h, b
	xor a
	call mul_ahl_1852

	pop de
	add hl, de          ; add the last 1.8 kilometers
	adc a, #0

	ret


; AHL centiminutes to AHL meters (DE is multiplier: meters / minute)

centiminutes_to_meters:

	ld c, #100
	call div248         ; HL has full minutes, A has hundredths of minutes

	push hl             ; remember full minutes for a while
	ld hl, #0            ; start to accumulate

	ld b, a             ; decimal minutes ?
	xor a               ; (v3_Z kept them in A: + hundredths * 655 m)
	inc b
	dec b
	jr z, 2f            ; happens to be none.
1:
	add hl, de
	adc a, #0
	djnz 1b             ; continue adding 0.01 * minute     max 100 loops

	ld c, #100
	call div248         ; HL has last 1.8 kilometers from decimal mins.
2:
	xor a               ; AHL has.

	pop bc              ; get full minutes now
	push bc
	inc c               ; full minutes % 256 ?
	dec c
	jr z, 2f            ; happens to be none.
	ld b, c
1:
	add hl, de          ; meters per minute
	adc a, #0
	djnz 1b             ; continue adding 1 * minute     max 256 loops
2:
	pop bc              ; full minutes / 256 ?
	ld c, d             ; (after the pop: v3_Z lost C, the upper byte of
	ld d, e             ; the multiplier, to the minutes' low byte)
	ld e, #0             ; now upper byte of full minute

	inc b
	dec b
	jr z, 2f
1:
	add hl, de
	adc a, c
	djnz 1b             ; continue adding 256 * minute  max 256 loops
2:
	ret


; align AHL centiminutes between -180 and +180 degrees. what a mess.

delta_longitude_fixup:

	; < -180 ? add 180 two times
	; > +180 ? sub 180 two times

	ld de, #(180 * 60 * 100) % 65536
	ld b,  #(180 * 60 * 100) / 65536

	bit 7, a
	jr nz, 2f       ; go if difference is negative, maybe add 360 once.

	and a
	sbc hl, de
	sbc a, b
	jr c, 1f            ; was less than +180, undo
	sbc hl, de          ; again to get -= 360
	sbc a, b
	ret
1:
	add hl, de
	adc a, b
	ret
2:
	add hl, de
	adc a, b
	jr c, 1f             ; was more positive than -180, undo
	add hl, de           ; again to get += 360
	adc a, b
	ret
1:
	and a
	sbc hl, de
	sbc a, b
	ret

mprs_qrb_dir_char:
	bit 2, a
	jr nz, 1f      ; E/W direction.

	bit 0, a       ; N/S ?
	ld a, #'N'
	ret nz
	ld a, #'S'
	ret
1:
	bit 1, a       ; E/W ?
	ld a, #'E'
	ret nz
	ld a, #'W'
	ret


; flat-model
; XXX near poles, use cone-model

mprs_qrb:

	ld iy, #cfg_gps_latitude            ; my latitude
	ld ix, #my_coord_tmp_6bytes + 0
	call mprs_degmin_pack

	ld iy, #cfg_gps_longitude           ; my longitude
	ld ix, #my_coord_tmp_6bytes + 3
	call mprs_degmin_pack

	xor a
	ld (mprs_qrb_dir_bits), a          ; direction.

	; latitude calculations

	ld ix, #mprs_packed_packet + 6      ; his/hers latitude
	ld a, (ix+0)
	ld b, (ix+1)
	ld c, (ix+2)
	call degmin_to_centiminutes_from_south_pole
	push af
	push hl                            ; remember his latitude

	ld ix, #my_coord_tmp_6bytes + 0     ; my latitude
	ld a, (ix+0)
	ld b, (ix+1)
	ld c, (ix+2)
	call degmin_to_centiminutes_from_south_pole

	pop de               ; now sub his latitude
	and a
	sbc hl, de
	pop de
	sbc a, d              ; AHL has signed latitude difference in centiminutes
	jr nc, 1f

	call negate_ahl

	ld iy, #mprs_qrb_dir_bits
	set 0, (iy)         ; he/she is north from me
1:

	; AHL has abs(latitude centiminutes), turn into distance

	call centiminutes_to_1852_meters

	push af
	push hl            ; remember northwise difference in meters



	; longitude calculations

	ld ix, #mprs_packed_packet + 9      ; his/hers longitude
	ld a, (ix+0)
	ld b, (ix+1)
	ld c, (ix+2)
	call degmin_to_centiminutes_from_meridian

	push af
	push hl                            ; remember his longitude

	ld ix, #my_coord_tmp_6bytes + 3     ; my longitude
	ld a, (ix+0)
	ld b, (ix+1)
	ld c, (ix+2)
	call degmin_to_centiminutes_from_meridian

	pop de                  ; now sub his longitude
	and a
	sbc hl, de
	pop de
	sbc a, d          ; AHL has signed longitude difference in centiminutes

	call delta_longitude_fixup

	bit 7, a
	jr z, 1f

	call negate_ahl

	ld iy, #mprs_qrb_dir_bits
	set 1, (iy)         ; he/she is east from me
1:

	; AHL has abs(longitude delta), turn into distance

	ld ix, #my_coord_tmp_6bytes + 0     ; my latitude
	ld d, #0
	ld e, (ix+0)
	sla e
	ld ix, #minutes_to_meters_wrt_latitude_degree
	add ix, de
	ld e, (ix+0)
	ld d, (ix+1)
	call centiminutes_to_meters


	pop de
	pop bc              ; BDE has nortwise meters
	ld c, a             ; CHL has eastwise meters

	; which of them is longer ?

	ld ix, #my_coord_tmp_6bytes + 0
	ld (ix+0), e
	ld (ix+1), d
	ld (ix+2), b        ; northwise in ix

	ld iy, #my_coord_tmp_6bytes + 3
	ld (iy+0), l
	ld (iy+1), h
	ld (iy+2), c        ; eastwise in iy

	and a
	sbc hl, de
	sbc a, b
	jr c, 1f             ; major axis is N/S in ix, BDE

	ld ix, #my_coord_tmp_6bytes + 3
	ld iy, #my_coord_tmp_6bytes + 0  ; now major axis is in ix

	ld hl, #mprs_qrb_dir_bits
	set 2, (hl)          ; remember the direction major axis is E/W
1:

	; simple distance approximation
	; distance = major + minor * 83 / 256
	; less than %5 error except 7% at 45 degrees directions

	ld e, (iy+0)
	ld d, (iy+1)
	ld l, (iy+2)
	ld h, #0
	push de
	pop iy               ; minor axis in HLIY

	push hl              ; remember 1 times
	push iy

	add iy, iy
	adc hl, hl    ;  2 times
	add iy, iy
	adc hl, hl    ;  4 times
	add iy, iy
	adc hl, hl    ;  8 times
	add iy, iy
	adc hl, hl    ; 16 times
	push hl              ; remember 16 times
	push iy
	add iy, iy
	adc hl, hl    ; 32 times
	add iy, iy
	adc hl, hl    ; 64 times
	pop de               ; get 16 times
	pop bc
	add iy, de
	adc hl, bc    ; + 16 times
	pop de
	pop bc               ; get one times
	add iy, de
	adc hl, bc    ; + 1 times
	add iy, de
	adc hl, bc    ; + 1 times
	add iy, de
	adc hl, bc    ; + 1 times, totals 83 times

	push iy
	pop de               ; in HLDE
	ld e, d
	ld d, l
	ld c, h              ; divided by 256, in CDE

	ld l, (ix+0)
	ld h, (ix+1)
	ld a, (ix+2)
	add hl, de
	adc a, c                ; distance meters complete in AHL.

	ld (ix+0), l
	ld (ix+1), h
	ld (ix+2), a         ; save for a while

	; determine scale 

	and a

	ld de, #1000
	sbc hl, de
	sbc a, #0
	ld l, (ix+0)
	ld h, (ix+1)
	ld a, (ix+2)
	ld b, #0                  ; assume scale 1, zero trailing "0"
	jr c, mprs_qrb_present   ; already < 1000, skip stuff at 1f

	ld de, #10000
	sbc hl, de
	sbc a, #0
	ld l, (ix+0)
	ld h, (ix+1)
	ld a, (ix+2)
	inc b              ; trailing "0"
	ld c, #10           ; divider to get the significant part
	jr c, 1f

	ld de, #100000 % 65536
	sbc hl, de
	sbc    a, #100000 / 65536
	ld l, (ix+0)
	ld h, (ix+1)
	ld a, (ix+2)
	inc b              ; trailing "00"
	ld c, #100          ; divider is 100
	jr c, 1f

	ld de, #1000000 % 65536
	sbc hl, de
	sbc    a, #1000000 / 65536
	ld l, (ix+0)
	ld h, (ix+1)
	ld a, (ix+2)
	inc b               ; trailing "000"

	ret nc     ; "too far"

	; AHL / 100 / 10 some extra dancing.

	ld c, #100
	call div248
	xor a             ; extend back for another div

	ld c, #10            ; again to get the total /= 1000

	; fall thru
1:
	; scale down by C, keep B valid.

	call div248         ; AHL / C => HL

	; fall thru

mprs_qrb_present:

	; scaled to less than 1000
	;
	; HL has 0...999 and
	; B has number of trailing zeroes vs meters.

	ld iy, #distance_bearing

	ld c, #'.'      ; decimal point
	inc b          ; preincrement to use djnz

	djnz 1f
	ld (iy), c     ; .999  kilometers
	inc iy
1:
	ld a, #-1
	ld de, #100     ; /= 100
	and a          ; for sbc hl
1:
	inc a
	sbc hl, de
	jr nc, 1b      ;                                   max 9 loops
	add hl, de     ; correct remainder

	ld (iy), a     ; first digit
	inc iy

	djnz 1f
	ld (iy), c     ; 9.99
	inc iy
1:
	ld a, l        ; remaining 0...99 fits A
	ld e, #-1
1:
	inc e
	sub #10         ; /= 10
	jr nc, 1b      ;                                   max 9 loops
	add a, #10         ; and the remainder for third significant (ha!) place.

	ld (iy), e     ; second digit
	inc iy

	djnz 1f
	ld (iy), c     ; 99.9
	inc iy
1:
	ld (iy), a     ; third (last) digit
	inc iy

	dec b
	jr z, 1f       ; 3 trailing zeroes
	ld c, #0        ; 4 trailing zeroes, no decimal point but a "0"
1:
	ld (iy), c     ; 999. or 9990
	inc iy

	ld a, #' '
	ld (iy), a     ; blank separator for "xxxx d" format
	inc iy

	; direction character as the sixth in buffer

	ld a, (mprs_qrb_dir_bits)
	call mprs_qrb_dir_char

	ld (iy+0), a
	ld a, #EOS
	ld (iy+1), a

	ret            ; Whew.

;----------------------------------------------------------------------

minutes_to_meters_wrt_latitude_degree:
	.dw 1852 ;  0
	.dw 1852 ;  1
	.dw 1851 ;  2
	.dw 1849 ;  3
	.dw 1847 ;  4
	.dw 1845 ;  5
	.dw 1842 ;  6
	.dw 1838 ;  7
	.dw 1834 ;  8
	.dw 1829 ;  9
	.dw 1824 ; 10
	.dw 1818 ; 11
	.dw 1812 ; 12
	.dw 1805 ; 13
	.dw 1797 ; 14
	.dw 1789 ; 15
	.dw 1780 ; 16
	.dw 1771 ; 17
	.dw 1761 ; 18
	.dw 1751 ; 19
	.dw 1740 ; 20
	.dw 1729 ; 21
	.dw 1717 ; 22
	.dw 1705 ; 23
	.dw 1692 ; 24
	.dw 1678 ; 25
	.dw 1665 ; 26
	.dw 1650 ; 27
	.dw 1635 ; 28
	.dw 1620 ; 29
	.dw 1604 ; 30
	.dw 1587 ; 31
	.dw 1571 ; 32
	.dw 1553 ; 33
	.dw 1535 ; 34
	.dw 1517 ; 35
	.dw 1498 ; 36
	.dw 1479 ; 37
	.dw 1459 ; 38
	.dw 1439 ; 39
	.dw 1419 ; 40
	.dw 1398 ; 41
	.dw 1376 ; 42
	.dw 1354 ; 43
	.dw 1332 ; 44
	.dw 1310 ; 45
	.dw 1287 ; 46
	.dw 1263 ; 47
	.dw 1239 ; 48
	.dw 1215 ; 49
	.dw 1190 ; 50
	.dw 1166 ; 51
	.dw 1140 ; 52
	.dw 1115 ; 53
	.dw 1089 ; 54
	.dw 1062 ; 55
	.dw 1036 ; 56
	.dw 1009 ; 57
	.dw  981 ; 58
	.dw  954 ; 59
	.dw  926 ; 60
	.dw  898 ; 61
	.dw  869 ; 62
	.dw  841 ; 63
	.dw  812 ; 64
	.dw  783 ; 65
	.dw  753 ; 66
	.dw  724 ; 67
	.dw  694 ; 68
	.dw  664 ; 69
	.dw  633 ; 70
	.dw  603 ; 71
	.dw  572 ; 72
	.dw  541 ; 73
	.dw  510 ; 74
	.dw  479 ; 75
	.dw  448 ; 76
	.dw  417 ; 77
	.dw  385 ; 78
	.dw  353 ; 79
	.dw  322 ; 80
	.dw  290 ; 81
	.dw  258 ; 82
	.dw  226 ; 83
	.dw  194 ; 84
	.dw  161 ; 85
	.dw  129 ; 86
	.dw   97 ; 87
	.dw   65 ; 88
	.dw   32 ; 89


;----------------------------------------------------------------------


; OH5NXO-1>APRS:!6103.52N/02806.18E>

mbus_mprs_call_latlon:

	ld a, (cfg_mbus_mprs)      ; how exactly ?
	cp #4
	jr z, mbus_mprs_out_logger  ; different from the others below


	ld de, #mbus_mprs_buffer     ; format message like !6103.52N/02806.18E>


	ld a, #'!'
	ld (de), a
	inc de

	ld ix, #mprs_packed_packet + 6
	call mprs_lat_format
	ld a, (ix+2)
	and #0x80
	ld a, #'N'
	jr z, 1f
	ld a, #'S'
1:
	ld (de), a
	inc de

	ld a, #'/'                   ; Primary symbol table
	ld (de), a
	inc de

	ld ix, #mprs_packed_packet + 9
	call mprs_lon_format
	ld a, (ix+2)
	and #0x80
	ld a, #'E'
	jr z, 1f
	ld a, #'W'
1:
	ld (de), a
	inc de

	ld a, (mprs_packed_packet + 6 + 1)
	and #0xC0
	srl a
	srl a
	srl a
	srl a
	ld b, a
	ld a, (mprs_packed_packet + 9 + 1)
	and #0xC0
	rlca
	rlca
	or b                                   ; symbol nibble complete
	ld hl, #symbol_nibble_to_primary_symbol
	cp #15
	jr nz, 1f
	ld a, (mprs_packed_packet + 4)         ; symbol=15, indirect symbol from SSID
	srl a
	srl a
	srl a
	srl a
	ld hl, #ssid_nibble_to_primary_symbol
1:
	ld b, #0
	ld c, a
	add hl, bc
	ld a, (hl)
	ld (de), a
	inc de

	ld a, #EOS
	ld (de), a               ; !6103.52N/02806.18E>  complete

	ld a, (cfg_mbus_mprs)      ; how exactly ?

	dec a                            ; if 1
	jp z, mbus_mprs_out_emu_tnc
	dec a                            ; if 2
	jp z, mbus_mprs_out_emu_kiss_tnc
	dec a                            ; if 3
	jp z, mbus_mprs_out_3rd_party

	ret ; ???

; 120000 6103.52N 02806.18E KP41BB 0 128 OH5NXO-15 <CRLF>
;  utc    lat       lon     loc  sym rssi call

mbus_mprs_out_logger:

	ld de, #mbus_mprs_buffer     ; format message " 6103.52N 02806.18E "


	ld a, #' '
	ld (de), a
	inc de

	ld ix, #mprs_packed_packet + 6
	call mprs_lat_format
	ld a, (ix+2)
	and #0x80
	ld a, #'N'
	jr z, 1f
	ld a, #'S'
1:
	ld (de), a
	inc de

	ld a, #' '
	ld (de), a
	inc de

	ld ix, #mprs_packed_packet + 9
	call mprs_lon_format
	ld a, (ix+2)
	and #0x80
	ld a, #'E'
	jr z, 1f
	ld a, #'W'
1:
	ld (de), a
	inc de

	ld a, #' '
	ld (de), a
	inc de

	ld a, #EOS
	ld (de), a               ; " 6103.52N 02806.18E "  complete

	ld ix, #gps_utc
	call mbus_mprs_out_string_ascify

	ld ix, #mbus_mprs_buffer         ; message formatted above
	call mbus_mprs_out_string

	ld ix, #locator_display_buffer
	call mbus_mprs_out_string

	ld c, #' '
	call putchar

	ld a, (mprs_packed_packet + 6 + 1)
	and #0xC0
	rrca
	rrca
	rrca
	rrca      ; 0x0C
	ld b, a
	ld a, (mprs_packed_packet + 9 + 1)
	and #0xC0
	rlca
	rlca      ; 0x03
	or b                    ; symbol nibble complete
	call putchar_hex_nybble ; print just as a hex digit

	ld c, #' '
	call putchar                    ; so far fixed width fields

	ld a, (packet_rssi)
	call putchar_hex_byte

	ld c, #' '
	call putchar                    ; so far fixed width fields

	ld ix, #remote_display_buffer    ; OH5NXO-15
	call mbus_mprs_out_string

	ld c, #0x0D
	call putchar
	ld c, #0x0A
	call putchar                    ; CRLF

	ret

putchar_hex_byte:

	ld b, a
	rra
	rra
	rra
	rra
	call putchar_hex_nybble

	ld a, b

putchar_hex_nybble:

	and #0xF
	cp #10
	jr c, 1f
	add a, #'A' - 10 - '0'
1:
	add a, #'0'
	ld c, a
	jp putchar


mprs_fake_dst_0:	.ascii "APRS"
.db EOS, EOS, EOS, EOS
mprs_fake_dst_1:	.ascii "RELAY"
.db      EOS, EOS, EOS
mprs_fake_dst_2:	.ascii "WIDE"
.db EOS, EOS, EOS, EOS

mprs_fake_dst_mprs:	.ascii "MPRS"
.db EOS, EOS, EOS, EOS

mbus_mprs_out_string:
1:
	ld a, (ix)
	cp #EOS
	ret z
	inc ix
	ld c, a
	call putchar
	jr 1b

mbus_mprs_out_string_ascify:
1:
	ld a, (ix)
	cp #EOS
	ret z
	cp #0x10         ; 0...9, 0xA...0xF
	jr nc, 2f       ; nope.
	cp #10           ; 
	jr c, 3f        ; 0...9
	add a, #'A' - 10 - '0'
3:
	add a, #'0'         ; '0' ... '9' or 'A' ... 'F'
2:
	inc ix
	ld c, a
	call putchar
	jr 1b

mbus_mprs_out_emu_tnc:          ; OH5NXO-15>APRS,RELAY,WIDE:!nnn/nnn>

	ld ix, #remote_display_buffer    ; OH5NXO-15
	call mbus_mprs_out_string

	ld ix, #mprs_fake_dst_0
	ld c, #'>'                       ; >APRS
	call putchar
	call mbus_mprs_out_string

	ld ix, #mprs_fake_dst_1
	ld a, (ix)
	cp #EOS
	jr z, 1f
		ld c, #','                   ; ,digi
		call putchar
		call mbus_mprs_out_string
1:
	ld ix, #mprs_fake_dst_2
	ld a, (ix)
	cp #EOS
	jr z, 1f
		ld c, #','                   ; ,digi
		call putchar
		call mbus_mprs_out_string
1:

	ld c, #':'                       ; >APRS,RELAY,WIDE:
	call putchar

	ld ix, #mbus_mprs_buffer         ; preformatted APRS message !nnn/nnn>
	call mbus_mprs_out_string

	ld c, #0x0D
	call putchar
	ld c, #0x0A
	call putchar                    ; CRLF

	ret

mbus_mprs_out_3rd_party:

	ld c, #'}'
	call putchar                    ; third party format

	ld ix, #remote_display_buffer    ; OH5NXO-15
	call mbus_mprs_out_string

	ld c, #'>'                       ; >APRS
	call putchar
	ld ix, #mprs_fake_dst_0
	call mbus_mprs_out_string

	ld c, #','                   ; ,digi
	call putchar
	ld ix, #mprs_fake_dst_mprs
	call mbus_mprs_out_string

	ld c, #'*'
	call putchar
	ld c, #':'                       ; }OH5NXO-15>APRS,MPRS*:
	call putchar

	ld ix, #mbus_mprs_buffer         ; preformatted APRS message !nnn/nnn>
	call mbus_mprs_out_string

	ld c, #0x0D
	call putchar           ; CR only, CONVERS send

	ret

;
;  KISS
;
;  FEND 0300(0xc0), FESC 0333(0xdb), TFEND 0334(0xdc), TFESC 0335(0xdd)
;
;  first byte after FEND is 0xW0 = data from tnc port W.
;  rest is ax25 packet without crc or flags:
;
;  addresses                      control pid  info    
;                                   03     F0  !nnn/nnn>
;  destination[7] source[7] digis[n*7]  n=0-8
;  chars <<= 1
;  dest SSID    011ssid0
;  src  SSID    011ssidL
;  digi-SSID    H11ssidL   H has-been-repeated, L last-of-addresses
;

putchar_slipped:
	cp #192
	jr z, 1f
	cp #219
	jr z, 2f

	ld c, a
	jp putchar
1:
	ld c, #219
	call putchar
	ld c, #220
	jp putchar
2:
	ld c, #219
	call putchar
	ld c, #221
	jp putchar

mbus_mprs_out_address_kiss:

	ld b, #6         ; 6 characters (and ssid) always
1:
	ld c, #' '       ; assume at end of call
	ld a, (ix)
	cp #EOS
	jr z, 2f
	cp #'-'
	jr z, 2f
	ld c, a
	inc ix           ; do not step over end of call
2:
	ld a, c
	sla a          ; characters shifted up
	call putchar_slipped
	djnz 1b

	ld c, #0         ; assume no ssid
	ld a, (ix+0)
	cp #'-'
	jr nz, 1f       ; no ssid was there
	ld a, (ix+1)
	sub #'0'
	ld c, a         ; assume -x singledigit ssid
	ld a, (ix+2)
	cp #EOS
	jr z, 1f        ; not -1x
	sub #'0' - 10
	ld c, a
1:
	ld a, c
	sla a           ; SSID shifted up
	and #0x1E        ; gigo safety
	or #0x60         ; SSID reserved bits
	or d            ; Last-bit maybe
	call putchar_slipped

	ret


mbus_mprs_out_emu_kiss_tnc:

	ld c, #192
	call putchar                ; flush junk

	ld c, #0x00                  ; data from tnc 0
	call putchar

	ld ix, #mprs_fake_dst_0          ; APRS - destination
	ld d, #0                         ; not last
	call mbus_mprs_out_address_kiss

	ld ix, #remote_display_buffer    ; OH5NXO-15 - source
	ld d, #1                         ; also last one
	call mbus_mprs_out_address_kiss


	ld c, #0x03                  ; control
	call putchar
	ld c, #0xF0                  ; PID
	call putchar

	ld ix, #mbus_mprs_buffer     ; preformatted APRS message !nnn/nnn>
	call mbus_mprs_out_string   ; ... it will not contain FEND or FESC, ever

	ld c, #192
	call putchar                ; end slip

	ret



mprs_lon_format:
	ld a, (ix+0)                  ; no reserved bit in lon degrees (0...180)
	ld c, a
	sub #100
	jr c, 1f
	ld c, a
	ld a, #'1'
	jr 2f
1:
	ld a, #'0'
2:
	ld (de), a
	inc de
	ld a, c
	jr 1f                         ; rest is same with lat and lon

	; JUMP THRU

mprs_lat_format:                  ; lat is 0..90, one less digit

	ld a, (ix+0)
	and #0x7F                      ; mask off reserved bit
1:
	call dekavalue_format

	ld a, (ix+1)
	and #0x3F                      ; mask off symbol bits
	call dekavalue_format

	ld a, #'.'
	ld (de), a
	inc de

	ld a, (ix+2)
	and #0x7F                      ; mask of hemisphere bit
	call dekavalue_format

	ret

dekavalue_format:

	ld c, #'0' - 1
1:
	inc c
	sub #10
	jr nc, 1b
	add a, #10 + '0'             ; undo last subtract and ascify also
	push af

	ld a, c
	ld (de), a
	inc de

	pop af
	ld (de), a
	inc de

	ret

;----------------------------------------------------------------------

;; Garmin GPS12, MAP168, GPSII+, GPSIII, GPSIII+, EMap(updated Software),
;; Etrex Venture, Legend, and Vista(with updated software),
;; Garmin 45, StreetPilot III(with 2.11 and above software),
;; and the GPS 12xl are known to be capable of this function.
;
; $GPWPL,6103.52,N,02806.18,E,OH5NXO-15*XX <CRLF>
; $PMGNWPL,6103.52,N,02806.18,E,altitude,F/M,call,,icon,*XX <CRLF>

1:   .ascii "GPWPL,"             ; last char must be , it is also copyed.
2:   .ascii "PMGNWPL,"

gps_mprs_call_latlon:

	; upload at 4800 bauds takes less time than mprs packet in 1200 bauds.
	; buffer will be free.

	ld de, #mbus_mprs_buffer      ; careful with the buffer size !

	ld hl, #1b                    ; more common sentence
	ld a, (cfg_gps_upload)
	cp #2
	jr nz, 1f
	ld hl, #2b                    ; Magellan enhanced

1:
	ld a, (hl)
	inc hl
	ld (de), a
	inc de
	cp #','
	jr nz, 1b                        ; $FOO,

	ld ix, #mprs_packed_packet + 6
	call mprs_lat_format

	ld a, #','
	ld (de), a
	inc de    ; $FOO,lat.lat,

	ld a, (ix+2)
	and #0x80
	ld a, #'N'
	jr z, 1f
	ld a, #'S'
1:
	ld (de), a
	inc de

	ld a, #','
	ld (de), a
	inc de    ; $FOO,lat.lat,N,

	ld ix, #mprs_packed_packet + 9
	call mprs_lon_format

	ld a, #','
	ld (de), a
	inc de

	ld a, (ix+2)
	and #0x80
	ld a, #'E'
	jr z, 1f
	ld a, #'W'
1:
	ld (de), a
	inc de

	ld a, #','
	ld (de), a
	inc de   ; $FOO,lat.lat,N,lon.lon,E,

	ld a, (cfg_gps_upload)
	cp #2
	jr nz, 1f
	ld a, #','
	ld (de), a
	inc de   ; dummy altitude and altitude ...
	ld a, #','
	ld (de), a
	inc de   ; ... unit for Magellan
1:

	ld hl, #remote_display_buffer    ; OH5NXO-15
	push de                         ; remember start of waypoint name.
1:
	ld a, (hl)
	inc hl
	ld (de), a                      ; EOS is also stored, DE left over it.
	cp #EOS
	jr z, 1f
	inc de                          ; good character added, next.
	jr 1b
1:
	pop hl                          ; squeeze waypoint name
	call gps_waypoint_tidy

	ld a, #'*'
	ld (de), a
	inc de   ; Magellan extras are left out.

	ld hl, #mbus_mprs_buffer         ; NMEA checksum between $ and *
	ld c, #0
1:
	ld a, (hl)
	inc hl
	cp #'*'
	jr z, 1f
	xor c
	ld c, a
	jr 1b
1:
	ld a, c
	rra
	rra
	rra
	rra
	and #0xF
	cp #10
	jr c, 1f
	add a, #'A' - 10 - '0'
1:
	add a, #'0'
	ld (de), a
	inc de
	ld a, c
	and #0x0F
	cp #10
	jr c, 1f
	add a, #'A' - 10 - '0'
1:
	add a, #'0'
	ld (de), a
	inc de

	ld a, #0x0D
	ld (de), a
	inc de       ; CR
	ld a, #0x0A
	ld (de), a
	inc de       ; LF
	ld a, #0x00
	ld (de), a
	inc de       ; NUL

	; buffer holds "GPWPL,6103.52,N,02806.18,E,OH5NXO-15*XX\r\n\0"

	ld hl, #mbus_mprs_buffer         ; message formatted above
	ld (gps_upload_ptr), hl

	ld a, #'$'
	out (SIO+ADATA), a              ; start !

	ret

; input: HL points to string ending with EOS, DE points to the EOS.
; output: DE points just past waypoint name

gps_waypoint_tidy:
	ret

;------------------------------------------------------------------------

ascify:
	cp #16
	ret nc        ; not hex digit
	cp #10
	jr nc, 1f
	add a, #'0'       ; 0x0 into '0'
	ret
1:
	add a, #'A' - 10  ; 0xA into 'A'
	ret

pack_aprs_report_digi_maybe:
	or a
	ret z                           ; None

	ld hl, #cfg_ax25_digi_other     ; maybe this ?
	cp #AX25_DIGI_OTHER_IDX
	jr nc, pack_aprs_report_packet_call

	ld hl, #tab_ax25_digi + 1  ; others are verbatim in menu
	push de
	add a, a          ; 2x
	add a, a          ; 4x
	add a, a          ; 8x   junk in setup, junk into packet
	ld d, #0
	ld e, a
	add hl, de     ; index into selected string
	pop de

	; FALL THRU

pack_aprs_report_packet_call:

	ld b, #6         ; 6 characters (plus ssid) always
2:
	ld c, #' '       ; assume at end of call, blank padded
	ld a, (hl)
	cp #EOS
	jr z, 1f
	cp #'-'
	jr z, 1f
	inc hl          ; do not step over end of call
	call ascify
	ld c, a
	cp #'a'          ; lowercase ?
	jr c, 1f        ; nope.
	res 5, c        ; make upper case
1:
	ld a, c
	sla a           ; characters are shifted up
	ld (de), a
	inc de
	djnz 2b         ; do all 6 characters.

	; then SSID

	ld c, #0         ; assume no ssid
	ld a, (hl)
	cp #'-'
	jr nz, 2f       ; no -ssid was there
	inc hl
	ld a, (hl)      ; -x
	sub #'0'         ; turn to binary
	jr nc, 1f
	add a, #'0'         ; oops, was already binary
1:
	ld c, a         ; assume -x singledigit ssid
	cp #1
	jr nz, 2f       ; not -1(x)
	inc hl
	ld a, (hl)
	cp #EOS
	jr z, 2f        ; not -1x
	sub #'0'
	jr nc, 1f
	add a, #'0'         ; morerepetitition
1:
	add a, #10          ; must be 10...15
	ld c, a
2:
	ld a, c
	jr 9f           ; save a few bytes

	; jumpover

pack_aprs_report_packet_mycall:

	ld hl, #cfg_mprs_callsign        ; OH5NXO - source
	ld b, #6                         ; 6 characters (plus ssid) always
2:
	ld c, #' '       ; assume at end of call
	ld a, (hl)
	cp #EOS
	jr z, 1f
	inc hl           ; do not step over end of call
	call ascify
	ld c, a
1:
	ld a, c
	sla a          ; characters shifted up
	ld (de), a
	inc de
	djnz 2b

	ld a, (cfg_mprs_ssid)
9:
	rla             ; SSID shifted up
	and #0x1E        ; gigo safety - also clear C bit
	or #0x60         ; SSID reserved bits are set
	ld (de), a      ; Last-bit (0x01) clear
	inc de          ; DE points one past SSID

	ret



encode_aprs_report_packet_normal:          ; store into DE

	ld hl, #mprs_fake_dst_0                 ; APRS - destination
	call pack_aprs_report_packet_call

	call pack_aprs_report_packet_mycall    ; MYCALL - source

	ld a, (cfg_ax25_digi0)                 ; digipeat paths, if any
	call pack_aprs_report_digi_maybe
	ld a, (cfg_ax25_digi1)
	call pack_aprs_report_digi_maybe
	ld a, (cfg_ax25_digi2)
	call pack_aprs_report_digi_maybe
	ld a, (cfg_ax25_digi3)
	call pack_aprs_report_digi_maybe

	ex de, hl           ; use HL to insert stuff, for a while

	dec hl              ; back over SSID of last address
	set 0, (hl)         ; insert LAST-bit in last address
	inc hl

	; control and PID

	ld (hl), #0x03                ; control
	inc hl
	ld (hl), #0xF0                ; PID
	inc hl

	; aprs message in data part

	ld (hl), #'!'               ; data is like !6103.52N/02806.18E>  
	inc hl

	ld ix, #cfg_gps_latitude
	ld a, (ix+1)
	add a, #'0'
	ld (hl), a
	inc hl    ; 6
	ld a, (ix+2)
	add a, #'0'
	ld (hl), a
	inc hl    ; 1
	ld a, (ix+3)
	add a, #'0'
	ld (hl), a
	inc hl    ; 0
	ld a, (ix+4)
	add a, #'0'
	ld (hl), a
	inc hl    ; 3
	                       ld (hl), #'.'
	                       inc hl  ; .
	ld a, (ix+5)
	add a, #'0'
	ld (hl), a
	inc hl    ; 5
	ld a, (ix+6)
	add a, #'0'
	ld (hl), a
	inc hl    ; 2

	ld a, (ix+7)
	cp #'S'
	jr z, 1f
	ld a, #'N'              ; anything but 'S' means North
1:
	ld (hl), a
	inc hl     ; N

	ld (hl), #'/'
	inc hl                         ; / Primary symbol table

	ld ix, #cfg_gps_longitude
	ld a, (ix+0)
	add a, #'0'
	ld (hl), a
	inc hl   ; 0
	ld a, (ix+1)
	add a, #'0'
	ld (hl), a
	inc hl   ; 2
	ld a, (ix+2)
	add a, #'0'
	ld (hl), a
	inc hl   ; 8
	ld a, (ix+3)
	add a, #'0'
	ld (hl), a
	inc hl   ; 0
	ld a, (ix+4)
	add a, #'0'
	ld (hl), a
	inc hl   ; 6
	                       ld (hl), #'.'
	                       inc hl ; .
	ld a, (ix+5)
	add a, #'0'
	ld (hl), a
	inc hl   ; 1
	ld a, (ix+6)
	add a, #'0'
	ld (hl), a
	inc hl   ; 8

	ld a, (ix+7)
	cp #'W'
	jr z, 1f
	ld a, #'E'              ; anything but 'W' means East
1:
	ld (hl), a
	inc hl     ; E

	; swap "insert pointer" to DE for the rest of this

	ex de, hl

	; the station symbol

	ld a, (cfg_mprs_symbol)
	ld hl, #symbol_nibble_to_primary_symbol
	cp #15
	jr nz, 1f
	ld a, (cfg_mprs_ssid)         ; symbol=15, indirect symbol from SSID
	ld hl, #ssid_nibble_to_primary_symbol
1:
	ld c, a
	ld b, #0
	add hl, bc
	ldi                   ; [DE++] = [HL++], BC--

	; course/speed - only if moving at speed over 1 knots

	ld hl, (gps_knots)
	ld bc, #-2
	add hl, bc
	jr nc, 1f               ; speed less than 2 knots, no CSE/SPD

	call gps_course_1_to_360_degrees
	call HL_to_3_ascii_at_DE

	ld a, #'/'
	ld (de), a
	inc de

	ld hl, (gps_knots)
	call HL_to_3_ascii_at_DE
1:
	; finished message.

	ex de, hl               ; HL has "one past last byte"
	ret                     ; endptr of packet in HL

gps_course_1_to_360_degrees:

	ld hl, (gps_course)
	ld a, l
	or h
	ret nz               ; not 0 degrees course, ok
	ld hl, #360           ; 0 degrees goes as 360 degrees.
	ret

; HL to ascii digits in [DE], [DE+1] and [DE+2]
; DE += 3
; A, BC and HL trashed

9:	.ascii "999"

HL_to_3_ascii_at_DE:

	ld bc, #-1000      ; paranoid, clamp at 999
	add hl, bc
	jr nc, 1f         ; go if less than 1000

	ld hl, #9b
	ldi
	ldi
	ldi
	ret               ; 999
1:
	sbc hl, bc        ; undo it. NC condition nicely

	; it fits in 3 characters, so do it

	ld bc, #-100       ; possibly more than 8 bits in HL
	ld a, #'0' - 1
1:
	inc a
	add hl, bc
	jr c, 1b
	sbc hl, bc        ; NC condition nicely

	ld (de), a        ; hundreds
	inc de

	ld a, l           ; now 8 bits is enough

	ld c, #10
	ld b, #'0' - 1
1:
	inc b
	sub c
	jr nc, 1b
	add a, c
	add a, #'0'           ; leftover to ascii too

	ex de, hl

	ld (hl), b        ; tens
	inc hl

	ld (hl), a        ; ones
	inc hl

	ex de, hl
	ret               ; and done

mic_e_binary_dmh:
	ld a, (hl)     ; tens       these are 0x00 ... 0x09 always
	add a, a          ; 2 times
	add a, a          ; 4 times
	add a, (hl)       ; 5 times
	add a, a          ; 10 times
	inc hl
	add a, (hl)       ; plus ones
	inc hl
	cp #100
	ret c
	ld a, #99       ; hmpft
	ret

mic_e_DC_tab: .ascii " *4>HR"
.db 0x5C
.ascii "fpz"
mic_e_DC_tab_size = . - mic_e_DC_tab
ASSERT_EQ(mic_e_DC_tab_size, 10)

encode_aprs_report_packet_mic_e:        ; into DE

	; first fish for the message/N/+100/W bits

	ld a, (cfg_mic_e_message)
	cp #8           ; Was this a custom message (messages 8-14) ?
	ld h, #'P'      ; Assume will be standard message, chars for 1-bits from 'P'
	jr c, 1f       ; yes, index 0 ... 7, OffDuty ... -HELP-
	ld h, #'A'      ; Custom message uses characters from 'A'
1:
	ld l, #3        ; custom characters, if any, only in 3 first slots
	and #7          ; mask out custom indicator, bit 0x08
	xor #7          ; complement the bits - at index 0 is OffDuty = Std 111
	rrca
	rrca
	rrca           ; leftjustify them into bits 765 - picked out from left
	ld c, a        ; keep them in C

	ld a, (cfg_gps_latitude + 7)
	cp #'S'
	jr z, 1f       ; South. skip
	set 4, c       ; Northern latitude - bit 1 in 4th byte
1:
	ld a, (cfg_gps_longitude + 7)
	cp #'W'
	jr nz, 1f      ; Not West. skip
	set 2, c       ; Western longitude - bit 1 in 6th byte
1:
	ld a, (cfg_gps_longitude + 0)
	or a           ; 1xx ?
	jr nz, 2f      ; Longitude >= 100 degrees - "+100 bit" is always set
	ld a, (cfg_gps_longitude + 1)
	or a           ; 00x ?
	jr nz, 1f      ; Longitude 010..099 degrees, skip
2:
	set 3, c       ; 100 or more, or less than 10 degrees, "lon +100"
1:

	; DESTINATION ADDRESS
	; XXX position uncertainty

	ld ix, #cfg_gps_latitude + 1     ; latitude [0] is always 0
	ld b, #6
2:
	ld a, h        ; assume 1-bit
	rl c           ; next message/n/l/w bit into carry
	jr c, 1f
	ld a, #'0'      ; zerobit. character is one of 0123456789
1:
	add a, (ix)       ; latitude digit (0x00...0x09)
	inc ix
	sla a          ; leftshifted characters in ax.25 addresses
	ld (de), a
	inc de
	dec l          ; just did slot 3 ?
	jr nz, 1f
	ld h, #'P'      ; then later 1-bits will use PQRST... always
1:
	djnz 2b        ; all six characters of destaddr

	; destination address ssid (distribution/routing thing)

	ld a, (cfg_mic_e_dest_ssid)
	rla
	and #0x1E       ; CrrSSID0 - C mbz
	or #0x60        ; and rr mbo
	ld (de), a     ; SSID slot
	inc de

	; SOURCE ADDRESS

	call pack_aprs_report_packet_mycall

	; use HL for cursor, for a while

	ex de, hl

	dec hl
	set 0, (hl)           ; insert LAST-bit in last address (no digis here)
	inc hl

	; CONTROL AND PID

	ld (hl), #0x03        ; UI packet
	inc hl
	ld (hl), #0xF0        ; No level 3 protocol
	inc hl

	; INFORMATION FIELD

	; first slot of information field

	ld (hl), #0x60  ; MIC-E valid GPS data XXX 'GPS data is old' unsupported
	inc hl

	; HL needed for arithmetic, back to DE as  "cursor"

	ex de, hl

	; lon degrees

	ld hl, #cfg_gps_longitude + 0
	ld b, (hl)               ; lon hundreds of degrees
	inc hl
	call mic_e_binary_dmh    ; and tens and ones
	dec b
	jr nz, 1f      ; was not 1 (1xx degrees)
	add a, #100        ; longitude degrees total 0...179
1:
	cp #10
	jr nc, 1f
	add a, #190        ; if 0-9, add 190, get 190-199
	jr 2f
1:
	cp #100
	jr c, 2f
	cp #110
	jr nc, 2f
	add a, #80         ; if 100-109, add 80, get 180-189
2:
	cp #100
	jr c, 1f
	sub #100        ; get % 100
1:
	add a, #28
	ld (de), a
	inc de

	; lon minutes

	call mic_e_binary_dmh
	cp #10
	jr nc, 1f
	add a, #60         ; 0-9 goes as 60-69
1:
	add a, #28
	ld (de), a
	inc de

	; lon hundredths of minute

	call mic_e_binary_dmh
	add a, #28
	ld (de), a
	inc de

	; encoded speed, hundreds and tens of knots

	ld hl, (gps_knots)
	ld bc, #100
	xor a           ; clear carry

	ld a, #'l'       ; 0-99 knots - 'l' (ell) ... 'u'
	sbc hl, bc
	jr c, 1f

	ld a, #'v'       ; 100-199 knots - 'v' ... DEL
	sbc hl, bc
	jr c, 1f

	ld a, #'0'       ; 200-299 knots - '0' ... '9'
	sbc hl, bc
	jr c, 1f

	ld a, #':'       ; 300 knots - ':'
	ld hl, #-100     ; tsk - clamp at 300 knots.
1:
	add hl, bc      ; fixup to 0...99 range
	ld b, a
	ld a, l
	dec b           ; fixup one-inc-too-many
1:
	inc b
	sub #10
	jr nc, 1b       ; divide by 10
	add a, #10          ; fixup remainder
	ld c, a         ; remember it.

	ld a, b
	ld (de), a      ; SP+28
	inc de

	; encoded speed, ones of knots, plus ...
	; ... encoded course, hundreds of degrees

	ld b, #0
	ld hl, #mic_e_DC_tab
	add hl, bc           ; recall knots % 10
	ld b, (hl)           ; encoded speed % 10

	ld hl, (gps_knots)
	ld a, l
	or h
	jr z, 1f             ; zero knots implies course 0.
	call gps_course_1_to_360_degrees ; to HL
1:
	ld a, b              ; encoded speed % 10 from above
	ld bc, #-100          ; divide by 100
	dec a                ; fixup one-inc-too-many
1:
	inc a
	add hl, bc
	jr c, 1b             ; inverted carry from add -100
	sbc hl, bc           ; fixup remainder

	ld (de), a           ; DC+28
	inc de

	; encoded course, tens and ones of degrees

	ld a, l              ; course % 100 from above
	add a, #28
	ld (de), a           ; SE+28
	inc de

	; symbol and symbol table (XXX symtab always /)

	ld hl, #symbol_nibble_to_primary_symbol
	ld a, (cfg_mprs_symbol)
	cp #15
	jr c, 1f                             ; codes 0-14 select symbols
	ld hl, #ssid_nibble_to_primary_symbol
	ld a, (cfg_mprs_ssid)                ; code 15, redirect from SSID
	and #0x0F
1:
	ld c, a
	ld b, #0
	add hl, bc
	ld a, (hl)

	ld (de), a           ; symbol
	inc de

	ld a, #'/'
	ld (de), a           ; and symtab.
	inc de

	; MIC-E PACKET FINISHED

	ex de, hl            ; packet in aprs_packet_out, 'endptr' in HL

	ret


encode_aprs_report_packet:
	ld a, (cfg_report_type)
	cp #2
	jp z, encode_aprs_report_packet_mic_e ; MIC-E format

	jp encode_aprs_report_packet_normal   ; else normal ascii format

send_aprs_report_packet:

	ld de, #aprs_packet_out

	call encode_aprs_report_packet

	ld de, #aprs_packet_out
	and a
	sbc hl, de
	ld b, l
	push bc                ; remember length

	ld ix, #aprs_packet_out

	call calc_ax25_crc     ; ix and b
	cpl
	ld (ix + 0), a         ; notice the MSByte/LSByte difference
	ld a, c
	cpl
	ld (ix + 1), a


	; bitstuffing. XXX do this on the fly in emit() xxx no time for that

	ld ix, #aprs_bits_out   ; buffer for stuffed data
	ld d, #0x80             ; spool bits here, catch every 8th rr

	; preamble, first some filler ...

	ld a, (cfg_ax25_padbits)
	ld b, a
	or a
	jr nz, 1f
	ld b, #36            ; default to 36 bits = 30 milliseconds
1:
	srl d                  ; zerobit
	call c, stuffed_8bits
	djnz 1b

	; ... (unstuffed) starting flag ...

	ld e, #0x7E
	ld b, #8
1:
	srl e
	rr d
	call c, stuffed_8bits
	djnz 1b

	; ... the frame content (stuffed) ...

	pop bc
	ld c, b                    ; bytecount to C
	inc c
	inc c                      ; crc added two bytes to length
	xor a                      ; count onebits here XXX cumbersome 
	ld hl, #aprs_packet_out
2:
	ld e, (hl)
	inc hl
	ld b, #8
1:
	srl e
	call stuff_ax25_bit
	djnz 1b                   ; another bit in byte
	dec c
	jr nz, 2b                 ; another byte in data

	; ... ending flag ...

	ld e, #0x7E
	ld b, #8
1:
	srl e
	rr d
	call c, stuffed_8bits
	djnz 1b

	; ... then flush residue (always 1 to 8 zerobits) ...
1:
	srl d
	jr nc, 1b
	call stuffed_8bits

	; ... finally the terminator marker for emit(). xxx ought to do bit-level.

	ld (ix), #0x7F

	ld hl, #aprs_bits_out

	jp emit_ax25_packet


stuff_ax25_bit:
	jr nc, 1f              ; zerobits are simple.
	rr d                   ; shift in the one
	call c, stuffed_8bits  ; flush if needed.
	inc a                  ; one more onebit.
	cp #5                   ; need stuffing zero ?
	ret c                  ; if less than 5 ones, no.
1:
	xor a                ; no onebits now.
	srl d                  ; add zerobit.
	ret nc                 ; done if no need to flush.

	; fall thru, if flushing

stuffed_8bits:

	ld (ix), d
	inc ix
	ld d, #0x80             ; rewind counting pattern
	ret

;----------------------------------------------------------------------
	;--------------------------------------------------


;----- FSK packet dispatch, remote config and MPRS sending (was fixed ROM) -----

;-------------------
;
; ix points to correct position in packet, 6 byte buffer for packed callsign
; hl points to string to pack into packet.
;
packet_callsign_pack:

	call 1f
	call 1f
	ret
1:
	call get_next_cfg_6bits        ;   543210
	ld c, a                        ;   543210
	call get_next_cfg_6bits        ;   fedcba
	ld b, a
	and #3                          ;       ba
	rrca
	rrca                           ; ba
	or c                           ; ba543210
	ld (ix + 0), a

	srl b
	srl b                          ;     fedc

	call get_next_cfg_6bits        ;   543210
	ld c, a
	sla a
	sla a
	sla a
	sla a                          ; 3210    
	or b                           ; 3210fedc
	ld (ix + 1), a

	srl c
	srl c
	srl c
	srl c                          ;       54

	call get_next_cfg_6bits        ;   fedcba
	sla a
	sla a                          ; fedcba
	or c                           ; fedcba54
	ld (ix + 2), a

	inc ix
	inc ix
	inc ix
	ret

;
;  ix points to packed callsign in packet buffer
;  de points to buffer to store string
;
packet_callsign_unpack:

	call 1f
	call 1f
	ret
1:
	ld a, (ix + 0)          ; 10fedcba
	call store_next_6bits

	ld a, (ix + 0)          ; 10fedcba
	rlca
	rlca                    ; fedcba10
	and #0x03                ;       10

	ld b, (ix + 1)          ; dcba5432
	sla b
	sla b                   ; ba5432
	or b                    ; ba543210
	call store_next_6bits

	ld a, (ix + 1)          ; dcba5432
	and #0xF0                ; dcba
	ld b, a

	ld a, (ix + 2)          ; 543210fe
	and #0x03                ;       fe
	or b                    ; dcba  fe
	rrca
	rrca
	rrca
	rrca                    ;   fedcba
	call store_next_6bits

	ld a, (ix + 2)          ; 543210fe
	srl a
	srl a                   ;   543210
	call store_next_6bits

	inc ix
	inc ix
	inc ix
	ret

; iy has deg[3] min[2] decimal_min[2] unpacked bcd, pack into 3 bytes at ix

mprs_degmin_pack:

	ld a, (iy+0)
	or a         ; 0xx degrees or 1xx degrees only
	ld b, #0      ; 0xx
	jr z, 1f
	ld b, #100    ; 1xx
1:
	ld a, (iy+1)
	add a, a        ; 2
	ld c, a
	add a, a        ; 4
	add a, a        ; 8
	add a, c        ; 8 + 2 = 10
	add a, b        ; plus hundreds
	add a, (iy+2)   ; plus ones

	ld (ix+0), a ; degrees (0...180)

	ld a, (iy+3)
	add a, a        ; 2
	ld c, a
	add a, a        ; 4
	add a, a        ; 8
	add a, c        ; 8 + 2 = 10
	add a, (iy+4)   ; plus ones

	ld (ix+1), a ; minutes (0..59)

	ld a, (iy+5)
	add a, a        ; 2
	ld c, a
	add a, a        ; 4
	add a, a        ; 8
	add a, c        ; 8 + 2 = 10
	add a, (iy+6)   ; plus ones

	ld (ix+2), a ; decimal minutes (0..99)

	ld a, (iy+7)
	cp #'N'
	ret z        ; North is 'positive'
	cp #'W'
	ret nz       ; not West is 'positive'

	set 7, (ix+2) ; 'negative' sign in seconds-byte

	ret

;----------------------------------------------------------------------

packet_for_whom:
	ld a, (packet_good)
	ld l, a
	ld h, #HI(fsk_history)
	ld a, (hl)

	cp #0xC
	jp z, handle_call_packet

	cp #0xA
	jr z, handle_config_packets    ; ask
	cp #0xE
	jr z, handle_config_packets    ; enter
	cp #0xD
	jp z, handle_display_packets
	cp #0x4
	jp z, far_handle_mprs_packets
	cp #0x5
	jr z, handle_relay_packets

	ret

handle_relay_packets:

	ld b, #12
1:
	ld c, (hl)
	inc l			; in the ring (v3_Z: inc hl, sent gps_history
				; bytes for a packet across its end)
	push hl
	call putchar
	pop hl
	djnz 1b

	ret


handle_config_packets:

	ld b, a                     ; remember msnibble of tag, Ask or Enter
	inc l

	ld a, (hl)
	inc l
	cp #0xC                      ; AC/EC ii DD ptr PTR possible data
	ret nz

	; destined to us ?

	ld de, (cfg_remote_id)
	ld a, d
	or e
	ret z                  ; remote id zero equals not used

	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	cp e
	ret nz
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	cp d
	ret nz

	; ours. get variable pointer (0xABCD is "CDAB")

	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld e, a

	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld d, a

	push hl
	pop ix

	; Would be too easy :-)

	ld hl, #cfg_remote_passwd + cfg_remote_passwd_size - 1
	and a
	sbc hl, de                          ; last - ptr
	jr c, 1f                            ; CY -> after passwd
	ld hl, #cfg_remote_passwd - SIZE_STR ; reply data length max
	sbc hl, de
	jr nc, 1f                           ; NC -> before passwd

	ret                    ; refuse to reveal/modify passwd data
1:

	; Setting or just Asking ?

	ld a, b          ; Ask or Enter
	cp #0xE
	jr nz, 1f

	push de           ; save ptr
	push ix
	pop hl
	call far_remote_config_execute         ; Enter: de=ptr, hl=data (wrap page)
	call far_leaved_setup
	pop de
1:
	; FSK reply in either case

	jp send_display_config_packet ; ptr in DE


handle_display_packets:
	inc l
	ld a, (hl)
	cp #0xD
	jp z, handle_display_data
	cp #0xC
	jr z, handle_display_config
	ret

handle_display_config:
	ld de, (cfg_remote_id)
	ld a, d
	or e
	ret z                     ; dont bother when remote id zeroed.

	ld de, #remote_display_buffer
	inc l

	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (de), a
	inc de
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (de), a
	inc de
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (de), a
	inc de
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (de), a
	inc de

	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (de), a
	inc de
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (de), a
	inc de
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (de), a
	inc de
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (de), a
	inc de

	ld a, #EOS
	ld (de), a
	inc de
	ld (de), a  ; all 10 characters

	ld a, #5
	ld (display_buffer_time), a

	xor a
	ld (digidx), a            ; As an ack

	jp redraw

handle_display_data:
	ld de, #remote_display_buffer
	inc l

	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (de), a
	inc de
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (de), a
	inc de
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (de), a
	inc de
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (de), a
	inc de

	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (de), a
	inc de
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (de), a
	inc de
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (de), a
	inc de
	ld a, (hl)
	inc l
	sla4
	or (hl)
	inc l
	ld (de), a
	inc de

	ld a, #EOS
	ld (de), a
	inc de
	ld (de), a    ; all 10 characters

	ld a, #5
	ld (display_buffer_time), a

	jp redraw

handle_call_packet:

	ld a, l
	add a, #6                 ; destination address offset
	ld l, a
	ld ix, #cfg_mycall_1

	ld a, (hl)
	inc l
	cp (ix + 0)
	ret nz
	ld a, (hl)
	inc l
	cp (ix + 1)
	ret nz
	ld a, (hl)
	inc l
	cp (ix + 2)
	ret nz
	ld a, (hl)
	inc l
	cp (ix + 3)
	ret nz
	ld a, (hl)
	inc l
	cp (ix + 4)
	ret nz

	ld a, #1
	call start_call_timer

	call cu_lights_on
	call cu_call_on
	call redraw
	call ding
	ret

; PTT in menu, send query or config packet

send_remote_config_packets:

	ld hl, (cfg_remote_id)
	ld a, h
	or l
	ret z                     ; dont bother when remote id zeroed.

	call mic_off_ccir_off

	ld a, (digidx)
	or a
	jr z, send_remote_config_query

	; Enter config then

	ld ix, (menu_ptr)    ; current record
	ld de, #outpacket

	ld a, #0xEC
	ld (de), a
	inc de               ; "Enter Config" ...

	ld hl, (cfg_remote_id)
	ld a, l
	ld (de), a
	inc de             ; ... with this remote config identifier
	ld a, h
	ld (de), a
	inc de

	call fill_enter_config_packet
	call append_secret_packet_crc

	ld b, #LONG_PACLEN
	call send_packet_buffer
	ret

send_remote_config_query:
	ld ix, (menu_ptr)    ; current record
	ld de, #outpacket

	ld a, #0xAC
	ld (de), a
	inc de               ; "Ask Config" ...

	ld hl, (cfg_remote_id)
	ld a, l
	ld (de), a
	inc de             ; ... from this rig identifier
	ld a, h
	ld (de), a
	inc de

	call fill_query_config_packet
	call append_short_packet_crc

	ld b, #SHORT_PACLEN
	call send_packet_buffer
	ret

; at DE is the variable XXX

send_display_config_packet:

	ld a, (txon)
	or a
	jr nz, 1f             ; in case tx already on, repeater ?

	push de
	call tx_on
	pop de
	jp c, tx_error

	sub a              ; Z, must txoff
1:
	push af               ; txon flag for later

	push de
	call mic_off_ccir_off

	pop hl             ; swap de to hl
	ld de, #outpacket

	ld a, #0xDC
	ld (de), a
	inc de

	call fill_display_config_packet
	call append_long_packet_crc

	ld b, #LONG_PACLEN
	call send_packet_buffer
	call mdm_delay
	ld b, #LONG_PACLEN
	call send_packet_buffer

	pop af
	call z, tx_off       ; turned on, so turn off also
	ret

send_mprs_report_packet_maybe:

	ld a, (cfg_keyup_mprs)
	or a
	ret z                              ; oFF.
	dec a                              ; if 1
	jr z, send_mprs_report_packet      ; ALL.

	call check_for_mprs_timer          ; on_demand else. is there demand ?
	ret c                              ; not yet

	; fall thru

send_mprs_report_packet:

	ld hl, #0
	ld (mprs_report_timer), hl

	call mic_off_ccir_off

	; fall thru

send_mprs_report_packet_1:

	ld a, (gps_speed)
	ld (gps_reported_speed), a   ; remember what was the speed during report

	ld a, (cfg_report_type)
	or a
	jp nz, far_send_aprs_report_packet

	ld a, #0x40
	ld (outpacket + 0), a        ; "MPRS #0" ...

	ld hl, #cfg_mprs_callsign     ; unpacked callsign
	ld ix, #outpacket + 1
	call packet_callsign_pack

	ld ix, #outpacket + 1
	ld a, (ix+4)
	and #0x0F                     ; SSID goes to 4 bits after packed 6 characters, top nibble of byte 4
	ld b, a
	ld a, (cfg_mprs_ssid)
	sla a
	sla a
	sla a
	sla a                        ; SSID in bits ????0000
	or b
	ld (ix+4), a                ; ssid inserted

	xor a
	ld (ix+5), a                ; routing/digipeating reserved byte zeroed

	ld iy, #cfg_gps_latitude
	ld ix, #outpacket + 1 + 6
	call mprs_degmin_pack

	ld iy, #cfg_gps_longitude
	ld ix, #outpacket + 1 + 6 + 3
	call mprs_degmin_pack

	; 40 cc cc cc cc cs xx la la la lo lo lo
	; 0  ------6---------- ---3---- ---3----

	ld a, (cfg_mprs_symbol)          ; ----dcba
	sla a                            ; ---dcba0
	sla a                            ; --dcba00
	sla a                            ; -dcba000
	sla a                            ; dcba0000
	and #0xC0                         ; dc000000
	ld ix, #outpacket + 1 + 6
	or (ix+1)
	ld (ix+1), a                     ; hibits of symbol

	ld a, (cfg_mprs_symbol)          ; ----dcba
	rrca                             ; a----dcb
	rrca                             ; ba----dc
	and #0xC0                         ; ba000000
	ld ix, #outpacket + 1 + 6 + 3
	or (ix+1)
	ld (ix+1), a                     ; lobits of symbol


	call append_long_packet_crc

	ld b, #LONG_PACLEN
	call send_packet_buffer      ; once.
	ret

	; following called from fsk interrupt


;----- Config packet filling and the call packet (was fixed ROM) -----

map_special_ptrs:
	ld a, h
	cp #HI(version)
	jr nz, 1f
	ld a, l
	cp #LO(version)
	jr nz, 1f
	ld hl, #0                     ; VERSION = 0
	ret
1:
	ld a, h
	cp #HI(menu_rfc_change)
	jr nz, 1f
	ld a, l
	cp #LO(menu_rfc_change)
	jr nz, 1f
	ld hl, #1                     ; RFC = 1
	ret
1:
	ld a, h
	cp #HI(menu_sql_change)
	jr nz, 1f
	ld a, l
	cp #LO(menu_sql_change)
	jr nz, 1f
	ld hl, #2                     ; SQL = 2
	ret
1:
	ld a, h
	cp #HI(menu_sqB_change)
	jr nz, 1f
	ld a, l
	cp #LO(menu_sqB_change)
	jr nz, 1f
	ld hl, #3                     ; SQL BI = 3
	ret
1:
	ret     ; unchanged

onesies: .db 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF

fill_enter_config_packet:

	call far_load_menu_ptr       ; variable is specified by RAM address
	call map_special_ptrs    ; or page 0 pseudoptr

	ld a, l
	ld (de), a
	inc de
	ld a, h
	ld (de), a
	inc de       ; ptr

	ld bc, #8                 ; assume will copy 8 chars, b clear
	ld hl, #digbuf
	ld a, (digidx)           ; depending on number of characters:
	cp #8
	jr c, 1f                 ; less than 8, padding
	jr z, 2f                 ; exact 8
	jr 3f                    ; 9 or more -> means 0 characters (silly)
1:
	ld c, a                  ; valid chars
	ld a, #8
	sub c                    ; this much padding
	ldir                     ; copy
	ld c, a                  ; padding now
3:
	ld hl, #onesies
2:
	ldir                     ; copy
	ret

fill_query_config_packet:

	call far_load_menu_ptr       ; variable is specified by RAM address
	call map_special_ptrs

	ld a, l
	ld (de), a
	inc de
	ld a, h
	ld (de), a
	inc de
	ld hl, #onesies
	ldi
	ldi
	ldi
	ret

fill_display_config_packet:
	ld a, h
	or a
	ld a, l
	jr z, 1f        ; special variables look like they live in page 0
5:
	ldi
	ldi
3:
	ldi
	ldi
	ldi
	ldi
	ldi
	ldi
	ret
1:
	cp #0                    ; VERSION = 0
	jr nz, 1f
	ld hl, #version
	jr 5b
1:
	cp #1                    ; RFC = 1
	jr nz, 1f
	ld hl, #rfc
	ldi
	ld hl, #ad_rssi
	ldi
	ld hl, #onesies
	jr 3b
1:
	cp #2                    ; SQL = 2
	jr nz, 1f
	ld hl, #cfg_squelch_level
	ldi
	call read_squelcher_value
	ld (de), a
	inc de
	ld hl, #onesies
	jr 3b
1:
	cp #3                    ; SQL BI = 3
	jr nz, 1f
	ld hl, #cfg_squelch_BIG
	ldi
	ld a, (ad_rssi)         ; sql_bi w/ RSSI, not: call read_squelcher_value
	ld (de), a
	inc de
	ld hl, #onesies
	jr 3b
1:
	ld hl, #onesies
	jr 5b

	;--------------------------------------------------

send_call_packet:

	call tx_on
	jp c, tx_error

	call mic_off_ccir_off

	call waitkey

	call build_call_packet_buffer
	call append_short_packet_crc

	ld b, #SHORT_PACLEN
	call send_packet_buffer
	call mdm_delay
	ld b, #SHORT_PACLEN
	call send_packet_buffer
	call mdm_delay
	ld b, #SHORT_PACLEN
	call send_packet_buffer

	call tx_off
	call clear_buffer

	ret

build_call_packet_buffer:

	ld hl, #digbuf
	ld a, (digidx)
	ld b, a
	cp #1
	jr nz, 1f
	ld a, (hl)
	cp #0
	ret z				; 0* = send it again
1:
	ld de, #outpacket
	ld ix, #cfg_mycall_1
	ld a, #0xC0
	or (ix + 0)
	ld (de), a
	inc de
	ld a, (ix + 1)
	sla4
	or (ix + 2)
	ld (de), a
	inc de
	ld a, (ix + 3)
	sla4
	or (ix + 4)
	ld (de), a
	inc de
	ld c, #3
1:
	inc c
	ld a, (hl)
	inc hl
	rla
	rla
	rla
	rla
	or #0xF
	ld (de), a
	inc de
	dec b
	jr z, 1f
	and #0xF0
	or (hl)
	inc hl
	dec de
	ld (de), a
	inc de
	dec b
	jr z, 1f
	ld a, c
	cp #6
	jr nz, 1b
1:
	ld a, c
	cp #6
	jr z, 1f
	ld a, #0xFF
	ld (de), a
	inc de
	inc c
	jr 1b
1:
	ret


#endif /* C_MODULES */

;----- Repeater main state machine (was fixed ROM) -----
#ifndef C_MODULES	/* c/rptr.c, bank 2 */

repeater_halt:
	call repeater_aoff
	call repeater_txoff
	jp repeater_init

repeater_run:
	ld a, (cfg_function)
	dec a                       ; if 1
	jp nz, repeater_init        ; not repeater, init in case later turned on

	ld a, (cfg_repeater_suspended)
	or a
	jr z, 1f
		ld a, (repeater_is_suspended)
		or a
		ret nz                     ; already. normal path during suspension.

		ld a, #1
		ld (repeater_is_suspended), a ; now going suspended.

		ld a, (txon)
		or a
		call z, repeater_txon
		call repeater_send_qrt

		jr repeater_halt
1:
	ld a, (repeater_is_suspended)
	or a
	jr z, 1f
		xor a
		ld (repeater_is_suspended), a     ; no more suspended.

		jp repeater_open_by_reset        ; back in business immediately.
1:

	; /LOCAL rising resets repeater into opening state

	ld a, (sio_bctrl_local)
	and #SB_LOCAL
	jr nz, 1f                   ; skip if pin was 1, already handled.
		ld a, (sio_bctrl_mirror)
		and #SB_LOCAL
		jr z, 1f                 ; skip if pin is 0 (and was 0).
		ld (sio_bctrl_local), a  ; remember bit

		jp repeater_open_by_reset
1:

	; Check any #? DTMF commands

	ld a, (repeater_req)
	cp #9                        ; #9_, close NOW
	jr nz, 1f
		xor a
		ld (repeater_req), a

		ld a, (cfg_repeater_cmd_9_hidden)
		or a
		jr nz, 2f                          ; not allowed, skip

		call repeater_aoff
		call repeater_send_roger
		call repeater_txoff
		jp repeater_idle
1:
	cp #0xFF                            ; #0_, restore squelch & power
	jr nz, 1f
		xor a
		ld (repeater_req), a
		ld (squelch_tightening), a
		ld (txpwr_increment), a
		call update_txpwr_if_tx
		call repeater_send_roger
		jr 2f
1:
	cp #1                              ; #1_, tighten squelch
	jr nz, 1f
		xor a
		ld (repeater_req), a
		ld a, (repeater_cfg_sqincr)
		ld (squelch_tightening), a
		call repeater_send_roger
		jr 2f
1:
	cp #3                                  ; #3_ rise tx power
	jr nz, 1f
		xor a
		ld (repeater_req), a
		ld a, (repeater_cfg_txincr)
		ld (txpwr_increment), a
		call update_txpwr_if_tx
		call repeater_send_roger
		jr 2f
1:
	cp #5                                  ; #5_ toggle sending of rssi-bongos
	jr nz, 1f
		xor a
		ld (repeater_req), a
		ld a, (repeater_cfg_rssi_bongos)
		xor #1
		ld (repeater_cfg_rssi_bongos), a
		call repeater_send_roger
		jr 2f
1:
	cp #0xFE                                ; internal - just roger
	jr nz, 1f
		xor a
		ld (repeater_req), a
		ld a, (txon)
		or a
		push af
		call z, repeater_txon
		call repeater_send_roger
		pop af
		call z, repeater_txoff
		jr 2f
1:
2:
	ld hl, (repeater_state)
	jp (hl)

;
;  No id sent here, operator announce assumed
;
repeater_operator_ptt:
	ld a, (cfg_function)
	dec a                   ; if 1
	ret nz
	call repeater_txon
	call repeater_aoff
	call repeater_send_blip
	call repeater_start_timer_ID
	call repeater_start_timer_OPEN
	jp repeater_open


;----- Repeater state and timer helpers (was fixed ROM) -----

repeater_setstate:
	pop hl
	ld (repeater_state), hl
	jp (hl)

;----------------------------------------------------------------------

repeater_check_carrier_access:
	ld a, (squelch_open)
	or a
	ret z                  ; Z, no signal -> no beep

	; squelch is open, do we use access=1=carrier

	ld a, (repeater_cfg_access_method)
	or a
	ret z                  ; Z, access=0=beeps
	cp #2
	ret z                  ; Z, access=2=none

	ret                    ; NZ, signal -> open, bypass toneaccess


repeater_recheck_beep_quickly:

	ld a, (pioa_data)
	and #PA_CCIR
	cp #0x80
	jr nz, 1f
	or #1                    ; NZ, 1750 Hz on
	ret
1:
	ld a, (dtmf_prevdata)
	cp #0x80 | (0xB << 3)       ; StD and DTMF * in raw format (shifted up)
	jr nz, 1f
	or #1
	ret                     ; NZ, DTMF * on
1:
	sub a                   ; Z, no beep
	ret

repeater_check_beep:

	call is_ptt_pressed
	ret nz                  ; PTT is pressed, act as if accesstone.

	ld a, (repeater_cfg_access_method)
	cp #2
	ret z                  ; Z, access none -> no beep (2 = none)
	cp #3
	ret z                  ; Z, access ctcss(3) -> no beep 

	ld a, (squelch_open)
	or a
	ret z                  ; Z, no signal -> no beep

	ld a, (pioa_data)
	and #PA_CCIR
	cp #0x80
	jr nz, 1f
	ld a, (ccir_tonetime)
	cp #25
	jr c, 1f
	or #1                    ; NZ, 1750 Hz on
	ret
1:
	ld a, (dtmf_prevdata)
	cp #0x80 | (0xB << 3)       ; StD and DTMF * in raw format (shifted up)
	jr nz, 1f
	or #1
	ret                     ; NZ, DTMF * on
1:
	sub a                   ; Z, no beep
	ret

repeater_check_carrier:

	; just reflect squelch

	ld a, (squelch_open)
	or a
	ret                     ; NZ, carrier


repeater_check_timer_ID:
	ld hl, (repeater_timer_ID)
	ld a, h
	or l
	ret

repeater_check_timer:
	ld hl, (repeater_timer_other)
	ld a, h
	or l
	ret                     ; NZ if timer still running

repeater_check_timer_BLIP:
	ld a, (repeater_timer_BLIP_state)
	cp #2
	ret nz                      ; NZ = stopped (0) or still counting (1)
	ld a, #0
	ld (repeater_timer_BLIP_state), a   ; make it idle. Z kept.
	ret                                 ; Z = counted down.

repeater_start_timer_ID:
	ld hl, (repeater_cfg_TID)
	ld (repeater_timer_ID), hl
	ret

repeater_start_timer_OPEN:
	ld hl, (repeater_cfg_TOPEN)
	ld (repeater_timer_other), hl
	ret

repeater_start_timer_HOG:
	ld hl, (repeater_cfg_THOG)
	ld (repeater_timer_other), hl
	ret

repeater_start_timer_CLS:
	ld hl, (repeater_cfg_TCLS)
	ld (repeater_timer_other), hl
	ret

repeater_start_timer_DEAD:
	ld hl, (repeater_cfg_TDEAD)
	ld (repeater_timer_other), hl
	ret

repeater_start_timer_BLIP:
	ld a, #0
	ld (repeater_timer_BLIP_state), a  ; stop
	ld a, (repeater_cfg_TBLIP)
	ld (repeater_timer_BLIP), a        ; reload
	ld a, #1
	ld (repeater_timer_BLIP_state), a  ; start (1), goes 2 when done.
	ret

;----------------------------------------------------------------------


;----- Repeater states, CW and note sequences (was fixed ROM) -----

	;
	; boot: (no emission)
	; stick here for a minute (allow std function to be restored)
	;
repeater_boot:
	ld hl, #60
	ld (repeater_timer_other), hl

	call repeater_setstate

	call repeater_check_timer
	jr nz, 1f
		jr repeater_idle
1:
	ret

	;
	; idle: (no emission)
	; 	beep or (carrier and using carrier access) ?
	; 		goto opening
	;
repeater_idle:
	xor a
	ld (squelch_tightening), a
	ld (txpwr_increment), a

	call repeater_setstate
	call repeater_check_beep
	jr z, 1f
		jr repeater_opening
1:
	call repeater_check_carrier_access
	jr z, 1f
		jr repeater_opening
1:
	ret

	;
	; opening: (no emission)
	;   tone/carrier exceeds N seconds ?
	;       goto idle
	; 	no carrier?
	; 		TXON, "ID", TMR0=TOPEN, TMR1=TID, goto open
	;
repeater_opening:

	call repeater_bump_open_counter

	ld hl, (repeater_cfg_TBEEPMAX)
	ld (repeater_timer_other), hl      ; validate tone length

	call repeater_setstate

	call repeater_check_timer
	jr nz, 1f
		jr repeater_beep_too_long
1:
	call repeater_check_carrier
	jr nz, 1f

repeater_open_by_reset:                ; from /LOCAL

		call repeater_txon
		call repeater_send_id_greet
		call repeater_start_timer_ID
		call repeater_start_timer_OPEN
		jr repeater_open
1:
	ret


repeater_beep_too_long:
	call repeater_setstate

	call repeater_check_carrier
	ret nz                               ; still carrier
	call repeater_recheck_beep_quickly
	ret nz                               ; still accesstone

	jr repeater_idle                     ; nothing. go idle.

	;
	; open: (tx on, but audio muted)
	; 	carrier?
	;     AND no beeps (quick check, cut off whistles) ?
	; 		AON, TMR0=THOG, goto active
	; 	TMR1?
	; 		"ID", TMR1=TID
	; 	TMR0?
	; 		TXOFF, TMR0=TCLS, goto closing
	;
repeater_open:
	call repeater_setstate

	call repeater_check_report_req

	call repeater_check_timer_BLIP
	jr nz, 1f
		call repeater_send_blip
1:
	call repeater_check_carrier
	jr z, 1f
		call repeater_recheck_beep_quickly
		jr nz, 1f
			call repeater_aon
			call repeater_start_timer_HOG
			jr repeater_active
1:
	call is_ptt_pressed
	jr z, 1f
		call repeater_aon
		call repeater_start_timer_HOG
		jr repeater_active
1:
	call repeater_check_timer_ID
	jr nz, 1f
		call repeater_send_id_during
		call repeater_start_timer_ID
1:
	call repeater_check_timer
	jr nz, 1f
		; end of open time.
		; either stay in closing state
		; or fully close now

		ld hl, (repeater_cfg_TCLS)
		ld a, l
		or h
		jr z, 2f
			call repeater_txoff               ; quiet time
			call repeater_start_timer_CLS
			jr repeater_closing
	2:
		call repeater_send_id_bye             ; fully close, no closing state
		call repeater_txoff
		jp repeater_idle
1:
	ret

	;
	; active: (tx AND audio on (or forced with PTT))
	; 	no carrier?
	; 		AOFF, TMR0=TOPEN, "BLIP", goto open
	; 	TMR1?
	; 		"ID", TMR1=TID
	; 	TMR0?
	; 		AOFF, "TO", TXOFF, TMR0=TLOCKOUT, goto lockout
	;
repeater_active:
	xor a
	ld (repeater_sig), a         ; determine peak rssi during an over

	call repeater_setstate

	call repeater_check_carrier
	jr nz, 1f

		call is_ptt_pressed
		jr nz, 1f                    ; if PTT is pressed, stay active.
			call repeater_aoff
			call repeater_start_timer_BLIP
			call repeater_start_timer_OPEN
			jr repeater_open
1:

	; this omission is a crummy fix
	; for oh5rab letting noise thru if
	; an over ends during identification
	; XXX now id will wait until an over ends
	; XXX still cannot speak over id

#if 0
	call repeater_check_timer_ID
	jp nz, 1f
		call repeater_send_id_during
		call repeater_start_timer_ID
1:
#endif

	call repeater_check_timer
	jr nz, 1f
		call repeater_aoff
		call repeater_send_to
		call repeater_txoff
		call repeater_start_timer_DEAD
		jp repeater_lockout
1:
	ret

	;
	; closing: (no emission)
	; 	carrier?
	;     no beeps (quick check) ?
	; 		TXON, AON, TMR0=THOG, goto active
	;     else
	;       goto reopening.
	; 	TMR0?
	; 		( TXON, "ID VA", TXOFF ) (if "ID VA" exists). goto idle.
	;
repeater_closing:
	call repeater_setstate

	call repeater_check_carrier
	jr z, 1f
		call repeater_recheck_beep_quickly
		jr nz, repeater_reopening

		call repeater_txon
		call repeater_aon
		call repeater_start_timer_HOG
		jr repeater_active
1:
	call is_ptt_pressed
	jr z, 1f
		call repeater_txon
		call repeater_aon
		call repeater_start_timer_HOG
		jr repeater_active
1:
	call repeater_check_timer
	jr nz, 1f
		call repeater_test_id_bye_length
		jp z, repeater_idle            ; if id bye is empty, 

		call repeater_txon
		call repeater_send_id_bye
		call repeater_txoff
		jp repeater_idle
1:
	ret

	;
	; reopening: (no emission)
	;   no beeps ?
	;      still carrier?
	;         goto active
	;      else
	; 		  goto open.
	; 	TMR0?
	; 		( TXON, "ID VA", TXOFF ) (if "ID VA" exists). goto idle.
	;
repeater_reopening:
	call repeater_setstate

	call repeater_recheck_beep_quickly
	jr nz, 1f

		call repeater_check_carrier
		jr z, 2f
			call repeater_txon
			call repeater_aon
			call repeater_start_timer_HOG
			jp repeater_active
	2:
		call repeater_txon
		call repeater_start_timer_BLIP
		call repeater_start_timer_OPEN
		jp repeater_open
1:
	call is_ptt_pressed
	jr z, 1f
		call repeater_txon
		call repeater_aon
		call repeater_start_timer_HOG
		jp repeater_active
1:
	call repeater_check_timer
	jr nz, 1f
		call repeater_test_id_bye_length
		jp z, repeater_idle            ; if id bye is empty, 

		call repeater_txon
		call repeater_send_id_bye
		call repeater_txoff
		jp repeater_idle
1:
	ret

	;
	; lockout: (no emission)
	; 		TMR0?
	; 			TXON, "ID VA", TXOFF
	; 
repeater_lockout:
	call repeater_setstate
	call repeater_check_timer
	jr nz, 1f
		call repeater_txon
		call repeater_send_id_bye
		call repeater_txoff
		jp repeater_idle
1:
	ret

;----------------------------------------------------------------------

repeater_bump_open_counter:
	ld ix, #repeater_cfg_open_counter
	inc (ix+0)
	ret nz
	inc (ix+1)
	ret nz
	inc (ix+2)
	ret

;----------------------------------------------------------------------

repeater_txon:
	ld a, (cfg_ctcss_output_when)
	cp #1                          ; CTCSS OUTPUT WHEN = TRANSMITTER
	call z, ctcss_maybe

	call tx_on
	jp force_redraw

repeater_txoff:
	ld a, (cfg_ctcss_output_when)
	cp #1                          ; CTCSS OUTPUT WHEN = TRANSMITTER
	call z, ctcss_off

	call tx_off
	jp force_redraw

ctcss_output_signal_or_cust:
	ld a, (cfg_ctcss_output_when)
	cp #2                          ; CTCSS OUTPUT WHEN = SIGNAL
	ret z
	cp #4                          ; CTCSS OUTPUT WHEN = CUSTOM
	ret

repeater_aon:

	call ctcss_output_signal_or_cust
	call z, ctcss_maybe           ; CTCSS OUTPUT WHEN = SIGNAL or CUSTOM

	ld a, (repeater_cfg_afsrc) ; Selects which way /MIC affects AF relaying
	cp #2
	jr z, 1f                    ; 2 = bypassed audio path
	cp #0
	jp z, mic_off               ; 0 = reversed MIC control
	jp mic_on
1:
	call is_ptt_pressed         ; bypassed case, MIC just controls handset
	jp z, mic_off               ; no ptt, no mic
	jp mic_on

repeater_aoff:

	call ctcss_output_signal_or_cust
	call z, ctcss_off_nohang      ; CTCSS OUTPUT WHEN = SIGNAL or CUSTOM

	ld a, (repeater_cfg_afsrc) ; Selects which way /MIC affects AF relaying
	cp #0
	jp z, mic_on
	jp mic_off

;----------------------------------------------------------------------

repeater_test_id_bye_length:          ; return Z if no bye message.

	ld a, (repeater_cfg_id_bye1)
	cp #EOS
	ret nz                            ; message is not ""
	ld a, (repeater_cfg_id_bye2)
	cp #EOS
	ret nz                            ; message is not ""
	ld a, (repeater_cfg_id_bye3)
	cp #EOS
	ret nz                            ; message is not ""

	ld a, (repeater_cfg_mprs_id)
	and #0x04
	ret                               ; zero-flag valid

;----------------------------------------------------------------------

repeater_send_id_greet:
	call send_cw_prolog

	ld hl, #repeater_cfg_id_greet1
	call send_cw
	ld hl, #repeater_cfg_id_greet2
	call send_cw
	ld hl, #repeater_cfg_id_greet3
	call send_cw

	call repeater_append_any_alerts
	call send_cw_epilog

	ld a, (repeater_cfg_mprs_id)
	and #0x01
	call nz, far_send_mprs_report_packet_1

	ret

repeater_send_id_during:
	call send_cw_prolog

	ld hl, #repeater_cfg_id_during1
	call send_cw
	ld hl, #repeater_cfg_id_during2
	call send_cw
	ld hl, #repeater_cfg_id_during3
	call send_cw

	call repeater_append_any_alerts
	call send_cw_epilog

	ld a, (repeater_cfg_mprs_id)
	and #0x02
	call nz, far_send_mprs_report_packet_1

	ret

repeater_send_id_bye:
	call send_cw_prolog

	ld hl, #repeater_cfg_id_bye1
	call send_cw
	ld hl, #repeater_cfg_id_bye2
	call send_cw
	ld hl, #repeater_cfg_id_bye3
	call send_cw

	call repeater_append_any_alerts
	call send_cw_epilog

	ld a, (repeater_cfg_mprs_id)
	and #0x04
	call nz, far_send_mprs_report_packet_1

	ret

repeater_append_any_alerts:

	; temperature outside window ?
	; NTC resistor to ground, so A/D goes down as temperature rises

	ld a, (ad_tp4)
	ld hl, #cfg_temperature_limit_hot
	cp (hl)
	ld hl, #repeater_cfg_msg_hot_alert
	call c, send_cw                     ; a/d below limit

	ld a, (cfg_temperature_limit_cold)
	ld hl, #ad_tp4
	cp (hl)
	ld hl, #repeater_cfg_msg_cold_alert
	call c, send_cw                     ; limit below a/d

	; high swr?
	; external coupler(s) at appropriate locations

	ld a, (cfg_rpm_limit)
	ld hl, #ad_rpm
	cp (hl)                           ; limit - curr
	ld hl, #repeater_cfg_msg_ant_bad
	call c, send_cw                   ; if current above limit

	ret

repeater_send_blip:
	call send_cw_prolog

	xor a
	ld (repeater_cw_sendit_all), a     ; but blip is pre-empted by carrier

	call repeater_select_which_blip    ; message string in HL
	ld c, a                            ; pitch now in C

	ld a, (repeater_cfg_musical_blips)
	or a
	jr z, 1f

	call send_notes
	call send_cw_epilog
	ret
1:
	push hl
	call cw_calc_blip                  ; C into timer value
	pop hl

	call send_cw                       ; from HL
	call send_cw_epilog
	ret


repeater_select_which_blip:

	ld a, (repeater_ptt_seen)             ; PTT BONGO ?
	or a
	jr z, 1f                              ; skip if no /PTT seen
		xor a
		ld (repeater_ptt_seen), a

		ld hl, #repeater_cfg_blip_link     ; send link-blip
		ld a, (cfg_cw_pitch_blip_link)
		ret
1:
	; GPIO BONGO ?

	ld a, (cfg_gpio2_state)               ; GPio2 - 2 bits
	and #3
	sla a
	ld b, a
	ld a, (cfg_gpio1_state)               ; GPio1 - 1 bits
	and #1
	or b                                  ; 0000 0cba
	jr z, 1f                              ; both off, normal blip
		dec a                             ; 0, 1 or 2
		sla a       ; 2 times
		sla a       ; 4 times
		sla a       ; 8 times
		ASSERT_EQ(SIZE_STR, 8)
		ld c, a
		ld b, #0
		ld hl, #repeater_cfg_blip_gpio_001 ; all 7 special gpio blips MUST be consecutive
		add hl, bc
		ld a, #EOS
		cp (hl)                           ; is this gpio-blip empty ?
		ld a, (cfg_cw_pitch_blip_gpio)
		ret nz                            ; not empty, send it.
1:
	; rssi bongos ?

	ld hl, #repeater_cfg_blip              ; default

	ld a, (repeater_cfg_rssi_bongos)
	or a
	jr z, 2f                              ; nope. just the default bongo.

	ld b, #255                             ; pick any better compares

	ld ix, #repeater_cfg_rssi_A
	ld a, (repeater_sig)                  ; peak rssi from the last second of last over
	sub (ix)
	jr c, 1f                              ; rssi < limit, cannot be this
	ld b, a                               ; this much over limit
	ld hl, #repeater_cfg_blip_rssi_A
1:
	ld ix, #repeater_cfg_rssi_B
	ld a, (repeater_sig)                  ; peak rssi from the last second of last over
	sub (ix)
	jr c, 1f                              ; rssi < limit, cannot be this
	cp b
	jr nc, 1f                             ; delta > previous delta, this limit was lower
	ld b, a                               ; better or equal, prefer this
	ld hl, #repeater_cfg_blip_rssi_B
1:
	ld ix, #repeater_cfg_rssi_C
	ld a, (repeater_sig)                  ; peak rssi from the last second of last over
	sub (ix)
	jr c, 1f                              ; rssi < limit, cannot be this
	cp b
	jr nc, 1f                             ; delta > previous delta, this limit was lower
	ld hl, #repeater_cfg_blip_rssi_C
1:


	ld a, (hl)
	cp #EOS
	jr nz, 2f
	ld hl, #repeater_cfg_blip              ; use this as the default again
2:
	ld a, (cfg_cw_pitch_blip)
	ret


repeater_send_to:
	call send_cw_prolog
	ld hl, #repeater_cfg_msg_hog
	call send_cw
	call send_cw_epilog
	ret

repeater_send_roger:
	call send_cw_prolog
	ld hl, #cw_msg_roger
	call send_cw
	call send_cw_epilog
	ret

repeater_send_qrt:
	call send_cw_prolog
	ld hl, #cw_msg_qrt
	call send_cw
	call send_cw_epilog
	ret

repeater_check_report_req:
	ld a, (repeater_req)
	cp #'#'
	ret nz

	xor a
	ld (repeater_req), a

	call send_cw_prolog

	ld hl, #cw_msg_u_are
	call send_cw                  ; UR_

	ld a, (last_sqtail)    ; 1 if tail, 0 if tailless
	ld b, a
	ld a, #5
	sub b                        ; 5-0 or 5-1
	call send_cw_chr             ; UR_5

	; S calculation, first see if 
	; 9 (greater than or equal to s9level) or
	; 1 (less than s1level).

	ld a, (repeater_sig)

	ld b, #9
	ld hl, #cfg_rssi_S9
	cp (hl)
	jr nc, 2f                  ; rssi >= level9

	ld b, #1
	ld hl, #cfg_rssi_S1
	sub (hl)                    ; fraction -= floor_value
	jr c, 2f                   ; rssi < level1

	; damned, need some dancing for S-levels 2...8

	ld b, #0
	ld c, a                    ; fraction in bc (8bit value)

	ld a, (cfg_rssi_S9)
	sub (hl)                    ; fullscale -= floor_value, into A

	; S = 7 * fraction / fullscale + 2

	ld h, b
	ld l, c
	add hl, bc
	add hl, bc
	add hl, bc
	add hl, bc
	add hl, bc
	add hl, bc      ; six adds, *= 7

	ld b, #0
	ld c, a            ; fullscale in bc (8bit value)

	ld a, #1            ; start from 2-1, always at least one inc
	and a              ; clear CY for sbc hl
1:
	inc a
	sbc hl, bc
	jr nc, 1b
	ld b, a
2:
	ld a, b
	call send_cw_chr          ; UR_59

	call send_cw_epilog

	ld a, (repeater_cfg_mprs_id)
	and #0x08
	call nz, far_send_mprs_report_packet_1

	ret

	ALIGN(3, 0)
cw_msg_roger:	.ascii "R"
.db EOS, EOS, EOS, EOS, EOS, EOS, EOS
cw_msg_u_are:	.ascii "UR "
.db         EOS, EOS, EOS, EOS, EOS
cw_msg_qrt:		.ascii "QRT"
.db         EOS, EOS, EOS, EOS, EOS

;----------------------------------------------------------------------
;----------------------------------------------------------------------
;
;  CW beeper
;
; Note, the cw routines sometimes longjmp out from the depths
; and abort messages. cw_epilog must undo stuff.
;
; tabled bits 1=dit, 0=dash. right aligned into byte.
; unused bits contain first one 1, then zeroes (0b10000000 terminate).
;
send_cw_prolog:

	ld h, #0                  ; maybe do ctcss during blips (v3_Z had
				  ; "xor h": the flag got the caller's H, and
				  ; the epilog cut CTCSS after every message)
	ld a, (cfg_ctcss_output_when)
	cp #4
	jr nz, 1f                 ; not CUSTOM
	ld a, (ctcss_is_on)
	or a
	jr nz, 1f                 ; already on, A nz
	call ctcss_maybe
	ld a, (ctcss_is_on)       ; maybe?
	or a
	jr z, 1f                  ; 'maybe' was 'no'
	inc h                     ; set flag to stop it at cw_epilog
1:
	ld a, h
	ld (ctcss_custom_flag), a ; picked by cw_epilog


	call cw_calc_delays

	ld a, #1
	ld (nosir), a
	ld (repeater_cw_sendit_all), a

	call ccir_on
	call silence_timer1
	jr 1f

send_cw_epilog:

	ld a, (ctcss_custom_flag)  ; need to stop ctcss sometimes, if CUSTOM
	or a
	call nz, ctcss_off

	call ccir_off
	call silence_timer1

	xor a
	ld (nosir), a
1:
	ld a, #20
	call b0_ccir_tx_timer_wait

	ret

send_cw:
	ld (repeater_cw_jmpbuf), sp    ; in case sequence is pre-empted

	ld b, #SIZE_STR
1:
	ld a, (hl)
	inc hl
	cp #EOS
	jr z, 1f
	call cw_chr
	djnz 1b
1:
	jp silence_timer1

send_cw_chr:
	call cw_chr
	jp silence_timer1

; Separate character, 3 dit-times of silence after last tone

cw_chr:
	push hl
	push bc
	call cw_chr_1        ; *_===_
	call cw_pause_2      ; __
	pop bc
	pop hl
	ret

; play one cw character. No extra slot is appended, just the one silence.
; i.e. 2 slots per dit, 4 slots per dash.

cw_chr_1:               ; fill slots contained in chr
	ld b, #0
	ld c, a
	ld hl, #cw_tab
	add hl, bc
	ld a, (hl)
	or a                ; terminator 1-bit there ?
	jr nz, 1f
	ld a, #0b11001110    ; ? and 0b10 to terminate
1:
	cp #0x80             ; terminator at left edge ?
	ret z               ; return then

	sla a               ; CY has dit/dah, rest shifted, 0 appended
	push af
	call cw_ditdash     ; 1 or 3 slots tone
	call cw_pause_1     ; 1 slot silence
	pop af
	jr 1b

cw_pause_1:
	ld a, (cw_slot_ticks)
	ld hl, #4
	jr cw_slots

cw_pause_2:
	ld a, (cw_slot_ticks)
	add a, a
	ld hl, #4
	jr cw_slots

cw_ditdash:
	ld a, (cw_slot_ticks)
	jr c, 1f            ; CY=1=dit = 1 slot only
	ld d, a
	add a, d
	add a, d               ; small values, *= 3 wont carry
1:
	ld hl, (cw_pitch_cnt)
	jr cw_slots

cw_slots:
	ld d, a
	call start_marker_tone ; hl pitch, d dur

	; nothing needs to be saved here

	call b0_cw_wait_tone                ; waits in bank 0, NZ = pre-empt
	jr z, 1f
		ld sp, (repeater_cw_jmpbuf)
		ret                                 ; ZAP back.
1:

	; tone or silence ends,
	; place to open or close relay audio
	; XXX infinite stupidity

	call repeater_check_carrier         ; NZ if carrier
	jp nz, repeater_aon
	jp repeater_aoff


note_to_pitch_table:
	.dw MT_CALCHZ( 500), MT_CALCHZ( 600), MT_CALCHZ( 700), MT_CALCHZ( 800), MT_CALCHZ( 900)
	.dw MT_CALCHZ(1000), MT_CALCHZ(1100), MT_CALCHZ(1200), MT_CALCHZ(1300), MT_CALCHZ(1400)
	.dw MT_CALCHZ(1500), MT_CALCHZ(1600), MT_CALCHZ(1700), MT_CALCHZ(1800), MT_CALCHZ(1900)
	.dw MT_CALCHZ(2000), MT_CALCHZ(2100), MT_CALCHZ(2200), MT_CALCHZ(2300), MT_CALCHZ(2400)
	.dw MT_CALCHZ(2500), MT_CALCHZ(2600), MT_CALCHZ(2700), MT_CALCHZ(2800), MT_CALCHZ(2900)
	.dw 4

send_notes:
	ld (repeater_cw_jmpbuf), sp    ; in case sequence is pre-empted

	ld b, #SIZE_STR
1:
	ld a, (hl)
	inc hl
	cp #EOS
	jr z, 1f
	push hl
	push bc
	call send_note_chr
	pop bc
	pop hl
	djnz 1b
1:
	jp silence_timer1


send_note_chr:
	cp #25                  ; 0 ... 9, A ... F, G ...O are "notes"
	jr c, 1f
	ld a, #25               ; 25 valid and one last for silence in above table
1:
	sla a                  ; word index
	ld c, a
	ld b, #0
	ld ix, #note_to_pitch_table
	add ix, bc
	ld l, (ix+0)
	ld h, (ix+1)

	ld d, #10                           ; 100msec per tone or pause
	call start_marker_tone             ; hl pitch, d dur

	call b0_cw_wait_tone                ; waits in bank 0, NZ = pre-empt
	ret z
		ld sp, (repeater_cw_jmpbuf)
		ret                                 ; ZAP back.

;----------------------------------------------------------------------
;----------------------------------------------------------------------
;
; feel free to skip the gunk with /-------
;
; 1 is dit, 0 is dash, terminating pattern 10*
; not quite complete.

cw_tab:
	.db 0b00000100 ; 0
	.db 0b10000100 ; 1
	.db 0b11000100 ; 2
	.db 0b11100100 ; 3
	.db 0b11110100 ; 4
	.db 0b11111100 ; 5
	.db 0b01111100 ; 6
	.db 0b00111100 ; 7
	.db 0b00011100 ; 8
	.db 0b00001100 ; 9
	.db 0b10100000 ; A
	.db 0b01111000 ; B
	.db 0b01011000 ; C
	.db 0b01110000 ; D
	.db 0b11000000 ; E
	.db 0b11011000 ; F
	.org cw_tab + ' '
	.db 0b10000000 ; sp
	.org cw_tab + 0x22
	.db 0b10110110 ; "
	.org cw_tab + '#'
	.db 0b11101010 ; VA aka SK overload #
	.org cw_tab + '$'
	.db 0b10111100 ; AS overload $
	.org cw_tab + 0x27
	.db 0b10000110 ; '
	.org cw_tab + '('
	.db 0b01001010 ; (
	.db 0b01001010 ; ) ) balance is everything
	.org cw_tab + ','
	.db 0b00110010 ; ,
	.db 0b01111010 ; -
	.db 0b10101010 ; .
	.db 0b01101100 ; /
	.org cw_tab + '0'
	.db 0b00000100 ; 0
	.db 0b10000100 ; 1
	.db 0b11000100 ; 2
	.db 0b11100100 ; 3
	.db 0b11110100 ; 4
	.db 0b11111100 ; 5
	.db 0b01111100 ; 6
	.db 0b00111100 ; 7
	.db 0b00011100 ; 8
	.db 0b00001100 ; 9
	.db 0b00011110 ; :
	.org cw_tab + '?'
	.db 0b11001110 ; ?
	.org cw_tab + 'A'
	.db 0b10100000 ; A
	.db 0b01111000 ; B
	.db 0b01011000 ; C
	.db 0b01110000 ; D
	.db 0b11000000 ; E
	.db 0b11011000 ; F
	.db 0b00110000 ; G
	.db 0b11111000 ; H
	.db 0b11100000 ; I
	.db 0b10001000 ; J
	.db 0b01010000 ; K
	.db 0b10111000 ; L
	.db 0b00100000 ; M
	.db 0b01100000 ; N
	.db 0b00010000 ; O
	.db 0b10011000 ; P
	.db 0b00101000 ; Q
	.db 0b10110000 ; R
	.db 0b11110000 ; S
	.db 0b01000000 ; T
	.db 0b11010000 ; U
	.db 0b11101000 ; V
	.db 0b10010000 ; W
	.db 0b01101000 ; X
	.db 0b01001000 ; Y
	.db 0b00111000 ; Z
	.db 0b10101000 ; aiti
	.db 0b10100110 ; ruats. o
	.db 0b00011000 ; oljy

	.org cw_tab + 128
#endif /* C_MODULES */

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
;  as bank 1, entered through far2_* stubs (bank2_call).  Linked at the
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
#ifdef C_MODULES
	; c/freq.c hard-codes the band record layout
	ASSERT_EQ(num_bandrecs, 6)
	ASSERT_EQ(size_bandrec, 14)
	ASSERT_EQ(cfg_band1_duplex - cfg_band1_start, 6)
	ASSERT_EQ(cfg_band1_step - cfg_band1_start, 9)
	ASSERT_EQ(cfg_band1_autoreject - cfg_band1_start, 12)
	ASSERT_EQ(cfg_other_duplex - cfg_band1_start, 6 * 14 + 6)
	ASSERT_EQ(DPX_SPLIT, 3)
#endif
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

	cfg_serv_blip_pitch:    BYTE     ; local vÃ¤libongo

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
#ifdef C_MODULES
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
#endif

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
gps_sentence_size = . - gps_sentence      ; must be bigger than 44 (aisin_seiki)

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

#ifdef C_MODULES
C_BSS_SIZE = 192
c_bss:	.ds C_BSS_SIZE	; the C modules' _DATA area is linked here (tools/link.py)
c_bss_end:
#endif

_end:
cfg_image_buffer:		; all_config_get receives the NV image here (up to the stack)

chk_size_stack = 0x10000 - _end
slack_for_stack = chk_size_stack

	ASSERT_GT(chk_size_stack, (4 * 1024))

