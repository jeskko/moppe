// Print references to, and the decompiled C of, functions given as script
// arguments: hex addresses or symbol names.  "xref:NAME" lists the
// functions that reference symbol NAME instead.
//
//   analyzeHeadless reference/ghidra-r40 R40 -process ABSBIN -noanalysis \
//       -scriptPath tools/r40/ghidra -postScript Decompile.java 3689c xref:P7DR
//@category R40

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.Symbol;
import java.util.TreeSet;

public class Decompile extends GhidraScript {
	Address resolve(String s) {
		for (Symbol sym : currentProgram.getSymbolTable().getSymbols(s)) {
			return sym.getAddress();
		}
		return toAddr(Long.parseLong(s, 16));
	}

	@Override
	public void run() throws Exception {
		DecompInterface d = new DecompInterface();
		d.openProgram(currentProgram);
		for (String arg : getScriptArgs()) {
			if (arg.startsWith("xref:")) {
				Address t = resolve(arg.substring(5));
				TreeSet<String> users = new TreeSet<>();
				for (Reference r : getReferencesTo(t)) {
					Function f = getFunctionContaining(r.getFromAddress());
					users.add(String.format("%s %s from %s",
						f == null ? "-" : f.getName(), r.getReferenceType(),
						r.getFromAddress()));
				}
				println("references to " + arg.substring(5) + " (" + t + "):");
				for (String u : users) {
					println("  " + u);
				}
				continue;
			}
			Function f = getFunctionContaining(resolve(arg));
			if (f == null) {
				println("no function at " + arg);
				continue;
			}
			DecompileResults r = d.decompileFunction(f, 120, monitor);
			println("==== " + f.getName() + " @ " + f.getEntryPoint());
			println(r.getDecompiledFunction() == null ? r.getErrorMessage()
				: r.getDecompiledFunction().getC());
		}
	}
}
