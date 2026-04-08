import Darwin
import Foundation

struct FileManagerArchiveItemWorkflowContext {
    let archive: SZArchive
    let hostDirectory: URL
    let displayPathPrefix: String
}

final class FileManagerArchiveItemWorkflowService {
    private struct StagedArchiveItem {
        let temporaryDirectory: URL
        let fileURL: URL
    }

    private let fileManager: FileManager
    private let temporaryDirectoriesLock = NSLock()
    private var temporaryDirectories: Set<URL> = []

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func register(_ url: URL) {
        rememberTemporaryDirectory(url)
    }

    func cleanup(_ url: URL?) {
        guard let url else { return }
        _ = cleanupIfPossible(url)
    }

    func cleanupAll() {
        for url in trackedTemporaryDirectories() {
            _ = cleanupIfPossible(url)
        }
    }

    func open(_ item: ArchiveItem,
              context: FileManagerArchiveItemWorkflowContext,
              openArchiveInline: (URL, URL, String, URL) -> FileManagerArchiveOpenResult,
              openExternally: (URL, URL, URL) -> Bool,
              openExternallyIfPossible: (URL, URL) -> Bool) throws {
        let stagedItem = try stage(item: item,
                                   context: context,
                             temporaryDirectoryPrefix: FileManagerTemporaryDirectorySupport.openArchivePrefix)
        let preferredApplicationURL = FileManagerExternalOpenRouter.preferredExternalApplicationURL(forArchiveItemPath: item.path)

        if FileManagerExternalOpenRouter.shouldOpenExternallyBeforeArchiveAttempt(archiveItemPath: item.path) {
            guard let preferredApplicationURL else {
                cleanup(stagedItem.temporaryDirectory)
                throw unavailableExternalOpenError(for: item.name)
            }

            _ = openExternally(stagedItem.fileURL,
                               preferredApplicationURL,
                               stagedItem.temporaryDirectory)
            return
        }

        switch openArchiveInline(stagedItem.fileURL,
                                 stagedItem.temporaryDirectory,
                                 nestedDisplayPath(for: item,
                                                   displayPathPrefix: context.displayPathPrefix),
                                 context.hostDirectory) {
        case .opened:
            return

        case let .unsupportedArchive(error):
            let shouldFallbackExternally = FileManagerExternalOpenRouter.shouldFallbackUnsupportedArchiveExternally(for: stagedItem.fileURL)
            if shouldFallbackExternally {
                if let preferredApplicationURL {
                    _ = openExternally(stagedItem.fileURL,
                                       preferredApplicationURL,
                                       stagedItem.temporaryDirectory)
                } else if !openExternallyIfPossible(stagedItem.fileURL,
                                                    stagedItem.temporaryDirectory) {
                    cleanup(stagedItem.temporaryDirectory)
                    throw error
                }
            } else {
                cleanup(stagedItem.temporaryDirectory)
                throw error
            }

        case .cancelled:
            return

        case let .failed(error):
            throw error
        }
    }

    func writePromise(for item: ArchiveItem,
                      context: FileManagerArchiveItemWorkflowContext,
                      to destinationURL: URL,
                      session: SZOperationSession?) throws {
        let standardizedDestinationURL = destinationURL.standardizedFileURL

        if try extractPromiseDirectlyIfPossible(for: item,
                                               context: context,
                                               to: standardizedDestinationURL,
                                               session: session) {
            return
        }

        let stagedItem = try stage(item: item,
                                   context: context,
                                   temporaryDirectoryPrefix: FileManagerTemporaryDirectorySupport.dragPrefix,
                                   session: session)
        defer {
            cleanup(stagedItem.temporaryDirectory)
        }

        try moveItemPreservingMetadata(from: stagedItem.fileURL,
                                       to: standardizedDestinationURL)
    }

    private func stage(item: ArchiveItem,
                       context: FileManagerArchiveItemWorkflowContext,
                       temporaryDirectoryPrefix: String,
                       session: SZOperationSession? = nil) throws -> StagedArchiveItem {
        let temporaryDirectory = try createTemporaryDirectory(prefix: temporaryDirectoryPrefix)

        do {
            let settings = stagingExtractionSettings()
            if let session {
                try context.archive.extractEntries([NSNumber(value: item.index)],
                                                  toPath: temporaryDirectory.path,
                                                  settings: settings,
                                                  session: session)
            } else {
                try context.archive.extractEntries([NSNumber(value: item.index)],
                                                  toPath: temporaryDirectory.path,
                                                  settings: settings,
                                                  progress: nil)
            }

            let fileURL = temporaryDirectory.appendingPathComponent(item.path)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                throw extractionPreparationError()
            }

            return StagedArchiveItem(temporaryDirectory: temporaryDirectory,
                                     fileURL: fileURL)
        } catch {
            cleanup(temporaryDirectory)
            throw error
        }
    }

    private func extractPromiseDirectlyIfPossible(for item: ArchiveItem,
                                                  context: FileManagerArchiveItemWorkflowContext,
                                                  to destinationURL: URL,
                                                  session: SZOperationSession?) throws -> Bool {
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        let extractedURL = destinationDirectory.appendingPathComponent(item.name, isDirectory: false)
        let standardizedExtractedURL = extractedURL.standardizedFileURL

        if standardizedExtractedURL != destinationURL,
           fileManager.fileExists(atPath: standardizedExtractedURL.path) {
            return false
        }

        let settings = directPromiseExtractionSettings()

        do {
            if let session {
                try context.archive.extractEntries([NSNumber(value: item.index)],
                                                  toPath: destinationDirectory.path,
                                                  settings: settings,
                                                  session: session)
            } else {
                try context.archive.extractEntries([NSNumber(value: item.index)],
                                                  toPath: destinationDirectory.path,
                                                  settings: settings,
                                                  progress: nil)
            }

            guard fileManager.fileExists(atPath: standardizedExtractedURL.path) else {
                throw extractionPreparationError()
            }

            if standardizedExtractedURL != destinationURL {
                try moveItemPreservingMetadata(from: standardizedExtractedURL,
                                               to: destinationURL)
            }

            return true
        } catch {
            if standardizedExtractedURL != destinationURL,
               fileManager.fileExists(atPath: standardizedExtractedURL.path) {
                try? fileManager.removeItem(at: standardizedExtractedURL)
            }
            throw error
        }
    }

    private func createTemporaryDirectory(prefix: String) throws -> URL {
        let tempDir = try FileManagerTemporaryDirectorySupport.makeTemporaryDirectory(prefix: prefix,
                                                                                      fileManager: fileManager)
        rememberTemporaryDirectory(tempDir)
        return tempDir
    }

    @discardableResult
    private func cleanupIfPossible(_ url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL

        if !fileManager.fileExists(atPath: standardizedURL.path) {
            forgetTemporaryDirectory(standardizedURL)
            return true
        }

        do {
            try fileManager.removeItem(at: standardizedURL)
            forgetTemporaryDirectory(standardizedURL)
            return true
        } catch {
            return false
        }
    }

    private func stagingExtractionSettings() -> SZExtractionSettings {
        let settings = SZExtractionSettings()
        settings.overwriteMode = .overwrite
        settings.pathMode = .fullPaths
        return settings
    }

    private func directPromiseExtractionSettings() -> SZExtractionSettings {
        let settings = SZExtractionSettings()
        settings.overwriteMode = .overwrite
        settings.pathMode = .noPaths
        return settings
    }

    private func nestedDisplayPath(for item: ArchiveItem,
                                   displayPathPrefix: String) -> String {
        displayPathPrefix + "/" + item.pathParts.joined(separator: "/")
    }

    private func extractionPreparationError() -> NSError {
        NSError(domain: SZArchiveErrorDomain,
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "The archive item could not be prepared for opening."])
    }

    private func unavailableExternalOpenError(for itemName: String) -> NSError {
        NSError(domain: SZArchiveErrorDomain,
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No application is available to open \"\(itemName)\"."])
    }

    private func rememberTemporaryDirectory(_ url: URL) {
        temporaryDirectoriesLock.lock()
        temporaryDirectories.insert(url.standardizedFileURL)
        temporaryDirectoriesLock.unlock()
    }

    private func forgetTemporaryDirectory(_ url: URL) {
        temporaryDirectoriesLock.lock()
        temporaryDirectories.remove(url.standardizedFileURL)
        temporaryDirectories.remove(url)
        temporaryDirectoriesLock.unlock()
    }

    private func trackedTemporaryDirectories() -> [URL] {
        temporaryDirectoriesLock.lock()
        let urls = Array(temporaryDirectories)
        temporaryDirectoriesLock.unlock()
        return urls
    }

    private func moveItemPreservingMetadata(from sourceURL: URL,
                                            to destinationURL: URL) throws {
        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            return
        } catch {
            if fileManager.fileExists(atPath: destinationURL.path) {
                throw error
            }
        }

        try copyItemPreservingMetadata(from: sourceURL, to: destinationURL)
        try fileManager.removeItem(at: sourceURL)
    }

    private func copyItemPreservingMetadata(from sourceURL: URL,
                                            to destinationURL: URL) throws {
        let cloneResult = sourceURL.path.withCString { sourcePath in
            destinationURL.path.withCString { destinationPath in
                copyfile(sourcePath,
                         destinationPath,
                         nil,
                         copyfile_flags_t(COPYFILE_ALL | COPYFILE_CLONE_FORCE))
            }
        }
        if cloneResult == 0 {
            return
        }

        let copyResult = sourceURL.path.withCString { sourcePath in
            destinationURL.path.withCString { destinationPath in
                copyfile(sourcePath,
                         destinationPath,
                         nil,
                         copyfile_flags_t(COPYFILE_ALL))
            }
        }
        if copyResult == 0 {
            return
        }

        let errorCode = errno
        throw NSError(domain: NSPOSIXErrorDomain,
                      code: Int(errorCode),
                      userInfo: [NSLocalizedDescriptionKey: "The promised file could not be written."])
    }
}