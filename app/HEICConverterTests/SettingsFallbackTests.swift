import XCTest
@testable import HEICConverter

final class SettingsFallbackTests: XCTestCase {

    func testEmptyConfigFallsBackToDownloads() throws {
        let resolved = OutputDirectoryResolver.resolve(configured: "")
        let downloads = try XCTUnwrap(FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first?.path)
        XCTAssertEqual(resolved.path, downloads)
    }

    func testNonexistentPathFallsBackToDownloads() throws {
        let resolved = OutputDirectoryResolver.resolve(
            configured: "/no/such/directory/exists/anywhere/\(UUID().uuidString)")
        let downloads = try XCTUnwrap(FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first?.path)
        XCTAssertEqual(resolved.path, downloads)
    }

    func testValidPathPassesThrough() {
        let tmp = NSTemporaryDirectory()
        let resolved = OutputDirectoryResolver.resolve(configured: tmp)
        XCTAssertEqual(resolved.path, URL(fileURLWithPath: tmp).path)
    }

    func testFilePathIsRejected() throws {
        // Create a regular file (not a directory) and verify resolve rejects it,
        // falling back to ~/Downloads instead of returning the file path.
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let filePath = tmpDir.appendingPathComponent("resolver-test-\(UUID().uuidString).txt")
        try Data().write(to: filePath)
        defer { try? FileManager.default.removeItem(at: filePath) }

        let resolved = OutputDirectoryResolver.resolve(configured: filePath.path)
        let downloads = try XCTUnwrap(FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first?.path)
        XCTAssertEqual(resolved.path, downloads, "resolve() must reject non-directory paths")
    }

    func testResolveDoesNotMutateUserDefaults() {
        let defaults = UserDefaults.standard
        let before = defaults.string(forKey: SettingsKey.outputDir)
        defer { defaults.set(before, forKey: SettingsKey.outputDir) }

        defaults.set("/nonexistent/\(UUID().uuidString)", forKey: SettingsKey.outputDir)
        let snapshot = defaults.string(forKey: SettingsKey.outputDir)
        _ = OutputDirectoryResolver.resolve(configured: snapshot ?? "")

        XCTAssertEqual(defaults.string(forKey: SettingsKey.outputDir), snapshot,
                       "resolve() must be pure — no UserDefaults side effects")
    }
}
