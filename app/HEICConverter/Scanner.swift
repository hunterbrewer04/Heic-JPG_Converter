import Foundation

enum Scanner {
    /// Expand a mixed list of file and directory URLs into a flat list of HEIC files.
    /// Directories are scanned recursively. Non-HEIC files are dropped.
    static func collectHEICFiles(from inputs: [URL]) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default

        for url in inputs {
            if let it = fm.enumerator(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles])
            {
                for case let f as URL in it where isHEIC(f) {
                    out.append(f)
                }
            } else if isHEIC(url) {
                out.append(url)
            }
        }
        return out
    }

    /// Drop entries that would write to the same JPEG path when an explicit output
    /// directory is set.
    static func dedupeByOutput(_ files: [URL], outputDir: URL) -> [URL] {
        var seen: Set<URL> = []
        var out: [URL] = []
        for f in files {
            let target = outputDir
                .appendingPathComponent(f.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("jpg")
            if seen.insert(target).inserted {
                out.append(f)
            }
        }
        return out
    }

    private static func isHEIC(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "heic"
    }
}
