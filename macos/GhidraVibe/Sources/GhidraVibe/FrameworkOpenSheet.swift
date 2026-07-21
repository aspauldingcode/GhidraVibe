import SwiftUI

/// First-class “Open Framework from Shared Cache” — IDA-like: filter → Open → CodeBrowser.
/// Layout order matches stock flow; spacing follows macOS HIG sheet margins (20 pt).
struct FrameworkOpenSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            // Header — Cancel aligned trailing (standard sheet chrome).
            HStack(alignment: .firstTextBaseline) {
                Text("Open Framework from Shared Cache")
                    .font(.headline)
                Spacer(minLength: VibeChrome.Space.xl)
                Button("Cancel") {
                    model.showFrameworkOpenSheet = false
                    dismiss()
                }
                .a11yCatalog("ghidra.vibe.framework_open.cancel")
            }
            .padding(.horizontal, VibeChrome.Space.margin)
            .padding(.top, VibeChrome.Space.marginTop)
            .padding(.bottom, VibeChrome.Space.section)

            Text(
                "Browse the on-device dyld shared cache and open one framework/dylib into your project — "
                    + "same flow as IDA’s DSC Index. Listing, Decompile, Function Graph, and Classes open automatically."
            )
            .font(.callout)
            .foregroundStyle(Color.vibeSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, VibeChrome.Space.margin)
            .padding(.bottom, VibeChrome.Space.related)

            Text(model.dyldCachePath ?? "Discovering on-device cache…")
                .font(.caption.monospaced())
                .lineLimit(2)
                .textSelection(.enabled)
                .padding(.horizontal, VibeChrome.Space.margin)
                .padding(.bottom, VibeChrome.Space.section)
                .a11yCatalog("ghidra.vibe.framework_open.cache_path")

            // Search + Auto Analyze — related controls, then breathing room before the list.
            VStack(alignment: .leading, spacing: VibeChrome.Space.related) {
                TextField("Search frameworks (AppKit, SwiftUI, SkyLight…)", text: $model.dyldQuery)
                    .textFieldStyle(.roundedBorder)
                    .a11yCatalog("ghidra.vibe.framework_open.search")
                    .onSubmit { model.refreshDyldImagesAsync(query: model.dyldQuery) }
                    .onChange(of: model.dyldQuery) { _, newValue in
                        model.scheduleDyldFilter(newValue)
                    }

                Toggle("Auto Analyze after open", isOn: $model.dyldRunAnalysisOnImport)
                    .toggleStyle(.checkbox)
                    .help("Off = open module first (IDA-like). On = run full analysis (slower).")
                    .a11yCatalog("ghidra.vibe.framework_open.analyze_toggle")

                if model.dyldListingBusy || model.dyldImportBusy {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: VibeChrome.Space.related) {
                            ProgressView().controlSize(.small)
                            Text(model.dyldImportBusy
                                ? "Importing from dyld shared cache…"
                                : "Scanning shared cache…")
                                .font(.caption.weight(.semibold))
                        }
                        if model.dyldImportBusy {
                            Text(model.statusMessage)
                                .font(.caption)
                                .foregroundStyle(Color.vibeSecondary)
                                .lineLimit(3)
                            Text("Live transcript → Console  ·  log: ~/Library/Logs/GhidraVibe/dsc-import-latest.log")
                                .font(.caption2)
                                .foregroundStyle(Color.vibeMuted)
                        }
                    }
                    .a11yCatalog("ghidra.vibe.framework_open.progress")
                }
            }
            .padding(.horizontal, VibeChrome.Space.margin)
            // HIG: pad below the last control before a scrolling list (≥12–16 pt).
            .padding(.bottom, VibeChrome.Space.listInset)

            List(model.dyldImages, id: \.self, selection: $model.selectedDyldImage) { img in
                Text((img as NSString).lastPathComponent)
                    .font(.body.monospaced())
                    .help(img)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { openSelected(img) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.visible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: VibeChrome.Radius.nestMin, style: .continuous))
            .disabled(model.dyldImportBusy)
            .padding(.horizontal, VibeChrome.Space.margin)
            // Space between list and footer actions (related group → button row).
            .padding(.bottom, VibeChrome.Space.section)
            .a11yCatalog("ghidra.vibe.framework_open.list")

            HStack(spacing: VibeChrome.Space.related) {
                Text("\(model.dyldImages.count) matches")
                    .font(.caption)
                    .foregroundStyle(Color.vibeSecondary)
                Spacer(minLength: VibeChrome.Space.xl)
                if model.dyldImportBusy {
                    Button("Show Console") {
                        model.showFrameworkOpenSheet = false
                        model.showProvider(.console)
                    }
                    .help("Watch the live DSC import transcript")
                    .a11yCatalog("ghidra.vibe.framework_open.show_console")
                }
                Button("Browse cache index…") {
                    model.showFrameworkOpenSheet = false
                    model.openDyldCache()
                }
                .disabled(model.dyldImportBusy)
                .help("Open the full Shared Cache provider")
                Button(model.dyldImportBusy ? "Importing…" : "Open") {
                    if let img = model.selectedDyldImage {
                        openSelected(img)
                    }
                }
                .buttonStyle(.borderedProminent)
                    .tint(Color.vibeAccent)
                .disabled(model.selectedDyldImage == nil || model.dyldImportBusy)
                .keyboardShortcut(.defaultAction)
                .a11yCatalog("ghidra.vibe.framework_open.open")
            }
            .padding(.horizontal, VibeChrome.Space.margin)
            .padding(.bottom, VibeChrome.Space.margin)
        }
        .frame(minWidth: 520, idealWidth: 640, minHeight: 420, idealHeight: 520)
        .vibeContainer(radius: VibeChrome.Radius.shell)
        .a11yContainerCatalog("ghidra.vibe.framework_open")
        .onAppear {
            model.ensureVibeMCP()
            model.discoverDyldCache()
            if model.dyldImages.isEmpty {
                model.refreshDyldImagesAsync(query: model.dyldQuery)
            }
        }
    }

    private func openSelected(_ image: String) {
        model.selectedDyldImage = image
        // Keep sheet open with live status; Console also receives the transcript.
        // Sheet dismisses automatically when import succeeds.
        model.importDyldImage(image)
        model.showProvider(.console)
    }
}
