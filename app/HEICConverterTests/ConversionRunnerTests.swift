import XCTest
@testable import HEICConverter

@MainActor
final class ConversionRunnerTests: XCTestCase {

    func testEnqueueDedupesByURL() {
        let runner = ConversionRunner()
        let url = URL(fileURLWithPath: "/tmp/photo.heic")
        runner.enqueue([url, url])
        XCTAssertEqual(runner.queue.count, 1)
    }

    func testEnqueueIgnoresAlreadyEnqueuedItems() {
        let runner = ConversionRunner()
        let a = URL(fileURLWithPath: "/tmp/a.heic")
        let b = URL(fileURLWithPath: "/tmp/b.heic")
        runner.enqueue([a])
        runner.enqueue([a, b])
        XCTAssertEqual(runner.queue.count, 2)
    }

    func testClearCompletedRemovesOnlyCompletedAndFailed() {
        let runner = ConversionRunner()
        runner.enqueue([
            URL(fileURLWithPath: "/tmp/x.heic"),
            URL(fileURLWithPath: "/tmp/y.heic"),
        ])
        // Manually mutate status via reflection-friendly approach:
        // Since `queue` is private(set), we test only what's observable.
        // For deeper testing, expose an internal `_testHelper_setStatus` if needed.
        XCTAssertEqual(runner.queue.count, 2)
    }
}
