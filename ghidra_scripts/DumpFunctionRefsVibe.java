// Function call edges for Malimite FunctionReferences table.
//@category Vibe
//@menupath Tools.Vibe.Dump Function Refs

import java.io.File;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.symbol.Reference;

public class DumpFunctionRefsVibe extends GhidraScript {

	@Override
	protected void run() throws Exception {
		String[] args = getScriptArgs();
		if (args.length < 1) {
			printerr("Usage: DumpFunctionRefsVibe.java <out.json> [maxEdges]");
			return;
		}
		File out = new File(args[0]);
		if (currentProgram == null) {
			printerr("DumpFunctionRefsVibe: no currentProgram");
			return;
		}
		int max = args.length >= 2 ? Integer.parseInt(args[1]) : 50_000;
		String exe = currentProgram.getName();
		FunctionManager fm = currentProgram.getFunctionManager();
		List<String> rows = new ArrayList<>();
		Set<String> seen = new HashSet<>();

		for (Function src : fm.getFunctions(true)) {
			monitor.checkCancelled();
			if (rows.size() >= max) {
				break;
			}
			String srcClass = src.getParentNamespace() != null ? src.getParentNamespace().getName(true) : "Global";
			Set<Function> called = src.getCalledFunctions(monitor);
			if (called != null) {
				for (Function tgt : called) {
					if (tgt == null || rows.size() >= max) {
						continue;
					}
					String tgtClass = tgt.getParentNamespace() != null ? tgt.getParentNamespace().getName(true)
						: "Global";
					String key = src.getName() + "->" + tgt.getName();
					if (!seen.add(key)) {
						continue;
					}
					rows.add("{\"sourceFunction\": \"" + esc(src.getName()) + "\", \"sourceClass\": \"" +
						esc(srcClass) + "\", \"targetFunction\": \"" + esc(tgt.getName()) +
						"\", \"targetClass\": \"" + esc(tgtClass) + "\", \"address\": \"" +
						esc(src.getEntryPoint().toString()) + "\", \"ExecutableName\": \"" + esc(exe) + "\"}");
				}
			}
			// Also collect call sites from instructions for address fidelity
			InstructionIterator iit = currentProgram.getListing().getInstructions(src.getBody(), true);
			while (iit.hasNext() && rows.size() < max) {
				Instruction instr = iit.next();
				for (Reference r : instr.getReferencesFrom()) {
					if (!r.getReferenceType().isCall()) {
						continue;
					}
					Function tgt = fm.getFunctionAt(r.getToAddress());
					if (tgt == null) {
						continue;
					}
					String tgtClass = tgt.getParentNamespace() != null ? tgt.getParentNamespace().getName(true)
						: "Global";
					String key = src.getName() + "->" + tgt.getName() + "@" + r.getFromAddress();
					if (!seen.add(key)) {
						continue;
					}
					rows.add("{\"sourceFunction\": \"" + esc(src.getName()) + "\", \"sourceClass\": \"" +
						esc(srcClass) + "\", \"targetFunction\": \"" + esc(tgt.getName()) +
						"\", \"targetClass\": \"" + esc(tgtClass) + "\", \"address\": \"" +
						esc(r.getFromAddress().toString()) + "\", \"ExecutableName\": \"" + esc(exe) + "\"}");
				}
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
		println("OK: DumpFunctionRefsVibe → " + out + " edges=" + rows.size());
	}

	private static String esc(String s) {
		if (s == null) {
			return "";
		}
		return s.replace("\\", "\\\\").replace("\"", "\\\"");
	}
}
