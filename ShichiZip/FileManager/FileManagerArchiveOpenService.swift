import Foundation

enum FileManagerArchiveOpenResult {
    case opened
    case unsupportedArchive(Error)
    case cancelled
    case failed(Error)
}

struct FileManagerPreparedArchiveOpen {
    let hostDirectory: URL
    let archivePath: String
    let displayPathPrefix: String
    let archive: SZArchive
    let entries: [ArchiveItem]
    let temporaryDirectory: URL?
}

enum FileManagerPreparedArchiveOpenResult {
    case opened(FileManagerPreparedArchiveOpen)
    case unsupportedArchive(Error)
    case cancelled
    case failed(Error)
}

enum FileManagerArchiveOpenService {
    @MainActor
    static func openSynchronously(url: URL,
                                  hostDirectory: URL,
                                  temporaryDirectory: URL?,
                                  displayPathPrefix: String) -> FileManagerPreparedArchiveOpenResult {
        do {
            return try ArchiveOperationRunner.runSynchronously(operationTitle: "Opening archive...",
                                                              initialFileName: displayPathPrefix,
                                                              deferredDisplay: true) { session in
                prepareArchiveOpen(url: url,
                                   hostDirectory: hostDirectory,
                                   temporaryDirectory: temporaryDirectory,
                                   displayPathPrefix: displayPathPrefix,
                                   session: session)
            }
        } catch {
            return .failed(error)
        }
    }

    static func prepareArchiveOpen(url: URL,
                                   hostDirectory: URL,
                                   temporaryDirectory: URL?,
                                   displayPathPrefix: String,
                                   session: SZOperationSession) -> FileManagerPreparedArchiveOpenResult {
        let archive = SZArchive()
        do {
            try archive.open(atPath: url.path, session: session)
        } catch {
            if szIsUnsupportedArchive(error) {
                return .unsupportedArchive(error)
            }
            if szIsUserCancellation(error) {
                return .cancelled
            }
            return .failed(error)
        }

        let entries = archive.entries().map { ArchiveItem(from: $0) }
        return .opened(FileManagerPreparedArchiveOpen(hostDirectory: hostDirectory,
                                                      archivePath: url.path,
                                                      displayPathPrefix: displayPathPrefix,
                                                      archive: archive,
                                                      entries: entries,
                                                      temporaryDirectory: temporaryDirectory))
    }
}