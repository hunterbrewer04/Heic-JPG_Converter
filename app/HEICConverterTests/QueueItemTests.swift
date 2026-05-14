import XCTest
@testable import HEICConverter

final class QueueItemTests: XCTestCase {

    func testInitDefaultsToWaiting() {
        let item = QueueItem(sourceURL: URL(fileURLWithPath: "/tmp/photo.heic"))
        XCTAssertEqual(item.status, .waiting)
        XCTAssertNil(item.destinationURL)
        XCTAssertNil(item.errorMessage)
    }

    func testFilenameExtractsLastComponent() {
        let item = QueueItem(sourceURL: URL(fileURLWithPath: "/tmp/photos/img.heic"))
        XCTAssertEqual(item.filename, "img.heic")
    }

    func testStandardizesURL() {
        let item = QueueItem(sourceURL: URL(fileURLWithPath: "/tmp/../tmp/x.heic"))
        XCTAssertEqual(item.sourceURL.path, "/tmp/x.heic")
    }

    func testConvertingStatusEquality() {
        XCTAssertEqual(QueueItem.Status.converting(progress: 0.5),
                       .converting(progress: 0.5))
        XCTAssertNotEqual(QueueItem.Status.converting(progress: 0.5),
                          .converting(progress: 0.6))
    }
}
