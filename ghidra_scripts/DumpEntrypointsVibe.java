// Malimite-style entrypoints list (main, UIApplicationMain, SwiftUI, ObjC +UIApplicationDelegate).
//@category Vibe
//@menupath Tools.Vibe.Dump Entrypoints

import java.io.File;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolIterator;
import ghidra.program.model.symbol.SymbolTable;
import ghidra.program.model.symbol.SymbolType;

public class DumpEntrypointsVibe extends GhidraScript {

	private static final String[] NAME_HINTS = {
		"main", "_main", "start", "_start",
		"UIApplicationMain", "NSApplicationMain",
		"applicationDidFinishLaunching", "application:didFinishLaunchingWithOptions:",
		"applicationDidBecomeActive", "scene:willConnectToSession:",
		"$s", // Swift mangled — filtered further
	};

	@Override
	protected void run() throws Exception {
		String[] args = getScriptArgs();
		if (args.length < 1) {
			printerr("Usage: DumpEntrypointsVibe.java <out.json>");
			return;
		}
		File out = new File(args[0]);
		if (currentProgram == null) {
			printerr("DumpEntrypointsVibe: no currentProgram");
			return;
		}
		List<String> rows = new ArrayList<>();
		FunctionManager fm = currentProgram.getFunctionManager();
		for (Function f : fm.getFunctions(true)) {
			monitor.checkCancelled();
			String n = f.getName();
			String full = f.getName(true);
			if (isEntrypointName(n) || isEntrypointName(full)) {
				rows.add(row(n, full, f.getEntryPoint().toString(), "function"));
			}
		}
		SymbolTable st = currentProgram.getSymbolTable();
		SymbolIterator it = st.getAllSymbols(true);
		while (it.hasNext()) {
			monitor.checkCancelled();
			Symbol s = it.next();
			if (s.getSymbolType() != SymbolType.FUNCTION && s.getSymbolType() != SymbolType.LABEL) {
				continue;
			}
			String n = s.getName(true);
			if (isEntrypointName(n) && rows.stream().noneMatch(r -> r.contains(n))) {
				rows.add(row(s.getName(), n, s.getAddress().toString(), s.getSymbolType().toString()));
			}
		}

		try (PrintWriter pw = new PrintWriter(out, java.nio.charset.StandardCharsets.UTF_8)) {
			pw.println("{\"program\": \"" + esc(currentProgram.getName()) + "\", \"entrypoints\": [");
			for (int i = 0; i < rows.size(); i++) {
				pw.print("  " + rows.get(i));
				pw.println(i + 1 < rows.size() ? "," : "");
			}
			pw.println("]}");
		}
		println("OK: DumpEntrypointsVibe → " + out.getAbsolutePath() + " count=" + rows.size());
	}

	private static boolean isEntrypointName(String n) {
		if (n == null) {
			return false;
		}
		String l = n.toLowerCase(Locale.ROOT);
		if (l.equals("main") || l.equals("_main") || l.endsWith(".main") || l.contains("uapplicationmain") ||
			l.contains("nsapplicationmain") || l.contains("didfinishlaunching") ||
			l.contains("willconnecttosession") || l.contains("applicationdidbecomeactive")) {
			return true;
		}
		// SwiftUI App protocol entry-ish
		return n.contains("App") && (n.contains("$s") || n.contains("main"));
	}

	private static String row(String name, String full, String addr, String kind) {
		return "{\"name\": \"" + esc(name) + "\", \"full\": \"" + esc(full) + "\", \"address\": \"" +
			esc(addr) + "\", \"kind\": \"" + esc(kind) + "\"}";
	}

	private static String esc(String s) {
		if (s == null) {
			return "";
		}
		return s.replace("\\", "\\\\").replace("\"", "\\\"");
	}
}
