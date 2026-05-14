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
            var files = Scanner.collectHEICFiles(from: inputs)
            if let outputDir = converter.outputDirectory {
                files = Scanner.dedupeByOutput(files, outputDir: outputDir)
            }
            guard !files.isEmpty else {
                await self?.finish(converted: 0, skipped: 0, errored: 0, empty: true)
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

            var converted = 0, skipped = 0, errored = 0, done = 0
            await withTaskGroup(of: ConvertStatus.self) { group in
                for f in files {
                    group.addTask { converter.convert(f) }
                }
                for await result in group {
                    switch result {
                    case .converted: converted += 1
                    case .skipped:   skipped += 1
                    case .error:     errored += 1
                    }
                    done += 1
                    await self?.setRunning(done: done, total: files.count)
                }
            }

            await self?.finish(
                converted: converted, skipped: skipped, errored: errored, empty: false)
        }
    }

    private func setRunning(done: Int, total: Int) {
        state = .running(done: done, total: total)
    }

    private func finish(converted: Int, skipped: Int, errored: Int, empty: Bool) {
        let body = empty
            ? "No HEIC files found."
            : "Converted \(converted), skipped \(skipped), errored \(errored)"
        state = .finished(summary: body)
        Notifier.send(title: "HEIC Converter", body: body)
    }
}

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]) { _, _ in }
    }

    static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
