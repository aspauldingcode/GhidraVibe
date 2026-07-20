// Relocation table dump.
//@category Vibe
//@menupath Tools.Vibe.Dump Relocations

import java.io.File;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.List;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.reloc.Relocation;
import ghidra.program.model.reloc.RelocationTable;

public class DumpRelocationsVibe extends GhidraScript {

	@Override
	protected void run() throws Exception {
		String[] args = getScriptArgs();
		if (args.length < 1) {
			printerr("Usage: DumpRelocationsVibe.java <out.json>");
			return;
		}
		if (currentProgram == null) {
			printerr("DumpRelocationsVibe: no currentProgram");
			return;
		}
		File out = new File(args[0]);
		List<String> rows = new ArrayList<>();
		RelocationTable rt = currentProgram.getRelocationTable();
		var it = rt.getRelocations();
		int n = 0;
		while (it.hasNext() && n < 5000) {
			monitor.checkCancelled();
			Relocation r = it.next();
			rows.add(String.format(
				"{\"address\": \"%s\", \"type\": %d, \"values\": \"%s\"}",
				r.getAddress().toString(),
				r.getType(),
				esc(java.util.Arrays.toString(r.getValues()))));
			n++;
		}
		try (PrintWriter pw = new PrintWriter(out, java.nio.charset.StandardCharsets.UTF_8)) {
			pw.println("{\"program\": \"" + esc(currentProgram.getName()) + "\", \"relocations\": [");
			for (int i = 0; i < rows.size(); i++) {
				pw.print("  " + rows.get(i));
				pw.println(i + 1 < rows.size() ? "," : "");
			}
			pw.println("]}");
		}
		println("OK: DumpRelocationsVibe count=" + rows.size());
	}

	private static String esc(String s) {
		if (s == null) {
			return "";
		}
		return s.replace("\\", "\\\\").replace("\"", "\\\"");
	}
}
