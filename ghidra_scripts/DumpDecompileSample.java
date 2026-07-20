//Dump a few decompiled functions from the current program (headless-friendly).
//@category Vibe
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolType;
import ghidra.util.task.ConsoleTaskMonitor;

public class DumpDecompileSample extends GhidraScript {
	@Override
	public void run() throws Exception {
		if (currentProgram == null) {
			printerr("No currentProgram");
			return;
		}
		println("PROGRAM=" + currentProgram.getName());
		println("LANG=" + currentProgram.getLanguageID());
		DecompInterface ifc = new DecompInterface();
		ifc.openProgram(currentProgram);
		int n = 0;
		int limit = 5;
		String want = System.getenv("GHIDRA_VIBE_DECOMP_FILTER");
		boolean allowFun = "1".equals(System.getenv("GHIDRA_VIBE_DECOMP_ALLOW_FUN"));
		long total = currentProgram.getFunctionManager().getFunctionCount();
		println("FUNCTION_COUNT=" + total);
		FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
		while (it.hasNext() && n < limit) {
			Function f = it.next();
			String name = f.getName();
			if (want != null && !want.isEmpty() && !name.toLowerCase().contains(want.toLowerCase())) {
				continue;
			}
			if (!allowFun && (name.startsWith("FUN_") || name.startsWith("thunk_"))) {
				continue;
			}
			dumpOne(ifc, f);
			n++;
		}
		if (n == 0 && want != null && !want.isEmpty()) {
			println("No functions matched; scanning symbols for " + want);
			for (Symbol s : currentProgram.getSymbolTable().getAllSymbols(true)) {
				if (n >= limit) {
					break;
				}
				String name = s.getName();
				if (!name.toLowerCase().contains(want.toLowerCase())) {
					continue;
				}
				if (s.getSymbolType() != SymbolType.FUNCTION && s.getSymbolType() != SymbolType.LABEL) {
					continue;
				}
				Function f = getFunctionAt(s.getAddress());
				if (f == null) {
					f = createFunction(s.getAddress(), name);
				}
				if (f == null) {
					continue;
				}
				dumpOne(ifc, f);
				n++;
			}
		}
		println("DUMPED=" + n + " functions (of filter=" + want + ")");
		ifc.dispose();
	}

	private void dumpOne(DecompInterface ifc, Function f) {
		DecompileResults r = ifc.decompileFunction(f, 60, new ConsoleTaskMonitor());
		String c = r.decompileCompleted() ? r.getDecompiledFunction().getC()
				: ("FAIL: " + r.getErrorMessage());
		println("==== DECOMP " + f.getName() + " @ " + f.getEntryPoint() + " ====");
		println(c.length() > 4000 ? c.substring(0, 4000) + "\n...truncated..." : c);
	}
}
