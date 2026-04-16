import XCTest

final class SuspendedPaneUITests: ShichiZipUITestCase {
    private func closeDirectory() {
        app.menuBars.menuBarItems["File"].click()
        app.menuBars.menuBarItems["File"].menus.menuItems["Close Directory"].click()
    }

    func testCloseDirectoryAndReactivationCycle() throws {
        let tempDir = try makeTemporaryDirectory(named: "SuspendCycle")
        try createTextFile(at: tempDir.appendingPathComponent("file.txt"))
        navigateLeftPane(to: tempDir.path)

        let table = leftPaneTable
        XCTAssertTrue(table.waitForExistence(timeout: 5))

        let reactivateButton = app.buttons.matching(identifier: "fileManager.reactivateButton").firstMatch

        // 1. Close directory — overlay appears, table is empty
        closeDirectory()
        XCTAssertTrue(reactivateButton.waitForExistence(timeout: 5), "Reactivate button should appear")
        XCTAssertEqual(table.cells.count, 0, "Table should be empty while suspended")

        // 2. Reactivate via button — file list restored
        reactivateButton.click()
        let fileCell = table.cells.staticTexts["file.txt"]
        XCTAssertTrue(fileCell.waitForExistence(timeout: 5), "File list should restore after button click")
        XCTAssertFalse(reactivateButton.exists, "Reactivate button should be gone")

        // 3. Close again — overlay reappears
        closeDirectory()
        XCTAssertTrue(reactivateButton.waitForExistence(timeout: 5), "Reactivate button should reappear on second close")

        // 4. Reactivate via path field
        navigateLeftPane(to: tempDir.path)
        XCTAssertTrue(fileCell.waitForExistence(timeout: 5), "File list should restore after path field navigation")
        XCTAssertFalse(reactivateButton.exists, "Reactivate button should be gone after path reactivation")
    }
}
