import XCTest
@testable import TripTrack

final class MultipartFormDataBuilderTests: XCTestCase {
    func testAppendField() {
        var b = MultipartFormDataBuilder(boundary: "XYZ")
        b.append(field: "name", value: "hello")
        b.finalize()
        let s = String(data: b.body, encoding: .utf8)!
        XCTAssertTrue(s.contains("--XYZ"))
        XCTAssertTrue(s.contains("name=\"name\""))
        XCTAssertTrue(s.contains("hello"))
        XCTAssertTrue(s.hasSuffix("--XYZ--\r\n"))
    }

    func testAppendFileField() {
        var b = MultipartFormDataBuilder(boundary: "XYZ")
        b.append(fileField: "file", filename: "img.jpg", mimeType: "image/jpeg", data: Data([0x01, 0x02]))
        b.finalize()
        let s = String(data: b.body, encoding: .utf8)!
        XCTAssertTrue(s.contains("filename=\"img.jpg\""))
        XCTAssertTrue(s.contains("Content-Type: image/jpeg"))
    }

    func testContentTypeHeader() {
        let b = MultipartFormDataBuilder(boundary: "ABC")
        XCTAssertEqual(b.contentType, "multipart/form-data; boundary=ABC")
    }
}
