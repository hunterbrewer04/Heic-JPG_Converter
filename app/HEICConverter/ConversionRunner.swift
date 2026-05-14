import Foundation
import SwiftUI
import AppKit
import ImageIO
import UserNotifications

@MainActor
final class ConversionRunner: ObservableObject {
    @Published private(set) var queue: [QueueItem] = []
    private var panelIsKey: Bool = false

    private var processorTask: Task<Void, Never>?

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.panelIsKey = true }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.panelIsKey = false }
    }

    var hasInflight: Bool {
        queue.contains { item in
            switch item.status {
            case .waiting, .converting: return true
            case .completed, .failed:   return false
            }
        }
    }

    // MARK: - Public API

    func enqueue(_ urls: [URL]) {
        let expanded = HEICScanner.collectHEICFiles(from: urls)
        var seen = Set(queue.map { $0.sourceURL })
        var newItems: [QueueItem] = []
        for url in expanded.map({ $0.standardizedFileURL }) {
            if seen.insert(url).inserted {
                newItems.append(QueueItem(sourceURL: url))
            }
        }

        guard !newItems.isEmpty else { return }
        queue.append(contentsOf: newItems)
        startProcessingIfIdle()
    }

    func clearCompleted() {
        queue.removeAll { $0.status == .completed || $0.status == .failed }
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
        let outputDir = await MainActor.run {
            OutputDirectoryResolver.resolve(
                configured: UserDefaults.standard.string(forKey: SettingsKey.outputDir) ?? "")
        }
        try? FileManager.default.createDirectory(
            at: outputDir, withIntermediateDirectories: true)

        let converter = makeConverterForBatch(forcedOutputDir: outputDir)

        // Parallel, thermal-aware: spawn up to `effectiveLimit()` tasks at a time.
        await withTaskGroup(of: Void.self) { group in
            var inflight = 0

            while !Task.isCancelled {
                let limit = effectiveConcurrencyLimit()

                if inflight >= limit {
                    await group.next()
                    inflight -= 1
                    continue
                }

                guard let id = await self.pickNextWaitingID() else {
                    if inflight == 0 { break }
                    await group.next()
                    inflight -= 1
                    continue
                }

                group.addTask { [weak self] in
                    await self?.runOne(id: id, using: converter)
                }
                inflight += 1
            }
        }

        await fireCompletionNotificationIfAppropriate()
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

    private func runOne(id: UUID, using converter: Converter) async {
        await markConverting(id: id)
        let animation = startProgressAnimation(for: id)
        defer { animation.cancel() }

        guard let source = await currentItem(id: id)?.sourceURL else { return }
        let result = converter.convert(source)
        await applyResult(id: id, result: result)
    }

    // MARK: - Queue mutations (main actor)

    private func pickNextWaitingID() async -> UUID? {
        await MainActor.run {
            queue.first(where: { $0.status == .waiting })?.id
        }
    }

    private func currentItem(id: UUID) async -> QueueItem? {
        await MainActor.run { queue.first { $0.id == id } }
    }

    private func markConverting(id: UUID) async {
        await MainActor.run {
            if let idx = queue.firstIndex(where: { $0.id == id }) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    queue[idx].status = .converting(progress: 0)
                }
            }
        }
    }

    private func applyResult(id: UUID, result: ConvertStatus) async {
        await MainActor.run {
            guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
            switch result {
            case .converted(let url):
                queue[idx].destinationURL = url
                queue[idx].status = .completed
                Task { await self.generateThumbnail(for: id, url: url) }
            case .skipped(let url):
                queue[idx].destinationURL = url
                queue[idx].status = .completed
            case .error(_, let message):
                queue[idx].status = .failed
                queue[idx].errorMessage = message
            }
        }
    }

    private func startProgressAnimation(for id: UUID) -> Task<Void, Never> {
        Task { [weak self] in
            let start = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                // Asymptotic curve — caps near 0.95
                let p = min(0.95, 1.0 - exp(-elapsed / 0.4))
                await self?.updateProgress(id: id, progress: p)
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
        }
    }

    private func updateProgress(id: UUID, progress: Double) async {
        await MainActor.run {
            if let idx = queue.firstIndex(where: { $0.id == id }),
               case .converting = queue[idx].status {
                queue[idx].status = .converting(progress: progress)
            }
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

        await MainActor.run {
            if let idx = queue.firstIndex(where: { $0.id == id }) {
                queue[idx].thumbnailData = data
            }
        }
    }

    private func fireCompletionNotificationIfAppropriate() async {
        let (completed, failed, isKey) = await MainActor.run {
            (queue.filter { $0.status == .completed }.count,
             queue.filter { $0.status == .failed }.count,
             panelIsKey)
        }
        guard !isKey else { return }
        guard completed + failed > 0 else { return }
        var parts = ["Converted \(completed)"]
        if failed > 0 { parts.append("failed \(failed)") }
        Notifier.notify(title: "Loosey Goosey", body: parts.joined(separator: ", "))
    }
}

// MARK: - Settings glue

/// Build a Converter using current UserDefaults but overriding the output directory.
/// Matches the existing Converter memberwise init in Converter.swift (quality is Double 0–1).
func makeConverterForBatch(forcedOutputDir: URL) -> Converter {
    let d = UserDefaults.standard
    let q = d.object(forKey: SettingsKey.quality) as? Int ?? Defaults.quality
    return Converter(
        quality: Double(q) / 100.0,
        archiveOriginals: d.bool(forKey: SettingsKey.archive),
        force: d.bool(forKey: SettingsKey.force),
        outputDirectory: forcedOutputDir)
}

// MARK: - Notifier (preserved from existing code)

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
