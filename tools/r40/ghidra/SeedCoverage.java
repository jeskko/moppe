// Seed disassembly from the emulator's ROM coverage map (coverage.py):
// disassemble at every executed address Ghidra has not decoded, then make
// a function at every executed call target and exception entry (flags 4
// and 8) that has none (computed calls, the vectors' handlers).
// Reports the executed addresses Ghidra still decodes differently.
//
// Script argument: the coverage file (flags in the low nibble, the
// instruction length in the high nibble of executed addresses).
//@category R40

import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressSet;
import ghidra.program.model.listing.Data;
import java.nio.file.Files;
import java.nio.file.Paths;

public class SeedCoverage extends GhidraScript {
	@Override
	public void run() throws Exception {
		byte[] cov = Files.readAllBytes(Paths.get(getScriptArgs()[0]));
		AddressSet seeds = new AddressSet();
		int executed = 0;
		for (int a = 0; a < cov.length; a++) {
			if ((cov[a] & 1) == 0) {
				continue;
			}
			executed++;
			Address ad = toAddr(a);
			if (getInstructionAt(ad) == null) {
				seeds.add(ad);
				// executed bytes are code: drop data the analyzers put over
				// them (the high nibble is the instruction length)
				for (int k = 0; k < Math.max(1, (cov[a] >> 4) & 15); k++) {
					Data d = getDataContaining(ad.add(k));
					if (d != null) {
						removeData(d);
					}
				}
			}
		}
		println(String.format("%d executed addresses, %d not yet decoded", executed,
			seeds.getNumAddresses()));
		DisassembleCommand cmd = new DisassembleCommand(seeds, null, true);
		cmd.applyTo(currentProgram, monitor);

		int funcs = 0;
		for (int a = 0; a < cov.length; a++) {
			if ((cov[a] & 12) == 0) {
				continue;
			}
			Address ad = toAddr(a);
			if (getInstructionAt(ad) != null && getFunctionAt(ad) == null) {
				if (createFunction(ad, null) != null) {
					funcs++;
				}
			}
		}
		int bad = 0;
		for (int a = 0; a < cov.length; a++) {
			if ((cov[a] & 1) != 0 && getInstructionAt(toAddr(a)) == null) {
				if (bad++ < 20) {
					println("still not an instruction start: " + toAddr(a));
				}
			}
		}
		println(String.format("%d functions created, %d executed addresses not decoded",
			funcs, bad));
	}
}
