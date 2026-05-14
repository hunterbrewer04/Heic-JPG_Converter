import SwiftUI

struct QueueSection: View {
    @EnvironmentObject var runner: ConversionRunner

    var body: some View {
        if !runner.queue.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("CONVERSION QUEUE")
                    .font(Theme.Typography.labelSm)
                    .foregroundStyle(Theme.Color.onSurfaceVariant)
                    .textCase(.uppercase)
                    .padding(.horizontal, Theme.Space.container)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(runner.queue) { item in
                            QueueRowView(item: item) {
                                runner.showInFinder(item)
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                            if item.id != runner.queue.last?.id {
                                Rectangle()
                                    .fill(Theme.Color.outlineVariant.opacity(0.4))
                                    .frame(height: 1)
                                    .padding(.horizontal, Theme.Space.container)
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)
                .animation(.spring(response: 0.4, dampingFraction: 0.85),
                           value: runner.queue.map(\.id))
            }
        }
    }
}

#Preview {
    let runner = ConversionRunner()
    runner.enqueue([
        URL(fileURLWithPath: "/tmp/IMG_0842.heic"),
        URL(fileURLWithPath: "/tmp/Vacation_01.heic"),
    ])
    return QueueSection()
        .environmentObject(runner)
        .frame(width: 340)
        .background(Theme.Color.surfaceContainer)
}
