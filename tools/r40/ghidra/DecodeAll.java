// Decode the instruction at every address listed in the input file (one
// hex address per line) with the program's language, without changing the
// program, and write "address length text" (length 0: no constructor) to
// the output file.  check_decoder.py feeds it the linear sweep of the
// patched binutils decoder.
//
// Script arguments: input file, output file.
//@category R40

import ghidra.app.script.GhidraScript;
import ghidra.app.util.PseudoDisassembler;
import ghidra.app.util.PseudoInstruction;
import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Paths;

public class DecodeAll extends GhidraScript {
	@Override
	public void run() throws Exception {
		PseudoDisassembler pd = new PseudoDisassembler(currentProgram);
		try (PrintWriter w = new PrintWriter(getScriptArgs()[1])) {
			for (String line : Files.readAllLines(Paths.get(getScriptArgs()[0]))) {
				long a = Long.parseLong(line.trim(), 16);
				PseudoInstruction i = null;
				try {
					i = pd.disassemble(toAddr(a));
				} catch (Exception e) {
					i = null;
				}
				if (i == null) {
					w.printf("%x 0 -%n", a);
				} else {
					w.printf("%x %d %s%n", a, i.getLength(), i.toString());
				}
			}
		}
	}
}
