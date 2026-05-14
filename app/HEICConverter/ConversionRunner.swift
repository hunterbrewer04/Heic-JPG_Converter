import Foundation
import SwiftUI
import AppKit
import ImageIO
import UserNotifications

@MainActor
final class ConversionRunner: ObservableObject {
    @Published private(set) var queue: [QueueItem] = []
    private(set) var panelIsKey: Bool = false

    private var processorTask: Task<Void, Never>?

    func setPanelVisible(_ visible: Bool) {
        panelIsKey = visible
    }

    var hasInflight: Bool {
        queue.contains { !$0.status.isTerminal }
    }

    // MARK: - Public API

    func enqueue(_ urls: [URL]) {
        let expanded = HEICScanner.collectHEICFiles(from: urls)
        let outputDir = OutputDirectoryResolver.resolveFromDefaults()
        let dedupedByTarget = HEICScanner.dedupeByOutput(expanded, outputDir: outputDir)

        var seen = Set(queue.map { $0.sourceURL })
        var newItems: [QueueItem] = []
        for url in dedupedByTarget.map({ $0.standardizedFileURL }) {
            if seen.insert(url).inserted {
                newItems.append(QueueItem(sourceURL: url))
            }
        }
        guard !newItems.isEmpty else { return }
        queue.append(contentsOf: newItems)
        startProcessingIfIdle()
    }

    func clearCompleted() {
        queue.removeAll { $0.status.isTerminal }
    }

    func cancelAll() {
        processorTask?.cancel()
        processorTask = nil
        queue.removeAll()
    }

    func showInFinder(_ item: QueueItem) {
        guard let url = item.destinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Processing loop

    private func startProcessingIfIdle() {
        guard processorTask == nil else { return }
        processorTask = Task.detached(priority: .userInitiated) { [weak self] in
            await self?.processQueue()
            await MainActor.run { [weak self] in self?.processorTask = nil }
        }
    }

    private nonisolated func processQueue() async {
        let outputDir = await MainActor.run { OutputDirectoryResolver.resolveFromDefaults() }
        try? FileManager.default.createDirectory(
            at: outputDir, withIntermediateDirectories: true)

        let converter = makeConverterFromSettings(outputDirectory: outputDir)

        await withTaskGroup(of: Void.self) { group in
            var inflight = 0
            while !Task.isCancelled {
                let limit = effectiveConcurrencyLimit()
                if inflight >= limit {
                    await group.next()
                    inflight -= 1
                    continue
                }
                guard let claim = await self.pickAndClaimNext() else {
                    if inflight == 0 { break }
                    await group.next()
                    inflight -= 1
                    continue
                }
                group.addTask { [weak self] in
                    await self?.runOne(claim: claim, using: converter)
                }
                inflight += 1
            }
        }

        await self.fireCompletionNotificationIfAppropriate()
    }

    private nonisolated func effectiveConcurrencyLimit() -> Int {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        switch ProcessInfo.processInfo.thermalState {
        case .nominal, .fair:   return cores
        case .serious:          return max(2, cores / 2)
        case .critical:         return 1
        @unknown default:       return cores
        }
    }

    private struct ClaimedItem: Sendable {
        let id: UUID
        let sourceURL: URL
    }

    /// Picks the next waiting item and marks it .converting in a single MainActor
    /// transaction. Two workers can't claim the same item because the status flip
    /// happens before another `pickAndClaimNext` can run.
    private func pickAndClaimNext() -> ClaimedItem? {
        guard let idx = queue.firstIndex(where: { $0.status == .waiting }) else { return nil }
        let claim = ClaimedItem(id: queue[idx].id, sourceURL: queue[idx].sourceURL)
        withAnimation(.easeInOut(duration: 0.2)) {
            queue[idx].status = .converting(progress: 0)
        }
        return claim
    }

    nonisolated private func runOne(claim: ClaimedItem, using converter: Converter) async {
        let animation = await self.startProgressAnimation(for: claim.id)
        defer { animation.cancel() }
        let result = converter.convert(claim.sourceURL)
        await self.applyResult(id: claim.id, result: result)
    }

    // MARK: - Queue mutations (main actor)

    private func applyResult(id: UUID, result: ConvertStatus) {
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        switch result {
        case .converted(let url):
            queue[idx].destinationURL = url
            queue[idx].status = .completed
            Task { await self.generateThumbnail(for: id, url: url) }
        case .skipped(let url):
            queue[idx].destinationURL = url
            queue[idx].status = .skipped
        case .error(_, let message):
            queue[idx].status = .failed
            queue[idx].errorMessage = message
        }
    }

    private func startProgressAnimation(for id: UUID) -> Task<Void, Never> {
        Task { [weak self] in
            let start = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                // Asymptotic curve — caps near 0.95 so the bar doesn't hit 100% before completion.
                let p = min(0.95, 1.0 - exp(-elapsed / 0.4))
                self?.updateProgress(id: id, progress: p)
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func updateProgress(id: UUID, progress: Double) {
        if let idx = queue.firstIndex(where: { $0.id == id }),
           case .converting = queue[idx].status {
            queue[idx].status = .converting(progress: progress)
        }
    }

    private func generateThumbnail(for id: UUID, url: URL) async {
        let data: Data? = await Task.detached(priority: .utility) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 160,
                      kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary)
            else { return nil }
            let rep = NSBitmapImageRep(cgImage: img)
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        }.value

        if let idx = queue.firstIndex(where: { $0.id == id }) {
            queue[idx].thumbnailData = data
        }
    }

    private func fireCompletionNotificationIfAppropriate() {
        guard !panelIsKey else { return }
        var converted = 0, skipped = 0, failed = 0
        for item in queue {
            switch item.status {
            case .completed:                    converted += 1
            case .skipped:                      skipped += 1
            case .failed:                       failed += 1
            case .waiting, .converting:         break
            }
        }
        guard converted + skipped + failed > 0 else { return }

        var parts = ["Converted \(converted)"]
        if skipped > 0 { parts.append("skipped \(skipped)") }
        if failed > 0 { parts.append("failed \(failed)") }
        Notifier.notify(title: "Loosey Goosey", body: parts.joined(separator: ", "))
    }
}

#if DEBUG
extension ConversionRunner {
    /// Test seam: allows tests to set item status directly so they can verify
    /// behavior that depends on specific queue states without running real conversions.
    func _testSetStatus(_ status: QueueItem.Status, at index: Int) {
        queue[index].status = status
    }
}
#endif

enum Notifier {
    private static var requested = false
    static func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        let send = {
            let c = UNMutableNotificationContent()
            c.title = title; c.body = body; c.sound = .default
            center.add(UNNotificationRequest(
                identifier: UUID().uuidString, content: c, trigger: nil))
        }
        if requested { send(); return }
        requested = true
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            if ok { send() }
        }
    }
}
