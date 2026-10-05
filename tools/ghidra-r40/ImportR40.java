// Nokia R40 (RC40 / RD40) ROM set-up for Ghidra: run as a pre-script on a
// raw import of the 256 KB EPROM at address 0 with language H8:BE:32:H8532
// (tools/ghidra-r40/install.sh, import.sh).  Lays out the L100 memory map,
// the H8/532 register field, the page-register context the firmware sets at
// reset, the interrupt vectors and the addresses known from notes/r40.md.
//@category R40

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.lang.Register;
import ghidra.program.model.listing.ProgramContext;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.symbol.SourceType;
import ghidra.program.model.data.DWordDataType;
import java.math.BigInteger;

public class ImportR40 extends GhidraScript {

	Address a(long off) {
		return currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(off);
	}

	void block(String name, long start, long len, boolean volatileIo, String comment)
			throws Exception {
		Memory mem = currentProgram.getMemory();
		MemoryBlock b = mem.createUninitializedBlock(name, a(start), len, false);
		b.setRead(true);
		b.setWrite(true);
		b.setExecute(false);
		b.setVolatile(volatileIo);
		b.setComment(comment);
	}

	void label(long off, String name) throws Exception {
		createLabel(a(off), name, true, SourceType.USER_DEFINED);
	}

	void context(String reg, long start, long end, long value) throws Exception {
		ProgramContext pc = currentProgram.getProgramContext();
		Register r = pc.getRegister(reg);
		pc.setValue(r, a(start), a(end), BigInteger.valueOf(value));
	}

	@Override
	public void run() throws Exception {
		Memory mem = currentProgram.getMemory();
		MemoryBlock rom = mem.getBlock(a(0));
		long romEnd = rom.getEnd().getOffset();
		rom.setName("rom");
		rom.setWrite(false);
		rom.setExecute(true);

		// the H8/532 register field overlays page 0 at FF80-FFFF
		mem.split(rom, a(0xFF80));
		MemoryBlock hi = mem.getBlock(a(0xFF80));
		mem.split(hi, a(0x10000));
		mem.removeBlock(mem.getBlock(a(0xFF80)), monitor);
		mem.getBlock(a(0x10000)).setName("rom_p1");
		block("regs", 0xFF80, 0x80, true, "H8/532 register field");

		// L100 memory map (notes/r40.md, Hardware)
		block("nvram", 0x80000, 0x4000, false,
			"battery-backed SRAM window; P9.2 selects the half; stack from TP:SP 8:1680");
		block("sram", 0x88000, 0x8000, false, "SRAM 32 KB");
		block("fx429", 0xA0000, 0x8, true, "FX429 FFSK modem");
		block("out0", 0xA8000, 0x1, true,
			"OUT0: D0 DAC CS, D1 RTC CS, D2 FX803 CS, D3 NV page, D6/D7 TMCI select");
		block("out1", 0xB0000, 0x1, true,
			"OUT1: D0 TX ON, D1-D3 4094 strobes, D4 CTS, D5 DSR, D6 DCD, D7 RI");
		block("pcf8584", 0xB8000, 0x2, true, "PCF8584 I2C: +0 data, +1 control");
		label(0xA0000, "FX429");
		label(0xA8000, "OUT0");
		label(0xB0000, "OUT1");
		label(0xB8000, "PCF8584_S0");
		label(0xB8001, "PCF8584_S1");

		// page registers as set at reset (0x2728): TP = DP = EP = 8, BR = FF;
		// CP is the page of the code
		context("DP", 0, romEnd, 8);
		context("EP", 0, romEnd, 8);
		context("TP", 0, romEnd, 8);
		context("BR", 0, romEnd, 0xFF);
		for (long p = 0; p <= romEnd; p += 0x10000) {
			long end = Math.min(p + 0xFFFF, romEnd);
			if (p == 0) {
				context("CP", 0, 0xFF7F, 0);
			} else {
				context("CP", p, end, p >> 16);
			}
		}

		// vectors: 4 bytes, byte 1 = CP, bytes 2-3 = PC
		for (int v = 0; v < 64; v++) {
			Address va = a(v * 4);
			int page = mem.getByte(va.add(1)) & 0xFF;
			int pc = mem.getShort(va.add(2)) & 0xFFFF;
			if (page == 0xFF && pc == 0xFFFF) {
				continue;
			}
			createData(va, new DWordDataType());
			long target = ((long) page << 16) | pc;
			createMemoryReference(getDataAt(va), a(target),
				ghidra.program.model.symbol.RefType.DATA);
			String name = getSymbolAt(va) != null
				? getSymbolAt(va).getName().replaceFirst("^vec_", "")
				: String.format("vector_%d", v);
			if (getFunctionAt(a(target)) == null) {
				disassemble(a(target));
				createFunction(a(target), v == 0 ? "reset" : "isr_" + name);
			}
			addEntryPoint(a(target));
		}

		// found in earlier sessions (notes/r40.md)
		label(0x180, "version_string");
		label(0x2E34, "font_5x7");
		label(0x31398, "fx429_read");
		label(0x3689C, "nv_block_commit");
		label(0x36966, "nv_block_table_dispatch");
		label(0x36A47, "nv_block2_commit");
		createFunction(a(0x3689C), "nv_block_commit");
		createFunction(a(0x31398), "fx429_read");

		// synthesizers (Ghidra + emulator, 2026-10-05)
		label(0x2E346, "pll_shift");		// word, bit count on SD/CLK
		label(0x2F674, "pll_rx_load");		// RX 0-channel + channel, SRE
		label(0x2F6F5, "pll_tx_load");		// TX 0-channel + channel, STE
		label(0x2F831, "pll_reference_load");	// R word by spacing, both strobes
		label(0x36202, "rx_tune");		// remembers the channel at 8BC9C
		label(0x36220, "tx_tune");		// remembers the channel at 8BC9E
		label(0x1CD86, "tx_park");		// arg != 1: tx_tune(last + 10)
		label(0x1B50, "pll_far_vectors");
		label(0x8BAE1, "p7_shadow");
		label(0x8BAF1, "out1_shadow");
		label(0x8BC9C, "rx_channel");
		label(0x8BC9E, "tx_channel");

		// dial codes and simplex (Ghidra + emulator, 2026-10-05).  ROM
		// 0x5EE2-0x63CA is copied to 8:1680 at reset; the code table
		// ("*2*" .. "*31*") is used from there
		label(0x81A88, "dial_codes");
		label(0x81AF1, "dial_code_star55");
		label(0xA213, "dial_star55");		// preloads "*55*", installs the key handler
		label(0xA22A, "dial_star55_key");	// '#': "Give simplex channel" or go
		label(0xA288, "dial_hash55");		// #55: leave simplex
		label(0x34ADB, "simplex_channel_check");	// n <= 251 and record n st bit 3
		label(0x1CE91, "watchdog_kick");	// P9.0 pulse (external IC57) + WDT reload

		// NV parameter blocks (two checksummed copies, +0x2000)
		long[][] nv = {{0x000, 0x12B}, {0x12C, 0x135}, {0x136, 0x1CB}, {0x1CC, 0x3F1},
			{0x3F2, 0x487}, {0x488, 0xA6D}, {0xA6E, 0xE88}, {0xE89, 0x10A9},
			{0x10AA, 0x129E}, {0x129F, 0x15FB}, {0x15FC, 0x1674}};
		for (long[] b : nv) {
			label(0x80000 + b[0], String.format("nv_blk_%04X", b[0]));
			label(0x80000 + b[1], String.format("nv_blk_%04X_cks", b[0]));
		}
		label(0x80056, "nv_band_low");
		label(0x8005A, "nv_band_mid");
		label(0x8005E, "nv_band_high");
		label(0x80063, "nv_band");
		label(0x80064, "nv_tx_0channel");
		label(0x80068, "nv_rx_0channel");
		label(0x80071, "nv_spacing");
		label(0x80128, "nv_duplex");
		label(0x8048E, "nv_param_records");
		label(0x8053C, "nv_simplex_ch1");
	}
}
