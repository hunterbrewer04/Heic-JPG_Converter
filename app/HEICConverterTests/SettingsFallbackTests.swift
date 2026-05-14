import XCTest
@testable import HEICConverter

final class SettingsFallbackTests: XCTestCase {

    func testEmptyConfigFallsBackToDownloads() {
        let resolved = OutputDirectoryResolver.resolve(configured: "")
        let downloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
        XCTAssertEqual(resolved.path, downloads)
    }

    func testNonexistentPathFallsBackToDownloads() {
        let resolved = OutputDirectoryResolver.resolve(
            configured: "/no/such/directory/exists/anywhere/\(UUID().uuidString)")
        let downloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
        XCTAssertEqual(resolved.path, downloads)
    }

    func testValidPathPassesThrough() {
        let tmp = NSTemporaryDirectory()
        let resolved = OutputDirectoryResolver.resolve(configured: tmp)
        XCTAssertEqual(resolved.path, URL(fileURLWithPath: tmp).path)
    }
}
