// Import a Mach-O from an IPA / .app bundle / bare binary with Apple analyzers
// (ObjC, Swift demangle + type metadata, DWARF) — Malimite-inspired workflow.
//@category Vibe
//@menupath Tools.Vibe.Import Apple Bundle

import java.io.File;

import ghidra.app.script.GhidraScript;
import ghidra.app.util.importer.AutoImporter;
import ghidra.app.util.importer.MessageLog;
import ghidra.app.util.opinion.LoadResults;
import ghidra.app.util.opinion.Loaded;
import ghidra.framework.options.Options;
import ghidra.program.model.listing.Program;

public class ImportAppleBundle extends GhidraScript {

	@Override
	protected void run() throws Exception {
		String[] args = getScriptArgs();
		if (args.length < 1) {
			printerr("Usage: ImportAppleBundle.java <machoPath> [programName]");
			return;
		}

		File macho = new File(args[0]);
		String programName = args.length >= 2 ? args[1] : macho.getName();
		if (!macho.isFile()) {
			printerr("Binary not found: " + macho);
			return;
		}

		boolean appleSymbols =
			!"0".equals(System.getenv().getOrDefault("GHIDRA_VIBE_APPLE_SYMBOLS", "1"));
		boolean runAnalysis = !"0".equals(System.getenv().getOrDefault("GHIDRA_VIBE_ANALYZE", "1"));
		boolean skipLibHeavy =
			!"0".equals(System.getenv().getOrDefault("GHIDRA_VIBE_SKIP_LIB_ANALYSIS", "0"));

		MessageLog log = new MessageLog();
		println("Importing Apple Mach-O: " + macho.getAbsolutePath());

		try (LoadResults<Program> results = AutoImporter.importByUsingBestGuess(macho,
			state.getProject(), "/", this, log, monitor)) {

			if (results.size() == 0) {
				printerr("Import produced no program. Log: " + log);
				return;
			}

			Loaded<Program> primary = results.getPrimary();
			Program program = primary.getDomainObject(this);
			// Make available to subsequent -postScript dumps (Malimite DumpClassDataVibe).
			openProgram(program);
			if (appleSymbols) {
				enableAppleSymbolAnalyzers(program, skipLibHeavy);
			}
			if (runAnalysis) {
				println("Analyzing with Apple/ObjC/Swift options…");
				int txId = program.startTransaction("Vibe Apple analyze");
				boolean ok = false;
				try {
					analyzeAll(program);
					ok = true;
				}
				finally {
					program.endTransaction(txId, ok);
				}
			}
			results.save(monitor);
			println("OK: imported " + program.getName() + " as " + programName);
			println("APPLE_SYMBOLS=" + (appleSymbols ? "on" : "off"));
			println("SWIFT_ANALYZERS=" + (appleSymbols ? "Demangler Swift + Type Metadata" : "off"));
		}
	}

	private void enableAppleSymbolAnalyzers(Program program, boolean skipLibHeavy) {
		Options opts = program.getOptions(Program.ANALYSIS_PROPERTIES);
		setTrue(opts, "DWARF");
		setTrue(opts, "Objective-C 2 Class");
		setTrue(opts, "Demangler GNU");
		setTrue(opts, "Demangler Swift");
		setTrue(opts, "Swift Type Metadata Analyzer");
		setTrue(opts, "Apply Data Archives");
		setTrue(opts, "Function Start Search");
		if (skipLibHeavy) {
			// Malimite-style: prefer app code over system lib noise when analyzers honor it.
			setTrue(opts, "Shared Return Calls");
		}
		println("Enabled Apple-oriented analyzers (DWARF/ObjC/Swift demangle+metadata)");
	}

	private static void setTrue(Options opts, String name) {
		try {
			opts.setBoolean(name, true);
		}
		catch (Exception ignored) {
		}
	}
}
