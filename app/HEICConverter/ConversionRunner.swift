import Foundation
import SwiftUI
import UserNotifications

enum RunState: Equatable {
    case idle
    case running(done: Int, total: Int)
    case finished(summary: String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var label: String? {
        switch self {
        case .idle: return nil
        case .running(let done, let total): return "Converting \(done)/\(total)…"
        case .finished(let summary): return summary
        }
    }
}

@MainActor
final class ConversionRunner: ObservableObject {
    @Published private(set) var state: RunState = .idle

    func run(inputs: [URL]) {
        guard !state.isRunning else { return }
        let converter = makeConverterFromSettings()

        Task.detached(priority: .userInitiated) { [weak self] in
            var files = HEICScanner.collectHEICFiles(from: inputs)
            files = HEICScanner.dedupeByOutput(files, outputDir: converter.outputDirectory)
            guard !files.isEmpty else {
                await self?.finish(converted: 0, skipped: 0, failed: 0, empty: true)
                return
            }

            // Pre-create all unique target dirs once, not per file.
            let dirs = Set(files.map {
                (converter.outputDirectory ?? $0.deletingLastPathComponent())
            })
            for dir in dirs {
                try? FileManager.default.createDirectory(
                    at: dir, withIntermediateDirectories: true)
            }

            await self?.setRunning(done: 0, total: files.count)

            // Bounded concurrency: keep at most `maxConcurrent` decodes in flight at
            // once. CGImageSource/CGImageDestination hold the decoded frame in
            // memory, so an unbounded TaskGroup can balloon memory on large batches.
            let maxConcurrent = ProcessInfo.processInfo.activeProcessorCount
            var converted = 0, skipped = 0, failed = 0, done = 0
            let total = files.count

            await withTaskGroup(of: ConvertStatus.self) { group in
                var iterator = files.makeIterator()
                for _ in 0..<min(maxConcurrent, total) {
                    guard let next = iterator.next() else { break }
                    group.addTask { converter.convert(next) }
                }
                while let result = await group.next() {
                    switch result {
                    case .converted: converted += 1
                    case .skipped:   skipped += 1
                    case .error:     failed += 1
                    }
                    done += 1
                    await self?.setRunning(done: done, total: total)
                    if let next = iterator.next() {
                        group.addTask { converter.convert(next) }
                    }
                }
            }

            await self?.finish(
                converted: converted, skipped: skipped, failed: failed, empty: false)
        }
    }

    private func setRunning(done: Int, total: Int) {
        state = .running(done: done, total: total)
    }

    private func finish(converted: Int, skipped: Int, failed: Int, empty: Bool) {
        let body: String
        if empty {
            body = "No HEIC files found."
        } else {
            var parts = ["Converted \(converted)"]
            if skipped > 0 { parts.append("skipped \(skipped)") }
            if failed > 0  { parts.append("failed \(failed)") }
            body = parts.joined(separator: ", ")
        }
        state = .finished(summary: body)
        Notifier.notify(title: "HEIC Converter", body: body)
    }
}

enum Notifier {
    /// Request authorization on demand the first time we want to fire a
    /// notification. Doing it from `App.init` would prompt before the user has
    /// even clicked the menu bar icon; this defers it until first conversion.
    private static var requested = false

    static func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        let send = {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let req = UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(req, withCompletionHandler: nil)
        }
        if requested {
            send()
            return
        }
        requested = true
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted { send() }
        }
    }
}
