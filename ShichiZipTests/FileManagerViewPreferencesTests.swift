@testable import ShichiZip
import XCTest

final class FileManagerViewPreferencesTests: XCTestCase {
    func testMakeDateFormatterReturnsIndependentInstances() {
        let first = FileManagerViewPreferences.makeDateFormatter(dateStyle: .medium,
                                                                 timeStyle: .medium)
        let second = FileManagerViewPreferences.makeDateFormatter(dateStyle: .medium,
                                                                  timeStyle: .medium)

        XCTAssertFalse(first === second)
        XCTAssertEqual(first.string(from: Date(timeIntervalSince1970: 1_713_635_445)),
                       second.string(from: Date(timeIntervalSince1970: 1_713_635_445)))
    }

    func testMakeListDateFormatterReturnsIndependentInstances() {
        let first = FileManagerViewPreferences.makeListDateFormatter()
        let second = FileManagerViewPreferences.makeListDateFormatter()

        XCTAssertFalse(first === second)
        XCTAssertEqual(first.string(from: Date(timeIntervalSince1970: 1_713_635_445)),
                       second.string(from: Date(timeIntervalSince1970: 1_713_635_445)))
    }
}
