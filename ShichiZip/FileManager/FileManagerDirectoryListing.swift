import Foundation

enum FileManagerDirectoryListing {
    static func contentsPreservingPresentedPath(for url: URL,
                                                options: FileManager.DirectoryEnumerationOptions,
                                                fileManager: FileManager = .default) throws -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
        ]

        let resourceValues = try url.resourceValues(forKeys: resourceKeys)
        let listingURL: URL
        if resourceValues.isSymbolicLink == true,
           let resolvedIsDirectory = try url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
           resolvedIsDirectory {
            listingURL = url.resolvingSymlinksInPath()
        } else {
            listingURL = url
        }

        let contents = try fileManager.contentsOfDirectory(
            at: listingURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: options
        )

        guard listingURL != url else {
            return contents
        }

        return contents.map { childURL in
            let isDirectory = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return url.appendingPathComponent(childURL.lastPathComponent, isDirectory: isDirectory)
        }
    }
}