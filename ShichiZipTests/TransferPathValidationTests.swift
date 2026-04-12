@testable import ShichiZip
import XCTest

final class TransferPathValidationTests: XCTestCase {
    func testAncestryConflictRejectsDestinationInsideSelectedFolder() throws {
        let tempRoot = try makeTemporaryDirectory(named: "descendant-destination")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceFolder = tempRoot.appendingPathComponent("Source", isDirectory: true)
        let nestedDestination = sourceFolder.appendingPathComponent("Nested/Destination", isDirectory: true)

        try FileManager.default.createDirectory(at: nestedDestination,
                                                withIntermediateDirectories: true)

        let conflict = FileManagerTransferPathValidation.ancestryConflict(sourceURLs: [sourceFolder],
                                                                          destinationURL: nestedDestination)

        XCTAssertEqual(conflict?.sourceURL, sourceFolder.standardizedFileURL)
        XCTAssertEqual(conflict?.destinationURL, nestedDestination.standardizedFileURL)
        XCTAssertEqual(conflict?.sourceIsDirectory, true)
        XCTAssertEqual(conflict?.isSameLocation, false)
    }

    func testAncestryConflictRejectsDestinationMatchingSelectedFolder() throws {
        let tempRoot = try makeTemporaryDirectory(named: "same-folder-destination")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceFolder = tempRoot.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder,
                                                withIntermediateDirectories: true)

        let conflict = FileManagerTransferPathValidation.ancestryConflict(sourceURLs: [sourceFolder],
                                                                          destinationURL: sourceFolder)

        XCTAssertEqual(conflict?.sourceURL, sourceFolder.standardizedFileURL)
        XCTAssertEqual(conflict?.destinationURL, sourceFolder.standardizedFileURL)
        XCTAssertEqual(conflict?.sourceIsDirectory, true)
        XCTAssertEqual(conflict?.isSameLocation, true)
    }

    func testAncestryConflictIgnoresFilesInMixedSelection() throws {
        let tempRoot = try makeTemporaryDirectory(named: "mixed-selection")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("payload.txt")
        let sourceFolder = tempRoot.appendingPathComponent("Source", isDirectory: true)
        let nestedDestination = sourceFolder.appendingPathComponent("Nested", isDirectory: true)

        try Data("payload".utf8).write(to: fileURL)
        try FileManager.default.createDirectory(at: nestedDestination,
                                                withIntermediateDirectories: true)

        let conflict = FileManagerTransferPathValidation.ancestryConflict(sourceURLs: [fileURL, sourceFolder],
                                                                          destinationURL: nestedDestination)

        XCTAssertEqual(conflict?.sourceURL, sourceFolder.standardizedFileURL)
        XCTAssertEqual(conflict?.destinationURL, nestedDestination.standardizedFileURL)
        XCTAssertEqual(conflict?.sourceIsDirectory, true)
    }

    func testAncestryConflictAllowsSiblingDestination() throws {
        let tempRoot = try makeTemporaryDirectory(named: "sibling-destination")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceFolder = tempRoot.appendingPathComponent("Source", isDirectory: true)
        let siblingDestination = tempRoot.appendingPathComponent("Destination", isDirectory: true)

        try FileManager.default.createDirectory(at: sourceFolder,
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: siblingDestination,
                                                withIntermediateDirectories: true)

        XCTAssertNil(FileManagerTransferPathValidation.ancestryConflict(sourceURLs: [sourceFolder],
                                                                        destinationURL: siblingDestination))
    }

    func testAncestryConflictAllowsFileSelectionIntoDifferentDirectory() throws {
        let tempRoot = try makeTemporaryDirectory(named: "file-different-destination")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceFile = tempRoot.appendingPathComponent("payload.txt")
        let destinationDirectory = tempRoot.appendingPathComponent("Destination", isDirectory: true)

        try Data("payload".utf8).write(to: sourceFile)
        try FileManager.default.createDirectory(at: destinationDirectory,
                                                withIntermediateDirectories: true)

        XCTAssertNil(FileManagerTransferPathValidation.ancestryConflict(sourceURLs: [sourceFile],
                                                                        destinationURL: destinationDirectory))
    }

    func testAncestryConflictAllowsMixedSelectionIntoSiblingDirectory() throws {
        let tempRoot = try makeTemporaryDirectory(named: "mixed-sibling-destination")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceFile = tempRoot.appendingPathComponent("payload.txt")
        let sourceFolder = tempRoot.appendingPathComponent("Source", isDirectory: true)
        let destinationDirectory = tempRoot.appendingPathComponent("Destination", isDirectory: true)

        try Data("payload".utf8).write(to: sourceFile)
        try FileManager.default.createDirectory(at: sourceFolder,
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory,
                                                withIntermediateDirectories: true)

        XCTAssertNil(FileManagerTransferPathValidation.ancestryConflict(sourceURLs: [sourceFile, sourceFolder],
                                                                        destinationURL: destinationDirectory))
    }

    func testAncestryConflictRejectsSameDirectoryForFileSelection() throws {
        let tempRoot = try makeTemporaryDirectory(named: "same-dir-file-selection")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceFile = tempRoot.appendingPathComponent("payload.txt")
        try Data("payload".utf8).write(to: sourceFile)

        let conflict = FileManagerTransferPathValidation.ancestryConflict(sourceURLs: [sourceFile],
                                                                          destinationURL: tempRoot)

        XCTAssertEqual(conflict?.sourceURL, sourceFile.standardizedFileURL)
        XCTAssertEqual(conflict?.destinationURL, tempRoot.standardizedFileURL)
        XCTAssertEqual(conflict?.sourceIsDirectory, false)
        XCTAssertEqual(conflict?.kind, .sameDestination)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShichiZipTransferTests-\(name)-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
