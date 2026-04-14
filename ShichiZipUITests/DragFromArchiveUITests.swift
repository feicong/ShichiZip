import XCTest

/// Tests for dragging files out of an opened archive into a filesystem pane.
///
/// These tests launch the app in dual-pane mode by setting the
/// `FileManager.IsDualPane` user default via launch arguments.
/// The left pane opens an archive; the right pane shows a destination
/// directory.  The test then drags an archive entry from the left table
/// to the right table and verifies the file is extracted to disk.
final class DragFromArchiveUITests: ShichiZipUITestCase {
    // MARK: - Launch with dual-pane mode

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // NSUserDefaults picks up launch arguments as `-key value` pairs,
        // so this forces the file manager into two-column mode.
        app.launchArguments += ["-FileManager.IsDualPane", "YES"]
        app.launch()
    }

    // MARK: - Pane-scoped element accessors

    // Both panes reuse the same accessibility identifiers for their
    // table view ("fileManager.tableView") and path field
    // ("fileManager.pathField").  In dual-pane mode the split view
    // lays out the left pane first, so index 0 = left, index 1 = right.

    private var splitView: XCUIElement {
        fileManagerWindow.splitGroups.matching(identifier: "fileManager.splitView").firstMatch
    }

    private var leftTable: XCUIElement {
        fileManagerWindow.tables.matching(identifier: "fileManager.tableView").element(boundBy: 0)
    }

    private var rightTable: XCUIElement {
        fileManagerWindow.tables.matching(identifier: "fileManager.tableView").element(boundBy: 1)
    }

    private var leftPathField: XCUIElement {
        fileManagerWindow.textFields.matching(identifier: "fileManager.pathField").element(boundBy: 0)
    }

    private var rightPathField: XCUIElement {
        fileManagerWindow.textFields.matching(identifier: "fileManager.pathField").element(boundBy: 1)
    }

    // MARK: - Navigation helpers (pane-scoped)

    private func navigatePane(_ pathField: XCUIElement, to path: String) {
        XCTAssertTrue(pathField.waitForExistence(timeout: 10),
                      "Path field should exist before navigating")
        pathField.click()
        pathField.selectAll()
        pathField.typeText(path + "\r")
    }

    // MARK: - Workflow helpers

    /// Opens an archive in the left pane and navigates the right pane
    /// to a destination directory.  Returns after both panes are ready.
    private func openArchiveInLeftPane(_ archiveURL: URL,
                                       destinationDir: URL)
    {
        // Left pane: navigate to the archive's directory, then open it.
        navigatePane(leftPathField, to: archiveURL.deletingLastPathComponent().path)
        XCTAssertTrue(leftTable.waitForExistence(timeout: 10))

        let archiveCell = leftTable.cells.staticTexts[archiveURL.lastPathComponent]
        XCTAssertTrue(archiveCell.waitForExistence(timeout: 5),
                      "Archive should appear in the left pane")
        archiveCell.doubleClick()

        // Wait until the path field reflects the opened archive.
        let openPredicate = NSPredicate(format: "value CONTAINS %@",
                                        archiveURL.lastPathComponent)
        let openExpectation = XCTNSPredicateExpectation(predicate: openPredicate,
                                                        object: leftPathField)
        wait(for: [openExpectation], timeout: 10)

        // Right pane: point at the destination directory.
        navigatePane(rightPathField, to: destinationDir.path)
        XCTAssertTrue(rightTable.waitForExistence(timeout: 10))
    }

    // MARK: - Tests

    /// Sanity-check that dual-pane mode is active when the launch
    /// argument is set.
    func testDualPaneLaunches() {
        XCTAssertTrue(splitView.waitForExistence(timeout: 10),
                      "Split view should exist")
        XCTAssertTrue(leftTable.waitForExistence(timeout: 5),
                      "Left table should exist")
        XCTAssertTrue(rightTable.waitForExistence(timeout: 5),
                      "Right table should exist")
        XCTAssertTrue(leftPathField.waitForExistence(timeout: 5),
                      "Left path field should exist")
        XCTAssertTrue(rightPathField.waitForExistence(timeout: 5),
                      "Right path field should exist")
    }

    /// Opens an archive in the left pane, drags a single file to the
    /// right (filesystem) pane, and verifies the file on disk.
    func testDragSingleFileFromArchive() throws {
        let (archiveURL, tempDir) = try makeTestArchive(named: "dragtest",
                                                        payloads: ["payload.txt": "Drag-out test content."])
        let destinationDir = tempDir.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDir,
                                                withIntermediateDirectories: true)

        openArchiveInLeftPane(archiveURL, destinationDir: destinationDir)

        // Locate the entry inside the archive.
        let payloadCell = leftTable.cells.staticTexts["payload.txt"]
        XCTAssertTrue(payloadCell.waitForExistence(timeout: 5),
                      "payload.txt should be visible inside the opened archive")

        // Drag from archive (left) to filesystem (right).
        payloadCell.click(forDuration: 1.0, thenDragTo: rightTable)

        // Verify extraction on disk.
        let extractedFile = destinationDir.appendingPathComponent("payload.txt")
        XCTAssertTrue(waitForFile(at: extractedFile),
                      "payload.txt should be extracted to \(destinationDir.path)")

        let content = try String(contentsOf: extractedFile, encoding: .utf8)
        XCTAssertEqual(content, "Drag-out test content.",
                       "Extracted file content should match the original")

        // The app should remain responsive after drag-out (no deadlock).
        XCTAssertEqual(app.state, .runningForeground,
                       "App should still be in the foreground after drag-out")
        XCTAssertTrue(leftTable.isHittable,
                      "Left table should remain hittable after drag-out")
    }

    /// Selects two files inside an archive with Cmd-click, drags the
    /// selection to the right pane, and verifies both land on disk.
    func testDragMultipleFilesFromArchive() throws {
        let (archiveURL, tempDir) = try makeTestArchive(named: "dragmulti",
                                                        payloads: ["alpha.txt": "alpha",
                                                                   "beta.txt": "beta"])

        let destinationDir = tempDir.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDir,
                                                withIntermediateDirectories: true)

        openArchiveInLeftPane(archiveURL, destinationDir: destinationDir)

        // Locate both entries inside the archive.
        let alphaCell = leftTable.cells.staticTexts["alpha.txt"]
        let betaCell = leftTable.cells.staticTexts["beta.txt"]
        XCTAssertTrue(alphaCell.waitForExistence(timeout: 5))
        XCTAssertTrue(betaCell.waitForExistence(timeout: 5))

        // Build a multi-selection: click the first, Cmd-click the second.
        alphaCell.click()
        XCUIElement.perform(withKeyModifiers: .command) {
            betaCell.click()
        }

        // Drag the multi-selection to the right pane.
        // click(forDuration:thenDragTo:) initiates a drag of the
        // *current selection* starting from the clicked row.
        alphaCell.click(forDuration: 1.0, thenDragTo: rightTable)

        // Verify both files extracted.
        let alphaExtracted = destinationDir.appendingPathComponent("alpha.txt")
        let betaExtracted = destinationDir.appendingPathComponent("beta.txt")

        XCTAssertTrue(waitForFile(at: alphaExtracted), "alpha.txt should be extracted")
        XCTAssertTrue(waitForFile(at: betaExtracted), "beta.txt should be extracted")
    }
}
