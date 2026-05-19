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
        let b = URL(fileURLWithPath: "/tmp/b.png")
        runner.enqueue([a])
        runner.enqueue([a, b])
        XCTAssertEqual(runner.queue.count, 2)
    }

    func testEnqueueAcceptsMixedImageExtensions() {
        let runner = ConversionRunner()
        runner.enqueue([
            URL(fileURLWithPath: "/tmp/a.heic"),
            URL(fileURLWithPath: "/tmp/b.jpg"),
            URL(fileURLWithPath: "/tmp/c.png"),
            URL(fileURLWithPath: "/tmp/d.gif"),
            URL(fileURLWithPath: "/tmp/e.txt"),
        ])
        XCTAssertEqual(runner.queue.count, 4, ".txt is rejected; the four images enqueue")
    }

    func testDedupeByOutputUsesSelectedFormatExtension() {
        // Two inputs collide on the same PNG target name.
        let inputs = [
            URL(fileURLWithPath: "/tmp/photo.heic"),
            URL(fileURLWithPath: "/tmp/photo.jpg"),
        ]
        let deduped = ImageScanner.dedupeByOutput(
            inputs, outputDir: URL(fileURLWithPath: "/tmp/out"), outputExtension: "png")
        XCTAssertEqual(deduped.count, 1, "different inputs targeting the same png path collapse")
    }

    func testClearCompletedRemovesTerminalStatesOnly() {
        let runner = ConversionRunner()
        runner.enqueue([
            URL(fileURLWithPath: "/tmp/converted.heic"),
            URL(fileURLWithPath: "/tmp/skipped.heic"),
            URL(fileURLWithPath: "/tmp/failed.heic"),
            URL(fileURLWithPath: "/tmp/waiting.heic"),
            URL(fileURLWithPath: "/tmp/converting.heic"),
        ])
        XCTAssertEqual(runner.queue.count, 5)

        runner._testSetStatus(.completed, at: 0)
        runner._testSetStatus(.skipped, at: 1)
        runner._testSetStatus(.failed, at: 2)
        // index 3 stays .waiting
        runner._testSetStatus(.converting(progress: 0.5), at: 4)

        runner.clearCompleted()

        XCTAssertEqual(runner.queue.count, 2, "only .waiting and .converting should remain")
        XCTAssertEqual(runner.queue[0].status, .waiting)
        XCTAssertEqual(runner.queue[1].status, .converting(progress: 0.5))
    }

    func testHasInflightTreatsSkippedAsTerminal() {
        let runner = ConversionRunner()
        runner.enqueue([URL(fileURLWithPath: "/tmp/only.heic")])
        runner._testSetStatus(.skipped, at: 0)
        XCTAssertFalse(runner.hasInflight, "skipped items are terminal and don't block quit")
    }
}
