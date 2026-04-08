import Foundation

enum FileManagerArchiveExtractionService {
    static func extractionSettings(overwriteMode: SZOverwriteMode,
                                   pathMode: SZPathMode,
                                   currentSubdir: String) -> SZExtractionSettings {
        let settings = SZExtractionSettings()
        settings.overwriteMode = overwriteMode
        settings.pathMode = pathMode
        if pathMode == .currentPaths,
           !currentSubdir.isEmpty {
            settings.pathPrefixToStrip = currentSubdir
        }
        return settings
    }

    static func archiveEntryIndices(for selectedItems: [ArchiveItem],
                                    in allEntries: [ArchiveItem]) -> [NSNumber] {
        var indices = Set<Int>()

        for item in selectedItems {
            if item.index >= 0 {
                indices.insert(item.index)
            }

            if item.isDirectory || item.index < 0 {
                let directoryPath = normalizeArchivePath(item.path)
                let prefix = directoryPath.isEmpty ? "" : directoryPath + "/"

                for entry in allEntries where entry.index >= 0 {
                    let entryPath = normalizeArchivePath(entry.path)
                    if entryPath == directoryPath || (!prefix.isEmpty && entryPath.hasPrefix(prefix)) {
                        indices.insert(entry.index)
                    }
                }
            }
        }

        return indices.sorted().map { NSNumber(value: $0) }
    }

    private static func normalizeArchivePath(_ path: String) -> String {
        var normalized = path
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }
}