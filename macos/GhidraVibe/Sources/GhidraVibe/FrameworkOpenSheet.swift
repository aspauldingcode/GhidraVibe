import SwiftUI

/// First-class “Open Framework from Shared Cache” — IDA-like: filter → Open → CodeBrowser.
struct FrameworkOpenSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Open Framework from Shared Cache")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    model.showFrameworkOpenSheet = false
                    dismiss()
                }
                .a11yCatalog("ghidra.vibe.framework_open.cancel")
            }
            .padding()

            Text(
                "Browse the on-device dyld shared cache and open one framework/dylib into your project — "
                    + "same flow as IDA’s DSC Index. Listing, Decompile, Function Graph, and Classes open automatically."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.bottom, 8)

            Text(model.dyldCachePath ?? "Discovering on-device cache…")
                .font(.caption.monospaced())
                .lineLimit(2)
                .textSelection(.enabled)
                .padding(.horizontal)
                .a11yCatalog("ghidra.vibe.framework_open.cache_path")

            TextField("Search frameworks (AppKit, SwiftUI, SkyLight…)", text: $model.dyldQuery)
                .textFieldStyle(.roundedBorder)
                .padding()
                .a11yCatalog("ghidra.vibe.framework_open.search")
                .onSubmit { model.refreshDyldImagesAsync(query: model.dyldQuery) }
                .onChange(of: model.dyldQuery) { _, newValue in
                    model.scheduleDyldFilter(newValue)
                }

            Toggle("Auto Analyze after open", isOn: $model.dyldRunAnalysisOnImport)
                .toggleStyle(.checkbox)
                .padding(.horizontal)
                .help("Off = open module first (IDA-like). On = run full analysis (slower).")
                .a11yCatalog("ghidra.vibe.framework_open.analyze_toggle")

            if model.dyldListingBusy || model.dyldImportBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.dyldImportBusy ? "Opening framework…" : "Scanning shared cache…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }

            List(model.dyldImages, id: \.self, selection: $model.selectedDyldImage) { img in
                Text((img as NSString).lastPathComponent)
                    .font(.body.monospaced())
                    .help(img)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { openSelected(img) }
            }
            .a11yCatalog("ghidra.vibe.framework_open.list")

            HStack {
                Text("\(model.dyldImages.count) matches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Browse cache index…") {
                    model.showFrameworkOpenSheet = false
                    model.openDyldCache()
                }
                .help("Open the full Shared Cache provider")
                Button("Open") {
                    if let img = model.selectedDyldImage {
                        openSelected(img)
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(model.selectedDyldImage == nil || model.dyldImportBusy)
                .keyboardShortcut(.defaultAction)
                .a11yCatalog("ghidra.vibe.framework_open.open")
            }
            .padding()
        }
        .frame(minWidth: 520, idealWidth: 640, minHeight: 420, idealHeight: 520)
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
        model.showFrameworkOpenSheet = false
        model.importDyldImage(image)
    }
}
