import Foundation

enum FileManagerTransferPathValidation {
    enum ConflictKind: Equatable {
        case sameDestination
        case descendant
    }

    struct Conflict: Equatable {
        let sourceURL: URL
        let destinationURL: URL
        let sourceIsDirectory: Bool
        let kind: ConflictKind

        var isSameLocation: Bool {
            kind == .sameDestination
        }
    }

    static func ancestryConflict(sourceURLs: [URL],
                                 destinationURL: URL,
                                 fileManager: FileManager = .default) -> Conflict?
    {
        let normalizedDestinationURL = normalizedFileSystemURL(destinationURL)
        var fileSourceURLs: [URL] = []

        for sourceURL in sourceURLs {
            guard isDirectory(at: sourceURL, fileManager: fileManager) else {
                fileSourceURLs.append(sourceURL.standardizedFileURL)
                continue
            }

            let normalizedSourceURL = normalizedFileSystemURL(sourceURL)
            if normalizedDestinationURL == normalizedSourceURL {
                return Conflict(sourceURL: sourceURL.standardizedFileURL,
                                destinationURL: normalizedDestinationURL,
                                sourceIsDirectory: true,
                                kind: .sameDestination)
            }

            if isDescendant(normalizedDestinationURL, of: normalizedSourceURL) {
                return Conflict(sourceURL: sourceURL.standardizedFileURL,
                                destinationURL: normalizedDestinationURL,
                                sourceIsDirectory: true,
                                kind: .descendant)
            }
        }

        for sourceURL in fileSourceURLs {
            let normalizedParentURL = normalizedFileSystemURL(sourceURL.deletingLastPathComponent())
            guard normalizedDestinationURL == normalizedParentURL else {
                continue
            }

            return Conflict(sourceURL: sourceURL,
                            destinationURL: normalizedDestinationURL,
                            sourceIsDirectory: false,
                            kind: .sameDestination)
        }

        return nil
    }

    static func normalizedFileSystemURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func isDirectory(at url: URL,
                                    fileManager: FileManager) -> Bool
    {
        let normalizedURL = normalizedFileSystemURL(url)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: normalizedURL.path,
                                     isDirectory: &isDirectory)
        else {
            return false
        }

        return isDirectory.boolValue
    }

    private static func isDescendant(_ url: URL,
                                     of ancestorURL: URL) -> Bool
    {
        let pathComponents = url.pathComponents
        let ancestorComponents = ancestorURL.pathComponents
        guard pathComponents.count > ancestorComponents.count else {
            return false
        }

        return Array(pathComponents.prefix(ancestorComponents.count)) == ancestorComponents
    }
}
