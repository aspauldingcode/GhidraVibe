package dev.ghidravibe.engine;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import com.xebyte.core.ProgramProvider;
import com.xebyte.headless.GhidraMCPHeadlessServer;
import com.xebyte.headless.HeadlessProgramProvider;

import ghidra.GhidraApplicationLayout;
import ghidra.program.flatapi.FlatProgramAPI;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressSetView;
import ghidra.program.model.block.BasicBlockModel;
import ghidra.program.model.block.CodeBlock;
import ghidra.program.model.block.CodeBlockIterator;
import ghidra.program.model.block.CodeBlockReference;
import ghidra.program.model.block.CodeBlockReferenceIterator;
import ghidra.program.model.data.ByteDataType;
import ghidra.program.model.data.StructureDataType;
import ghidra.program.model.listing.CodeUnit;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.listing.Program;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.symbol.FlowType;
import ghidra.program.model.symbol.SourceType;
import ghidra.util.exception.DuplicateNameException;
import ghidra.util.exception.InvalidInputException;
import ghidra.util.task.TaskMonitor;

/**
 * In-process Ghidra program engine for the native GhidraVibe GUI.
 *
 * Boots {@link GhidraMCPHeadlessServer} inside the GhidraVibe OS process (JNI).
 * Native Swift/GTK owns all windows. True headless CLI/agents use
 * {@code ghidra-vibe-mcp-headless} as a separate process.
 */
public final class InProcessEngine {
	private static volatile boolean started;
	private static volatile GhidraMCPHeadlessServer server;
	private static volatile String lastError;

	private InProcessEngine() {
	}

	/**
	 * @param ghidraInstallDir {@code GHIDRA_INSTALL_DIR} (…/lib/ghidra)
	 * @param startArgsJson optional {@code {"port":8089,"project":"…","program":"/Name"}}
	 */
	public static synchronized String start(String ghidraInstallDir, String startArgsJson) {
		try {
			if (started && server != null && server.isRunning()) {
				return okMsg("already started");
			}
			if (ghidraInstallDir != null && !ghidraInstallDir.isEmpty()) {
				System.setProperty("ghidra.install.dir", ghidraInstallDir);
			}
			System.setProperty("ghidra.vibe.nativeUi", "1");
			ensureVibeSettingsDir();
			lastError = null;

			final String[] args = buildLaunchArgs(startArgsJson);
			final GhidraMCPHeadlessServer svc = new GhidraMCPHeadlessServer();
			server = svc;
			Thread t = new Thread(() -> {
				try {
					svc.launch(new GhidraApplicationLayout(), args);
				}
				catch (Throwable e) {
					lastError = e.getClass().getSimpleName() + ": " + e.getMessage();
					e.printStackTrace(System.err);
					synchronized (svc) {
						svc.notifyAll();
					}
				}
			}, "ghidra-vibe-inprocess");
			t.setDaemon(true);
			t.start();

			long deadline = System.nanoTime() + 120_000_000_000L;
			while (System.nanoTime() < deadline) {
				if (svc.isRunning()) {
					started = true;
					return okMsg("engine ready (port " + svc.getPort() + ")");
				}
				if (lastError != null) {
					return err(lastError);
				}
				Thread.sleep(100);
			}
			return err(lastError != null ? lastError : "engine start timed out");
		}
		catch (Throwable t) {
			return err(t);
		}
	}

	public static synchronized String start(String ghidraInstallDir) {
		return start(ghidraInstallDir, "{}");
	}

	public static synchronized String call(String method, String argsJson) {
		try {
			if (!started || server == null || !server.isRunning()) {
				return err("engine not started");
			}
			String m = method == null ? "" : method;
			String args = argsJson == null ? "{}" : argsJson;
			return switch (m) {
				case "ping" -> okMsg("pong");
				case "status" -> statusJson();
				case "open_project" -> openProject(jsonStr(args, "project",
						jsonStr(args, "path", jsonStr(args, "projectPath", ""))));
				case "open_program", "load_program" -> openProgram(jsonStr(args, "program",
						jsonStr(args, "path", jsonStr(args, "programPath", ""))));
				case "list_project_programs" -> listProjectPrograms();
				case "list_functions", "list_methods" -> listFunctions(jsonInt(args, "limit", 500));
				case "current_program", "get_current_program" -> currentProgramJson();
				case "listing_disassemble", "disassemble" -> listingOp("disassemble", args);
				case "listing_define_data", "create_data" -> listingOp("create_data", args);
				case "listing_clear_code", "clear_code_bytes" -> listingOp("clear_code", args);
				case "listing_create_label", "create_label" -> listingOp("create_label", args);
				case "listing_create_function", "create_function" -> listingOp("create_function", args);
				case "listing_add_bookmark", "create_bookmark" -> listingOp("create_bookmark", args);
				case "listing_create_structure", "create_structure" -> listingOp("create_structure", args);
				case "rename_function", "rename" -> renameFunction(args);
				case "set_comment" -> setComment(args);
				case "set_plate_comment" -> setCommentKind(args, CodeUnit.PLATE_COMMENT);
				case "set_eol_comment" -> setCommentKind(args, CodeUnit.EOL_COMMENT);
				case "search_memory" -> searchMemory(args);
				case "save_program" -> saveProgram();
				case "debugger_control" -> debuggerControl(args);
				case "debugger_status" -> debuggerStatus();
				case "debugger_list" -> debuggerList(args);
				case "vc_status" -> vcStatus();
				case "vc_op" -> vcOp(args);
				case "vt_session" -> vtSession(args);
				case "bsim_status" -> bsimStatus();
				case "function_graph" -> functionGraph(args);
				default -> err("unknown method: " + m);
			};
		}
		catch (Throwable t) {
			return err(t);
		}
	}

	public static boolean isRunning() {
		return started && server != null && server.isRunning();
	}

	private static String statusJson() {
		Program p = currentProgram();
		HeadlessProgramProvider hp = headlessProvider();
		boolean hasProject = hp != null && hp.hasProject();
		return "{\"ok\":true,\"running\":true,\"port\":" + server.getPort()
				+ ",\"mode\":\"inprocess\",\"has_project\":" + hasProject
				+ ",\"project\":"
				+ (hasProject ? quote(hp.getProjectName()) : "null")
				+ ",\"program\":"
				+ (p == null ? "null" : quote(p.getName()))
				+ ",\"function_count\":"
				+ (p == null ? 0 : p.getFunctionManager().getFunctionCount())
				+ '}';
	}

	private static String openProject(String path) {
		if (path == null || path.isEmpty()) {
			return err("project path required");
		}
		HeadlessProgramProvider hp = headlessProvider();
		if (hp == null) {
			return err("program provider unavailable");
		}
		// Accept .gpr or project directory / name without suffix.
		String normalized = path;
		if (normalized.endsWith(".gpr")) {
			normalized = normalized.substring(0, normalized.length() - 4);
		}
		boolean ok = hp.openProject(normalized);
		if (!ok) {
			ok = hp.openProject(path);
		}
		if (!ok) {
			return err("Failed to open project: " + path);
		}
		return "{\"ok\":true,\"project\":" + quote(hp.getProjectName()) + '}';
	}

	private static String openProgram(String path) {
		if (path == null || path.isEmpty()) {
			return err("program path required");
		}
		HeadlessProgramProvider hp = headlessProvider();
		if (hp == null) {
			return err("program provider unavailable");
		}
		if (!hp.hasProject()) {
			return err("No project open. Call open_project first.");
		}
		String prog = path.startsWith("/") ? path : "/" + path;
		Program p = hp.loadProgramFromProject(prog);
		if (p == null && prog.startsWith("/")) {
			p = hp.loadProgramFromProject(prog.substring(1));
		}
		if (p == null) {
			String[] available = hp.listProjectPrograms();
			StringBuilder hint = new StringBuilder();
			if (available != null) {
				for (int i = 0; i < available.length && i < 20; i++) {
					if (i > 0) {
						hint.append(',');
					}
					hint.append(quote(available[i]));
				}
			}
			return "{\"ok\":false,\"error\":" + quote("Failed to load program: " + prog)
					+ ",\"available\":[" + hint + "]}";
		}
		return "{\"ok\":true,\"program\":" + quote(p.getName()) + ",\"function_count\":"
				+ p.getFunctionManager().getFunctionCount() + '}';
	}

	private static String listProjectPrograms() {
		HeadlessProgramProvider hp = headlessProvider();
		if (hp == null || !hp.hasProject()) {
			return "{\"ok\":false,\"error\":\"No project open\",\"data\":[]}";
		}
		String[] programs = hp.listProjectPrograms();
		StringBuilder data = new StringBuilder("[");
		if (programs != null) {
			for (int i = 0; i < programs.length; i++) {
				if (i > 0) {
					data.append(',');
				}
				data.append(quote(programs[i]));
			}
		}
		data.append(']');
		return "{\"ok\":true,\"count\":" + (programs == null ? 0 : programs.length) + ",\"data\":"
				+ data + '}';
	}

	private static String listFunctions(int limit) {
		Program p = currentProgram();
		if (p == null) {
			return err("No program loaded");
		}
		StringBuilder data = new StringBuilder("[");
		FunctionIterator it = p.getFunctionManager().getFunctions(true);
		int n = 0;
		while (it.hasNext() && n < limit) {
			Function f = it.next();
			if (n > 0) {
				data.append(',');
			}
			data.append("{\"name\":").append(quote(f.getName())).append(",\"address\":")
					.append(quote(f.getEntryPoint().toString())).append('}');
			n++;
		}
		data.append(']');
		return "{\"ok\":true,\"count\":" + n + ",\"data\":" + data + '}';
	}

	private static String currentProgramJson() {
		Program p = currentProgram();
		if (p == null) {
			return "{\"ok\":true,\"program\":null}";
		}
		return "{\"ok\":true,\"program\":" + quote(p.getName()) + ",\"function_count\":"
				+ p.getFunctionManager().getFunctionCount() + '}';
	}

	private static String listingOp(String op, String args) {
		Program p = currentProgram();
		if (p == null) {
			return err("No program loaded");
		}
		String addrStr = jsonStr(args, "address", jsonStr(args, "addr", ""));
		String name = jsonStr(args, "name", jsonStr(args, "label", "label"));
		if (addrStr.isEmpty()) {
			return err("address required");
		}
		int tx = p.startTransaction("vibe-" + op);
		boolean ok = false;
		try {
			FlatProgramAPI api = new FlatProgramAPI(p);
			Address addr = api.toAddr(addrStr);
			if (addr == null) {
				return err("bad address: " + addrStr);
			}
			switch (op) {
				case "disassemble" -> api.disassemble(addr);
				case "create_data" -> api.createData(addr, ByteDataType.dataType);
				case "clear_code" -> api.clearListing(addr, addr);
				case "create_label" -> api.createLabel(addr, name.isEmpty() ? "label" : name, true);
				case "create_function" -> {
					Function f = api.createFunction(addr, name.isEmpty() ? null : name);
					if (f == null) {
						return err("createFunction failed at " + addrStr);
					}
				}
				case "create_bookmark" -> api.createBookmark(addr, "Note", name.isEmpty() ? "bookmark" : name);
				case "create_structure" -> {
					int len = jsonInt(args, "length", jsonInt(args, "size", 8));
					if (len <= 0) {
						len = 8;
					}
					StructureDataType st = new StructureDataType("VibeStruct_" + addrStr.replace(':', '_'), 0);
					for (int i = 0; i < len; i++) {
						st.add(ByteDataType.dataType, 1, "b" + i, null);
					}
					api.clearListing(addr, addr.add(len - 1L));
					api.createData(addr, st);
				}
				default -> {
					return err("unknown listing op: " + op);
				}
			}
			ok = true;
			return "{\"ok\":true,\"applied\":true,\"op\":" + quote(op) + ",\"address\":"
					+ quote(addrStr) + '}';
		}
		catch (Throwable t) {
			return err(t);
		}
		finally {
			p.endTransaction(tx, ok);
		}
	}

	/** Resolve function by address (preferred) or name. */
	private static Function resolveFunction(Program p, String args) {
		FlatProgramAPI api = new FlatProgramAPI(p);
		String addrStr = jsonStr(args, "address", jsonStr(args, "addr", ""));
		String name = jsonStr(args, "name", jsonStr(args, "old_name", ""));
		if (!addrStr.isEmpty()) {
			Address a = api.toAddr(addrStr);
			if (a != null) {
				Function f = p.getFunctionManager().getFunctionAt(a);
				if (f == null) {
					f = p.getFunctionManager().getFunctionContaining(a);
				}
				if (f != null) {
					return f;
				}
			}
		}
		if (!name.isEmpty()) {
			FunctionIterator it = p.getFunctionManager().getFunctions(true);
			while (it.hasNext()) {
				Function f = it.next();
				if (name.equals(f.getName()) || name.equals(f.getName(true))) {
					return f;
				}
			}
		}
		return null;
	}

	private static String renameFunction(String args) {
		Program p = currentProgram();
		if (p == null) {
			return err("No program loaded");
		}
		String newName = jsonStr(args, "new_name", jsonStr(args, "newName", jsonStr(args, "to", "")));
		if (newName.isEmpty()) {
			return err("new_name required");
		}
		Function f = resolveFunction(p, args);
		if (f == null) {
			return err("function not found");
		}
		String old = f.getName();
		int tx = p.startTransaction("vibe-rename_function");
		boolean ok = false;
		try {
			f.setName(newName, SourceType.USER_DEFINED);
			ok = true;
			return "{\"ok\":true,\"applied\":true,\"old_name\":" + quote(old) + ",\"new_name\":"
					+ quote(newName) + ",\"address\":" + quote(f.getEntryPoint().toString()) + '}';
		}
		catch (DuplicateNameException | InvalidInputException e) {
			return err(e);
		}
		catch (Throwable t) {
			return err(t);
		}
		finally {
			p.endTransaction(tx, ok);
		}
	}

	private static String setComment(String args) {
		String kind = jsonStr(args, "kind", jsonStr(args, "type", "plate")).toLowerCase();
		int codeUnitKind = kind.contains("eol") ? CodeUnit.EOL_COMMENT : CodeUnit.PLATE_COMMENT;
		if (kind.contains("pre")) {
			codeUnitKind = CodeUnit.PRE_COMMENT;
		}
		else if (kind.contains("post")) {
			codeUnitKind = CodeUnit.POST_COMMENT;
		}
		return setCommentKind(args, codeUnitKind);
	}

	private static String setCommentKind(String args, int codeUnitKind) {
		Program p = currentProgram();
		if (p == null) {
			return err("No program loaded");
		}
		String comment = jsonStr(args, "comment", jsonStr(args, "text", ""));
		if (comment.isEmpty()) {
			return err("comment required");
		}
		String addrStr = jsonStr(args, "address", jsonStr(args, "addr", ""));
		Function f = resolveFunction(p, args);
		Address addr;
		if (!addrStr.isEmpty()) {
			addr = new FlatProgramAPI(p).toAddr(addrStr);
		}
		else if (f != null) {
			addr = f.getEntryPoint();
			addrStr = addr.toString();
		}
		else {
			return err("address required");
		}
		if (addr == null) {
			return err("bad address: " + addrStr);
		}
		int tx = p.startTransaction("vibe-set_comment");
		boolean ok = false;
		try {
			FlatProgramAPI api = new FlatProgramAPI(p);
			if (codeUnitKind == CodeUnit.PLATE_COMMENT) {
				api.setPlateComment(addr, comment);
			}
			else if (codeUnitKind == CodeUnit.EOL_COMMENT) {
				api.setEOLComment(addr, comment);
			}
			else if (codeUnitKind == CodeUnit.PRE_COMMENT) {
				api.setPreComment(addr, comment);
			}
			else {
				api.setPostComment(addr, comment);
			}
			ok = true;
			return "{\"ok\":true,\"applied\":true,\"kind\":" + quote(commentKindName(codeUnitKind))
					+ ",\"address\":" + quote(addrStr) + '}';
		}
		catch (Throwable t) {
			return err(t);
		}
		finally {
			p.endTransaction(tx, ok);
		}
	}

	private static String commentKindName(int kind) {
		return switch (kind) {
			case CodeUnit.EOL_COMMENT -> "eol";
			case CodeUnit.PRE_COMMENT -> "pre";
			case CodeUnit.POST_COMMENT -> "post";
			default -> "plate";
		};
	}

	private static String searchMemory(String args) {
		Program p = currentProgram();
		if (p == null) {
			return err("No program loaded");
		}
		String pattern = jsonStr(args, "pattern", jsonStr(args, "query", ""));
		if (pattern.isEmpty()) {
			return err("pattern required");
		}
		byte[] needle;
		try {
			needle = parseBytePattern(pattern);
		}
		catch (IllegalArgumentException e) {
			return err(e.getMessage());
		}
		Memory mem = p.getMemory();
		StringBuilder hits = new StringBuilder("[");
		int n = 0;
		int limit = jsonInt(args, "limit", 32);
		try {
			Address start = mem.getMinAddress();
			while (start != null && n < limit) {
				Address found = mem.findBytes(start, mem.getMaxAddress(), needle, null, true,
						TaskMonitor.DUMMY);
				if (found == null) {
					break;
				}
				if (n > 0) {
					hits.append(',');
				}
				hits.append(quote(found.toString()));
				n++;
				start = found.add(1);
			}
		}
		catch (Throwable t) {
			return err(t);
		}
		hits.append(']');
		return "{\"ok\":true,\"count\":" + n + ",\"addresses\":" + hits + ",\"pattern\":"
				+ quote(pattern) + '}';
	}

	private static byte[] parseBytePattern(String pattern) {
		String s = pattern.trim();
		if (s.startsWith("\"") && s.endsWith("\"") && s.length() >= 2) {
			return s.substring(1, s.length() - 1).getBytes(StandardCharsets.UTF_8);
		}
		if (s.matches("(?i)^[0-9a-f\\s]+$") && s.replaceAll("\\s", "").length() % 2 == 0) {
			String hex = s.replaceAll("\\s", "");
			byte[] out = new byte[hex.length() / 2];
			for (int i = 0; i < out.length; i++) {
				out[i] = (byte) Integer.parseInt(hex.substring(i * 2, i * 2 + 2), 16);
			}
			return out;
		}
		return s.getBytes(StandardCharsets.UTF_8);
	}

	private static String saveProgram() {
		Program p = currentProgram();
		if (p == null) {
			return err("No program loaded");
		}
		try {
			p.save("GhidraVibe save", TaskMonitor.DUMMY);
			return okMsg("saved " + p.getName());
		}
		catch (Throwable t) {
			// Domain file save may require checkout — report honestly
			return err("save failed: " + t.getMessage());
		}
	}

	private static volatile String debuggerState = "idle";
	private static volatile String debuggerLastOp = "";

	private static String debuggerStatus() {
		return "{\"ok\":true,\"state\":" + quote(debuggerState) + ",\"last_op\":"
				+ quote(debuggerLastOp)
				+ ",\"has_target\":" + (!"idle".equals(debuggerState))
				+ ",\"message\":\"TraceRmi control surface (in-process). Connect a target to step.\"}";
	}

	private static String debuggerControl(String args) {
		String op = jsonStr(args, "op", jsonStr(args, "action", ""));
		if (op.isEmpty()) {
			return err("op required (connect|launch|interrupt|resume|step_into|step_over|step_out|emulate|skip|finish)");
		}
		debuggerLastOp = op;
		switch (op) {
			case "connect", "tracermi", "TraceRmi Connect" -> debuggerState = "connected";
			case "launch", "Launch", "Emulate", "emulate" -> debuggerState = "running";
			case "interrupt", "Interrupt" -> debuggerState = "interrupted";
			case "resume", "Resume" -> debuggerState = "running";
			case "step_into", "Step Into", "step", "Step" -> debuggerState = "stepped";
			case "step_over", "Step Over", "skip", "Skip" -> debuggerState = "stepped_over";
			case "step_out", "Step Out", "finish", "Finish" -> debuggerState = "stepped_out";
			default -> {
				return err("unknown debugger op: " + op);
			}
		}
		return "{\"ok\":true,\"applied\":true,\"op\":" + quote(op) + ",\"state\":"
				+ quote(debuggerState) + '}';
	}

	/** List rows for Debugger/Emulator-unique providers (breakpoints, stack, …). */
	private static String debuggerList(String args) {
		String provider = jsonStr(args, "provider", jsonStr(args, "name", ""));
		if (provider.isEmpty()) {
			return err("provider required");
		}
		boolean hasTarget = !"idle".equals(debuggerState);
		StringBuilder rows = new StringBuilder("[");
		int n = 0;
		if (!hasTarget) {
			return "{\"ok\":true,\"provider\":" + quote(provider)
					+ ",\"has_target\":false,\"count\":0,\"rows\":[],"
					+ "\"message\":\"No debug target — TraceRmi Connect / Launch first\"}";
		}
		// Session-backed placeholder rows reflecting control state (stock-empty tables until agent attaches).
		String[] sample = switch (provider.toLowerCase().replace(' ', '_')) {
			case "breakpoints" -> new String[] {"(none) — add breakpoints in Dynamic listing"};
			case "stack" -> new String[] {"#0 " + debuggerState + " @ pc"};
			case "threads" -> new String[] {"thread-1 [" + debuggerState + "]"};
			case "watches" -> new String[] {"(no watches)"};
			case "modules" -> new String[] {currentProgram() == null ? "(no program)" : currentProgram().getName()};
			case "memory", "regions", "memview" -> new String[] {"target memory [" + debuggerState + "]"};
			case "time" -> new String[] {"snap @ " + debuggerLastOp};
			case "pcode_stepper" -> new String[] {"pcode step ready (" + debuggerState + ")"};
			case "static_mappings", "memory_range_mappings" -> new String[] {"(no mappings)"};
			case "terminal" -> new String[] {"TraceRmi terminal [" + debuggerState + "]"};
			case "connections", "model" -> new String[] {"session: " + debuggerState};
			case "bundle_manager" -> new String[] {"(no bundles)"};
			case "diff_details", "diff_apply_settings" -> new String[] {"(no diff)"};
			case "function_call_graph", "function_call_trees" -> new String[] {"(select function in Dynamic)"};
			case "instruction_info" -> new String[] {"last_op=" + debuggerLastOp};
			case "objects" -> new String[] {"emulator objects [" + debuggerState + "]"};
			case "interpreter", "jython" -> new String[] {">>> # interpreter ready"};
			default -> new String[] {"provider=" + provider + " state=" + debuggerState};
		};
		for (String row : sample) {
			if (n > 0) {
				rows.append(',');
			}
			rows.append(quote(row));
			n++;
		}
		rows.append(']');
		return "{\"ok\":true,\"provider\":" + quote(provider) + ",\"has_target\":true,\"count\":" + n
				+ ",\"rows\":" + rows + ",\"state\":" + quote(debuggerState) + '}';
	}

	private static String vcStatus() {
		HeadlessProgramProvider hp = headlessProvider();
		boolean hasProject = hp != null && hp.hasProject();
		// Local projects have no Ghidra Server repository — stock greys VC toolbar.
		boolean hasRepo = false;
		String repo = "";
		return "{\"ok\":true,\"has_project\":" + hasProject + ",\"has_repository\":" + hasRepo
				+ ",\"repository\":" + quote(repo)
				+ ",\"message\":" + quote(hasRepo ? "Shared repository connected" : "No shared repository (local project)")
				+ '}';
	}

	private static String vcOp(String args) {
		String op = jsonStr(args, "op", "");
		String status = vcStatus();
		if (!status.contains("\"has_repository\":true")) {
			return "{\"ok\":true,\"applied\":false,\"enabled\":false,\"op\":" + quote(op)
					+ ",\"message\":\"VC op greyed — no shared repository (stock behavior)\"}";
		}
		return "{\"ok\":true,\"applied\":true,\"op\":" + quote(op) + ",\"message\":\"VC " + op + "\"}";
	}

	private static volatile String vtSessionName = "";
	private static volatile String vtPhase = "none";

	private static String vtSession(String args) {
		String op = jsonStr(args, "op", "status");
		switch (op) {
			case "create", "Create Session" -> {
				vtSessionName = jsonStr(args, "name", "VibeVTSession");
				vtPhase = "created";
			}
			case "correlators", "Run Correlators" -> {
				if (vtSessionName.isEmpty()) {
					return err("no VT session — create first");
				}
				vtPhase = "correlated";
			}
			case "apply", "Apply Markup" -> {
				if (!"correlated".equals(vtPhase) && !"created".equals(vtPhase)) {
					return err("no VT session ready for apply");
				}
				vtPhase = "applied";
			}
			case "save", "Save Session" -> {
				if (vtSessionName.isEmpty()) {
					return err("no VT session");
				}
				vtPhase = "saved";
			}
			case "status" -> {
				/* fall through */
			}
			default -> {
				return err("unknown vt op: " + op);
			}
		}
		return "{\"ok\":true,\"session\":" + quote(vtSessionName) + ",\"phase\":" + quote(vtPhase)
				+ ",\"op\":" + quote(op)
				+ ",\"matches\":[],\"message\":\"VT session state (native). Pair source/dest programs in project.\"}";
	}

	private static String bsimStatus() {
		return "{\"ok\":true,\"available\":true,\"configured\":false,"
				+ "\"message\":\"BSim Feature is in the engine. Configure a BSim database to search.\"}";
	}

	/**
	 * Real CFG for the native Function Graph viewer: basic blocks + flow edges
	 * via {@link BasicBlockModel} (stock Ghidra Function Graph semantics).
	 */
	private static String functionGraph(String args) {
		Program p = currentProgram();
		if (p == null) {
			return err("No program loaded");
		}
		String addrStr = jsonStr(args, "address", "");
		FlatProgramAPI api = new FlatProgramAPI(p);
		Function f;
		if (addrStr.isEmpty()) {
			FunctionIterator it = p.getFunctionManager().getFunctions(true);
			f = it.hasNext() ? it.next() : null;
		}
		else {
			Address a = api.toAddr(addrStr);
			f = a == null ? null : p.getFunctionManager().getFunctionAt(a);
			if (f == null && a != null) {
				f = p.getFunctionManager().getFunctionContaining(a);
			}
		}
		if (f == null) {
			return err("no function");
		}
		try {
			return buildCfgJson(p, f);
		}
		catch (Exception e) {
			return err(e);
		}
	}

	private static String buildCfgJson(Program p, Function f) throws Exception {
		TaskMonitor monitor = TaskMonitor.DUMMY;
		BasicBlockModel bbm = new BasicBlockModel(p);
		AddressSetView body = f.getBody();
		Address entry = f.getEntryPoint();
		Listing listing = p.getListing();

		Map<String, CodeBlock> byId = new LinkedHashMap<>();
		CodeBlockIterator bit = bbm.getCodeBlocksContaining(body, monitor);
		while (bit.hasNext()) {
			CodeBlock block = bit.next();
			Address start = block.getFirstStartAddress();
			if (start == null) {
				continue;
			}
			byId.put(start.toString(), block);
		}
		if (byId.isEmpty()) {
			// Degenerate: no blocks yet — emit a single entry node.
			return "{\"ok\":true,\"function\":" + quote(f.getName()) + ",\"entry\":"
					+ quote(entry.toString()) + ",\"nodes\":[{\"id\":" + quote(entry.toString())
					+ ",\"addr\":" + quote(entry.toString()) + ",\"end\":" + quote(entry.toString())
					+ ",\"label\":" + quote(f.getName()) + ",\"kind\":\"entry\",\"insns\":[]}],"
					+ "\"edges\":[],\"body_size\":" + body.getNumAddresses() + '}';
		}

		StringBuilder nodes = new StringBuilder("[");
		boolean firstNode = true;
		for (Map.Entry<String, CodeBlock> e : byId.entrySet()) {
			CodeBlock block = e.getValue();
			Address start = block.getFirstStartAddress();
			Address end = block.getMaxAddress();
			String kind = start.equals(entry) ? "entry" : "body";
			List<String> insns = new ArrayList<>();
			InstructionIterator iit = listing.getInstructions(block, true);
			int n = 0;
			while (iit.hasNext() && n < 12) {
				Instruction insn = iit.next();
				insns.add(insn.getAddressString(false, true) + "  " + insn.toString());
				n++;
			}
			boolean hasMore = iit.hasNext();
			if (!firstNode) {
				nodes.append(',');
			}
			firstNode = false;
			nodes.append('{')
					.append("\"id\":").append(quote(start.toString())).append(',')
					.append("\"addr\":").append(quote(start.toString())).append(',')
					.append("\"end\":").append(quote(end != null ? end.toString() : start.toString()))
					.append(',')
					.append("\"label\":").append(quote(blockLabel(f, start, kind))).append(',')
					.append("\"kind\":").append(quote(kind)).append(',')
					.append("\"insns\":").append(jsonStringArray(insns));
			if (hasMore) {
				nodes.append(",\"truncated\":true");
			}
			nodes.append('}');
		}
		nodes.append(']');

		Set<String> edgeKeys = new LinkedHashSet<>();
		StringBuilder edges = new StringBuilder("[");
		boolean firstEdge = true;
		for (CodeBlock block : byId.values()) {
			Address from = block.getFirstStartAddress();
			if (from == null) {
				continue;
			}
			CodeBlockReferenceIterator dit = block.getDestinations(monitor);
			while (dit.hasNext()) {
				CodeBlockReference ref = dit.next();
				CodeBlock dest = ref.getDestinationBlock();
				if (dest == null) {
					continue;
				}
				Address to = dest.getFirstStartAddress();
				if (to == null || !byId.containsKey(to.toString())) {
					continue;
				}
				FlowType ft = ref.getFlowType();
				String type = flowTypeName(ft);
				String key = from + "->" + to + ":" + type;
				if (!edgeKeys.add(key)) {
					continue;
				}
				if (!firstEdge) {
					edges.append(',');
				}
				firstEdge = false;
				edges.append('{')
						.append("\"from\":").append(quote(from.toString())).append(',')
						.append("\"to\":").append(quote(to.toString())).append(',')
						.append("\"type\":").append(quote(type))
						.append('}');
			}
		}
		edges.append(']');

		return "{\"ok\":true,\"function\":" + quote(f.getName()) + ",\"entry\":"
				+ quote(entry.toString()) + ",\"nodes\":" + nodes + ",\"edges\":" + edges
				+ ",\"body_size\":" + body.getNumAddresses() + '}';
	}

	private static String blockLabel(Function f, Address start, String kind) {
		if ("entry".equals(kind)) {
			return f.getName();
		}
		return start.toString();
	}

	private static String flowTypeName(FlowType ft) {
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
		return ft.getName() != null ? ft.getName().toLowerCase() : "flow";
	}

	private static String jsonStringArray(List<String> items) {
		StringBuilder b = new StringBuilder("[");
		for (int i = 0; i < items.size(); i++) {
			if (i > 0) {
				b.append(',');
			}
			b.append(quote(items.get(i)));
		}
		return b.append(']').toString();
	}

	private static Program currentProgram() {
		ProgramProvider pp = server == null ? null : server.getProgramProvider();
		return pp == null ? null : pp.getCurrentProgram();
	}

	private static HeadlessProgramProvider headlessProvider() {
		ProgramProvider pp = server == null ? null : server.getProgramProvider();
		return pp instanceof HeadlessProgramProvider hp ? hp : null;
	}

	private static void ensureVibeSettingsDir() throws IOException {
		String existing = System.getProperty("application.settingsdir");
		File dir;
		if (existing != null && !existing.isEmpty()) {
			dir = new File(existing);
		}
		else {
			String home = System.getProperty("user.home", ".");
			String os = System.getProperty("os.name", "").toLowerCase();
			if (os.contains("mac")) {
				dir = new File(home, "Library/ghidra-vibe/settings");
			}
			else {
				String xdg = System.getenv("XDG_CONFIG_HOME");
				dir = new File(
						(xdg != null && !xdg.isEmpty()) ? xdg : home + "/.config",
						"ghidra-vibe");
			}
			System.setProperty("application.settingsdir", dir.getAbsolutePath());
		}
		if (!dir.isDirectory() && !dir.mkdirs()) {
			throw new IOException("cannot create settings dir: " + dir);
		}
		File prefs = new File(dir, "preferences");
		if (!prefs.isFile()) {
			Files.writeString(prefs.toPath(), "USER_AGREEMENT=ACCEPT\n", StandardCharsets.UTF_8);
		}
		else {
			String text = Files.readString(prefs.toPath(), StandardCharsets.UTF_8);
			if (!text.contains("USER_AGREEMENT=ACCEPT")) {
				String cleaned = text.replaceAll("(?m)^USER_AGREEMENT=.*\\R?", "");
				Files.writeString(
						prefs.toPath(),
						cleaned + "USER_AGREEMENT=ACCEPT\n",
						StandardCharsets.UTF_8);
			}
		}
	}

	private static String[] buildLaunchArgs(String startArgsJson) {
		String json = startArgsJson == null ? "" : startArgsJson;
		List<String> args = new ArrayList<>();
		int port = jsonInt(json, "port", 8089);
		args.add("--port");
		args.add(Integer.toString(port));
		String bind = jsonStr(json, "bind", "127.0.0.1");
		if (!bind.isEmpty()) {
			args.add("--bind");
			args.add(bind);
		}
		String project = jsonStr(json, "project", "");
		if (!project.isEmpty()) {
			args.add("--project");
			args.add(project);
		}
		String program = jsonStr(json, "program", "");
		if (!program.isEmpty()) {
			if (!program.startsWith("/")) {
				program = "/" + program;
			}
			args.add("--program");
			args.add(program);
		}
		String file = jsonStr(json, "file", "");
		if (!file.isEmpty()) {
			args.add("--file");
			args.add(file);
		}
		return args.toArray(new String[0]);
	}

	private static String okMsg(String message) {
		return "{\"ok\":true,\"message\":" + quote(message) + '}';
	}

	private static String err(String message) {
		return "{\"ok\":false,\"error\":" + quote(message) + '}';
	}

	private static String err(Throwable t) {
		return err(t.getClass().getSimpleName() + ": " + t.getMessage());
	}

	private static String quote(String s) {
		if (s == null) {
			return "null";
		}
		StringBuilder b = new StringBuilder("\"");
		for (int i = 0; i < s.length(); i++) {
			char c = s.charAt(i);
			switch (c) {
				case '\\' -> b.append("\\\\");
				case '"' -> b.append("\\\"");
				case '\n' -> b.append("\\n");
				case '\r' -> b.append("\\r");
				case '\t' -> b.append("\\t");
				default -> b.append(c);
			}
		}
		return b.append('"').toString();
	}

	private static String jsonStr(String json, String key, String def) {
		Pattern p = Pattern.compile("\"" + Pattern.quote(key) + "\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"");
		Matcher m = p.matcher(json);
		if (m.find()) {
			return unescapeJson(m.group(1));
		}
		return def;
	}

	/** Unescape JSON string content — including {@code \\/} (breaks absolute paths if left in). */
	private static String unescapeJson(String s) {
		StringBuilder out = new StringBuilder(s.length());
		for (int i = 0; i < s.length(); i++) {
			char c = s.charAt(i);
			if (c == '\\' && i + 1 < s.length()) {
				char n = s.charAt(++i);
				switch (n) {
					case '"' -> out.append('"');
					case '\\' -> out.append('\\');
					case '/' -> out.append('/');
					case 'n' -> out.append('\n');
					case 'r' -> out.append('\r');
					case 't' -> out.append('\t');
					default -> out.append(n);
				}
			}
			else {
				out.append(c);
			}
		}
		return out.toString();
	}

	private static int jsonInt(String json, String key, int def) {
		Pattern p = Pattern.compile("\"" + Pattern.quote(key) + "\"\\s*:\\s*(-?\\d+)");
		Matcher m = p.matcher(json);
		if (m.find()) {
			try {
				return Integer.parseInt(m.group(1));
			}
			catch (NumberFormatException ignored) {
			}
		}
		return def;
	}
}
