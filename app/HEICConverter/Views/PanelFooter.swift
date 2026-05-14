import SwiftUI
import AppKit

struct PanelFooter: View {
    @EnvironmentObject var runner: ConversionRunner
    @AppStorage(SettingsKey.outputDir) private var outputDir: String = Defaults.outputDirPath

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var canClear: Bool {
        runner.queue.contains { $0.status.isTerminal }
    }

    var body: some View {
        HStack {
            Text("v\(version)")
                .font(Theme.Typography.labelSm)
                .foregroundStyle(Theme.Color.onSurfaceVariant)
            Spacer()
            Button("Open Folder") {
                let url = OutputDirectoryResolver.resolve(configured: outputDir)
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(FooterLinkStyle(enabled: true))

            Text("·").foregroundStyle(Theme.Color.onSurfaceVariant)

            Button("Clear") {
                withAnimation { runner.clearCompleted() }
            }
            .buttonStyle(FooterLinkStyle(enabled: canClear))
            .disabled(!canClear)
            .keyboardShortcut("k")
        }
        .padding(.horizontal, Theme.Space.container)
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.Color.outlineVariant.opacity(0.5))
                .frame(height: 1)
        }
    }
}

private struct FooterLinkStyle: ButtonStyle {
    let enabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.labelMd)
            .foregroundStyle(enabled
                ? Theme.Color.primary
                : Theme.Color.onSurfaceVariant.opacity(0.4))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

#Preview {
    PanelFooter()
        .environmentObject(ConversionRunner())
        .frame(width: 340)
        .background(Theme.Color.surfaceContainer)
}
