import SwiftUI

struct PanelHeader: View {
    @Binding var showingSettings: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("Loosey Goosey")
                .font(Theme.Typography.headlineMd)
                .foregroundStyle(Theme.Color.onSurface)
            Spacer()
            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Color.onSurfaceVariant)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(Theme.Color.surfaceContainerHigh.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.horizontal, Theme.Space.container)
        .padding(.top, 20)
        .padding(.bottom, Theme.Space.gutter)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Color.outlineVariant.opacity(0.5))
                .frame(height: 1)
        }
    }
}

#Preview {
    PanelHeader(showingSettings: .constant(false))
        .frame(width: 340)
        .background(Theme.Color.surfaceContainer)
}
