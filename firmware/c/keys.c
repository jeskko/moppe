/*
 * Key dispatch in C (Phase 4, notes/hybrid-plan.md).  Built with
 * `make C=1`; replaces keycheck, dokey, dokey_not_menu, menu_input and
 * handle_key_during_tx of r58.s (see the C_MODULES blocks there).
 *
 * Every handler takes the key code in A, which is where --sdcccall 1
 * passes a uint8_t argument (checked: none reads B or C before writing
 * them).  The handlers do not preserve IX, so no function here has a
 * stack frame.  Mainline only.
 *
 * Key codes: 0-9 digits, '#', '*', 'C', 'E', 'B', 'S', 'R', 'K', 'T',
 * '+', '-'; 0x0B/0x0C/0x0E are B/C/E from the CU53AN; 0x80-0x89 long
 * presses of 0-9.
 */
#include <stdint.h>

extern uint8_t key, menu_active, cu_is_alfa;

extern void clear_key(void);			/* preserves A */
extern void no_feedback(void);
extern void open_selective(void);
extern void redraw(void);

extern void insdig_or_scan_toggle(uint8_t), mute_squelch_selective(uint8_t),
	execute(uint8_t), backspace(uint8_t), far_toggle_or_position_menu(uint8_t),
	beep_or_fsk_send(uint8_t), up_vola(uint8_t), dn_vola(uint8_t),
	monitor_audio(uint8_t), up_sqlv(uint8_t), dn_sqlv(uint8_t),
	def_sqlv(uint8_t), up_memo(uint8_t), dn_memo(uint8_t), def_memo(uint8_t),
	up_freq(uint8_t), dn_freq(uint8_t), def_freq(uint8_t), def_vola(uint8_t),
	scanner_key(uint8_t), duplex_key(uint8_t), step_audio_dst(uint8_t),
	insdig(uint8_t), insdig_alpha(uint8_t), insdig_punct(uint8_t),
	far_menu_enter_or_walk(uint8_t), far_menu_defval_or_exec(uint8_t),
	far_menu_up_value(uint8_t), far_menu_dn_value(uint8_t),
	far_menu_next_group(uint8_t), far_menu_prev(uint8_t),
	step_txpwr_up(uint8_t), step_txpwr_down(uint8_t),
	dtmf_cu58af(uint8_t), dtmf_bang_tone(uint8_t);

void dokey_not_menu(uint8_t k)
{
	if (k < 10) {
		insdig_or_scan_toggle(k);
		return;
	}
	switch (k) {
	case 'T':	mute_squelch_selective(k); break;
	case '#':	execute(k); break;
	case 'C':
	case 0x0C:	backspace(k); break;
	case 'E':
	case 0x0E:	far_toggle_or_position_menu(k); break;
	case '*':	beep_or_fsk_send(k); break;
	case '+':	up_vola(k); break;
	case '-':	dn_vola(k); break;
	case 'B':
	case 0x0B:	monitor_audio(k); break;
	case 0x81:	up_sqlv(k); break;
	case 0x84:	dn_sqlv(k); break;
	case 0x87:	def_sqlv(k); break;
	case 0x82:	up_memo(k); break;
	case 0x85:	dn_memo(k); break;
	case 0x88:	def_memo(k); break;
	case 0x83:	up_freq(k); break;
	case 0x86:	dn_freq(k); break;
	case 0x89:	def_freq(k); break;
	case 0x80:	def_vola(k); break;
	case 'S':	scanner_key(k); break;
	case 'R':	duplex_key(k); break;
	case 'K':	step_audio_dst(k); break;
	}
}

static void menu_input(uint8_t k)
{
	if (k < 10) {
		insdig(k);
		return;
	}
	if (k >= 0x81 && k <= 0x89) {		/* long digit: letters */
		insdig_alpha(k);
		return;
	}
	switch (k) {
	case 'C':
	case 0x0C:	backspace(k); break;
	case 'E':
	case 0x0E:	far_toggle_or_position_menu(k); break;
	case '#':	far_menu_enter_or_walk(k); break;
	case '*':	far_menu_defval_or_exec(k); break;
	case '+':	far_menu_up_value(k); break;
	case '-':	far_menu_dn_value(k); break;
	case 'B':
	case 0x0B:	monitor_audio(k); break;
	case 0x80:	insdig_punct(k); break;	/* long 0: punctuation */
	case 'S':	far_menu_next_group(k); break;
	case 'R':	far_menu_prev(k); break;
	case 'K':	step_audio_dst(k); break;
	}
}

static void dokey(uint8_t k)
{
	if (menu_active)
		menu_input(k);
	else
		dokey_not_menu(k);
}

/* mainloop: one pending key */
static uint8_t pending;			/* static: no stack frame */

void keycheck(void)
{
	if (key == 0xFF)
		return;
	pending = key;
	clear_key();
	dokey(pending);
	no_feedback();
	open_selective();
	redraw();
}

/* from pttcheck while transmitting: +/- step the TX power, others send
 * DTMF */
void handle_key_during_tx(uint8_t k)
{
	clear_key();
	if (k == '+')
		step_txpwr_up(k);
	else if (k == '-')
		step_txpwr_down(k);
	else if (cu_is_alfa)
		dtmf_cu58af(k);
	else
		dtmf_bang_tone(k);
}
