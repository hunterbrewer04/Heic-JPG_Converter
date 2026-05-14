import Foundation
import SwiftUI

enum SettingsKey {
    static let quality   = "quality"
    static let archive   = "archiveOriginals"
    static let force     = "forceOverwrite"
    static let outputDir = "outputDirectory"
}

struct Defaults {
    static let quality = 95
    static let archive = false
    static let force   = false

    /// Default output directory is the user's Downloads folder path,
    /// or empty (meaning "alongside source") if it can't be located.
    static var outputDirPath: String {
        FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask)
            .first?.path ?? ""
    }
}

/// Build a Converter using current UserDefaults, overriding the output directory.
func makeConverterFromSettings(outputDirectory: URL) -> Converter {
    let d = UserDefaults.standard
    let q = d.object(forKey: SettingsKey.quality) as? Int ?? Defaults.quality
    return Converter(
        quality: Double(q) / 100.0,
        archiveOriginals: d.bool(forKey: SettingsKey.archive),
        force: d.bool(forKey: SettingsKey.force),
        outputDirectory: outputDirectory)
}

enum OutputDirectoryResolver {
    static func resolveFromDefaults() -> URL {
        resolve(configured: UserDefaults.standard.string(forKey: SettingsKey.outputDir) ?? "")
    }

    /// Returns the directory we should write to, following the fallback chain:
    /// configured path → ~/Downloads → temporary directory. Pure — no side effects,
    /// safe to call from SwiftUI view bodies and concurrent contexts.
    static func resolve(configured: String) -> URL {
        let fm = FileManager.default
        if !configured.isEmpty {
            let url = URL(fileURLWithPath: configured)
            if isWritableDirectory(url, fm: fm) {
                return url
            }
        }

        if let dl = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first,
           isWritableDirectory(dl, fm: fm) {
            return dl
        }

        return URL(fileURLWithPath: NSTemporaryDirectory())
    }

    private static func isWritableDirectory(_ url: URL, fm: FileManager) -> Bool {
        guard fm.isWritableFile(atPath: url.path) else { return false }
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return isDir
    }
}
