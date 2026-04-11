import Darwin
import XCTest

@testable import ShichiZip

final class QuarantineRegressionTests: XCTestCase {
    private let quarantineAttributeName = "com.apple.quarantine"

    func testNormalExtractionShouldInheritSourceArchiveQuarantine() throws {
        let tempRoot = try makeTemporaryDirectory(named: "normal-extract")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let payloadURL = tempRoot.appendingPathComponent("payload.txt")
        let archiveURL = tempRoot.appendingPathComponent("payload.7z")
        let destinationURL = tempRoot.appendingPathComponent("extract", isDirectory: true)

        try "payload".write(to: payloadURL, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: destinationURL, withIntermediateDirectories: true)

        let compressionSettings = SZCompressionSettings()
        compressionSettings.pathMode = .relativePaths
        try SZArchive.create(
            atPath: archiveURL.path,
            fromPaths: [payloadURL.path],
            settings: compressionSettings,
            session: nil)

        let quarantineData = Data("0081;661aaff0;ShichiZipTests;".utf8)
        try setExtendedAttribute(quarantineAttributeName, data: quarantineData, on: archiveURL)

        let archive = SZArchive()
        try archive.open(atPath: archiveURL.path, session: nil)
        defer { archive.close() }

        let extractionSettings = SZExtractionSettings()
        extractionSettings.pathMode = .fullPaths
        extractionSettings.sourceArchivePathForQuarantine = archiveURL.path
        try archive.extract(
            toPath: destinationURL.path,
            settings: extractionSettings,
            session: nil)

        let extractedURL = destinationURL.appendingPathComponent("payload.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedURL.path))
        XCTAssertEqual(
            try extendedAttributeData(quarantineAttributeName, on: extractedURL), quarantineData)
    }

    func testStagedArchiveItemsShouldInheritSourceArchiveQuarantine() throws {
        let tempRoot = try makeTemporaryDirectory(named: "quarantine")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let payloadURL = tempRoot.appendingPathComponent("payload.txt")
        let archiveURL = tempRoot.appendingPathComponent("payload.7z")
        let stagingFileManager = FileManager.default

        try "payload".write(to: payloadURL, atomically: true, encoding: .utf8)

        let settings = SZCompressionSettings()
        settings.pathMode = .relativePaths
        try SZArchive.create(
            atPath: archiveURL.path,
            fromPaths: [payloadURL.path],
            settings: settings,
            session: nil)

        let quarantineData = Data("0081;661aaff0;ShichiZipTests;".utf8)
        try setExtendedAttribute(quarantineAttributeName, data: quarantineData, on: archiveURL)

        let archive = SZArchive()
        try archive.open(atPath: archiveURL.path, session: nil)
        defer { archive.close() }

        let archiveItems = archive.entries().map(ArchiveItem.init(from:))
        let payloadItem = try XCTUnwrap(archiveItems.first { !$0.isDirectory })
        let workflowService = FileManagerArchiveItemWorkflowService(
            fileManager: stagingFileManager,
            quarantineInheritanceEnabled: { true })
        let context = FileManagerArchiveItemWorkflowContext(
            archive: archive,
            hostDirectory: tempRoot,
            displayPathPrefix: archiveURL.path,
            quarantineSourceArchivePath: archiveURL.path,
            mutationTarget: nil)
        let preview = try workflowService.stageQuickLookItems(
            [payloadItem],
            context: context,
            session: nil)
        defer { workflowService.cleanup(preview.temporaryDirectory) }

        let stagedURL = try XCTUnwrap(preview.fileURLs.first)
        XCTAssertTrue(stagingFileManager.fileExists(atPath: stagedURL.path))
        XCTAssertEqual(
            try extendedAttributeData(quarantineAttributeName, on: stagedURL), quarantineData)
    }

    func testNestedArchiveExtractionShouldInheritOriginalSourceArchiveQuarantine() throws {
        let tempRoot = try makeTemporaryDirectory(named: "nested-extract")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let innerPayloadURL = tempRoot.appendingPathComponent("inner-payload.txt")
        let innerArchiveURL = tempRoot.appendingPathComponent("inner.7z")
        let outerArchiveURL = tempRoot.appendingPathComponent("outer.7z")
        let outerHostDirectory = tempRoot.appendingPathComponent("outer-host", isDirectory: true)
        let nestedExtractURL = tempRoot.appendingPathComponent(
            "nested-extract-output", isDirectory: true)

        try "nested payload".write(to: innerPayloadURL, atomically: true, encoding: .utf8)

        let compressionSettings = SZCompressionSettings()
        compressionSettings.pathMode = .relativePaths
        try SZArchive.create(
            atPath: innerArchiveURL.path,
            fromPaths: [innerPayloadURL.path],
            settings: compressionSettings,
            session: nil)
        try SZArchive.create(
            atPath: outerArchiveURL.path,
            fromPaths: [innerArchiveURL.path],
            settings: compressionSettings,
            session: nil)

        let quarantineData = Data("0081;661aaff0;ShichiZipTests;".utf8)
        try setExtendedAttribute(quarantineAttributeName, data: quarantineData, on: outerArchiveURL)

        let outerArchive = SZArchive()
        try outerArchive.open(atPath: outerArchiveURL.path, session: nil)
        defer { outerArchive.close() }

        let outerItems = outerArchive.entries().map(ArchiveItem.init(from:))
        let nestedArchiveItem = try XCTUnwrap(outerItems.first { $0.name == "inner.7z" })
        let workflowService = FileManagerArchiveItemWorkflowService(
            fileManager: .default,
            quarantineInheritanceEnabled: { true })
        let outerContext = FileManagerArchiveItemWorkflowContext(
            archive: outerArchive,
            hostDirectory: outerHostDirectory,
            displayPathPrefix: outerArchiveURL.path,
            quarantineSourceArchivePath: outerArchiveURL.path,
            mutationTarget: nil)
        let stagedNestedArchive = try workflowService.stageQuickLookItems(
            [nestedArchiveItem],
            context: outerContext,
            session: nil)
        defer { workflowService.cleanup(stagedNestedArchive.temporaryDirectory) }

        let stagedNestedArchiveURL = try XCTUnwrap(stagedNestedArchive.fileURLs.first)
        XCTAssertEqual(
            try extendedAttributeData(quarantineAttributeName, on: stagedNestedArchiveURL),
            quarantineData)

        let innerArchive = SZArchive()
        try innerArchive.open(atPath: stagedNestedArchiveURL.path, session: nil)
        defer { innerArchive.close() }

        let extractionSettings = SZExtractionSettings()
        extractionSettings.pathMode = .fullPaths
        extractionSettings.sourceArchivePathForQuarantine = stagedNestedArchiveURL.path
        try FileManager.default.createDirectory(
            at: nestedExtractURL, withIntermediateDirectories: true)
        try innerArchive.extract(
            toPath: nestedExtractURL.path,
            settings: extractionSettings,
            session: nil)

        let extractedURL = nestedExtractURL.appendingPathComponent("inner-payload.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedURL.path))
        XCTAssertEqual(
            try extendedAttributeData(quarantineAttributeName, on: extractedURL), quarantineData)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ShichiZipSecurityTests-\(name)-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func setExtendedAttribute(_ name: String, data: Data, on url: URL) throws {
        let result = data.withUnsafeBytes { buffer in
            url.path.withCString { pathPointer in
                name.withCString { namePointer in
                    setxattr(
                        pathPointer,
                        namePointer,
                        buffer.baseAddress,
                        buffer.count,
                        0,
                        XATTR_NOFOLLOW)
                }
            }
        }

        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func extendedAttributeData(_ name: String, on url: URL) throws -> Data? {
        let size = url.path.withCString { pathPointer in
            name.withCString { namePointer in
                getxattr(pathPointer, namePointer, nil, 0, 0, XATTR_NOFOLLOW)
            }
        }

        if size < 0 {
            if errno == ENOATTR || errno == ENOENT {
                return nil
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var data = Data(count: size)
        let result = data.withUnsafeMutableBytes { buffer in
            url.path.withCString { pathPointer in
                name.withCString { namePointer in
                    getxattr(
                        pathPointer,
                        namePointer,
                        buffer.baseAddress,
                        buffer.count,
                        0,
                        XATTR_NOFOLLOW)
                }
            }
        }

        if result < 0 {
            if errno == ENOATTR || errno == ENOENT {
                return nil
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        return data
    }
}
