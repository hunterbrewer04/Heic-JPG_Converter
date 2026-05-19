import SwiftUI

struct FormatPickerRow: View {
    @AppStorage(SettingsKey.outputFormat) private var outputFormatRaw: String = Defaults.outputFormat

    private var outputFormat: Binding<SupportedFormat> {
        Binding(
            get: { SupportedFormat.from(rawValue: outputFormatRaw) },
            set: { outputFormatRaw = $0.rawValue }
        )
    }

    var body: some View {
        HStack(spacing: Theme.Space.elementGap) {
            Text("Convert to")
                .font(Theme.Typography.labelMd)
                .foregroundStyle(Theme.Color.onSurfaceVariant)
            Picker("", selection: outputFormat) {
                ForEach(SupportedFormat.allCases) { fmt in
                    Text(fmt.displayName).tag(fmt)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, Theme.Space.container)
        .padding(.top, Theme.Space.gutter)
    }
}

#Preview {
    FormatPickerRow()
        .frame(width: 340)
        .background(Theme.Color.surfaceContainer)
}
