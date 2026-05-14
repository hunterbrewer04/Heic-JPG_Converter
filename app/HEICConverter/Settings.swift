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

/// Build a Converter from the values currently stored in UserDefaults.
/// (Preserved from original Settings.swift.)
func makeConverterFromSettings() -> Converter {
    let d = UserDefaults.standard
    let q = d.object(forKey: SettingsKey.quality) as? Int ?? Defaults.quality
    let outDir: URL? = {
        let s = d.string(forKey: SettingsKey.outputDir) ?? ""
        guard !s.isEmpty else { return nil }
        return URL(fileURLWithPath: s)
    }()
    return Converter(
        quality: Double(q) / 100.0,
        archiveOriginals: d.bool(forKey: SettingsKey.archive),
        force: d.bool(forKey: SettingsKey.force),
        outputDirectory: outDir)
}

enum OutputDirectoryResolver {
    /// Returns the directory we should write to, following the fallback chain.
    /// Configured path → ~/Downloads → temporary directory.
    /// Updates UserDefaults if the configured path is invalid.
    static func resolve(configured: String) -> URL {
        let fm = FileManager.default
        if !configured.isEmpty {
            let url = URL(fileURLWithPath: configured)
            if fm.fileExists(atPath: url.path), fm.isWritableFile(atPath: url.path) {
                return url
            }
        }

        if let dl = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first,
           fm.isWritableFile(atPath: dl.path) {
            UserDefaults.standard.set(dl.path, forKey: SettingsKey.outputDir)
            return dl
        }

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        UserDefaults.standard.set(tmp.path, forKey: SettingsKey.outputDir)
        return tmp
    }
}
