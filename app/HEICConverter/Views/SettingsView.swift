import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage(SettingsKey.outputDir)    private var outputDir: String = Defaults.outputDirPath
    @AppStorage(SettingsKey.quality)      private var quality: Int = Defaults.quality
    @AppStorage(SettingsKey.archive)      private var archive: Bool = Defaults.archive
    @AppStorage(SettingsKey.force)        private var force: Bool = Defaults.force
    @AppStorage(SettingsKey.outputFormat) private var outputFormatRaw: String = Defaults.outputFormat

    private var outputFormat: SupportedFormat {
        SupportedFormat.from(rawValue: outputFormatRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.gutter) {
            Text("Settings")
                .font(Theme.Typography.headlineMd)

            VStack(alignment: .leading, spacing: 6) {
                Text("Output Folder").font(Theme.Typography.labelMd)
                HStack {
                    Text(OutputDirectoryResolver.resolve(configured: outputDir).lastPathComponent)
                        .font(Theme.Typography.bodyMd)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Change") {
                        if let url = Picker.chooseOutputDirectory() {
                            outputDir = url.path
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if outputFormat.supportsQuality {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Quality").font(Theme.Typography.labelMd)
                        Spacer()
                        Text("\(quality)")
                            .font(Theme.Typography.bodyMd.monospacedDigit())
                    }
                    Slider(value: Binding(
                        get: { Double(quality) },
                        set: { quality = Int($0) }
                    ), in: 60...100, step: 5)
                }
            }

            Toggle("Archive originals to image_originals/", isOn: $archive)
                .font(Theme.Typography.bodyMd)
            Toggle("Overwrite existing files", isOn: $force)
                .font(Theme.Typography.bodyMd)
        }
        .padding(Theme.Space.container)
    }
}

#Preview {
    SettingsView().frame(width: 280)
}
