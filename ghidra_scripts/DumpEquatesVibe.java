// Equate table dump.
//@category Vibe
//@menupath Tools.Vibe.Dump Equates

import java.io.File;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.List;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.symbol.Equate;
import ghidra.program.model.symbol.EquateTable;

public class DumpEquatesVibe extends GhidraScript {

	@Override
	protected void run() throws Exception {
		String[] args = getScriptArgs();
		if (args.length < 1) {
			printerr("Usage: DumpEquatesVibe.java <out.json>");
			return;
		}
		if (currentProgram == null) {
			printerr("DumpEquatesVibe: no currentProgram");
			return;
		}
		File out = new File(args[0]);
		List<String> rows = new ArrayList<>();
		EquateTable et = currentProgram.getEquateTable();
		var it = et.getEquates();
		while (it.hasNext()) {
			monitor.checkCancelled();
			Equate eq = it.next();
			rows.add(String.format(
				"{\"name\": \"%s\", \"value\": \"%s\", \"refs\": %d}",
				esc(eq.getName()),
				esc(Long.toString(eq.getValue())),
				eq.getReferenceCount()));
		}
		try (PrintWriter pw = new PrintWriter(out, java.nio.charset.StandardCharsets.UTF_8)) {
			pw.println("{\"program\": \"" + esc(currentProgram.getName()) + "\", \"equates\": [");
			for (int i = 0; i < rows.size(); i++) {
				pw.print("  " + rows.get(i));
				pw.println(i + 1 < rows.size() ? "," : "");
			}
			pw.println("]}");
		}
		println("OK: DumpEquatesVibe count=" + rows.size());
	}

	private static String esc(String s) {
		if (s == null) {
			return "";
		}
		return s.replace("\\", "\\\\").replace("\"", "\\\"");
	}
}
