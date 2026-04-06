import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    private var fileManagerWindowController: FileManagerWindowController?
    private var additionalFileManagerWindows: [FileManagerWindowController] = []
    private var benchmarkWindowController: BenchmarkWindowController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.setup()
        // Delay slightly — if we're opening a file, the document system will handle it
        // Only show file manager if no documents are being opened
        DispatchQueue.main.async { [weak self] in
            if NSDocumentController.shared.documents.isEmpty &&
               NSApp.windows.filter({ $0.isVisible }).isEmpty {
                self?.showFileManager(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showFileManager(nil)
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Menu Actions

    @IBAction func showFileManager(_ sender: Any?) {
        if fileManagerWindowController == nil {
            fileManagerWindowController = FileManagerWindowController()
        }
        fileManagerWindowController?.showWindow(self)
    }

    /// Open an archive file in the file manager (navigate into it inline)
    func openArchiveInFileManager(_ url: URL) {
        showFileManager(nil)
        fileManagerWindowController?.navigateToArchive(url)
    }

    /// Open an archive in a NEW file manager window (for "Open With" from Finder)
    func openArchiveInNewFileManager(_ url: URL) {
        let wc = FileManagerWindowController()
        additionalFileManagerWindows.append(wc)
        wc.showWindow(self)
        wc.navigateToArchive(url)
    }

    @IBAction func newArchive(_ sender: Any?) {
        let dialog = CompressDialogController()
        dialog.showAsStandaloneDialog()
    }

    @IBAction func showBenchmark(_ sender: Any?) {
        if benchmarkWindowController == nil {
            benchmarkWindowController = BenchmarkWindowController()
        }
        benchmarkWindowController?.showWindow(self)
    }

    @IBAction func showPreferences(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(self)
    }
}
