// Malimite DumpClassData parity — write class/function/string JSON to files (no socket).
// Skips decompilation for library namespaces (LibraryDefinitions-compatible prefixes).
//@category Vibe
//@menupath Tools.Vibe.Dump Class Data

import java.io.File;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.data.DataType;
import ghidra.program.model.data.StringDataType;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.DataIterator;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.symbol.Namespace;
import ghidra.util.task.ConsoleTaskMonitor;

public class DumpClassDataVibe extends GhidraScript {

	/** Mirrors Malimite LibraryDefinitions defaults + common system prefixes. */
	private static final List<String> DEFAULT_LIB_PREFIXES = Arrays.asList(
		"UIKit", "Foundation", "CoreData", "CoreGraphics", "CoreLocation", "AVFoundation",
		"WebKit", "Security", "NetworkExtension", "SystemConfiguration", "CoreBluetooth",
		"CoreMotion", "Photos", "Contacts", "HealthKit", "HomeKit", "MapKit", "MessageUI",
		"StoreKit", "UserNotifications", "SwiftStandardLibrary", "SwiftUI", "Combine",
		"CoreFoundation", "QuartzCore", "CFNetwork", "CoreImage", "Metal", "SceneKit",
		"ARKit", "SpriteKit", "GameKit", "BackgroundTasks", "CloudKit", "FileProvider",
		"CoreText", "Vision", "TextKit", "CoreML", "NaturalLanguage", "AppTrackingTransparency",
		"AuthenticationServices", "Intents", "CallKit", "MediaPlayer", "PassKit",
		"AppKit", "SkyLight", "libswift", "libobjc", "libc++", "libSystem", "dyld", "/usr/lib");

	@Override
	protected void run() throws Exception {
		String[] args = getScriptArgs();
		if (args.length < 1) {
			printerr("Usage: DumpClassDataVibe.java <outDir> [libPrefixesCommaSep] [maxDecompile]");
			return;
		}
		File outDir = new File(args[0]);
		outDir.mkdirs();
		if (currentProgram == null) {
			printerr("DumpClassDataVibe: no currentProgram (import failed?)");
			return;
		}
		List<String> libPrefixes = args.length >= 2 && !args[1].isEmpty()
			? Arrays.asList(args[1].split(","))
			: DEFAULT_LIB_PREFIXES;
		int maxDecompile = args.length >= 3 ? Integer.parseInt(args[2]) : 400;
		boolean skipLibs = !"0".equals(System.getenv().getOrDefault("GHIDRA_VIBE_SKIP_LIB_NS", "1"));
		String exe = currentProgram.getName();

		Map<String, List<String>> byNs = new LinkedHashMap<>();
		List<JSONFunc> funcs = new ArrayList<>();
		FunctionManager fm = currentProgram.getFunctionManager();
		DecompInterface decomp = new DecompInterface();
		decomp.openProgram(currentProgram);
		int decompiled = 0;
		int skippedLib = 0;

		for (Function f : fm.getFunctions(true)) {
			monitor.checkCancelled();
			Namespace ns = f.getParentNamespace();
			String className = formatNs(ns != null ? ns.getName(true) : "Global");
			boolean lib = skipLibs && isLibrary(className, libPrefixes);
			byNs.computeIfAbsent(className, k -> new ArrayList<>()).add(f.getName());

			String code = "";
			if (!lib && decompiled < maxDecompile) {
				DecompileResults r = decomp.decompileFunction(f, 30, new ConsoleTaskMonitor());
				if (r.decompileCompleted() && r.getDecompiledFunction() != null) {
					code = r.getDecompiledFunction().getC();
					decompiled++;
				}
			}
			else if (lib) {
				skippedLib++;
			}
			funcs.add(new JSONFunc(f.getName(), className, code, exe, f.getEntryPoint().toString()));
		}
		decomp.dispose();

		File classesFile = new File(outDir, "classes.json");
		File functionsFile = new File(outDir, "functions.json");
		File stringsFile = new File(outDir, "strings.json");

		try (PrintWriter pw = new PrintWriter(classesFile, java.nio.charset.StandardCharsets.UTF_8)) {
			pw.println("[");
			int i = 0;
			for (Map.Entry<String, List<String>> e : byNs.entrySet()) {
				pw.print("  {\"ClassName\": " + j(e.getKey()) + ", \"ExecutableName\": " + j(exe) +
					", \"Functions\": [");
				List<String> fns = e.getValue();
				for (int k = 0; k < fns.size(); k++) {
					if (k > 0) {
						pw.print(", ");
					}
					pw.print(j(fns.get(k)));
				}
				pw.print("]}");
				pw.println(++i < byNs.size() ? "," : "");
			}
			pw.println("]");
		}

		try (PrintWriter pw = new PrintWriter(functionsFile, java.nio.charset.StandardCharsets.UTF_8)) {
			pw.println("[");
			for (int i = 0; i < funcs.size(); i++) {
				JSONFunc f = funcs.get(i);
				pw.print("  {\"FunctionName\": " + j(f.name) + ", \"ClassName\": " + j(f.cls) +
					", \"ExecutableName\": " + j(f.exe) + ", \"Address\": " + j(f.addr) +
					", \"DecompiledCode\": " + j(f.code) + "}");
				pw.println(i + 1 < funcs.size() ? "," : "");
			}
			pw.println("]");
		}

		writeStrings(stringsFile, exe);

		println("OK: DumpClassDataVibe → " + outDir.getAbsolutePath() +
			" classes=" + byNs.size() + " funcs=" + funcs.size() +
			" decompiled=" + decompiled + " skippedLib=" + skippedLib);
	}

	private void writeStrings(File out, String exe) throws Exception {
		Memory memory = currentProgram.getMemory();
		Listing listing = currentProgram.getListing();
		List<String> rows = new ArrayList<>();
		for (MemoryBlock block : memory.getBlocks()) {
			if (!block.isInitialized()) {
				continue;
			}
			DataIterator it = listing.getDefinedData(block.getStart(), true);
			while (it.hasNext()) {
				monitor.checkCancelled();
				Data data = it.next();
				if (!block.contains(data.getAddress())) {
					continue;
				}
				DataType dt = data.getDataType();
				if (!(dt instanceof StringDataType)) {
					continue;
				}
				String value = data.getDefaultValueRepresentation();
				if (value == null || value.length() < 5) {
					continue;
				}
				String label = data.getLabel() != null ? data.getLabel() : "";
				rows.add("{\"address\": " + j(data.getAddress().toString()) + ", \"value\": " + j(value) +
					", \"segment\": " + j(block.getName()) + ", \"label\": " + j(label) +
					", \"ExecutableName\": " + j(exe) + "}");
			}
		}
		try (PrintWriter pw = new PrintWriter(out, java.nio.charset.StandardCharsets.UTF_8)) {
			pw.println("[");
			for (int i = 0; i < rows.size(); i++) {
				pw.print("  " + rows.get(i));
				pw.println(i + 1 < rows.size() ? "," : "");
			}
			pw.println("]");
		}
	}

	private static String formatNs(String name) {
		if (name == null || name.isEmpty() || " ".equals(name)) {
			return "Global";
		}
		return name;
	}

	private static boolean isLibrary(String name, List<String> prefixes) {
		for (String p : prefixes) {
			if (p != null && !p.isEmpty() && name.contains(p)) {
				return true;
			}
		}
		return false;
	}

	private static String j(String s) {
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

	private static final class JSONFunc {
		final String name, cls, code, exe, addr;

		JSONFunc(String name, String cls, String code, String exe, String addr) {
			this.name = name;
			this.cls = cls;
			this.code = code;
			this.exe = exe;
			this.addr = addr;
		}
	}
}
