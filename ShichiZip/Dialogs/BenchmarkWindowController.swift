import Cocoa

class BenchmarkWindowController: NSWindowController {

    private var resultTextView: NSTextView!
    private var startButton: NSButton!
    private var progressBar: NSProgressIndicator!
    private var statusLabel: NSTextField!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 450),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Benchmark — ShichiZip"
        window.center()
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        statusLabel = NSTextField(labelWithString: "Ready")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 12)
        contentView.addSubview(statusLabel)

        progressBar = NSProgressIndicator()
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.isIndeterminate = true
        progressBar.style = .bar
        progressBar.isHidden = true
        contentView.addSubview(progressBar)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true

        resultTextView = NSTextView()
        resultTextView.isEditable = false
        resultTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        resultTextView.textContainerInset = NSSize(width: 8, height: 8)
        resultTextView.string = """
        ShichiZip Benchmark
        ===================

        Tests LZMA compression and decompression speed.
        Click "Start Benchmark" to begin.

        This benchmark uses the 7-Zip core engine.
        Results are comparable to 7-Zip benchmark on other platforms.
        """
        scrollView.documentView = resultTextView
        contentView.addSubview(scrollView)

        startButton = NSButton(title: "Start Benchmark", target: self, action: #selector(startBenchmark(_:)))
        startButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(startButton)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            progressBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            progressBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            progressBar.widthAnchor.constraint(equalToConstant: 150),

            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: startButton.topAnchor, constant: -12),

            startButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            startButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    @objc private func startBenchmark(_ sender: Any?) {
        startButton.isEnabled = false
        progressBar.isHidden = false
        progressBar.startAnimation(nil)
        statusLabel.stringValue = "Running benchmark..."

        let ncpu = ProcessInfo.processInfo.processorCount
        let physMem = ProcessInfo.processInfo.physicalMemory
        let memStr = ByteCountFormatter.string(fromByteCount: Int64(physMem), countStyle: .memory)

        resultTextView.string = """
        ShichiZip LZMA Benchmark
        ========================
        CPU Cores: \(ncpu)  |  RAM: \(memStr)  |  \(Self.cpuArchitecture())

        Running...

        """

        SZArchive.runBenchmark(withIterations: 1) { [weak self] line in
            self?.resultTextView.string += line + "\n"
            self?.resultTextView.scrollToEndOfDocument(nil)
        } completion: { [weak self] success in
            self?.progressBar.stopAnimation(nil)
            self?.progressBar.isHidden = true
            self?.startButton.isEnabled = true
            self?.statusLabel.stringValue = success ? "Benchmark complete" : "Benchmark failed"
        }
    }

    private static func cpuArchitecture() -> String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Unknown"
        #endif
    }
}
