// Dump Swift/ObjC-style namespaces → functions JSON (Malimite DumpClassData learnings).
// Writes to a file for headless/MCP; skips common system library prefixes when requested.
//@category Vibe
//@menupath Tools.Vibe.Dump Swift Namespaces

import java.io.File;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.symbol.Namespace;

public class DumpSwiftNamespaces extends GhidraScript {

	private static final List<String> DEFAULT_LIB_PREFIXES = Arrays.asList(
		"libswift", "libobjc", "libc++", "libSystem", "dyld",
		"/usr/lib", "Foundation", "CoreFoundation", "UIKit", "AppKit");

	@Override
	protected void run() throws Exception {
		String[] args = getScriptArgs();
		if (args.length < 1) {
			printerr("Usage: DumpSwiftNamespaces.java <out.json> [libPrefixesCommaSep]");
			return;
		}
		File out = new File(args[0]);
		List<String> libPrefixes = args.length >= 2
			? Arrays.asList(args[1].split(","))
			: DEFAULT_LIB_PREFIXES;
		boolean skipLibs = !"0".equals(System.getenv().getOrDefault("GHIDRA_VIBE_SKIP_LIB_NS", "1"));

		FunctionManager fm = currentProgram.getFunctionManager();
		Map<String, List<String>> byNs = new LinkedHashMap<>();
		int skipped = 0;
		for (Function f : fm.getFunctions(true)) {
			monitor.checkCancelled();
			Namespace ns = f.getParentNamespace();
			String nsName = ns != null ? ns.getName(true) : "Global";
			if (skipLibs && isLibraryNamespace(nsName, libPrefixes)) {
				skipped++;
				continue;
			}
			byNs.computeIfAbsent(nsName, k -> new ArrayList<>()).add(f.getName());
		}

		try (PrintWriter pw = new PrintWriter(out, java.nio.charset.StandardCharsets.UTF_8)) {
			pw.println("{");
			pw.println("  \"program\": " + jsonString(currentProgram.getName()) + ",");
			pw.println("  \"skippedLibraryFunctions\": " + skipped + ",");
			pw.println("  \"classes\": [");
			int i = 0;
			for (Map.Entry<String, List<String>> e : byNs.entrySet()) {
				pw.print("    {\"ClassName\": " + jsonString(e.getKey()) + ", \"Functions\": [");
				List<String> fns = e.getValue();
				for (int j = 0; j < fns.size(); j++) {
					if (j > 0) {
						pw.print(", ");
					}
					pw.print(jsonString(fns.get(j)));
				}
				pw.print("]}");
				if (++i < byNs.size()) {
					pw.println(",");
				}
				else {
					pw.println();
				}
			}
			pw.println("  ]");
			pw.println("}");
		}
		println("OK: wrote " + byNs.size() + " namespaces → " + out.getAbsolutePath() +
			" (skippedLib=" + skipped + ")");
	}

	private static boolean isLibraryNamespace(String name, List<String> prefixes) {
		String n = name == null ? "" : name;
		for (String p : prefixes) {
			if (p != null && !p.isEmpty() && n.contains(p)) {
				return true;
			}
		}
		return false;
	}

	private static String jsonString(String s) {
		if (s == null) {
			return "\"\"";
		}
		StringBuilder b = new StringBuilder("\"");
		for (int i = 0; i < s.length(); i++) {
			char c = s.charAt(i);
			switch (c) {
				case '\\':
					b.append("\\\\");
					break;
				case '"':
					b.append("\\\"");
					break;
				case '\n':
					b.append("\\n");
					break;
				case '\r':
					b.append("\\r");
					break;
				case '\t':
					b.append("\\t");
					break;
				default:
					if (c < 0x20) {
						b.append(String.format("\\u%04x", (int) c));
					}
					else {
						b.append(c);
					}
			}
		}
		b.append('"');
		return b.toString();
	}
}
