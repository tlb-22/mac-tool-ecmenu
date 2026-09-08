import Foundation
import XCTest
@testable import ECMenu

final class FileTemplateTests: XCTestCase {
    func testNamesMayRepeatAndIdentityIsIndependent() throws {
        let first = try FileTemplate(displayName: "TXT", defaultFileName: "untitled.txt")
        let second = try FileTemplate(displayName: "TXT", defaultFileName: "untitled.txt")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.displayName, second.displayName)
        XCTAssertEqual(first.defaultFileName, second.defaultFileName)
        XCTAssertEqual(
            try JSONDecoder().decode(FileTemplate.self, from: JSONEncoder().encode(first)),
            first
        )
    }

    func testInputAndDecodedNamesMustDescribeValidValues() throws {
        for displayName in ["", " \n\t"] {
            XCTAssertThrowsError(try FileTemplate(displayName: displayName, defaultFileName: "a.txt")) { error in
                XCTAssertEqual(error as? FileTemplateValidationError, .emptyDisplayName)
            }
        }
        for fileName in ["", " \n", ".", "..", "/tmp/a", "nested/a", "a\0b"] {
            XCTAssertThrowsError(try FileTemplate(displayName: "TXT", defaultFileName: fileName)) { error in
                XCTAssertEqual(error as? FileTemplateValidationError, .invalidDefaultFileName)
            }
            let data = try JSONSerialization.data(withJSONObject: [
                "id": UUID().uuidString,
                "displayName": "TXT",
                "defaultFileName": fileName,
            ])
            XCTAssertThrowsError(try JSONDecoder().decode(FileTemplate.self, from: data))
        }
        let named = try FileTemplate(displayName: " 笔记 ", defaultFileName: ".config")
        XCTAssertEqual(named.displayName, " 笔记 ")
        XCTAssertEqual(named.defaultFileName, ".config")
    }
}
