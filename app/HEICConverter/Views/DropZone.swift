import SwiftUI
import UniformTypeIdentifiers

struct DropZone: View {
    @EnvironmentObject var runner: ConversionRunner
    @State private var isDragHovered = false
    @State private var shake = false

    var body: some View {
        Button(action: openPicker) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.Color.primary)
                        .frame(width: 44, height: 44)
                    Image(systemName: "doc.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.Color.onPrimary)
                }
                Text("Drag & Drop HEIC files")
                    .font(Theme.Typography.bodyLg)
                    .foregroundStyle(Theme.Color.onSurface)
                Text("or click to browse")
                    .font(Theme.Typography.bodyMd)
                    .foregroundStyle(Theme.Color.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(isDragHovered
                          ? Theme.Color.primary.opacity(0.08)
                          : Theme.Color.surfaceContainerLow.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(
                        isDragHovered ? Theme.Color.primary : Theme.Color.outlineVariant,
                        style: StrokeStyle(
                            lineWidth: 1.5,
                            dash: isDragHovered ? [] : [6, 4])
                    )
            )
            .modifier(ShakeEffect(animatable: shake ? 1 : 0))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("o", modifiers: .command)
        .padding(.horizontal, Theme.Space.container)
        .padding(.vertical, Theme.Space.gutter)
        .onDrop(of: [.fileURL], isTargeted: $isDragHovered) { providers in
            handleDrop(providers: providers)
            return true
        }
        .accessibilityLabel("Drop HEIC files or click to browse")
    }

    private func openPicker() {
        if let urls = Picker.chooseFilesOrFolders(), !urls.isEmpty {
            runner.enqueue(urls)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let heicCount = HEICScanner.collectHEICFiles(from: urls).count
            if heicCount == 0 {
                triggerShake()
            } else {
                runner.enqueue(urls)
            }
        }
    }

    private func triggerShake() {
        withAnimation(.linear(duration: 0.05).repeatCount(4, autoreverses: true)) {
            shake.toggle()
        }
    }
}

private struct ShakeEffect: GeometryEffect {
    var animatable: CGFloat
    var animatableData: CGFloat {
        get { animatable }
        set { animatable = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(animatable * .pi * 2), y: 0))
    }
}

#Preview {
    DropZone()
        .environmentObject(ConversionRunner())
        .frame(width: 340)
        .background(Theme.Color.surfaceContainer)
}
