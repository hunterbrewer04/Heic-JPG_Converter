import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var runner: ConversionRunner

    @AppStorage(SettingsKey.quality) private var quality: Int = Defaults.quality
    @AppStorage(SettingsKey.archive) private var archive: Bool = Defaults.archive
    @AppStorage(SettingsKey.force)   private var force: Bool = Defaults.force
    @AppStorage(SettingsKey.outputDir) private var outputDir: String = ""

    var body: some View {
        Button(runner.state.isRunning
               ? "Working: \(runner.state.label ?? "")"
               : "Convert files or folder…") {
            chooseAndConvert()
        }
        .disabled(runner.state.isRunning)
        .keyboardShortcut("o")

        if case .finished(let summary) = runner.state {
            Text(summary).disabled(true)
        }

        Divider()

        Menu("Settings") {
            Menu("Quality: \(quality)") {
                ForEach([60, 75, 85, 90, 95, 100], id: \.self) { q in
                    Button("\(q)") { quality = q }
                }
            }
            Toggle("Archive originals to heic_originals/", isOn: $archive)
            Toggle("Overwrite existing JPEGs", isOn: $force)

            Divider()

            Button(outputDir.isEmpty
                   ? "Output: alongside source"
                   : "Output: \(URL(fileURLWithPath: outputDir).lastPathComponent)") {
                if let url = Picker.chooseOutputDirectory() {
                    outputDir = url.path
                }
            }
            if !outputDir.isEmpty {
                Button("Clear custom output folder") { outputDir = "" }
            }
        }

        Divider()

        Button("Quit HEIC Converter") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func chooseAndConvert() {
        guard let urls = Picker.chooseFilesOrFolders(), !urls.isEmpty else { return }
        runner.run(inputs: urls)
    }
}
