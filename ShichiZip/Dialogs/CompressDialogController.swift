import Cocoa

struct CompressDialogResult {
    let settings: SZCompressionSettings
    let archiveURL: URL
}

final class CompressDialogController: NSObject, NSTextFieldDelegate {

    private struct Option<Value: Equatable>: Equatable {
        let title: String
        let value: Value
    }

    private struct MethodOption: Equatable {
        let title: String
        let enumValue: SZCompressionMethod?
        let methodName: String
        let dictionaryLabel: String
        let dictionaryOptions: [Option<UInt64>]
        let wordLabel: String
        let wordOptions: [Option<UInt32>]
    }

    private struct FormatOption: Equatable {
        let title: String
        let codecName: String
        let format: SZArchiveFormat
        let defaultExtension: String
        let levelOptions: [Option<SZCompressionLevel>]
        let methods: [MethodOption]
        let supportsSolid: Bool
        let supportsThreads: Bool
        let encryptionOptions: [Option<SZEncryptionMethod>]
        let supportsEncryptFileNames: Bool
    }

    private enum ArchivePathHistory {
        private static let defaults = UserDefaults.standard
        private static let entriesKey = "FileManager.CompressArchivePathHistory"
        private static let maxEntries = 20

        static func entries() -> [String] {
            defaults.stringArray(forKey: entriesKey) ?? []
        }

        static func record(_ path: String) {
            let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            var updatedEntries = entries().filter { $0 != normalizedPath }
            updatedEntries.insert(normalizedPath, at: 0)
            if updatedEntries.count > maxEntries {
                updatedEntries.removeSubrange(maxEntries..<updatedEntries.count)
            }
            defaults.set(updatedEntries, forKey: entriesKey)
        }
    }

    private enum DialogPreferences {
        private static let defaults = UserDefaults.standard
        private static let formatKey = "FileManager.CompressFormat"
        private static let updateModeKey = "FileManager.CompressUpdateMode"
        private static let pathModeKey = "FileManager.CompressPathMode"
        private static let openSharedKey = "FileManager.CompressOpenSharedFiles"
        private static let deleteAfterKey = "FileManager.CompressDeleteAfter"
        private static let encryptNamesKey = "FileManager.CompressEncryptNames"
        private static let showPasswordKey = "FileManager.CompressShowPassword"

        static func format(defaultValue: String,
                           allowedValues: [String]) -> String {
            guard let value = defaults.string(forKey: formatKey),
                  allowedValues.contains(value) else {
                return defaultValue
            }
            return value
        }

        static func updateMode(defaultValue: SZCompressionUpdateMode) -> SZCompressionUpdateMode {
            guard let rawValue = defaults.object(forKey: updateModeKey) as? Int,
                  let value = SZCompressionUpdateMode(rawValue: rawValue) else {
                return defaultValue
            }
            return value
        }

        static func pathMode(defaultValue: SZCompressionPathMode) -> SZCompressionPathMode {
            guard let rawValue = defaults.object(forKey: pathModeKey) as? Int,
                  let value = SZCompressionPathMode(rawValue: rawValue) else {
                return defaultValue
            }
            return value
        }

        static func openSharedFiles() -> Bool {
            defaults.bool(forKey: openSharedKey)
        }

        static func deleteAfterCompression() -> Bool {
            defaults.bool(forKey: deleteAfterKey)
        }

        static func encryptNames() -> Bool {
            defaults.bool(forKey: encryptNamesKey)
        }

        static func showPassword() -> Bool {
            defaults.bool(forKey: showPasswordKey)
        }

        static func record(format: String,
                           updateMode: SZCompressionUpdateMode,
                           pathMode: SZCompressionPathMode,
                           openSharedFiles: Bool,
                           deleteAfterCompression: Bool,
                           encryptNames: Bool,
                           showPassword: Bool) {
            defaults.set(format, forKey: formatKey)
            defaults.set(updateMode.rawValue, forKey: updateModeKey)
            defaults.set(pathMode.rawValue, forKey: pathModeKey)
            defaults.set(openSharedFiles, forKey: openSharedKey)
            defaults.set(deleteAfterCompression, forKey: deleteAfterKey)
            defaults.set(encryptNames, forKey: encryptNamesKey)
            defaults.set(showPassword, forKey: showPasswordKey)
        }
    }

    private final class ArchivePathPicker: NSObject {
        private weak var ownerWindow: NSWindow?
        private weak var pathField: NSComboBox?
        private let baseDirectory: URL
        private let defaultFileNameProvider: () -> String

        init(ownerWindow: NSWindow?,
             pathField: NSComboBox,
             baseDirectory: URL,
             defaultFileNameProvider: @escaping () -> String) {
            self.ownerWindow = ownerWindow
            self.pathField = pathField
            self.baseDirectory = baseDirectory.standardizedFileURL
            self.defaultFileNameProvider = defaultFileNameProvider
        }

        @objc func browse(_ sender: Any?) {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.directoryURL = suggestedDirectoryURL()
            panel.nameFieldStringValue = suggestedFileName()

            if let ownerWindow {
                panel.beginSheetModal(for: ownerWindow) { [weak self] response in
                    guard response == .OK, let url = panel.url else { return }
                    self?.pathField?.stringValue = url.standardizedFileURL.path
                }
                return
            }

            guard panel.runModal() == .OK, let url = panel.url else { return }
            pathField?.stringValue = url.standardizedFileURL.path
        }

        private func suggestedDirectoryURL() -> URL {
            guard let pathField else {
                return baseDirectory
            }

            let currentValue = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !currentValue.isEmpty else {
                return baseDirectory
            }

            let expandedPath = NSString(string: currentValue).expandingTildeInPath
            let candidateURL: URL
            if NSString(string: expandedPath).isAbsolutePath {
                candidateURL = URL(fileURLWithPath: expandedPath)
            } else {
                candidateURL = URL(fileURLWithPath: expandedPath, relativeTo: baseDirectory)
            }

            let standardizedURL = candidateURL.standardizedFileURL
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory) {
                return isDirectory.boolValue ? standardizedURL : standardizedURL.deletingLastPathComponent()
            }
            return standardizedURL.deletingLastPathComponent()
        }

        private func suggestedFileName() -> String {
            guard let pathField else {
                return defaultFileNameProvider()
            }

            let currentValue = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !currentValue.isEmpty else {
                return defaultFileNameProvider()
            }

            let expandedPath = NSString(string: currentValue).expandingTildeInPath
            return URL(fileURLWithPath: expandedPath).lastPathComponent
        }
    }

    private static let knownArchiveExtensions: Set<String> = ["7z", "zip", "tar", "gz", "gzip", "bz2", "bzip2", "xz", "wim", "zst", "zstd"]
    private static let formLabelWidth: CGFloat = 126
    private static let leftColumnWidth: CGFloat = 320
    private static let rightColumnWidth: CGFloat = 364
    private static let columnSpacing: CGFloat = 20

    private static let levelOptions: [Option<SZCompressionLevel>] = [
        Option(title: "Store", value: .store),
        Option(title: "Fastest", value: .fastest),
        Option(title: "Fast", value: .fast),
        Option(title: "Normal", value: .normal),
        Option(title: "Maximum", value: .maximum),
        Option(title: "Ultra", value: .ultra),
    ]

    private static let storeOnlyLevelOptions: [Option<SZCompressionLevel>] = [
        Option(title: "Store", value: .store)
    ]

    private static let standardDictionaryOptions: [Option<UInt64>] = [
        Option(title: "Auto", value: 0),
        Option(title: "64 KB", value: 64 * 1024),
        Option(title: "256 KB", value: 256 * 1024),
        Option(title: "1 MB", value: 1 << 20),
        Option(title: "4 MB", value: 4 << 20),
        Option(title: "8 MB", value: 8 << 20),
        Option(title: "16 MB", value: 16 << 20),
        Option(title: "32 MB", value: 32 << 20),
        Option(title: "64 MB", value: 64 << 20),
        Option(title: "128 MB", value: 128 << 20),
        Option(title: "256 MB", value: 256 << 20),
    ]

    private static let ppmdDictionaryOptions: [Option<UInt64>] = [
        Option(title: "Auto", value: 0),
        Option(title: "1 MB", value: 1 << 20),
        Option(title: "2 MB", value: 2 << 20),
        Option(title: "4 MB", value: 4 << 20),
        Option(title: "8 MB", value: 8 << 20),
        Option(title: "16 MB", value: 16 << 20),
        Option(title: "32 MB", value: 32 << 20),
        Option(title: "64 MB", value: 64 << 20),
        Option(title: "128 MB", value: 128 << 20),
        Option(title: "256 MB", value: 256 << 20),
    ]

    private static let standardWordOptions: [Option<UInt32>] = [
        Option(title: "Auto", value: 0),
        Option(title: "8", value: 8),
        Option(title: "12", value: 12),
        Option(title: "16", value: 16),
        Option(title: "24", value: 24),
        Option(title: "32", value: 32),
        Option(title: "48", value: 48),
        Option(title: "64", value: 64),
        Option(title: "96", value: 96),
        Option(title: "128", value: 128),
        Option(title: "192", value: 192),
        Option(title: "256", value: 256),
        Option(title: "273", value: 273),
    ]

    private static let orderOptions: [Option<UInt32>] =
        [Option(title: "Auto", value: 0)] + (2...32).map { Option(title: "\($0)", value: UInt32($0)) }

    private static let updateModeOptions: [Option<SZCompressionUpdateMode>] = [
        Option(title: "Add and replace files", value: .add),
        Option(title: "Update and add files", value: .update),
        Option(title: "Freshen existing files", value: .fresh),
        Option(title: "Synchronize files", value: .sync),
    ]

    private static let pathModeOptions: [Option<SZCompressionPathMode>] = [
        Option(title: "Relative paths", value: .relativePaths),
        Option(title: "Full paths", value: .fullPaths),
        Option(title: "Absolute paths", value: .absolutePaths),
    ]

    private static let solidOptions: [Option<Bool>] = [
        Option(title: "Non-solid", value: false),
        Option(title: "Solid", value: true),
    ]

    private static let splitVolumePresets = [
        "10M",
        "100M",
        "1000M",
        "650M - CD",
        "700M - CD",
        "4092M - FAT",
        "4480M - DVD",
        "8128M - DVD DL",
        "23040M - BD",
    ]

    private static let sevenZipMethods: [MethodOption] = [
        MethodOption(title: "LZMA2", enumValue: .LZMA2, methodName: "LZMA2", dictionaryLabel: "Dictionary size:", dictionaryOptions: standardDictionaryOptions, wordLabel: "Word size:", wordOptions: standardWordOptions),
        MethodOption(title: "LZMA", enumValue: .LZMA, methodName: "LZMA", dictionaryLabel: "Dictionary size:", dictionaryOptions: standardDictionaryOptions, wordLabel: "Word size:", wordOptions: standardWordOptions),
        MethodOption(title: "PPMd", enumValue: .ppMd, methodName: "PPMd", dictionaryLabel: "Memory usage:", dictionaryOptions: ppmdDictionaryOptions, wordLabel: "Order:", wordOptions: orderOptions),
        MethodOption(title: "BZip2", enumValue: .bZip2, methodName: "BZip2", dictionaryLabel: "Dictionary size:", dictionaryOptions: standardDictionaryOptions, wordLabel: "Word size:", wordOptions: standardWordOptions),
        MethodOption(title: "Deflate", enumValue: .deflate, methodName: "Deflate", dictionaryLabel: "Dictionary size:", dictionaryOptions: standardDictionaryOptions, wordLabel: "Word size:", wordOptions: standardWordOptions),
        MethodOption(title: "Deflate64", enumValue: .deflate64, methodName: "Deflate64", dictionaryLabel: "Dictionary size:", dictionaryOptions: standardDictionaryOptions, wordLabel: "Word size:", wordOptions: standardWordOptions),
        MethodOption(title: "Copy", enumValue: .copy, methodName: "Copy", dictionaryLabel: "Dictionary size:", dictionaryOptions: [], wordLabel: "Word size:", wordOptions: []),
    ]

    private static let zipMethods: [MethodOption] = [
        MethodOption(title: "Deflate", enumValue: .deflate, methodName: "Deflate", dictionaryLabel: "Dictionary size:", dictionaryOptions: standardDictionaryOptions, wordLabel: "Word size:", wordOptions: standardWordOptions),
        MethodOption(title: "Deflate64", enumValue: .deflate64, methodName: "Deflate64", dictionaryLabel: "Dictionary size:", dictionaryOptions: standardDictionaryOptions, wordLabel: "Word size:", wordOptions: standardWordOptions),
        MethodOption(title: "BZip2", enumValue: .bZip2, methodName: "BZip2", dictionaryLabel: "Dictionary size:", dictionaryOptions: standardDictionaryOptions, wordLabel: "Word size:", wordOptions: standardWordOptions),
        MethodOption(title: "LZMA", enumValue: .LZMA, methodName: "LZMA", dictionaryLabel: "Dictionary size:", dictionaryOptions: standardDictionaryOptions, wordLabel: "Word size:", wordOptions: standardWordOptions),
        MethodOption(title: "PPMd", enumValue: .ppMd, methodName: "PPMd", dictionaryLabel: "Memory usage:", dictionaryOptions: ppmdDictionaryOptions, wordLabel: "Order:", wordOptions: orderOptions),
    ]

    private static let gzipMethods: [MethodOption] = [
        MethodOption(title: "Deflate", enumValue: .deflate, methodName: "Deflate", dictionaryLabel: "Dictionary size:", dictionaryOptions: standardDictionaryOptions, wordLabel: "Word size:", wordOptions: standardWordOptions),
    ]

    private static let bzip2Methods: [MethodOption] = [
        MethodOption(title: "BZip2", enumValue: .bZip2, methodName: "BZip2", dictionaryLabel: "Dictionary size:", dictionaryOptions: standardDictionaryOptions, wordLabel: "Word size:", wordOptions: standardWordOptions),
    ]

    private static let xzMethods: [MethodOption] = [
        MethodOption(title: "LZMA2", enumValue: .LZMA2, methodName: "LZMA2", dictionaryLabel: "Dictionary size:", dictionaryOptions: standardDictionaryOptions, wordLabel: "Word size:", wordOptions: standardWordOptions),
    ]

    private static let tarMethods: [MethodOption] = [
        MethodOption(title: "GNU", enumValue: nil, methodName: "GNU", dictionaryLabel: "Dictionary size:", dictionaryOptions: [], wordLabel: "Word size:", wordOptions: []),
        MethodOption(title: "POSIX", enumValue: nil, methodName: "POSIX", dictionaryLabel: "Dictionary size:", dictionaryOptions: [], wordLabel: "Word size:", wordOptions: []),
    ]

    private static let zstdMethods: [MethodOption] = [
        MethodOption(title: "ZSTD", enumValue: nil, methodName: "ZSTD", dictionaryLabel: "Dictionary size:", dictionaryOptions: standardDictionaryOptions, wordLabel: "Word size:", wordOptions: []),
    ]

    private static let formatCatalog: [FormatOption] = [
        FormatOption(title: "7z", codecName: "7z", format: .format7z, defaultExtension: "7z", levelOptions: levelOptions, methods: sevenZipMethods, supportsSolid: true, supportsThreads: true, encryptionOptions: [Option(title: "AES-256", value: .AES256)], supportsEncryptFileNames: true),
        FormatOption(title: "zip", codecName: "zip", format: .formatZip, defaultExtension: "zip", levelOptions: levelOptions, methods: zipMethods, supportsSolid: false, supportsThreads: true, encryptionOptions: [Option(title: "ZipCrypto", value: .zipCrypto), Option(title: "AES-256", value: .AES256)], supportsEncryptFileNames: false),
        FormatOption(title: "tar", codecName: "tar", format: .formatTar, defaultExtension: "tar", levelOptions: storeOnlyLevelOptions, methods: tarMethods, supportsSolid: false, supportsThreads: false, encryptionOptions: [], supportsEncryptFileNames: false),
        FormatOption(title: "gzip", codecName: "gzip", format: .formatGZip, defaultExtension: "gz", levelOptions: levelOptions, methods: gzipMethods, supportsSolid: false, supportsThreads: false, encryptionOptions: [], supportsEncryptFileNames: false),
        FormatOption(title: "bzip2", codecName: "bzip2", format: .formatBZip2, defaultExtension: "bz2", levelOptions: levelOptions, methods: bzip2Methods, supportsSolid: false, supportsThreads: true, encryptionOptions: [], supportsEncryptFileNames: false),
        FormatOption(title: "xz", codecName: "xz", format: .formatXz, defaultExtension: "xz", levelOptions: levelOptions, methods: xzMethods, supportsSolid: true, supportsThreads: true, encryptionOptions: [], supportsEncryptFileNames: false),
        FormatOption(title: "wim", codecName: "wim", format: .formatWim, defaultExtension: "wim", levelOptions: storeOnlyLevelOptions, methods: [], supportsSolid: false, supportsThreads: false, encryptionOptions: [], supportsEncryptFileNames: false),
        FormatOption(title: "zstd", codecName: "zstd", format: .formatZstd, defaultExtension: "zst", levelOptions: levelOptions, methods: zstdMethods, supportsSolid: false, supportsThreads: true, encryptionOptions: [], supportsEncryptFileNames: false),
    ]

    private let sourceURLs: [URL]
    private let baseDirectory: URL
    private let messageText: String?
    private let suggestedBaseName: String
    private let availableFormats: [FormatOption]

    private var archivePathPicker: ArchivePathPicker?
    private weak var currentDialogWindow: NSWindow?
    private weak var archivePathField: NSComboBox?
    private weak var formatPopup: NSPopUpButton?
    private weak var levelPopup: NSPopUpButton?
    private weak var methodPopup: NSPopUpButton?
    private weak var dictionaryPopup: NSPopUpButton?
    private weak var wordPopup: NSPopUpButton?
    private weak var solidPopup: NSPopUpButton?
    private weak var threadField: NSComboBox?
    private weak var splitVolumesField: NSComboBox?
    private weak var parametersField: NSTextField?
    private weak var updateModePopup: NSPopUpButton?
    private weak var pathModePopup: NSPopUpButton?
    private weak var encryptionPopup: NSPopUpButton?
    private weak var encryptNamesCheckbox: NSButton?
    private weak var openSharedCheckbox: NSButton?
    private weak var deleteAfterCheckbox: NSButton?
    private weak var dictionaryLabel: NSTextField?
    private weak var wordLabel: NSTextField?
    private weak var securePasswordField: NSSecureTextField?
    private weak var plainPasswordField: NSTextField?
    private weak var secureConfirmPasswordField: NSSecureTextField?
    private weak var plainConfirmPasswordField: NSTextField?
    private weak var showPasswordCheckbox: NSButton?

    init(sourceURLs: [URL],
         baseDirectory: URL? = nil,
         message: String? = nil) {
        let normalizedSourceURLs = sourceURLs.map { $0.standardizedFileURL }
        let resolvedBaseDirectory = (baseDirectory ?? Self.suggestedBaseDirectory(for: normalizedSourceURLs)).standardizedFileURL

        self.sourceURLs = normalizedSourceURLs
        self.baseDirectory = resolvedBaseDirectory
        self.suggestedBaseName = Self.suggestedArchiveBaseName(for: normalizedSourceURLs,
                                                               baseDirectory: resolvedBaseDirectory)
        self.availableFormats = Self.makeAvailableFormats()
        self.messageText = message ?? Self.defaultMessage(for: normalizedSourceURLs,
                                                          baseDirectory: resolvedBaseDirectory)

        super.init()
    }

    func runModal(for parentWindow: NSWindow?) -> CompressDialogResult? {
        guard !availableFormats.isEmpty else {
            szPresentMessage(title: "No Archive Formats Available",
                             message: "7-Zip did not report any writable archive formats.",
                             style: .warning,
                             for: parentWindow)
            return nil
        }

        let allowedFormats = availableFormats.map(\.codecName)
        var selectedFormatName = DialogPreferences.format(defaultValue: availableFormats[0].codecName,
                                                          allowedValues: allowedFormats)
        var selectedUpdateMode = DialogPreferences.updateMode(defaultValue: .add)
        var selectedPathMode = DialogPreferences.pathMode(defaultValue: .relativePaths)
        var openSharedFiles = DialogPreferences.openSharedFiles()
        var deleteAfterCompression = DialogPreferences.deleteAfterCompression()
        var encryptNames = DialogPreferences.encryptNames()
        var showPassword = DialogPreferences.showPassword()
        var selectedArchivePath = defaultArchiveURL(for: selectedFormatName).path
        var selectedLevel = defaultLevel(for: selectedFormatName)
        var selectedMethodName = defaultMethodName(for: selectedFormatName)
        var selectedDictionarySize: UInt64 = 0
        var selectedWordSize: UInt32 = 0
        var selectedSolidMode = true
        var selectedThreadText = "Auto"
        var selectedSplitVolumes = ""
        var selectedParameters = ""
        var selectedPassword = ""
        var selectedConfirmation = ""
        var selectedEncryption = defaultEncryption(for: selectedFormatName)

        while true {
            let archivePathField = NSComboBox(frame: NSRect(x: 0, y: 0, width: 360, height: 26))
            archivePathField.usesDataSource = false
            archivePathField.completes = false
            archivePathField.isEditable = true
            archivePathField.addItems(withObjectValues: ArchivePathHistory.entries())
            archivePathField.stringValue = selectedArchivePath
            archivePathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true

            let browseButton = NSButton(title: "Browse...", target: nil, action: nil)
            browseButton.bezelStyle = .rounded

            let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
            availableFormats.forEach { formatPopup.addItem(withTitle: $0.title) }
            if let selectedIndex = availableFormats.firstIndex(where: { $0.codecName == selectedFormatName }) {
                formatPopup.selectItem(at: selectedIndex)
            }
            formatPopup.target = self
            formatPopup.action = #selector(formatChanged(_:))

            let levelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
            let methodPopup = NSPopUpButton(frame: .zero, pullsDown: false)
            methodPopup.target = self
            methodPopup.action = #selector(methodChanged(_:))
            let dictionaryPopup = NSPopUpButton(frame: .zero, pullsDown: false)
            let wordPopup = NSPopUpButton(frame: .zero, pullsDown: false)

            let solidPopup = NSPopUpButton(frame: .zero, pullsDown: false)
            Self.solidOptions.forEach { solidPopup.addItem(withTitle: $0.title) }

            let threadField = NSComboBox(frame: NSRect(x: 0, y: 0, width: 140, height: 26))
            threadField.usesDataSource = false
            threadField.completes = false
            threadField.isEditable = true
            threadField.addItems(withObjectValues: ["Auto"] + Self.threadChoices())
            threadField.stringValue = selectedThreadText

            let splitVolumesField = NSComboBox(frame: NSRect(x: 0, y: 0, width: 180, height: 26))
            splitVolumesField.usesDataSource = false
            splitVolumesField.completes = false
            splitVolumesField.isEditable = true
            splitVolumesField.addItems(withObjectValues: Self.splitVolumePresets)
            splitVolumesField.stringValue = selectedSplitVolumes

            let parametersField = NSTextField(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
            parametersField.stringValue = selectedParameters
            parametersField.placeholderString = "e.g. d=64m fb=273"

            let updateModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
            Self.updateModeOptions.forEach { updateModePopup.addItem(withTitle: $0.title) }
            if let selectedIndex = Self.updateModeOptions.firstIndex(where: { $0.value == selectedUpdateMode }) {
                updateModePopup.selectItem(at: selectedIndex)
            }

            let pathModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
            Self.pathModeOptions.forEach { pathModePopup.addItem(withTitle: $0.title) }
            if let selectedIndex = Self.pathModeOptions.firstIndex(where: { $0.value == selectedPathMode }) {
                pathModePopup.selectItem(at: selectedIndex)
            }

            let openSharedCheckbox = NSButton(checkboxWithTitle: "Compress shared files", target: nil, action: nil)
            openSharedCheckbox.state = openSharedFiles ? .on : .off
            let deleteAfterCheckbox = NSButton(checkboxWithTitle: "Delete files after compression", target: nil, action: nil)
            deleteAfterCheckbox.state = deleteAfterCompression ? .on : .off

            let encryptionPopup = NSPopUpButton(frame: .zero, pullsDown: false)

            let securePasswordField = NSSecureTextField(frame: .zero)
            securePasswordField.stringValue = selectedPassword
            securePasswordField.placeholderString = "Optional"
            securePasswordField.delegate = self

            let plainPasswordField = NSTextField(frame: .zero)
            plainPasswordField.stringValue = selectedPassword
            plainPasswordField.placeholderString = "Optional"
            plainPasswordField.delegate = self

            let secureConfirmPasswordField = NSSecureTextField(frame: .zero)
            secureConfirmPasswordField.stringValue = selectedConfirmation
            secureConfirmPasswordField.placeholderString = "Retype password"
            secureConfirmPasswordField.delegate = self

            let plainConfirmPasswordField = NSTextField(frame: .zero)
            plainConfirmPasswordField.stringValue = selectedConfirmation
            plainConfirmPasswordField.placeholderString = "Retype password"
            plainConfirmPasswordField.delegate = self

            let passwordContainer = makePasswordContainer(secureField: securePasswordField,
                                                          plainField: plainPasswordField)
            let confirmPasswordContainer = makePasswordContainer(secureField: secureConfirmPasswordField,
                                                                 plainField: plainConfirmPasswordField)

            let showPasswordCheckbox = NSButton(checkboxWithTitle: "Show password",
                                                target: self,
                                                action: #selector(showPasswordToggled(_:)))
            showPasswordCheckbox.state = showPassword ? .on : .off

            let encryptNamesCheckbox = NSButton(checkboxWithTitle: "Encrypt file names",
                                                target: nil,
                                                action: nil)
            encryptNamesCheckbox.state = encryptNames ? .on : .off

            let dictionaryLabel = NSTextField(labelWithString: "Dictionary size:")
            let wordLabel = NSTextField(labelWithString: "Word size:")

            let archivePathRow = makePathRow(label: "Archive:",
                                             pathField: archivePathField,
                                             browseButton: browseButton)

            let leftColumn = makeColumn(rows: [
                makeFormRow(label: "Archive format:", control: formatPopup),
                makeFormRow(label: "Compression level:", control: levelPopup),
                makeFormRow(label: "Compression method:", control: methodPopup),
                makeFormRow(labelField: dictionaryLabel, control: dictionaryPopup),
                makeFormRow(labelField: wordLabel, control: wordPopup),
                makeFormRow(label: "Solid block size:", control: solidPopup),
                makeFormRow(label: "CPU threads:", control: threadField),
                makeFormRow(label: "Split to volumes:", control: splitVolumesField),
                makeFormRow(label: "Parameters:", control: parametersField),
            ])

            let optionsColumn = makeTitledSection(title: "Options", rows: [
                openSharedCheckbox,
                deleteAfterCheckbox,
            ])

            let encryptionColumn = makeTitledSection(title: "Encryption", rows: [
                makeFormRow(label: "Password:", control: passwordContainer),
                makeFormRow(label: "Retype password:", control: confirmPasswordContainer),
                showPasswordCheckbox,
                makeFormRow(label: "Encryption method:", control: encryptionPopup),
                encryptNamesCheckbox,
            ])

            let rightColumn = makeColumn(rows: [
                makeFormRow(label: "Update mode:", control: updateModePopup),
                makeFormRow(label: "Path mode:", control: pathModePopup),
                optionsColumn,
                encryptionColumn,
            ])

            leftColumn.widthAnchor.constraint(equalToConstant: Self.leftColumnWidth).isActive = true
            rightColumn.widthAnchor.constraint(equalToConstant: Self.rightColumnWidth).isActive = true
            optionsColumn.widthAnchor.constraint(equalTo: rightColumn.widthAnchor).isActive = true
            encryptionColumn.widthAnchor.constraint(equalTo: rightColumn.widthAnchor).isActive = true

            let columns = NSStackView(views: [leftColumn, rightColumn])
            columns.orientation = .horizontal
            columns.alignment = .top
            columns.distribution = .fill
            columns.spacing = Self.columnSpacing
            columns.widthAnchor.constraint(equalToConstant: Self.leftColumnWidth + Self.rightColumnWidth + Self.columnSpacing).isActive = true

            let accessoryView = NSStackView(views: [archivePathRow, columns])
            accessoryView.orientation = .vertical
            accessoryView.alignment = .leading
            accessoryView.spacing = 16
            accessoryView.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

            let controller = SZModalDialogController(style: .informational,
                                                     title: "Add to Archive",
                                                     message: messageText,
                                                     buttonTitles: ["Cancel", "OK"],
                                                     accessoryView: accessoryView,
                                                     preferredFirstResponder: archivePathField,
                                                     cancelButtonIndex: 0)
            currentDialogWindow = controller.window
            self.archivePathField = archivePathField
            self.formatPopup = formatPopup
            self.levelPopup = levelPopup
            self.methodPopup = methodPopup
            self.dictionaryPopup = dictionaryPopup
            self.wordPopup = wordPopup
            self.solidPopup = solidPopup
            self.threadField = threadField
            self.splitVolumesField = splitVolumesField
            self.parametersField = parametersField
            self.updateModePopup = updateModePopup
            self.pathModePopup = pathModePopup
            self.encryptionPopup = encryptionPopup
            self.encryptNamesCheckbox = encryptNamesCheckbox
            self.openSharedCheckbox = openSharedCheckbox
            self.deleteAfterCheckbox = deleteAfterCheckbox
            self.dictionaryLabel = dictionaryLabel
            self.wordLabel = wordLabel
            self.securePasswordField = securePasswordField
            self.plainPasswordField = plainPasswordField
            self.secureConfirmPasswordField = secureConfirmPasswordField
            self.plainConfirmPasswordField = plainConfirmPasswordField
            self.showPasswordCheckbox = showPasswordCheckbox

            reloadFormatDependentControls(preferredLevel: selectedLevel,
                                          preferredMethodName: selectedMethodName,
                                          preferredDictionarySize: selectedDictionarySize,
                                          preferredWordSize: selectedWordSize,
                                          preferredEncryption: selectedEncryption)
            selectOption(Self.solidOptions, selectedValue: selectedSolidMode, on: solidPopup)
            updatePasswordVisibilityUI(moveFocus: false)
            refreshOptionAvailability()

            let picker = ArchivePathPicker(ownerWindow: controller.window,
                                           pathField: archivePathField,
                                           baseDirectory: baseDirectory) { [weak self] in
                self?.suggestedArchiveFileName() ?? "Archive.7z"
            }
            archivePathPicker = picker
            browseButton.target = picker
            browseButton.action = #selector(ArchivePathPicker.browse(_:))

            defer {
                archivePathPicker = nil
                currentDialogWindow = nil
                self.archivePathField = nil
                self.formatPopup = nil
                self.levelPopup = nil
                self.methodPopup = nil
                self.dictionaryPopup = nil
                self.wordPopup = nil
                self.solidPopup = nil
                self.threadField = nil
                self.splitVolumesField = nil
                self.parametersField = nil
                self.updateModePopup = nil
                self.pathModePopup = nil
                self.encryptionPopup = nil
                self.encryptNamesCheckbox = nil
                self.openSharedCheckbox = nil
                self.deleteAfterCheckbox = nil
                self.dictionaryLabel = nil
                self.wordLabel = nil
                self.securePasswordField = nil
                self.plainPasswordField = nil
                self.secureConfirmPasswordField = nil
                self.plainConfirmPasswordField = nil
                self.showPasswordCheckbox = nil
            }

            guard controller.runModal() == 1 else {
                return nil
            }

            syncPasswordFields()
            selectedArchivePath = archivePathField.stringValue
            selectedFormatName = selectedFormatOption()?.codecName ?? selectedFormatName
            selectedLevel = selectedLevelOption()?.value ?? selectedLevel
            selectedMethodName = selectedMethodOption()?.methodName ?? ""
            selectedDictionarySize = selectedDictionaryOption()?.value ?? 0
            selectedWordSize = selectedWordOption()?.value ?? 0
            selectedSolidMode = selectedSolidOption()?.value ?? selectedSolidMode
            selectedThreadText = threadField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            selectedSplitVolumes = splitVolumesField.stringValue
            selectedParameters = parametersField.stringValue
            selectedPassword = currentPasswordValue()
            selectedConfirmation = currentConfirmationValue()
            showPassword = showPasswordCheckbox.state == .on
            selectedUpdateMode = selectedUpdateModeOption()?.value ?? selectedUpdateMode
            selectedPathMode = selectedPathModeOption()?.value ?? selectedPathMode
            selectedEncryption = selectedEncryptionOption()?.value ?? .none
            encryptNames = encryptNamesCheckbox.state == .on
            openSharedFiles = openSharedCheckbox.state == .on
            deleteAfterCompression = deleteAfterCheckbox.state == .on

            do {
                let result = try buildResult(archivePath: selectedArchivePath,
                                             format: selectedFormatOption() ?? availableFormats[0],
                                             level: selectedLevel,
                                             method: selectedMethodOption(),
                                             dictionarySize: selectedDictionarySize,
                                             wordSize: selectedWordSize,
                                             solidMode: selectedSolidMode,
                                             threadText: selectedThreadText,
                                             splitVolumes: selectedSplitVolumes,
                                             parameters: selectedParameters,
                                             updateMode: selectedUpdateMode,
                                             pathMode: selectedPathMode,
                                             encryption: selectedEncryption,
                                             password: selectedPassword,
                                             confirmation: selectedConfirmation,
                                             encryptNames: encryptNames,
                                             openSharedFiles: openSharedFiles,
                                             deleteAfterCompression: deleteAfterCompression)
                ArchivePathHistory.record(result.archiveURL.path)
                DialogPreferences.record(format: selectedFormatName,
                                         updateMode: selectedUpdateMode,
                                         pathMode: selectedPathMode,
                                         openSharedFiles: openSharedFiles,
                                         deleteAfterCompression: deleteAfterCompression,
                                         encryptNames: encryptNames,
                                         showPassword: showPassword)
                return result
            } catch {
                szPresentError(error, for: parentWindow)
            }
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }

        if field === securePasswordField || field === plainPasswordField {
            securePasswordField?.stringValue = field.stringValue
            plainPasswordField?.stringValue = field.stringValue
        } else if field === secureConfirmPasswordField || field === plainConfirmPasswordField {
            secureConfirmPasswordField?.stringValue = field.stringValue
            plainConfirmPasswordField?.stringValue = field.stringValue
        }

        refreshOptionAvailability()
    }

    @objc private func formatChanged(_ sender: Any?) {
        let preferredLevel = selectedLevelOption()?.value
        let preferredMethodName = selectedMethodOption()?.methodName
        let preferredDictionarySize = selectedDictionaryOption()?.value
        let preferredWordSize = selectedWordOption()?.value
        let preferredEncryption = selectedEncryptionOption()?.value

        updateArchivePathExtension()
        reloadFormatDependentControls(preferredLevel: preferredLevel,
                                      preferredMethodName: preferredMethodName,
                                      preferredDictionarySize: preferredDictionarySize,
                                      preferredWordSize: preferredWordSize,
                                      preferredEncryption: preferredEncryption)
    }

    @objc private func methodChanged(_ sender: Any?) {
        let preferredDictionarySize = selectedDictionaryOption()?.value
        let preferredWordSize = selectedWordOption()?.value
        reloadMethodDependentControls(preferredDictionarySize: preferredDictionarySize,
                                      preferredWordSize: preferredWordSize)
    }

    @objc private func showPasswordToggled(_ sender: Any?) {
        syncPasswordFields()
        updatePasswordVisibilityUI(moveFocus: true)
        refreshOptionAvailability()
    }

    private func reloadFormatDependentControls(preferredLevel: SZCompressionLevel?,
                                               preferredMethodName: String?,
                                               preferredDictionarySize: UInt64?,
                                               preferredWordSize: UInt32?,
                                               preferredEncryption: SZEncryptionMethod?) {
        guard let format = selectedFormatOption() else { return }

        populate(levelPopup, with: format.levelOptions.map(\.title))
        if let preferredLevel,
           let selectedIndex = format.levelOptions.firstIndex(where: { $0.value == preferredLevel }) {
            levelPopup?.selectItem(at: selectedIndex)
        } else {
            levelPopup?.selectItem(at: defaultLevelIndex(for: format))
        }

        if format.methods.isEmpty {
            populate(methodPopup, with: ["Default"])
            methodPopup?.selectItem(at: 0)
        } else {
            populate(methodPopup, with: format.methods.map(\.title))
            if let preferredMethodName,
               let selectedIndex = format.methods.firstIndex(where: { $0.methodName == preferredMethodName }) {
                methodPopup?.selectItem(at: selectedIndex)
            } else {
                methodPopup?.selectItem(at: 0)
            }
        }

        if format.encryptionOptions.isEmpty {
            populate(encryptionPopup, with: ["Not available"])
            encryptionPopup?.selectItem(at: 0)
        } else {
            populate(encryptionPopup, with: format.encryptionOptions.map(\.title))
            if let preferredEncryption,
               let selectedIndex = format.encryptionOptions.firstIndex(where: { $0.value == preferredEncryption }) {
                encryptionPopup?.selectItem(at: selectedIndex)
            } else {
                encryptionPopup?.selectItem(at: 0)
            }
        }

        reloadMethodDependentControls(preferredDictionarySize: preferredDictionarySize,
                                      preferredWordSize: preferredWordSize)
        refreshOptionAvailability()
    }

    private func reloadMethodDependentControls(preferredDictionarySize: UInt64?,
                                               preferredWordSize: UInt32?) {
        let method = selectedMethodOption()
        dictionaryLabel?.stringValue = method?.dictionaryLabel ?? "Dictionary size:"
        wordLabel?.stringValue = method?.wordLabel ?? "Word size:"

        let dictionaryOptions = method?.dictionaryOptions ?? []
        if dictionaryOptions.isEmpty {
            populate(dictionaryPopup, with: ["Auto"])
            dictionaryPopup?.selectItem(at: 0)
        } else {
            populate(dictionaryPopup, with: dictionaryOptions.map(\.title))
            if let preferredDictionarySize,
               let selectedIndex = dictionaryOptions.firstIndex(where: { $0.value == preferredDictionarySize }) {
                dictionaryPopup?.selectItem(at: selectedIndex)
            } else {
                dictionaryPopup?.selectItem(at: 0)
            }
        }

        let wordOptions = method?.wordOptions ?? []
        if wordOptions.isEmpty {
            populate(wordPopup, with: ["Auto"])
            wordPopup?.selectItem(at: 0)
        } else {
            populate(wordPopup, with: wordOptions.map(\.title))
            if let preferredWordSize,
               let selectedIndex = wordOptions.firstIndex(where: { $0.value == preferredWordSize }) {
                wordPopup?.selectItem(at: selectedIndex)
            } else {
                wordPopup?.selectItem(at: 0)
            }
        }

        refreshOptionAvailability()
    }

    private func refreshOptionAvailability() {
        guard let format = selectedFormatOption() else { return }

        levelPopup?.isEnabled = format.levelOptions.count > 1
        methodPopup?.isEnabled = !format.methods.isEmpty
        dictionaryPopup?.isEnabled = !(selectedMethodOption()?.dictionaryOptions.isEmpty ?? true)
        wordPopup?.isEnabled = !(selectedMethodOption()?.wordOptions.isEmpty ?? true)
        solidPopup?.isEnabled = format.supportsSolid
        threadField?.isEnabled = format.supportsThreads

        if !format.supportsSolid {
            solidPopup?.selectItem(at: 0)
        }
        if !format.supportsThreads {
            threadField?.stringValue = "Auto"
        }

        let encryptionAvailable = !format.encryptionOptions.isEmpty
        encryptionPopup?.isEnabled = encryptionAvailable && format.encryptionOptions.count > 1
        securePasswordField?.isEnabled = encryptionAvailable
        plainPasswordField?.isEnabled = encryptionAvailable
        secureConfirmPasswordField?.isEnabled = encryptionAvailable
        plainConfirmPasswordField?.isEnabled = encryptionAvailable
        showPasswordCheckbox?.isEnabled = encryptionAvailable

        let canEncryptNames = encryptionAvailable && format.supportsEncryptFileNames && !currentPasswordValue().isEmpty
        encryptNamesCheckbox?.isEnabled = canEncryptNames
        if !canEncryptNames {
            encryptNamesCheckbox?.state = .off
        }
    }

    private func buildResult(archivePath: String,
                             format: FormatOption,
                             level: SZCompressionLevel,
                             method: MethodOption?,
                             dictionarySize: UInt64,
                             wordSize: UInt32,
                             solidMode: Bool,
                             threadText: String,
                             splitVolumes: String,
                             parameters: String,
                             updateMode: SZCompressionUpdateMode,
                             pathMode: SZCompressionPathMode,
                             encryption: SZEncryptionMethod,
                             password: String,
                             confirmation: String,
                             encryptNames: Bool,
                             openSharedFiles: Bool,
                             deleteAfterCompression: Bool) throws -> CompressDialogResult {
        let archiveURL = try resolveArchiveURL(from: archivePath, format: format)
        let threadCount = try parseThreadCount(threadText)
        let normalizedPassword = try validatePassword(password,
                                                      confirmation: confirmation,
                                                      for: format,
                                                      encryption: encryption)
        let settings = SZCompressionSettings()
        settings.format = format.format
        settings.level = level
        settings.method = method?.enumValue ?? .LZMA2
        settings.methodName = method?.methodName
        settings.updateMode = updateMode
        settings.pathMode = pathMode
        settings.encryption = normalizedPassword == nil ? .none : encryption
        settings.password = normalizedPassword
        settings.encryptFileNames = normalizedPassword != nil && format.supportsEncryptFileNames && encryptNames
        settings.solidMode = format.supportsSolid && solidMode
        settings.dictionarySize = dictionarySize
        settings.wordSize = wordSize
        settings.numThreads = threadCount

        let trimmedSplitVolumes = splitVolumes.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.splitVolumes = trimmedSplitVolumes.isEmpty ? nil : trimmedSplitVolumes

        let trimmedParameters = parameters.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.parameters = trimmedParameters.isEmpty ? nil : trimmedParameters

        settings.openSharedFiles = openSharedFiles
        settings.deleteAfterCompression = deleteAfterCompression

        return CompressDialogResult(settings: settings, archiveURL: archiveURL)
    }

    private func validatePassword(_ password: String,
                                  confirmation: String,
                                  for format: FormatOption,
                                  encryption: SZEncryptionMethod) throws -> String? {
        guard !password.isEmpty || !confirmation.isEmpty else {
            return nil
        }

        guard password == confirmation else {
            throw NSError(domain: NSCocoaErrorDomain,
                          code: NSUserCancelledError,
                          userInfo: [NSLocalizedDescriptionKey: "Passwords do not match."])
        }

        if format.codecName == "zip" {
            guard password.canBeConverted(to: .ascii) else {
                throw NSError(domain: NSCocoaErrorDomain,
                              code: NSUserCancelledError,
                              userInfo: [NSLocalizedDescriptionKey: "ZIP passwords must use ASCII characters."])
            }

            if encryption == .AES256 && password.utf8.count > 99 {
                throw NSError(domain: NSCocoaErrorDomain,
                              code: NSUserCancelledError,
                              userInfo: [NSLocalizedDescriptionKey: "ZIP AES passwords must be 99 bytes or fewer."])
            }
        }

        return password
    }

    private func parseThreadCount(_ text: String) throws -> UInt32 {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.caseInsensitiveCompare("Auto") != .orderedSame else {
            return 0
        }

        guard let value = UInt32(trimmed), value > 0 else {
            throw NSError(domain: NSCocoaErrorDomain,
                          code: NSUserCancelledError,
                          userInfo: [NSLocalizedDescriptionKey: "Thread count must be a positive number or Auto."])
        }

        return value
    }

    private func resolveArchiveURL(from archivePath: String,
                                   format: FormatOption) throws -> URL {
        let trimmedPath = archivePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = normalizedArchivePath(from: trimmedPath, format: format)
        let expandedPath = NSString(string: normalizedPath).expandingTildeInPath
        let archiveURL: URL
        if NSString(string: expandedPath).isAbsolutePath {
            archiveURL = URL(fileURLWithPath: expandedPath)
        } else {
            archiveURL = URL(fileURLWithPath: expandedPath, relativeTo: baseDirectory)
        }

        let standardizedURL = archiveURL.standardizedFileURL
        guard !standardizedURL.lastPathComponent.isEmpty else {
            throw NSError(domain: NSCocoaErrorDomain,
                          code: NSUserCancelledError,
                          userInfo: [NSLocalizedDescriptionKey: "Enter an archive path."])
        }

        let parentDirectory = standardizedURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parentDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw NSError(domain: NSCocoaErrorDomain,
                          code: NSUserCancelledError,
                          userInfo: [NSLocalizedDescriptionKey: "The destination folder does not exist."])
        }

        if FileManager.default.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            throw NSError(domain: NSCocoaErrorDomain,
                          code: NSUserCancelledError,
                          userInfo: [NSLocalizedDescriptionKey: "The archive path points to an existing folder."])
        }

        return standardizedURL
    }

    private func normalizedArchivePath(from archivePath: String,
                                       format: FormatOption) -> String {
        let trimmedPath = archivePath.isEmpty ? defaultArchiveURL(for: format.codecName).path : archivePath
        let pathNSString = NSString(string: trimmedPath)
        let existingExtension = pathNSString.pathExtension.lowercased()

        if existingExtension.isEmpty {
            return trimmedPath + ".\(format.defaultExtension)"
        }

        if existingExtension == format.defaultExtension.lowercased() {
            return trimmedPath
        }

        if Self.knownArchiveExtensions.contains(existingExtension) {
            return pathNSString.deletingPathExtension + ".\(format.defaultExtension)"
        }

        return trimmedPath + ".\(format.defaultExtension)"
    }

    private func updateArchivePathExtension() {
        guard let archivePathField,
              let format = selectedFormatOption() else {
            return
        }

        archivePathField.stringValue = normalizedArchivePath(from: archivePathField.stringValue,
                                                             format: format)
    }

    private func updatePasswordVisibilityUI(moveFocus: Bool) {
        let showsPassword = showPasswordCheckbox?.state == .on
        securePasswordField?.isHidden = showsPassword
        secureConfirmPasswordField?.isHidden = showsPassword
        plainPasswordField?.isHidden = !showsPassword
        plainConfirmPasswordField?.isHidden = !showsPassword

        guard moveFocus,
              let window = currentDialogWindow,
              let textView = window.firstResponder as? NSTextView,
              let owner = textView.delegate as? NSView else {
            return
        }

        let replacementResponder: NSView?
        switch owner {
        case securePasswordField, plainPasswordField:
            replacementResponder = showsPassword ? plainPasswordField : securePasswordField
        case secureConfirmPasswordField, plainConfirmPasswordField:
            replacementResponder = showsPassword ? plainConfirmPasswordField : secureConfirmPasswordField
        default:
            replacementResponder = nil
        }

        if let replacementResponder {
            window.makeFirstResponder(replacementResponder)
        }
    }

    private func syncPasswordFields() {
        let password = currentPasswordValue()
        securePasswordField?.stringValue = password
        plainPasswordField?.stringValue = password

        let confirmation = currentConfirmationValue()
        secureConfirmPasswordField?.stringValue = confirmation
        plainConfirmPasswordField?.stringValue = confirmation
    }

    private func currentPasswordValue() -> String {
        if showPasswordCheckbox?.state == .on {
            return plainPasswordField?.stringValue ?? securePasswordField?.stringValue ?? ""
        }
        return securePasswordField?.stringValue ?? plainPasswordField?.stringValue ?? ""
    }

    private func currentConfirmationValue() -> String {
        if showPasswordCheckbox?.state == .on {
            return plainConfirmPasswordField?.stringValue ?? secureConfirmPasswordField?.stringValue ?? ""
        }
        return secureConfirmPasswordField?.stringValue ?? plainConfirmPasswordField?.stringValue ?? ""
    }

    private func selectedFormatOption() -> FormatOption? {
        guard let formatPopup else { return nil }
        let index = formatPopup.indexOfSelectedItem
        guard availableFormats.indices.contains(index) else { return availableFormats.first }
        return availableFormats[index]
    }

    private func selectedLevelOption() -> Option<SZCompressionLevel>? {
        guard let format = selectedFormatOption(),
              let levelPopup else {
            return nil
        }
        let index = levelPopup.indexOfSelectedItem
        guard format.levelOptions.indices.contains(index) else {
            return format.levelOptions.first
        }
        return format.levelOptions[index]
    }

    private func selectedMethodOption() -> MethodOption? {
        guard let format = selectedFormatOption(),
              let methodPopup,
              !format.methods.isEmpty else {
            return nil
        }
        let index = methodPopup.indexOfSelectedItem
        guard format.methods.indices.contains(index) else {
            return format.methods.first
        }
        return format.methods[index]
    }

    private func selectedDictionaryOption() -> Option<UInt64>? {
        guard let method = selectedMethodOption(),
              let dictionaryPopup,
              !method.dictionaryOptions.isEmpty else {
            return nil
        }
        let index = dictionaryPopup.indexOfSelectedItem
        guard method.dictionaryOptions.indices.contains(index) else {
            return method.dictionaryOptions.first
        }
        return method.dictionaryOptions[index]
    }

    private func selectedWordOption() -> Option<UInt32>? {
        guard let method = selectedMethodOption(),
              let wordPopup,
              !method.wordOptions.isEmpty else {
            return nil
        }
        let index = wordPopup.indexOfSelectedItem
        guard method.wordOptions.indices.contains(index) else {
            return method.wordOptions.first
        }
        return method.wordOptions[index]
    }

    private func selectedSolidOption() -> Option<Bool>? {
        guard let solidPopup else { return nil }
        let index = solidPopup.indexOfSelectedItem
        guard Self.solidOptions.indices.contains(index) else { return Self.solidOptions.first }
        return Self.solidOptions[index]
    }

    private func selectedUpdateModeOption() -> Option<SZCompressionUpdateMode>? {
        guard let updateModePopup else { return nil }
        let index = updateModePopup.indexOfSelectedItem
        guard Self.updateModeOptions.indices.contains(index) else { return Self.updateModeOptions.first }
        return Self.updateModeOptions[index]
    }

    private func selectedPathModeOption() -> Option<SZCompressionPathMode>? {
        guard let pathModePopup else { return nil }
        let index = pathModePopup.indexOfSelectedItem
        guard Self.pathModeOptions.indices.contains(index) else { return Self.pathModeOptions.first }
        return Self.pathModeOptions[index]
    }

    private func selectedEncryptionOption() -> Option<SZEncryptionMethod>? {
        guard let format = selectedFormatOption(),
              !format.encryptionOptions.isEmpty,
              let encryptionPopup else {
            return nil
        }
        let index = encryptionPopup.indexOfSelectedItem
        guard format.encryptionOptions.indices.contains(index) else { return format.encryptionOptions.first }
        return format.encryptionOptions[index]
    }

    private func defaultArchiveURL(for formatName: String) -> URL {
        let format = formatOption(named: formatName) ?? availableFormats[0]
        return baseDirectory.appendingPathComponent("\(suggestedBaseName).\(format.defaultExtension)")
    }

    private func suggestedArchiveFileName() -> String {
        let format = selectedFormatOption() ?? availableFormats[0]
        return "\(suggestedBaseName).\(format.defaultExtension)"
    }

    private func formatOption(named formatName: String) -> FormatOption? {
        availableFormats.first { $0.codecName == formatName }
    }

    private func defaultLevel(for formatName: String) -> SZCompressionLevel {
        let format = formatOption(named: formatName) ?? availableFormats[0]
        return format.levelOptions[defaultLevelIndex(for: format)].value
    }

    private func defaultLevelIndex(for format: FormatOption) -> Int {
        if let normalIndex = format.levelOptions.firstIndex(where: { $0.value == .normal }) {
            return normalIndex
        }
        return 0
    }

    private func defaultMethodName(for formatName: String) -> String {
        (formatOption(named: formatName) ?? availableFormats[0]).methods.first?.methodName ?? ""
    }

    private func defaultEncryption(for formatName: String) -> SZEncryptionMethod {
        (formatOption(named: formatName) ?? availableFormats[0]).encryptionOptions.first?.value ?? .none
    }

    private func populate(_ popup: NSPopUpButton?, with titles: [String]) {
        popup?.removeAllItems()
        popup?.addItems(withTitles: titles)
    }

    private func selectOption<Value>(_ options: [Option<Value>],
                                     selectedValue: Value,
                                     on popup: NSPopUpButton) where Value: Equatable {
        if let selectedIndex = options.firstIndex(where: { $0.value == selectedValue }) {
            popup.selectItem(at: selectedIndex)
        } else {
            popup.selectItem(at: 0)
        }
    }

    private func makePathRow(label: String,
                             pathField: NSComboBox,
                             browseButton: NSButton) -> NSView {
        let labelField = NSTextField(labelWithString: label)
        labelField.alignment = .right
        labelField.font = .systemFont(ofSize: 12)
        labelField.setContentHuggingPriority(.required, for: .horizontal)
        labelField.widthAnchor.constraint(equalToConstant: 96).isActive = true

        let stack = NSStackView(views: [labelField, pathField, browseButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func makeFormRow(label: String,
                             control: NSView) -> NSView {
        makeFormRow(labelField: NSTextField(labelWithString: label), control: control)
    }

    private func makeFormRow(labelField: NSTextField,
                             control: NSView) -> NSView {
        labelField.alignment = .right
        labelField.font = .systemFont(ofSize: 12)
        labelField.setContentHuggingPriority(.required, for: .horizontal)
        labelField.widthAnchor.constraint(equalToConstant: Self.formLabelWidth).isActive = true

        let stack = NSStackView(views: [labelField, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func makeColumn(rows: [NSView]) -> NSStackView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    private func makeTitledSection(title: String,
                                   rows: [NSView]) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        let content = NSStackView(views: rows)
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8

        let panel = NSView(frame: .zero)
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 8
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = NSColor.separatorColor.cgColor
        panel.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.45).cgColor
        panel.addSubview(content)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10),
            content.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),
            content.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -10),
        ])

        let section = NSStackView(views: [titleLabel, panel])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 6
        return section
    }

    private func makePasswordContainer(secureField: NSSecureTextField,
                                       plainField: NSTextField) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        container.translatesAutoresizingMaskIntoConstraints = false
        secureField.translatesAutoresizingMaskIntoConstraints = false
        plainField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(secureField)
        container.addSubview(plainField)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 220),
            container.heightAnchor.constraint(equalToConstant: 24),
            secureField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            secureField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            secureField.topAnchor.constraint(equalTo: container.topAnchor),
            secureField.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            plainField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            plainField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            plainField.topAnchor.constraint(equalTo: container.topAnchor),
            plainField.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    private static func makeAvailableFormats() -> [FormatOption] {
        let supportedNames = Set(
            SZArchive.supportedFormats()
                .filter(\.canWrite)
                .map { $0.name.lowercased() }
        )
        let filteredFormats = formatCatalog.filter {
            supportedNames.isEmpty || supportedNames.contains($0.codecName.lowercased())
        }
        return filteredFormats.isEmpty ? formatCatalog : filteredFormats
    }

    private static func suggestedBaseDirectory(for sourceURLs: [URL]) -> URL {
        guard let firstURL = sourceURLs.first?.standardizedFileURL else {
            return FileManager.default.homeDirectoryForCurrentUser
        }

        var commonComponents = firstURL.deletingLastPathComponent().pathComponents
        for sourceURL in sourceURLs.dropFirst() {
            let components = sourceURL.standardizedFileURL.deletingLastPathComponent().pathComponents
            var updatedComponents: [String] = []
            for (lhs, rhs) in zip(commonComponents, components) where lhs == rhs {
                updatedComponents.append(lhs)
            }
            commonComponents = updatedComponents
        }

        guard !commonComponents.isEmpty else {
            return FileManager.default.homeDirectoryForCurrentUser
        }

        return URL(fileURLWithPath: NSString.path(withComponents: commonComponents))
    }

    private static func suggestedArchiveBaseName(for sourceURLs: [URL],
                                                 baseDirectory: URL) -> String {
        guard let firstURL = sourceURLs.first?.standardizedFileURL else {
            return "Archive"
        }

        let baseName: String
        if sourceURLs.count == 1 {
            let resourceValues = try? firstURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues?.isDirectory ?? false
            if isDirectory {
                baseName = firstURL.lastPathComponent
            } else {
                let fileName = firstURL.lastPathComponent
                if let dotIndex = fileName.firstIndex(of: "."),
                   fileName[fileName.index(after: dotIndex)...].contains(".") == false {
                    baseName = String(fileName[..<dotIndex])
                } else {
                    baseName = fileName
                }
            }
        } else {
            let folderName = baseDirectory.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            baseName = folderName.isEmpty ? "Archive" : folderName
        }

        let sanitizedBaseName = sanitizeFileName(baseName)
        return uniquedSuggestedBaseName(sanitizedBaseName, sourceURLs: sourceURLs)
    }

    private static func sanitizeFileName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalidCharacters = CharacterSet(charactersIn: "/:")
        let sanitized = trimmed.unicodeScalars.map { invalidCharacters.contains($0) ? "_" : String($0) }.joined()
        return sanitized.isEmpty ? "Archive" : sanitized
    }

    private static func uniquedSuggestedBaseName(_ baseName: String,
                                                 sourceURLs: [URL]) -> String {
        let selectedArchiveBaseNames = Set(sourceURLs.compactMap { url -> String? in
            let fileName = url.standardizedFileURL.lastPathComponent
            let pathExtension = (fileName as NSString).pathExtension.lowercased()
            guard knownArchiveExtensions.contains(pathExtension) else {
                return nil
            }
            return (fileName as NSString).deletingPathExtension.lowercased()
        })

        guard selectedArchiveBaseNames.contains(baseName.lowercased()) else {
            return baseName
        }

        var suffix = 2
        while selectedArchiveBaseNames.contains("\(baseName)_\(suffix)".lowercased()) {
            suffix += 1
        }
        return "\(baseName)_\(suffix)"
    }

    private static func defaultMessage(for sourceURLs: [URL],
                                       baseDirectory: URL) -> String? {
        if sourceURLs.count == 1 {
            return baseDirectory.path
        }
        return "Source folder: \(baseDirectory.path)"
    }

    private static func threadChoices() -> [String] {
        let processorCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let upperBound = max(processorCount, 16)
        return (1...upperBound).map(String.init)
    }
}
