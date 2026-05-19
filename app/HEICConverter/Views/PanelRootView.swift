import SwiftUI
import AppKit

struct PanelRootView: View {
    @EnvironmentObject var runner: ConversionRunner
    @State private var showingSettings = false
    @Environment(\.colorScheme) private var colorScheme

    private var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(showingSettings: $showingSettings)
                .popover(isPresented: $showingSettings, arrowEdge: .top) {
                    SettingsView()
                        .frame(width: 280)
                }
            FormatPickerRow()
            DropZone()
            QueueSection()
            PanelFooter()
        }
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing),
                    lineWidth: 1)
        )
    }

    @ViewBuilder private var panelBackground: some View {
        if reduceTransparency {
            Theme.Color.surfaceContainer
        } else {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        }
    }
}

#Preview {
    PanelRootView()
        .environmentObject(ConversionRunner())
        .frame(width: 340)
}
