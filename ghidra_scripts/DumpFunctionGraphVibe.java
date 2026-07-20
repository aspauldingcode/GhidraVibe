// Dump CFG (basic blocks + edges) as JSON for the native Function Graph viewer.
//@category Vibe
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.block.BasicBlockModel;
import ghidra.program.model.block.CodeBlock;
import ghidra.program.model.block.CodeBlockIterator;
import ghidra.program.model.block.CodeBlockReference;
import ghidra.program.model.block.CodeBlockReferenceIterator;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.symbol.FlowType;
import ghidra.util.task.ConsoleTaskMonitor;

public class DumpFunctionGraphVibe extends GhidraScript {
	@Override
	public void run() throws Exception {
		if (currentProgram == null) {
			printerr("No currentProgram");
			return;
		}
		Function f = getFunctionContaining(currentAddress);
		if (f == null) {
			f = getFunctionAt(currentAddress);
		}
		if (f == null) {
			printerr("No function at " + currentAddress);
			return;
		}
		BasicBlockModel bbm = new BasicBlockModel(currentProgram);
		ConsoleTaskMonitor monitor = new ConsoleTaskMonitor();
		Map<String, CodeBlock> byId = new LinkedHashMap<>();
		CodeBlockIterator bit = bbm.getCodeBlocksContaining(f.getBody(), monitor);
		while (bit.hasNext()) {
			CodeBlock block = bit.next();
			Address start = block.getFirstStartAddress();
			if (start != null) {
				byId.put(start.toString(), block);
			}
		}
		StringBuilder nodes = new StringBuilder("[");
		boolean first = true;
		Address entry = f.getEntryPoint();
		for (Map.Entry<String, CodeBlock> e : byId.entrySet()) {
			CodeBlock block = e.getValue();
			Address start = block.getFirstStartAddress();
			Address end = block.getMaxAddress();
			String kind = start.equals(entry) ? "entry" : "body";
			List<String> insns = new ArrayList<>();
			InstructionIterator iit = currentProgram.getListing().getInstructions(block, true);
			int n = 0;
			while (iit.hasNext() && n < 12) {
				Instruction insn = iit.next();
				insns.add(insn.getAddressString(false, true) + "  " + insn.toString());
				n++;
			}
			if (!first) {
				nodes.append(',');
			}
			first = false;
			nodes.append("{\"id\":\"").append(esc(start.toString())).append("\",")
					.append("\"addr\":\"").append(esc(start.toString())).append("\",")
					.append("\"end\":\"").append(esc(end.toString())).append("\",")
					.append("\"label\":\"").append(esc("entry".equals(kind) ? f.getName() : start.toString()))
					.append("\",")
					.append("\"kind\":\"").append(kind).append("\",")
					.append("\"insns\":").append(arr(insns)).append('}');
		}
		nodes.append(']');

		Set<String> seen = new LinkedHashSet<>();
		StringBuilder edges = new StringBuilder("[");
		first = true;
		for (CodeBlock block : byId.values()) {
			Address from = block.getFirstStartAddress();
			CodeBlockReferenceIterator dit = block.getDestinations(monitor);
			while (dit.hasNext()) {
				CodeBlockReference ref = dit.next();
				CodeBlock dest = ref.getDestinationBlock();
				if (dest == null || dest.getFirstStartAddress() == null) {
					continue;
				}
				String to = dest.getFirstStartAddress().toString();
				if (!byId.containsKey(to)) {
					continue;
				}
				String type = flowName(ref.getFlowType());
				String key = from + "->" + to + ":" + type;
				if (!seen.add(key)) {
					continue;
				}
				if (!first) {
					edges.append(',');
				}
				first = false;
				edges.append("{\"from\":\"").append(esc(from.toString())).append("\",")
						.append("\"to\":\"").append(esc(to)).append("\",")
						.append("\"type\":\"").append(esc(type)).append("\"}");
			}
		}
		edges.append(']');
		println("{\"ok\":true,\"function\":\"" + esc(f.getName()) + "\",\"entry\":\""
				+ esc(entry.toString()) + "\",\"nodes\":" + nodes + ",\"edges\":" + edges
				+ ",\"body_size\":" + f.getBody().getNumAddresses() + "}");
	}

	private static String flowName(FlowType ft) {
		if (ft == null) {
			return "flow";
		}
		if (ft.isConditional()) {
			return "conditional";
		}
		if (ft.isUnConditional()) {
			return "unconditional";
		}
		if (ft.isCall()) {
			return "call";
		}
		if (ft.isJump()) {
			return "jump";
		}
		if (ft.hasFallthrough()) {
			return "fallthrough";
		}
		return "flow";
	}

	private static String arr(List<String> items) {
		StringBuilder b = new StringBuilder("[");
		for (int i = 0; i < items.size(); i++) {
			if (i > 0) {
				b.append(',');
			}
			b.append('"').append(esc(items.get(i))).append('"');
		}
		return b.append(']').toString();
	}

	private static String esc(String s) {
		if (s == null) {
			return "";
		}
		return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n");
	}
}
