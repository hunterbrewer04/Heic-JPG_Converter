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
    case noImagesInSource
    case cannotCreateDestination
    case writeFailed

    var description: String {
        switch self {
        case .cannotOpen: return "cannot open source image"
        case .noImagesInSource: return "source contains no images"
        case .cannotCreateDestination: return "cannot create image destination"
        case .writeFailed: return "image write failed"
        }
    }
}

struct Converter: Sendable {
    var quality: Double          // 0.0 - 1.0
    var archiveOriginals: Bool
    var force: Bool
    var outputDirectory: URL?    // nil = alongside source
    var format: SupportedFormat

    func convert(_ source: URL) -> ConvertStatus {
        let targetDir = outputDirectory ?? source.deletingLastPathComponent()
        let targetURL = targetDir
            .appendingPathComponent(source.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(format.fileExtension)

        if FileManager.default.fileExists(atPath: targetURL.path) && !force {
            return .skipped(targetURL)
        }

        if Task.isCancelled {
            return .skipped(targetURL)
        }

        do {
            guard let src = CGImageSourceCreateWithURL(source as CFURL, nil) else {
                throw ConvertError.cannotOpen
            }
            guard CGImageSourceGetCount(src) > 0 else {
                throw ConvertError.noImagesInSource
            }
            // Same-format short-circuit: re-encoding JPG→JPG silently loses quality,
            // PNG→PNG is pointless. `--force` / "Overwrite" still re-encodes.
            if !force,
               let srcType = CGImageSourceGetType(src) as String?,
               srcType == format.utType.identifier {
                return .skipped(targetURL)
            }
            guard let dst = CGImageDestinationCreateWithURL(
                targetURL as CFURL, format.utType.identifier as CFString, 1, nil)
            else {
                throw ConvertError.cannotCreateDestination
            }

            var opts: [CFString: Any] = [:]
            if format.supportsQuality {
                opts[kCGImageDestinationLossyCompressionQuality] = quality
            }
            // Copies image + all metadata (EXIF, GPS, orientation, ICC) from source.
            CGImageDestinationAddImageFromSource(dst, src, 0, opts as CFDictionary)

            if Task.isCancelled {
                return .skipped(targetURL)
            }

            guard CGImageDestinationFinalize(dst) else {
                throw ConvertError.writeFailed
            }
        } catch let e as ConvertError {
            return .error(source, e.description)
        } catch {
            return .error(source, error.localizedDescription)
        }

        if archiveOriginals {
            do {
                try archiveOriginal(source)
            } catch {
                return .error(
                    source,
                    "\(format.displayName) saved but archive failed: \(error.localizedDescription)")
            }
        }

        return .converted(targetURL)
    }

    /// Move `source` into a sibling `image_originals/`, adding a numbered suffix
    /// (`name (2).HEIC`, `name (3).HEIC`, …) if a file with the same name was
    /// already archived from a different folder in this batch.
    private func archiveOriginal(_ source: URL) throws {
        let fm = FileManager.default
        let archiveDir = source.deletingLastPathComponent()
            .appendingPathComponent("image_originals")
        try fm.createDirectory(at: archiveDir, withIntermediateDirectories: true)

        let stem = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var candidate = archiveDir.appendingPathComponent(source.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = archiveDir
                .appendingPathComponent("\(stem) (\(n))")
                .appendingPathExtension(ext)
            n += 1
        }
        try fm.moveItem(at: source, to: candidate)
    }
}
