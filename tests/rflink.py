"""
A simulated RF channel between emulated radios, at FX429 byte level.

Radio.modem_rx() takes one packet (the emulator supplies SYNC, then the
bytes); a transmitting radio's modem output is MODEM_TX events, each
packet prefixed with the firmware's 5-byte `packet_header` (AA AA AA C4
D7). Link steps all radios in lockstep and forwards each packet a radio
sends to every other radio that would hear it: the sender's transmitter
was on when the bytes went out, its TX frequency is the receiver's RX
frequency, and the receiver is not transmitting itself.  Each radio
keeps its own clock (they may have booted at different times), so the log
uses link time.
"""
HEADER = bytes([0xAA, 0xAA, 0xAA, 0xC4, 0xD7])
GAP_S = 0.010          # no modem byte for this long ends a packet
BYTE_S = 8 / 1200      # FX429 byte time (the emulator's MDM_BYTE_XT)


class Link:
    def __init__(self, *radios, step=0.005):
        self.radios = list(radios)
        self.step = step
        self.tx_on = {id(r): False for r in radios}
        self.buf = {id(r): bytearray() for r in radios}
        self.last = {id(r): 0.0 for r in radios}
        self.t = 0.0           # link time: seconds of Link.run so far
        self.log = []          # (link time, sender index, packet)
        self.rxq = {id(r): [] for r in radios}     # modem_rx holds one packet
        self.busy = {id(r): 0.0 for r in radios}
        self.seen = {id(r): set() for r in radios}  # ids of handled events

    def run(self, seconds):
        end = self.t + seconds
        while self.t < end:
            for r in self.radios:
                r.run(self.step)
            self.t += self.step
            for i, r in enumerate(self.radios):
                self._collect(i, r)
            for r in self.radios:
                self._feed(r)

    def _feed(self, r):
        k = id(r)
        if self.rxq[k] and r.time >= self.busy[k]:
            pkt = self.rxq[k].pop(0)
            r.modem_rx(pkt)
            self.busy[k] = r.time + (len(pkt) + 2) * BYTE_S

    def _collect(self, i, r):
        k = id(r)
        keep, seen = [], set()
        for ev in r.events:
            t, kind, arg = ev
            if id(ev) in self.seen[k]:
                keep.append(ev)
                seen.add(id(ev))
                continue
            if kind == "TX_ON":
                self.tx_on[k] = True
            elif kind == "TX_OFF":
                self.tx_on[k] = False
            if kind == "MODEM_TX":
                if self.tx_on[k]:           # modem bytes with TX off go nowhere
                    self.buf[k].append(arg)
                    self.last[k] = t
                continue                    # consumed
            keep.append(ev)
            seen.add(id(ev))
        r.events[:] = keep
        self.seen[k] = seen                 # events the test took are gone
        if self.buf[k] and r.time - self.last[k] >= GAP_S:
            self._deliver(i, r, bytes(self.buf[k]))
            self.buf[k].clear()

    def _deliver(self, i, sender, data):
        for pkt in data.split(HEADER)[1:]:
            self.log.append((self.t, i, pkt))
            for r in self.radios:
                if r is sender or r.transmitting():
                    continue
                if abs(sender.tx_hz() - r.rx_hz()) > 1000:
                    continue
                self.rxq[id(r)].append(pkt)
