import Foundation
import SwiftUI

enum SettingsKey {
    static let quality = "quality"           // Int, 1-100
    static let archive = "archiveOriginals"  // Bool
    static let force = "forceOverwrite"      // Bool
    static let outputDir = "outputDirectory" // String (file URL), "" for alongside source
}

struct Defaults {
    static let quality = 95
    static let archive = false
    static let force = false
}

/// Build a Converter from the values currently stored in UserDefaults.
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
