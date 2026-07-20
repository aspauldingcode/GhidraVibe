// Block entropy histogram for Overview / Entropy panes.
//@category Vibe
//@menupath Tools.Vibe.Dump Entropy

import java.io.File;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.List;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.mem.MemoryBlock;

public class DumpEntropyVibe extends GhidraScript {

	@Override
	protected void run() throws Exception {
		String[] args = getScriptArgs();
		if (args.length < 1) {
			printerr("Usage: DumpEntropyVibe.java <out.json>");
			return;
		}
		if (currentProgram == null) {
			printerr("DumpEntropyVibe: no currentProgram");
			return;
		}
		File out = new File(args[0]);
		List<String> rows = new ArrayList<>();
		for (MemoryBlock block : currentProgram.getMemory().getBlocks()) {
			monitor.checkCancelled();
			long size = block.getSize();
			double entropy = estimateEntropy(block);
			rows.add(String.format(
				"{\"name\": \"%s\", \"start\": \"%s\", \"size\": %d, \"entropy\": %.4f, \"initialized\": %s}",
				esc(block.getName()),
				block.getStart().toString(),
				size,
				entropy,
				block.isInitialized()));
		}
		try (PrintWriter pw = new PrintWriter(out, java.nio.charset.StandardCharsets.UTF_8)) {
			pw.println("{\"program\": \"" + esc(currentProgram.getName()) + "\", \"blocks\": [");
			for (int i = 0; i < rows.size(); i++) {
				pw.print("  " + rows.get(i));
				pw.println(i + 1 < rows.size() ? "," : "");
			}
			pw.println("]}");
		}
		println("OK: DumpEntropyVibe → " + out.getAbsolutePath());
	}

	private double estimateEntropy(MemoryBlock block) {
		if (!block.isInitialized() || block.getSize() <= 0) {
			return 0.0;
		}
		try {
			int sample = (int) Math.min(block.getSize(), 65536);
			byte[] buf = new byte[sample];
			block.getBytes(block.getStart(), buf);
			int[] hist = new int[256];
			for (byte b : buf) {
				hist[b & 0xff]++;
			}
			double ent = 0.0;
			double n = sample;
			for (int c : hist) {
				if (c == 0) {
					continue;
				}
				double p = c / n;
				ent -= p * (Math.log(p) / Math.log(2));
			}
			return ent;
		}
		catch (Exception e) {
			return -1.0;
		}
	}

	private static String esc(String s) {
		if (s == null) {
			return "";
		}
		return s.replace("\\", "\\\\").replace("\"", "\\\"");
	}
}
