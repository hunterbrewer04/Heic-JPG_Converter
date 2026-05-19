import XCTest
import UniformTypeIdentifiers
@testable import HEICConverter

final class SupportedFormatTests: XCTestCase {

    func testFromRawValueResolvesEachCase() {
        XCTAssertEqual(SupportedFormat.from(rawValue: "jpeg"), .jpeg)
        XCTAssertEqual(SupportedFormat.from(rawValue: "png"),  .png)
        XCTAssertEqual(SupportedFormat.from(rawValue: "gif"),  .gif)
    }

    func testFromRawValueDefaultsToJpegForUnknown() {
        XCTAssertEqual(SupportedFormat.from(rawValue: nil),     .jpeg)
        XCTAssertEqual(SupportedFormat.from(rawValue: ""),      .jpeg)
        XCTAssertEqual(SupportedFormat.from(rawValue: "webp"),  .jpeg)
        XCTAssertEqual(SupportedFormat.from(rawValue: "JPEG"),  .jpeg, "rawValue lookup is case-sensitive; uppercase falls back to default")
    }

    func testUtTypeMatchesExpected() {
        XCTAssertEqual(SupportedFormat.jpeg.utType, UTType.jpeg)
        XCTAssertEqual(SupportedFormat.png.utType,  UTType.png)
        XCTAssertEqual(SupportedFormat.gif.utType,  UTType.gif)
    }

    func testFileExtensionMatchesPlatformConvention() {
        XCTAssertEqual(SupportedFormat.jpeg.fileExtension, "jpg")
        XCTAssertEqual(SupportedFormat.png.fileExtension,  "png")
        XCTAssertEqual(SupportedFormat.gif.fileExtension,  "gif")
    }

    func testSupportsQualityOnlyJpeg() {
        XCTAssertTrue(SupportedFormat.jpeg.supportsQuality)
        XCTAssertFalse(SupportedFormat.png.supportsQuality)
        XCTAssertFalse(SupportedFormat.gif.supportsQuality)
    }

    func testDefaultIsJpeg() {
        XCTAssertEqual(SupportedFormat.default, .jpeg)
    }

    func testKnownImageExtensionsCoverInputs() {
        for ext in ["heic", "heif", "jpg", "jpeg", "png", "gif", "tif", "tiff", "bmp", "webp"] {
            XCTAssertTrue(SupportedFormat.knownImageExtensions.contains(ext),
                          "expected \(ext) to be a known image extension")
        }
        XCTAssertFalse(SupportedFormat.knownImageExtensions.contains("txt"))
        XCTAssertFalse(SupportedFormat.knownImageExtensions.contains(""))
    }
}
