import Foundation

/// Represents a file system item for the file manager view
class FileSystemItem {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: UInt64
    let modifiedDate: Date?
    let createdDate: Date?

    init(url: URL) {
        self.url = url
        name = url.lastPathComponent

        let resourceValues = try? url.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
            .contentModificationDateKey, .creationDateKey,
        ])

        let resolvedDirectoryValue: Bool?
        if resourceValues?.isSymbolicLink == true {
            let resolvedURL = url.resolvingSymlinksInPath()
            resolvedDirectoryValue = try? resolvedURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
        } else {
            resolvedDirectoryValue = nil
        }

        isDirectory = resolvedDirectoryValue ?? resourceValues?.isDirectory ?? false
        size = UInt64(resourceValues?.fileSize ?? 0)
        modifiedDate = resourceValues?.contentModificationDate
        createdDate = resourceValues?.creationDate
    }

    var formattedSize: String {
        if isDirectory { return "--" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
