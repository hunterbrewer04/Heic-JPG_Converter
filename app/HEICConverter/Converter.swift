import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ConvertStatus {
    case converted(URL)
    case skipped(URL)
    case error(URL, String)
}

enum ConvertError: Error, CustomStringConvertible {
    case cannotOpen
    case cannotCreateDestination
    case writeFailed

    var description: String {
        switch self {
        case .cannotOpen: return "cannot open source image"
        case .cannotCreateDestination: return "cannot create JPEG destination"
        case .writeFailed: return "JPEG write failed"
        }
    }
}

struct Converter: Sendable {
    var quality: Double          // 0.0 - 1.0
    var archiveOriginals: Bool
    var force: Bool
    var outputDirectory: URL?    // nil = alongside source

    func convert(_ source: URL) -> ConvertStatus {
        let targetDir = outputDirectory ?? source.deletingLastPathComponent()
        let targetURL = targetDir
            .appendingPathComponent(source.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("jpg")

        if FileManager.default.fileExists(atPath: targetURL.path) && !force {
            return .skipped(targetURL)
        }

        do {
            guard let src = CGImageSourceCreateWithURL(source as CFURL, nil) else {
                throw ConvertError.cannotOpen
            }
            guard let dst = CGImageDestinationCreateWithURL(
                targetURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
            else {
                throw ConvertError.cannotCreateDestination
            }

            let opts: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: quality
            ]
            // Copies image + all metadata (EXIF, GPS, orientation, ICC) from source.
            CGImageDestinationAddImageFromSource(dst, src, 0, opts as CFDictionary)

            guard CGImageDestinationFinalize(dst) else {
                throw ConvertError.writeFailed
            }
        } catch let e as ConvertError {
            return .error(source, e.description)
        } catch {
            return .error(source, error.localizedDescription)
        }

        if archiveOriginals {
            let archiveDir = source.deletingLastPathComponent()
                .appendingPathComponent("heic_originals")
            do {
                try FileManager.default.createDirectory(
                    at: archiveDir, withIntermediateDirectories: true)
                try FileManager.default.moveItem(
                    at: source,
                    to: archiveDir.appendingPathComponent(source.lastPathComponent))
            } catch {
                return .error(
                    source,
                    "JPEG saved but archive failed: \(error.localizedDescription)")
            }
        }

        return .converted(targetURL)
    }
}
