import Foundation

struct QueueItem: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    var destinationURL: URL?
    var status: Status
    var thumbnailData: Data?
    var errorMessage: String?

    init(sourceURL: URL) {
        self.id = UUID()
        self.sourceURL = sourceURL.standardizedFileURL
        self.destinationURL = nil
        self.status = .waiting
        self.thumbnailData = nil
        self.errorMessage = nil
    }

    var filename: String { sourceURL.lastPathComponent }

    enum Status: Equatable {
        case waiting
        case converting(progress: Double)
        case completed
        case skipped
        case failed

        var isTerminal: Bool {
            switch self {
            case .completed, .skipped, .failed: return true
            case .waiting, .converting:         return false
            }
        }
    }
}
