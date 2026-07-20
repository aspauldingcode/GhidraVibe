// Import one image from an on-device dyld shared cache via DyldCacheFileSystem
// (IDA-like: open cache FS → select module → load). Applies DSC local symbols
// (Apple nlist in the cache) and enables DWARF / ObjC analyzers.
//@category Vibe
//@menupath Tools.Vibe.Import Dyld Cache Image

import java.io.File;

import ghidra.app.script.GhidraScript;
import ghidra.app.util.importer.AutoImporter;
import ghidra.app.util.importer.MessageLog;
import ghidra.app.util.opinion.LoadResults;
import ghidra.app.util.opinion.Loaded;
import ghidra.framework.options.Options;
import ghidra.formats.gfilesystem.FSRL;
import ghidra.formats.gfilesystem.FileSystemProbeConflictResolver;
import ghidra.formats.gfilesystem.FileSystemRef;
import ghidra.formats.gfilesystem.FileSystemService;
import ghidra.formats.gfilesystem.GFile;
import ghidra.formats.gfilesystem.GFileSystem;
import ghidra.program.model.listing.Program;

public class ImportDyldCacheImage extends GhidraScript {

	@Override
	protected void run() throws Exception {
		String[] args = getScriptArgs();
		if (args.length < 2) {
			printerr("Usage: ImportDyldCacheImage.java <cachePath> <imagePath> [programName]");
			return;
		}

		File cacheFile = new File(args[0]);
		String imagePath = args[1];
		String programName = args.length >= 3 ? args[2] : new File(imagePath).getName();

		if (!cacheFile.isFile()) {
			printerr("Cache not found: " + cacheFile);
			return;
		}

		boolean appleSymbols =
			!"0".equals(System.getenv().getOrDefault("GHIDRA_VIBE_APPLE_SYMBOLS", "1"));
		boolean runAnalysis = !"0".equals(System.getenv().getOrDefault("GHIDRA_VIBE_ANALYZE", "1"));

		FSRL container = FSRL.fromString("file://" + cacheFile.getAbsolutePath());
		FileSystemService fsService = FileSystemService.getInstance();
		MessageLog log = new MessageLog();

		try (FileSystemRef fsRef = fsService.probeFileForFilesystem(container, monitor,
			FileSystemProbeConflictResolver.CHOOSEFIRST)) {
			if (fsRef == null) {
				printerr("Could not open dyld cache as filesystem (DyldCacheFileSystem)");
				return;
			}
			GFileSystem fs = fsRef.getFilesystem();
			println("Opened DSC filesystem: " + fs.getName() + " type=" + fs.getType());

			GFile image = lookupImage(fs, imagePath);
			if (image == null) {
				printerr("Image not in cache FS: " + imagePath);
				return;
			}

			FSRL nested = image.getFSRL();
			println("Importing FSRL: " + nested);
			// DyldCacheFileSystem.getByteProvider applies slide fixups + local symbols.
			try (LoadResults<Program> results = AutoImporter.importByUsingBestGuess(nested,
				state.getProject(), "/", this, log, monitor)) {

				if (results.size() == 0) {
					printerr("Import produced no program. Log: " + log);
					return;
				}

				Loaded<Program> primary = results.getPrimary();
				Program program = primary.getDomainObject(this);
				if (appleSymbols) {
					enableAppleSymbolAnalyzers(program);
				}
				if (runAnalysis) {
					println("Analyzing with Apple/DWARF/ObjC/Swift options…");
					// Headless preScript must open an explicit DB transaction.
					int txId = program.startTransaction("Vibe analyze");
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
				println("OK: imported " + program.getName() + " as " + programName +
					" from " + imagePath);
				println("APPLE_SYMBOLS=" + (appleSymbols ? "on" : "off"));
				println("SWIFT_ANALYZERS=" + (appleSymbols ? "Demangler Swift + Type Metadata" : "off"));
			}
		}
	}

	private GFile lookupImage(GFileSystem fs, String imagePath) throws Exception {
		GFile direct = fs.lookup(imagePath);
		if (direct != null && !direct.isDirectory()) {
			return direct;
		}
		String alt = imagePath.startsWith("/") ? imagePath.substring(1) : "/" + imagePath;
		direct = fs.lookup(alt);
		if (direct != null && !direct.isDirectory()) {
			return direct;
		}
		return findBySuffix(fs, fs.getListing(null), imagePath, 0);
	}

	private GFile findBySuffix(GFileSystem fs, java.util.List<GFile> files, String needle,
			int depth) throws Exception {
		if (depth > 6 || files == null) {
			return null;
		}
		String n = needle.toLowerCase();
		String base = new File(needle).getName().toLowerCase();
		for (GFile f : files) {
			monitor.checkCancelled();
			String path = f.getPath();
			if (path == null) {
				continue;
			}
			String pl = path.toLowerCase();
			if (!f.isDirectory() && (pl.equals(n) || pl.endsWith("/" + base) || pl.endsWith(n))) {
				return f;
			}
			if (f.isDirectory()) {
				GFile hit = findBySuffix(fs, fs.getListing(f), needle, depth + 1);
				if (hit != null) {
					return hit;
				}
			}
		}
		return null;
	}

	private void enableAppleSymbolAnalyzers(Program program) {
		Options opts = program.getOptions(Program.ANALYSIS_PROPERTIES);
		setTrue(opts, "DWARF");
		setTrue(opts, "Objective-C 2 Class");
		setTrue(opts, "Demangler GNU");
		// Swift / SwiftUI: stock Ghidra SwiftDemangler + type metadata (needs `swift` on PATH).
		setTrue(opts, "Demangler Swift");
		setTrue(opts, "Swift Type Metadata Analyzer");
		setTrue(opts, "Apply Data Archives");
		setTrue(opts, "Function Start Search");
		println("Enabled Apple-oriented analyzers (DWARF/ObjC/Swift demangle+metadata/Demangler)");
	}

	private static void setTrue(Options opts, String name) {
		try {
			opts.setBoolean(name, true);
		}
		catch (Exception ignored) {
			// Analyzer name differs across Ghidra versions — best effort.
		}
	}
}
