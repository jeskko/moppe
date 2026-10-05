// Write every instruction Ghidra decoded as "address length mnemonic" lines
// to the file given as the script argument, for comparing against the
// emulator's decoder (check_lengths.py).
//@category R40

import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Instruction;
import java.io.PrintWriter;

public class ExportInsns extends GhidraScript {
	@Override
	public void run() throws Exception {
		String out = getScriptArgs()[0];
		try (PrintWriter w = new PrintWriter(out)) {
			for (Instruction i : currentProgram.getListing().getInstructions(true)) {
				w.printf("%x %d %s%n", i.getAddress().getOffset(), i.getLength(),
					i.toString());
			}
		}
		println("instructions: " + currentProgram.getListing().getNumInstructions()
			+ ", functions: " + currentProgram.getFunctionManager().getFunctionCount());
	}
}
