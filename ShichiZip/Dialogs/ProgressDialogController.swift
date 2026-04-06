import Cocoa

/// Progress dialog shown during extraction/compression operations
class ProgressDialogController: NSWindowController, SZProgressDelegate {

    private var progressBar: NSProgressIndicator!
    private var fileNameLabel: NSTextField!
    private var bytesLabel: NSTextField!
    private var operationLabel: NSTextField!
    private var cancelButton: NSButton!

    private var cancelled = false
    private var startTime: Date?
    private var speedLabel: NSTextField!
    private var elapsedLabel: NSTextField!

    var operationTitle: String = "Working..." {
        didSet {
            DispatchQueue.main.async { [weak self] in
                self?.operationLabel?.stringValue = self?.operationTitle ?? ""
            }
        }
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 175),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "ShichiZip"
        window.isMovableByWindowBackground = true
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        operationLabel = NSTextField(labelWithString: operationTitle)
        operationLabel.font = .boldSystemFont(ofSize: 13)
        operationLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(operationLabel)

        fileNameLabel = NSTextField(labelWithString: "")
        fileNameLabel.font = .systemFont(ofSize: 11)
        fileNameLabel.textColor = .secondaryLabelColor
        fileNameLabel.lineBreakMode = .byTruncatingMiddle
        fileNameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(fileNameLabel)

        progressBar = NSProgressIndicator()
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1.0
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressBar)

        bytesLabel = NSTextField(labelWithString: "")
        bytesLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        bytesLabel.textColor = .secondaryLabelColor
        bytesLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bytesLabel)

        speedLabel = NSTextField(labelWithString: "")
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        speedLabel.textColor = .secondaryLabelColor
        speedLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(speedLabel)

        elapsedLabel = NSTextField(labelWithString: "")
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        elapsedLabel.textColor = .secondaryLabelColor
        elapsedLabel.alignment = .right
        elapsedLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(elapsedLabel)

        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked(_:)))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.keyEquivalent = "\u{1b}" // Escape
        contentView.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            operationLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            operationLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            operationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            fileNameLabel.topAnchor.constraint(equalTo: operationLabel.bottomAnchor, constant: 4),
            fileNameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            fileNameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            progressBar.topAnchor.constraint(equalTo: fileNameLabel.bottomAnchor, constant: 8),
            progressBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            progressBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            bytesLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 4),
            bytesLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            speedLabel.topAnchor.constraint(equalTo: bytesLabel.bottomAnchor, constant: 2),
            speedLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            elapsedLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 4),
            elapsedLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -100),

            cancelButton.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 4),
            cancelButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            cancelButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    @objc private func cancelClicked(_ sender: Any?) {
        cancelled = true
        cancelButton.isEnabled = false
        cancelButton.title = "Cancelling..."
    }

    // MARK: - SZProgressDelegate (matches ProgressDialog2.cpp)

    @objc func progressDidUpdate(_ fraction: Double) {
        progressBar.doubleValue = fraction
    }

    @objc func progressDidUpdateFileName(_ fileName: String) {
        fileNameLabel.stringValue = fileName
    }

    @objc func progressDidUpdateBytesCompleted(_ completed: UInt64, total: UInt64) {
        if startTime == nil { startTime = Date() }

        let completedStr = ByteCountFormatter.string(fromByteCount: Int64(completed), countStyle: .file)
        let totalStr = ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
        let percent = total > 0 ? Int(Double(completed) / Double(total) * 100) : 0
        bytesLabel.stringValue = "\(completedStr) / \(totalStr) (\(percent)%)"

        // Speed and ETA calculation (like ProgressDialog2.cpp)
        if let start = startTime {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > 0.5 {
                let speed = Double(completed) / elapsed
                let speedStr = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file)
                speedLabel.stringValue = "Speed: \(speedStr)/s"

                let elapsedStr = formatDuration(elapsed)
                if total > 0 && completed > 0 {
                    let remaining = elapsed * Double(total - completed) / Double(completed)
                    let remainStr = formatDuration(remaining)
                    elapsedLabel.stringValue = "Elapsed: \(elapsedStr)  Remaining: \(remainStr)"
                } else {
                    elapsedLabel.stringValue = "Elapsed: \(elapsedStr)"
                }
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }

    @objc func progressShouldCancel() -> Bool {
        return cancelled
    }

    @objc func progressDidUpdateSpeed(_ bytesPerSecond: Double) {
        // Could show speed in UI
    }

    @objc func progressDidUpdateCompressionRatio(_ ratio: Double) {
        // Could show ratio in UI
    }
}
