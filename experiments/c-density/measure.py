"""Compare SDCC-compiled C sizes with the original assembler routines."""
import re, subprocess, sys, os
sys.path.insert(0, '../../emu/python')
from r58emu import load_symbols
SDCC = os.environ.get('SDCC', 'sdcc')
INC = os.environ.get('SDCC_INC', '')

def c_sizes(flags):
    subprocess.run([SDCC, '-mz80'] + (['-I' + INC] if INC else []) + flags +
                   ['-c', 'sample.c', '-o', 'sample.rel'], check=True,
                   stderr=subprocess.DEVNULL)
    labels, end = [], 0
    for ln in open('sample.lst'):
        m = re.match(r'^\s+([0-9A-F]{6})\s+(?:[0-9A-F]{2}\s)*\s*\d+\s+(_\w+)::?\s*$', ln)
        if m:
            labels.append((m.group(2)[1:], int(m.group(1), 16)))
        m2 = re.match(r'^\s+([0-9A-F]{6})\s+((?:[0-9A-F]{2}\s)+)', ln)
        if m2:
            end = max(end, int(m2.group(1), 16) + len(m2.group(2).split()))
    sizes = {}
    for i, (n, a) in enumerate(labels):
        nxt = labels[i + 1][1] if i + 1 < len(labels) else end
        sizes[n] = nxt - a
    return sizes

sym = load_symbols('../../firmware/build/r58.lst')
code = sorted(v for v in sym.values() if v < 0x8000)
def asm_size(name):
    a = sym[name]
    return min(v for v in code if v > a) - a

# asm routine groups equivalent to the C functions
groups = {
    'squelch (+helpers, audioc_on/off)': (['read_squelcher_value', 'squelch', 'squelch_is_closed',
                                           'squelch_is_open', 'audioc_on', 'audioc_off'],
                                          ['squelch', 'audioc_on', 'audioc_off', 'squelch_is_closed',
                                           'squelch_is_open', 'sat_sub', 'read_squelcher_value',
                                           'ctcss_gate']),
    'a2i': (['a2i'], ['a2i']),
    'bin_bcd': (['bin_bcd_AHL_DDEEHHLL'], ['bin_bcd']),
    'packet CRCs (short/long/secret)': (['append_short_packet_crc', 'append_secret_packet_crc',
                                         'append_long_packet_crc'],
                                        ['append_short_packet_crc', 'append_long_packet_crc',
                                         'append_secret_packet_crc', 'crc_run', 'put_crc']),
}
for flags in (['--opt-code-size', '--sdcccall', '1', '--max-allocs-per-node', '200000'],
              ['--opt-code-size', '--sdcccall', '0']):
    cs = c_sizes(flags)
    total_c = sum(cs.values())
    print('SDCC', ' '.join(flags))
    ta = tc = 0
    for g, (asmn, cn) in groups.items():
        a = sum(asm_size(n) for n in asmn)
        # C size: public functions plus their static helpers (whole file share)
        c = sum(cs.get(n, 0) for n in cn)
        ta += a; tc += c
        print('  %-36s asm %4d   C %4d   x%.2f' % (g, a, c, c / a))
    # statics are inlined or emitted separately: report whole-file total too
    print('  %-36s asm %4d   C %4d   x%.2f  (whole C file incl. static helpers)' % ('TOTAL', ta, total_c, total_c / ta))
