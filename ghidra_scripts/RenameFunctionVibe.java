// Rename a function and optionally set a plate comment (headless / analyzeHeadless).
//@category Vibe
//@menupath Tools.Vibe.Rename Function

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.SourceType;

public class RenameFunctionVibe extends GhidraScript {

	@Override
	protected void run() throws Exception {
		String[] args = getScriptArgs();
		if (args.length < 2) {
			printerr("Usage: RenameFunctionVibe.java <address|oldName> <newName> [plateComment]");
			return;
		}
		if (currentProgram == null) {
			printerr("RenameFunctionVibe: no currentProgram");
			return;
		}
		String target = args[0];
		String newName = args[1];
		String plate = args.length > 2 ? args[2] : "";

		Function f = null;
		try {
			Address a = toAddr(target);
			f = getFunctionAt(a);
			if (f == null) {
				f = getFunctionContaining(a);
			}
		}
		catch (Exception ignored) {
			// fall through to name lookup
		}
		if (f == null) {
			f = getGlobalFunctions(target).stream().findFirst().orElse(null);
		}
		if (f == null) {
			printerr("RenameFunctionVibe: function not found: " + target);
			return;
		}
		String old = f.getName();
		f.setName(newName, SourceType.USER_DEFINED);
		if (plate != null && !plate.isBlank()) {
			setPlateComment(f.getEntryPoint(), plate);
		}
		println("OK: RenameFunctionVibe " + old + " -> " + newName + " @ " + f.getEntryPoint());
	}
}
