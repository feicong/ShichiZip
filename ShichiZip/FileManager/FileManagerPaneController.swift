import Cocoa

/// Single pane of the file manager — displays file system contents
class FileManagerPaneController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSTextFieldDelegate {

    weak var delegate: FileManagerPaneDelegate?

    private var pathField: NSTextField!
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var statusLabel: NSTextField!

    private(set) var currentDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    var currentDirectoryURL: URL { currentDirectory }
    private var items: [FileSystemItem] = []

    // Archive navigation state (matches CFolderLink stack in Panel.cpp)
    private struct ArchiveLevel {
        let filesystemDirectory: URL   // directory we were in before opening the archive
        let archivePath: String        // path to the .zip/.7z file
        let archive: SZArchive         // open archive handle
        let allEntries: [ArchiveItem]  // all entries in the archive
        let currentSubdir: String      // current path within the archive ("" = root)
    }
    private var archiveStack: [ArchiveLevel] = []
    private var isInsideArchive: Bool { !archiveStack.isEmpty }
    private var archiveDisplayItems: [ArchiveItem] = [] // currently visible items in archive

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 600))

        // Up button (navigate to parent / exit archive)
        let upButton = NSButton(image: NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Up")!, target: self, action: #selector(goUpClicked(_:)))
        upButton.translatesAutoresizingMaskIntoConstraints = false
        upButton.bezelStyle = .accessoryBarAction
        upButton.isBordered = false
        container.addSubview(upButton)

        // Path text field (matches Windows 7-Zip address bar)
        pathField = NSTextField()
        pathField.translatesAutoresizingMaskIntoConstraints = false
        pathField.font = .systemFont(ofSize: 12)
        pathField.usesSingleLineMode = true
        pathField.lineBreakMode = .byTruncatingHead
        pathField.stringValue = currentDirectory.path
        pathField.target = self
        pathField.action = #selector(pathFieldSubmitted(_:))
        pathField.delegate = self
        container.addSubview(pathField)

        // Table view for file listing
        tableView = NSTableView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = true
        tableView.rowSizeStyle = .small
        tableView.style = .fullWidth

        // Columns
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "Name"
        nameCol.width = 250
        nameCol.minWidth = 100
        nameCol.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedStandardCompare(_:)))
        tableView.addTableColumn(nameCol)

        let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeCol.title = "Size"
        sizeCol.width = 80
        sizeCol.minWidth = 50
        sizeCol.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: false)
        tableView.addTableColumn(sizeCol)

        let modifiedCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("modified"))
        modifiedCol.title = "Modified"
        modifiedCol.width = 140
        modifiedCol.minWidth = 80
        modifiedCol.sortDescriptorPrototype = NSSortDescriptor(key: "modified", ascending: false)
        tableView.addTableColumn(modifiedCol)

        let createdCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("created"))
        createdCol.title = "Created"
        createdCol.width = 140
        createdCol.minWidth = 80
        createdCol.sortDescriptorPrototype = NSSortDescriptor(key: "created", ascending: false)
        tableView.addTableColumn(createdCol)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClickRow(_:))
        tableView.menu = buildContextMenu()
        NSLog("[ShichiZip] File manager pane context menu set with %ld items", tableView.menu?.items.count ?? 0)

        // Register for drag and drop
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        container.addSubview(scrollView)

        // Status bar
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        container.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            upButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            upButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            upButton.widthAnchor.constraint(equalToConstant: 24),
            upButton.heightAnchor.constraint(equalToConstant: 24),

            pathField.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            pathField.leadingAnchor.constraint(equalTo: upButton.trailingAnchor, constant: 2),
            pathField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            pathField.heightAnchor.constraint(equalToConstant: 24),

            scrollView.topAnchor.constraint(equalTo: pathField.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -2),

            statusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            statusLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
            statusLabel.heightAnchor.constraint(equalToConstant: 16),
        ])

        self.view = container
        loadDirectory(currentDirectory)
    }

    // MARK: - Navigation

    func loadDirectory(_ url: URL) {
        currentDirectory = url
        updatePathField()

        let fm = FileManager.default
        do {
            let contents = try fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            )
            items = contents.map { FileSystemItem(url: $0) }.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        } catch {
            items = []
        }

        tableView.reloadData()
        updateStatusBar()
    }

    func refresh() {
        loadDirectory(currentDirectory)
    }

    func selectedFilePaths() -> [String] {
        return tableView.selectedRowIndexes.compactMap { row -> String? in
            guard row < items.count else { return nil }
            return items[row].url.path
        }
    }

    func createFolder(named name: String) {
        let url = currentDirectory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            refresh()
        } catch {
            let alert = NSAlert(error: error)
            view.window.map { alert.beginSheetModal(for: $0) }
        }
    }

    private func updateStatusBar() {
        let fileCount = items.filter { !$0.isDirectory }.count
        let dirCount = items.filter { $0.isDirectory }.count
        let totalSize = items.filter { !$0.isDirectory }.reduce(UInt64(0)) { $0 + $1.size }
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
        statusLabel.stringValue = "\(fileCount) files, \(dirCount) folders — \(sizeStr)"
    }

    // MARK: - Actions

    @objc private func pathFieldSubmitted(_ sender: NSTextField) {
        let path = sender.stringValue
        if path.isEmpty { return }

        // Expand ~ to home directory
        let expanded = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)

        // Check if it's an archive file
        if FileSystemItem.archiveExtensions.contains(url.pathExtension.lowercased()) &&
           FileManager.default.fileExists(atPath: url.path) {
            // Exit any current archive first
            while !archiveStack.isEmpty {
                archiveStack.last?.archive.close()
                archiveStack.removeLast()
            }
            openArchiveInline(url)
            return
        }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            // Exit any current archive first
            while !archiveStack.isEmpty {
                archiveStack.last?.archive.close()
                archiveStack.removeLast()
            }
            loadDirectory(url)
        } else {
            // Path doesn't exist — revert to current
            updatePathField()
        }
        // Resign focus back to table
        view.window?.makeFirstResponder(tableView)
    }

    @objc private func goUpClicked(_ sender: Any?) {
        goUp()
    }

    private func updatePathField() {
        if isInsideArchive {
            let level = archiveStack.last!
            let archiveName = (level.archivePath as NSString).lastPathComponent
            let prefix = (level.filesystemDirectory.path as NSString).appendingPathComponent(archiveName)
            pathField.stringValue = level.currentSubdir.isEmpty ? prefix : prefix + "/" + level.currentSubdir
        } else {
            pathField.stringValue = currentDirectory.path
        }
    }

    @objc private func doubleClickRow(_ sender: Any?) {
        if isInsideArchive {
            let row = tableView.clickedRow
            guard row >= 0, row < archiveDisplayItems.count else { return }
            let item = archiveDisplayItems[row]
            if item.isDirectory {
                // Navigate deeper into archive subdirectory
                navigateArchiveSubdir(item.path)
            }
            return
        }

        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }

        let item = items[row]
        if item.isDirectory {
            loadDirectory(item.url)
        } else if item.isArchive {
            // Navigate INTO the archive (like Windows 7-Zip File Manager)
            openArchiveInline(item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Enter
            doubleClickRow(nil)
        } else if event.keyCode == 51 { // Backspace - go up
            goUp()
        } else {
            super.keyDown(with: event)
        }
    }

    private func goUp() {
        if isInsideArchive {
            let level = archiveStack.last!
            if !level.currentSubdir.isEmpty {
                // Go up within archive
                let parent: String
                if let lastSlash = level.currentSubdir.lastIndex(of: "/") {
                    parent = String(level.currentSubdir[level.currentSubdir.startIndex..<lastSlash])
                } else {
                    parent = ""
                }
                navigateArchiveSubdir(parent)
            } else {
                // Exit archive — pop stack, restore filesystem
                let fsDir = level.filesystemDirectory
                level.archive.close()
                archiveStack.removeLast()
                if archiveStack.isEmpty {
                    loadDirectory(fsDir)
                } else {
                    // Still inside an outer archive
                    let outer = archiveStack.last!
                    navigateArchiveSubdir(outer.currentSubdir)
                }
            }
        } else {
            let parent = currentDirectory.deletingLastPathComponent()
            loadDirectory(parent)
        }
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return isInsideArchive ? archiveDisplayItems.count : items.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let columnID = tableColumn?.identifier.rawValue else { return nil }

        // Determine the data source based on mode
        let itemName: String
        let itemSize: String
        let itemModified: String
        let itemCreated: String
        let itemIsDir: Bool
        let itemIconPath: String

        if isInsideArchive {
            guard row < archiveDisplayItems.count else { return nil }
            let ai = archiveDisplayItems[row]
            itemName = ai.name
            itemSize = ai.isDirectory ? "--" : ByteCountFormatter.string(fromByteCount: Int64(ai.size), countStyle: .file)
            let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
            itemModified = ai.modifiedDate.map { df.string(from: $0) } ?? ""
            itemCreated = ai.createdDate.map { df.string(from: $0) } ?? ""
            itemIsDir = ai.isDirectory
            itemIconPath = ai.isDirectory ? "" : ai.name
        } else {
            guard row < items.count else { return nil }
            let item = items[row]
            itemName = item.name
            itemSize = item.formattedSize
            let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
            itemModified = item.modifiedDate.map { df.string(from: $0) } ?? ""
            itemCreated = item.createdDate.map { df.string(from: $0) } ?? ""
            itemIsDir = item.isDirectory
            itemIconPath = item.url.path
        }

        let cellID = NSUserInterfaceItemIdentifier(columnID)
        let cell: NSTableCellView

        if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(textField)
            cell.textField = textField

            if columnID == "name" {
                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(imageView)
                cell.imageView = imageView

                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            } else {
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        switch columnID {
        case "name":
            cell.textField?.stringValue = itemName
            if isInsideArchive {
                // Archive mode: use SF Symbol for folders, extension-based for files
                if itemIsDir {
                    cell.imageView?.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Folder")
                    cell.imageView?.contentTintColor = .systemBlue
                } else {
                    let ext = (itemName as NSString).pathExtension
                    cell.imageView?.image = NSWorkspace.shared.icon(for: .init(filenameExtension: ext) ?? .data)
                    cell.imageView?.contentTintColor = nil
                }
            } else {
                // Filesystem mode: use system icon for everything (consistent with Finder)
                cell.imageView?.image = NSWorkspace.shared.icon(forFile: itemIconPath)
                cell.imageView?.contentTintColor = nil
            }
            cell.imageView?.image?.size = NSSize(width: 16, height: 16)

        case "size":
            cell.textField?.stringValue = itemSize
            cell.textField?.alignment = .right

        case "modified":
            cell.textField?.stringValue = itemModified

        case "created":
            cell.textField?.stringValue = itemCreated

        default:
            break
        }

        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 22
    }

    // MARK: - Drag source (provide file URLs to drag out)

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        if isInsideArchive {
            // Extract to temp folder on demand, then provide temp URL (PanelDrag.cpp pattern)
            guard row < archiveDisplayItems.count else { return nil }
            let ai = archiveDisplayItems[row]
            if ai.isDirectory || ai.index < 0 { return nil } // can't drag synthetic dirs

            guard let level = archiveStack.last else { return nil }
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("ShichiZip-drag-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let settings = SZExtractionSettings()
            settings.overwriteMode = .overwrite
            let indices = [NSNumber(value: ai.index)]
            try? level.archive.extractEntries(indices, toPath: tempDir.path, settings: settings, progress: nil)

            let extractedFile = tempDir.appendingPathComponent(ai.path)
            if FileManager.default.fileExists(atPath: extractedFile.path) {
                return extractedFile as NSURL
            }
            return nil
        }

        guard row < items.count else { return nil }
        return items[row].url as NSURL
    }

    // MARK: - Drop destination (accept files dragged into this folder)

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        // Accept drops onto the table (not between rows)
        if dropOperation == .on { return [] }
        tableView.setDropRow(-1, dropOperation: .on) // highlight whole table
        return info.draggingSourceOperationMask.contains(.move) ? .move : .copy
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty else { return false }

        let destDir = currentDirectory
        let isMove = info.draggingSourceOperationMask.contains(.move)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for url in urls {
                let dest = destDir.appendingPathComponent(url.lastPathComponent)
                do {
                    if isMove {
                        // rename() is atomic and preserves all metadata on same volume
                        try FileManager.default.moveItem(at: url, to: dest)
                    } else {
                        // copyfile with CLONE for APFS, falls back to full copy preserving all metadata
                        let result = copyfile(
                            url.path.cString(using: .utf8),
                            dest.path.cString(using: .utf8),
                            nil,
                            copyfile_flags_t(COPYFILE_ALL | COPYFILE_CLONE_FORCE)
                        )
                        if result != 0 {
                            // CLONE_FORCE failed (not APFS) — retry without clone (same as cp)
                            let r2 = copyfile(
                                url.path.cString(using: .utf8),
                                dest.path.cString(using: .utf8),
                                nil,
                                copyfile_flags_t(COPYFILE_ALL)
                            )
                            if r2 != 0 {
                                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                            }
                        }
                    }
                } catch {
                    NSLog("[ShichiZip] Drop error: %@", error.localizedDescription)
                }
            }
            DispatchQueue.main.async { self?.refresh() }
        }
        return true
    }

    // MARK: - Sorting (matches PanelSort.cpp: folders first, natural sort for names)

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        sortItems(by: tableView.sortDescriptors)
        tableView.reloadData()
    }

    private func sortItems(by descriptors: [NSSortDescriptor]) {
        guard let descriptor = descriptors.first else { return }
        let key = descriptor.key ?? "name"
        let ascending = descriptor.ascending

        items.sort { a, b in
            // PanelSort.cpp: folders always before files
            if a.isDirectory != b.isDirectory { return a.isDirectory }

            let result: ComparisonResult
            switch key {
            case "name":
                result = a.name.localizedStandardCompare(b.name)
            case "size":
                result = a.size == b.size ? .orderedSame : (a.size < b.size ? .orderedAscending : .orderedDescending)
            case "modified":
                let ad = a.modifiedDate ?? Date.distantPast
                let bd = b.modifiedDate ?? Date.distantPast
                result = ad.compare(bd)
            case "created":
                let ad = a.createdDate ?? Date.distantPast
                let bd = b.createdDate ?? Date.distantPast
                result = ad.compare(bd)
            default:
                result = a.name.localizedStandardCompare(b.name)
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }
}

// MARK: - Archive Inline Navigation (matches Panel.cpp _parentFolders stack)

extension FileManagerPaneController {

    func openArchiveInline(_ url: URL) {
        let archive = SZArchive()
        do {
            try archive.open(atPath: url.path)
        } catch {
            // Can't open as archive — fall back to opening in document window
            delegate?.paneDidOpenArchive(url.path)
            return
        }

        let entries = archive.entries().map { ArchiveItem(from: $0) }
        let level = ArchiveLevel(
            filesystemDirectory: currentDirectory,
            archivePath: url.path,
            archive: archive,
            allEntries: entries,
            currentSubdir: ""
        )
        archiveStack.append(level)
        navigateArchiveSubdir("")
    }

    func navigateArchiveSubdir(_ subdir: String) {
        guard var level = archiveStack.last else { return }

        // Update current subdir in the stack
        archiveStack[archiveStack.count - 1] = ArchiveLevel(
            filesystemDirectory: level.filesystemDirectory,
            archivePath: level.archivePath,
            archive: level.archive,
            allEntries: level.allEntries,
            currentSubdir: subdir
        )
        level = archiveStack.last!

        // Filter entries for the current subdirectory level
        let prefix = subdir.isEmpty ? "" : subdir + "/"
        var seenDirs = Set<String>()
        var displayItems: [ArchiveItem] = []

        for entry in level.allEntries {
            let path = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path

            // Must start with prefix
            if !prefix.isEmpty && !path.hasPrefix(prefix) { continue }
            // Skip the subdir entry itself
            if path == subdir { continue }

            let relativePath = prefix.isEmpty ? path : String(path.dropFirst(prefix.count))
            // Skip deeper entries (only show direct children)
            if relativePath.contains("/") {
                // This is a deeper entry — record the immediate subdirectory
                let dirName = String(relativePath.split(separator: "/").first ?? "")
                if !dirName.isEmpty && !seenDirs.contains(dirName) {
                    seenDirs.insert(dirName)
                    // Create a synthetic directory item
                    var dirItem = entry
                    let syntheticPath = prefix + dirName
                    // Find if there's an actual directory entry
                    if let realDir = level.allEntries.first(where: {
                        let p = $0.path.hasSuffix("/") ? String($0.path.dropLast()) : $0.path
                        return p == syntheticPath && $0.isDirectory
                    }) {
                        displayItems.append(realDir)
                    } else {
                        // Create a virtual directory entry
                        displayItems.append(ArchiveItem(
                            index: -1, path: syntheticPath, name: dirName,
                            size: 0, packedSize: 0, modifiedDate: entry.modifiedDate,
                            createdDate: nil, crc: 0, isDirectory: true,
                            isEncrypted: false, method: "", attributes: 0, comment: ""
                        ))
                    }
                }
            } else if !relativePath.isEmpty {
                // Direct child file or folder
                if !entry.isDirectory || !seenDirs.contains(entry.name) {
                    displayItems.append(entry)
                    if entry.isDirectory { seenDirs.insert(entry.name) }
                }
            }
        }

        // Sort: folders first, then by name
        displayItems.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        archiveDisplayItems = displayItems

        // Update path field to show full path including archive
        updatePathField()

        // Update status bar
        let fileCount = displayItems.filter { !$0.isDirectory }.count
        let dirCount = displayItems.filter { $0.isDirectory }.count
        let totalSize = displayItems.filter { !$0.isDirectory }.reduce(UInt64(0)) { $0 + $1.size }
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
        statusLabel.stringValue = "\(fileCount) files, \(dirCount) folders — \(sizeStr)"

        tableView.reloadData()
    }
}

// MARK: - NSMenuDelegate (auto-select row on right-click)

extension FileManagerPaneController {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let clickedRow = tableView.clickedRow
        if clickedRow >= 0 && !tableView.selectedRowIndexes.contains(clickedRow) {
            tableView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }
    }
}

// MARK: - Context Menu

extension FileManagerPaneController {

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self  // auto-select row on right-click
        let items: [(String, Selector)] = [
            ("Open", #selector(openSelectedItem(_:))),
            ("Open in ShichiZip", #selector(openInArchiveViewer(_:))),
        ]
        for (title, action) in items {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (title, action) in [
            ("Compress...", #selector(compressSelected(_:))),
            ("Extract Here", #selector(extractHere(_:))),
        ] as [(String, Selector)] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (title, action) in [
            ("Rename", #selector(renameSelected(_:))),
            ("Delete", #selector(deleteSelected(_:))),
        ] as [(String, Selector)] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let cf = NSMenuItem(title: "Create Folder", action: #selector(createFolderFromMenu(_:)), keyEquivalent: "")
        cf.target = self
        menu.addItem(cf)
        menu.addItem(.separator())
        let pr = NSMenuItem(title: "Properties", action: #selector(showItemProperties(_:)), keyEquivalent: "")
        pr.target = self
        menu.addItem(pr)
        return menu
    }

    @objc private func openSelectedItem(_ sender: Any?) {
        doubleClickRow(nil)
    }

    @objc private func openInArchiveViewer(_ sender: Any?) {
        guard let path = selectedFilePaths().first else { return }
        delegate?.paneDidOpenArchive(path)
    }

    @objc private func compressSelected(_ sender: Any?) {
        // Forward to FileManagerWindowController
        if let wc = view.window?.windowController as? FileManagerWindowController {
            wc.addToArchive(nil)
        }
    }

    @objc private func extractHere(_ sender: Any?) {
        guard let path = selectedFilePaths().first else { return }
        guard FileSystemItem.archiveExtensions.contains(
            (path as NSString).pathExtension.lowercased()) else { return }

        let destURL = currentDirectory
        let progressController = ProgressDialogController()
        progressController.operationTitle = "Extracting..."
        view.window?.beginSheet(progressController.window!) { _ in }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let archive = SZArchive()
                try archive.open(atPath: path)
                let settings = SZExtractionSettings()
                settings.overwriteMode = .ask
                try archive.extract(toPath: destURL.path, settings: settings, progress: progressController)
                archive.close()
                DispatchQueue.main.async {
                    self?.view.window?.endSheet(progressController.window!)
                    self?.refresh()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.view.window?.endSheet(progressController.window!)
                    if let win = self?.view.window {
                        NSAlert(error: error).beginSheetModal(for: win)
                    }
                }
            }
        }
    }

    @objc private func renameSelected(_ sender: Any?) {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        let item = items[row]

        let alert = NSAlert()
        alert.messageText = "Rename"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = item.name
        alert.accessoryView = input
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: view.window!) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let newName = input.stringValue
            guard !newName.isEmpty, newName != item.name else { return }
            let newURL = item.url.deletingLastPathComponent().appendingPathComponent(newName)
            do {
                try FileManager.default.moveItem(at: item.url, to: newURL)
                self?.refresh()
            } catch {
                if let win = self?.view.window {
                    NSAlert(error: error).beginSheetModal(for: win)
                }
            }
        }
    }

    @objc private func deleteSelected(_ sender: Any?) {
        let paths = selectedFilePaths()
        guard !paths.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Delete \(paths.count) item(s)?"
        alert.informativeText = "Items will be moved to Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: view.window!) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            for path in paths {
                try? FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            }
            self?.refresh()
        }
    }

    @objc private func createFolderFromMenu(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Create Folder"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        input.placeholderString = "New Folder"
        alert.accessoryView = input
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: view.window!) { [weak self] response in
            guard response == .alertFirstButtonReturn, !input.stringValue.isEmpty else { return }
            self?.createFolder(named: input.stringValue)
        }
    }

    @objc private func showItemProperties(_ sender: Any?) {
        NSLog("[ShichiZip] showItemProperties called")
        guard let path = selectedFilePaths().first else {
            NSLog("[ShichiZip] no selection for properties")
            return
        }
        let url = URL(fileURLWithPath: path)
        let resourceValues = try? url.resourceValues(forKeys: [
            .fileSizeKey, .isDirectoryKey, .contentModificationDateKey,
            .creationDateKey, .fileResourceTypeKey
        ])

        let alert = NSAlert()
        alert.messageText = url.lastPathComponent
        let size = ByteCountFormatter.string(fromByteCount: Int64(resourceValues?.fileSize ?? 0), countStyle: .file)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .medium
        alert.informativeText = """
        Type: \(resourceValues?.isDirectory == true ? "Folder" : url.pathExtension.uppercased())
        Size: \(size)
        Modified: \(resourceValues?.contentModificationDate.map { dateFormatter.string(from: $0) } ?? "—")
        Created: \(resourceValues?.creationDate.map { dateFormatter.string(from: $0) } ?? "—")
        """
        alert.beginSheetModal(for: view.window!)
    }
}
