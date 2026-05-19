import Foundation

enum ImageScanner {
    /// Expand a mixed list of file and directory URLs into a flat list of supported
    /// image files. Directories are scanned recursively. Files whose extension is
    /// not in `SupportedFormat.knownImageExtensions` are dropped.
    static func collectImageFiles(from inputs: [URL]) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default

        for url in inputs {
            if isDirectory(url) {
                guard let it = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles])
                else { continue }
                for case let f as URL in it where isImage(f) {
                    out.append(f)
                }
            } else if isImage(url) {
                out.append(url)
            }
        }
        return out
    }

    /// Drop entries that would write to the same output path. APFS is case-insensitive
    /// by default, so the key is the lowercased target path. Runs even when the
    /// output directory is implicit (alongside source), to catch sibling collisions
    /// like `IMG_1.HEIC` + `img_1.heic` in the same folder when both target the
    /// same output extension.
    static func dedupeByOutput(_ files: [URL], outputDir: URL?, outputExtension: String) -> [URL] {
        var seen: Set<String> = []
        var out: [URL] = []
        for f in files {
            let dir = outputDir ?? f.deletingLastPathComponent()
            let target = dir
                .appendingPathComponent(f.deletingPathExtension().lastPathComponent)
                .appendingPathExtension(outputExtension)
            if seen.insert(target.path.lowercased()).inserted {
                out.append(f)
            }
        }
        return out
    }

    private static func isImage(_ url: URL) -> Bool {
        SupportedFormat.knownImageExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
