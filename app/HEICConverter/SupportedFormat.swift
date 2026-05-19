import Foundation
import UniformTypeIdentifiers

enum SupportedFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg
    case png
    case gif

    var id: String { rawValue }

    var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png:  return .png
        case .gif:  return .gif
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png:  return "png"
        case .gif:  return "gif"
        }
    }

    var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png:  return "PNG"
        case .gif:  return "GIF"
        }
    }

    var supportsQuality: Bool {
        self == .jpeg
    }

    static let `default`: SupportedFormat = .jpeg

    /// Defaults to `.jpeg` when `raw` is nil or doesn't match a known case, so a
    /// stale UserDefaults value can never crash the app.
    static func from(rawValue raw: String?) -> SupportedFormat {
        guard let raw, let v = SupportedFormat(rawValue: raw) else { return .default }
        return v
    }

    /// Extensions the scanner accepts as input. Output formats are a subset.
    static let knownImageExtensions: Set<String> = [
        "heic", "heif", "jpg", "jpeg", "png", "gif",
        "tif", "tiff", "bmp", "webp"
    ]
}
