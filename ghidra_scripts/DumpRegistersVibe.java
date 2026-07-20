// Program context registers at current address (static, not live debugger).
//@category Vibe
//@menupath Tools.Vibe.Dump Registers

import java.io.File;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.List;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.lang.Register;
import ghidra.program.model.lang.RegisterValue;

public class DumpRegistersVibe extends GhidraScript {

	@Override
	protected void run() throws Exception {
		String[] args = getScriptArgs();
		if (args.length < 1) {
			printerr("Usage: DumpRegistersVibe.java <out.json>");
			return;
		}
		if (currentProgram == null) {
			printerr("DumpRegistersVibe: no currentProgram");
			return;
		}
		File out = new File(args[0]);
		Address addr = currentAddress != null ? currentAddress : currentProgram.getMinAddress();
		List<String> rows = new ArrayList<>();
		for (Register reg : currentProgram.getLanguage().getRegisters()) {
			monitor.checkCancelled();
			if (reg.isProcessorContext() || reg.getBaseRegister() != reg) {
				continue;
			}
			RegisterValue rv = currentProgram.getProgramContext().getRegisterValue(reg, addr);
			String val = rv != null && rv.hasValue() ? rv.getUnsignedValue().toString(16) : "";
			rows.add(String.format(
				"{\"name\": \"%s\", \"bits\": %d, \"value\": \"%s\"}",
				esc(reg.getName()),
				reg.getBitLength(),
				esc(val)));
		}
		try (PrintWriter pw = new PrintWriter(out, java.nio.charset.StandardCharsets.UTF_8)) {
			pw.println("{\"program\": \"" + esc(currentProgram.getName()) +
				"\", \"address\": \"" + addr + "\", \"registers\": [");
			for (int i = 0; i < rows.size(); i++) {
				pw.print("  " + rows.get(i));
				pw.println(i + 1 < rows.size() ? "," : "");
			}
			pw.println("]}");
		}
		println("OK: DumpRegistersVibe count=" + rows.size());
	}

	private static String esc(String s) {
		if (s == null) {
			return "";
		}
		return s.replace("\\", "\\\\").replace("\"", "\\\"");
	}
}
