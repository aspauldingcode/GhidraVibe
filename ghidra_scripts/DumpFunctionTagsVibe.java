// Function tags dump.
//@category Vibe
//@menupath Tools.Vibe.Dump Function Tags

import java.io.File;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionTag;

public class DumpFunctionTagsVibe extends GhidraScript {

	@Override
	protected void run() throws Exception {
		String[] args = getScriptArgs();
		if (args.length < 1) {
			printerr("Usage: DumpFunctionTagsVibe.java <out.json>");
			return;
		}
		if (currentProgram == null) {
			printerr("DumpFunctionTagsVibe: no currentProgram");
			return;
		}
		File out = new File(args[0]);
		List<String> rows = new ArrayList<>();
		int n = 0;
		for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
			monitor.checkCancelled();
			Set<? extends FunctionTag> tags = f.getTags();
			if (tags == null || tags.isEmpty()) {
				continue;
			}
			StringBuilder tb = new StringBuilder();
			boolean first = true;
			for (FunctionTag t : tags) {
				if (!first) {
					tb.append(",");
				}
				first = false;
				tb.append(esc(t.getName()));
			}
			rows.add(String.format(
				"{\"name\": \"%s\", \"address\": \"%s\", \"tags\": \"%s\"}",
				esc(f.getName()),
				f.getEntryPoint().toString(),
				tb.toString()));
			if (++n >= 5000) {
				break;
			}
		}
		try (PrintWriter pw = new PrintWriter(out, java.nio.charset.StandardCharsets.UTF_8)) {
			pw.println("{\"program\": \"" + esc(currentProgram.getName()) + "\", \"functions\": [");
			for (int i = 0; i < rows.size(); i++) {
				pw.print("  " + rows.get(i));
				pw.println(i + 1 < rows.size() ? "," : "");
			}
			pw.println("]}");
		}
		println("OK: DumpFunctionTagsVibe count=" + rows.size());
	}

	private static String esc(String s) {
		if (s == null) {
			return "";
		}
		return s.replace("\\", "\\\\").replace("\"", "\\\"");
	}
}
