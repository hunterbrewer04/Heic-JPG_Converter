import SwiftUI

struct QueueRowView: View {
    let item: QueueItem
    let onShow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(Theme.Typography.bodyMdMed)
                    .foregroundStyle(Theme.Color.onSurface)
                    .lineLimit(1)
                statusLine
            }
            Spacer(minLength: 4)
            trailingControl
        }
        .padding(.horizontal, Theme.Space.container)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var thumbnail: some View {
        if let data = item.thumbnailData, let img = NSImage(data: data) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        } else {
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(Theme.Color.surfaceContainerHigh.opacity(0.6))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(Theme.Color.onSurfaceVariant)
                )
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch item.status {
        case .waiting:
            Text("Waiting…")
                .font(Theme.Typography.labelMd)
                .foregroundStyle(Theme.Color.onSurfaceVariant)
        case .converting(let progress):
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(Theme.Color.primary)
                .frame(width: 180)
        case .completed:
            Text("Converted to JPG")
                .font(Theme.Typography.labelMd)
                .foregroundStyle(Theme.Color.onSurfaceVariant)
        case .failed:
            Text(item.errorMessage ?? "Failed")
                .font(Theme.Typography.labelMd)
                .foregroundStyle(Theme.Color.error)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var trailingControl: some View {
        switch item.status {
        case .waiting:
            EmptyView()
        case .converting(let progress):
            Text("\(Int(progress * 100))%")
                .font(Theme.Typography.labelMd)
                .foregroundStyle(Theme.Color.onSurfaceVariant)
                .monospacedDigit()
        case .completed:
            Button(action: onShow) {
                Text("Show")
                    .font(Theme.Typography.labelMd.weight(.semibold))
                    .foregroundStyle(Theme.Color.onPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Color.primary))
            }
            .buttonStyle(.plain)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Color.error)
                .help(item.errorMessage ?? "Failed")
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        QueueRowView(item: {
            var i = QueueItem(sourceURL: URL(fileURLWithPath: "/tmp/IMG_0842.heic"))
            i.status = .completed
            return i
        }(), onShow: {})
        QueueRowView(item: {
            var i = QueueItem(sourceURL: URL(fileURLWithPath: "/tmp/Vacation_01.heic"))
            i.status = .converting(progress: 0.49)
            return i
        }(), onShow: {})
        QueueRowView(item: QueueItem(sourceURL: URL(fileURLWithPath: "/tmp/DSC_0001.heic")),
                     onShow: {})
    }
    .frame(width: 340)
    .background(Theme.Color.surfaceContainer)
}
