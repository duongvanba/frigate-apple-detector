import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var modelField: NSTextField!
    private var hostField: NSTextField!
    private var portField: NSTextField!
    private var endpointPreview: NSTextField!
    private var statusLabel: NSTextField!
    private var statusBox: NSBox!
    private var logView: NSTextView!
    private var startButton: NSButton!
    private var stopButton: NSButton!
    private var autoModelButton: NSButton!
    private var verboseButton: NSButton!
    private var clearButton: NSButton!
    private var process: Process?
    private var outputPipe: Pipe?
    private var logFileHandle: FileHandle?

    private var detectorURL: URL {
        Bundle.main.resourceURL!.appendingPathComponent("detector-runner")
    }

    private var bundledModelURL: URL? {
        let url = Bundle.main.resourceURL!
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("yolov8n.onnx")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private var appSupportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("FrigateDetector", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        restoreDefaults()
        refreshEndpointPreview()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        stopDetector()
        return .terminateNow
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Frigate Detector"
        window.center()
        window.minSize = NSSize(width: 760, height: 560)

        let contentView = NSVisualEffectView()
        contentView.material = .underWindowBackground
        contentView.blendingMode = .behindWindow
        contentView.state = .active
        window.contentView = contentView

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .centerX
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false

        let header = makeHeader()
        let configuration = makeSection(
            title: "Cấu hình detector",
            subtitle: "Chọn model và mở endpoint TCP để Frigate gửi request nhận diện.",
            content: makeConfigurationView()
        )
        let controls = makeControlPanel()
        let status = makeStatusBar()
        let logPanel = makeLogPanel()
        [header, configuration, controls, status, logPanel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        root.addArrangedSubview(header)
        root.addArrangedSubview(configuration)
        root.addArrangedSubview(controls)
        root.addArrangedSubview(status)
        root.addArrangedSubview(logPanel)

        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
            header.widthAnchor.constraint(equalTo: root.widthAnchor),
            configuration.widthAnchor.constraint(equalTo: root.widthAnchor),
            controls.widthAnchor.constraint(equalTo: root.widthAnchor),
            status.widthAnchor.constraint(equalTo: root.widthAnchor),
            logPanel.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeHeader() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 14

        let title = NSTextField(labelWithString: "Frigate Apple Silicon Detector")
        title.alignment = .center
        title.font = .systemFont(ofSize: 28, weight: .semibold)

        let descriptionBox = NSBox()
        descriptionBox.boxType = .custom
        descriptionBox.borderType = .lineBorder
        descriptionBox.cornerRadius = 10
        descriptionBox.borderColor = NSColor.separatorColor
        descriptionBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.68)
        descriptionBox.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(wrappingLabelWithString: "Ứng dụng macOS native để chạy detector cho Frigate trên Apple Silicon. App đã đóng gói runtime và dependencies bên trong, không dùng Python hoặc môi trường của máy host. Chọn model, nhập host/port, rồi bấm Bắt đầu để Frigate kết nối tới endpoint TCP.")
        subtitle.alignment = .center
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        descriptionBox.contentView?.addSubview(subtitle)
        NSLayoutConstraint.activate([
            subtitle.leadingAnchor.constraint(equalTo: descriptionBox.contentView!.leadingAnchor, constant: 16),
            subtitle.trailingAnchor.constraint(equalTo: descriptionBox.contentView!.trailingAnchor, constant: -16),
            subtitle.topAnchor.constraint(equalTo: descriptionBox.contentView!.topAnchor, constant: 12),
            subtitle.bottomAnchor.constraint(equalTo: descriptionBox.contentView!.bottomAnchor, constant: -12)
        ])

        stack.addArrangedSubview(makeCenteredContainer(title))
        stack.addArrangedSubview(descriptionBox)
        return stack
    }

    private func makeSection(title: String, subtitle: String, content: NSView) -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.borderType = .lineBorder
        box.cornerRadius = 10
        box.borderColor = NSColor.separatorColor
        box.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72)
        box.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.alignment = .center

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center

        stack.addArrangedSubview(makeCenteredContainer(titleLabel))
        stack.addArrangedSubview(makeCenteredContainer(subtitleLabel))
        stack.addArrangedSubview(content)
        box.contentView?.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: box.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: box.contentView!.bottomAnchor)
        ])
        return box
    }

    private func makeConfigurationView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12

        stack.addArrangedSubview(makeModelRow())
        stack.addArrangedSubview(makeNetworkRow())
        stack.addArrangedSubview(makeOptionsRow())
        return stack
    }

    private func makeCenteredContainer(_ view: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor)
        ])
        return container
    }

    private func makeLogPanel() -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.borderType = .lineBorder
        box.cornerRadius = 10
        box.borderColor = NSColor(calibratedWhite: 0.18, alpha: 1.0)
        box.fillColor = NSColor.black
        box.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        let title = NSTextField(labelWithString: "Log trực tiếp")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .white
        title.alignment = .center

        clearButton = NSButton(title: "Xóa log", target: self, action: #selector(clearLogs))
        clearButton.bezelStyle = .rounded
        clearButton.contentTintColor = .white

        header.addArrangedSubview(title)
        header.addArrangedSubview(NSView())
        header.addArrangedSubview(clearButton)
        stack.addArrangedSubview(header)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.wantsLayer = true
        scroll.layer?.backgroundColor = NSColor.black.cgColor
        scroll.layer?.cornerRadius = 8

        logView = NSTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 300))
        logView.isEditable = false
        logView.isSelectable = true
        logView.isVerticallyResizable = true
        logView.isHorizontallyResizable = false
        logView.autoresizingMask = [.width]
        logView.textContainer?.widthTracksTextView = true
        logView.textContainerInset = NSSize(width: 8, height: 8)
        logView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logView.textColor = .white
        logView.insertionPointColor = .white
        logView.backgroundColor = .black
        logView.drawsBackground = true
        logView.string = ""
        appendLog("Sẵn sàng. Bấm Bắt đầu để chạy detector.\n")
        scroll.documentView = logView
        stack.addArrangedSubview(scroll)
        box.contentView?.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: box.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: box.contentView!.bottomAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280)
        ])
        return box
    }

    private func makeModelRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        let label = makeFieldLabel("Model")

        modelField = NSTextField()
        modelField.placeholderString = "AUTO hoặc đường dẫn .onnx"
        modelField.stringValue = "AUTO"
        modelField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let chooseButton = NSButton(title: "Chọn model", target: self, action: #selector(chooseModel))
        chooseButton.bezelStyle = .rounded
        autoModelButton = NSButton(checkboxWithTitle: "Tự động", target: self, action: #selector(toggleAutoModel))
        autoModelButton.state = .on

        let leadingSpacer = NSView()
        let trailingSpacer = NSView()
        row.addArrangedSubview(leadingSpacer)
        row.addArrangedSubview(label)
        row.addArrangedSubview(modelField)
        row.addArrangedSubview(chooseButton)
        row.addArrangedSubview(autoModelButton)
        row.addArrangedSubview(trailingSpacer)
        modelField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        modelField.widthAnchor.constraint(lessThanOrEqualToConstant: 680).isActive = true
        leadingSpacer.widthAnchor.constraint(equalTo: trailingSpacer.widthAnchor).isActive = true
        return row
    }

    private func makeNetworkRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        let leadingSpacer = NSView()
        let trailingSpacer = NSView()
        row.addArrangedSubview(leadingSpacer)
        row.addArrangedSubview(makeFieldLabel("Host"))
        hostField = NSTextField()
        hostField.placeholderString = "*"
        hostField.stringValue = "*"
        hostField.target = self
        hostField.action = #selector(refreshEndpointPreview)
        hostField.widthAnchor.constraint(equalToConstant: 190).isActive = true
        row.addArrangedSubview(hostField)

        row.addArrangedSubview(makeFieldLabel("Port"))
        portField = NSTextField()
        portField.placeholderString = "5555"
        portField.stringValue = "5555"
        portField.target = self
        portField.action = #selector(refreshEndpointPreview)
        portField.widthAnchor.constraint(equalToConstant: 90).isActive = true
        row.addArrangedSubview(portField)

        endpointPreview = NSTextField(labelWithString: "")
        endpointPreview.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        endpointPreview.textColor = .secondaryLabelColor
        endpointPreview.alignment = .center

        row.addArrangedSubview(endpointPreview)
        row.addArrangedSubview(trailingSpacer)
        leadingSpacer.widthAnchor.constraint(equalTo: trailingSpacer.widthAnchor).isActive = true
        return row
    }

    private func makeOptionsRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        verboseButton = NSButton(checkboxWithTitle: "Log chi tiết", target: nil, action: nil)
        let providers = NSTextField(labelWithString: "CoreML + CPU dự phòng")
        providers.font = .systemFont(ofSize: 12)
        providers.textColor = .secondaryLabelColor

        row.addArrangedSubview(NSView())
        row.addArrangedSubview(verboseButton)
        row.addArrangedSubview(providers)
        row.addArrangedSubview(NSView())
        return row
    }

    private func makeControlPanel() -> NSView {
        let container = NSView()
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false

        startButton = NSButton(title: "Bắt đầu", target: self, action: #selector(startDetector))
        startButton.bezelStyle = .rounded
        startButton.controlSize = .large
        startButton.contentTintColor = .systemGreen
        startButton.font = .systemFont(ofSize: 16, weight: .semibold)
        startButton.widthAnchor.constraint(equalToConstant: 150).isActive = true
        startButton.heightAnchor.constraint(equalToConstant: 44).isActive = true

        stopButton = NSButton(title: "Dừng", target: self, action: #selector(stopDetectorAction))
        stopButton.bezelStyle = .rounded
        stopButton.controlSize = .large
        stopButton.contentTintColor = .systemRed
        stopButton.font = .systemFont(ofSize: 16, weight: .semibold)
        stopButton.widthAnchor.constraint(equalToConstant: 150).isActive = true
        stopButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        stopButton.isEnabled = false

        row.addArrangedSubview(startButton)
        row.addArrangedSubview(stopButton)
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func makeStatusBar() -> NSView {
        let container = NSView()
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Trạng thái")
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor

        statusLabel = NSTextField(labelWithString: "Đã dừng")
        statusLabel.alignment = .center
        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = .secondaryLabelColor

        statusBox = NSBox()
        statusBox.boxType = .custom
        statusBox.borderType = .noBorder
        statusBox.cornerRadius = 10
        statusBox.fillColor = NSColor.controlBackgroundColor
        statusBox.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusBox.contentView?.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: statusBox.contentView!.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: statusBox.contentView!.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: statusBox.contentView!.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusBox.contentView!.trailingAnchor, constant: -12)
        ])
        statusBox.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        statusBox.heightAnchor.constraint(equalToConstant: 34).isActive = true

        statusLabel.wantsLayer = true
        statusLabel.layer?.backgroundColor = NSColor.clear.cgColor

        row.addArrangedSubview(label)
        row.addArrangedSubview(statusBox)
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func makeFieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.widthAnchor.constraint(equalToConstant: 64).isActive = true
        return label
    }

    private func restoreDefaults() {
        let defaults = UserDefaults.standard
        hostField.stringValue = defaults.string(forKey: "host") ?? "*"
        portField.stringValue = defaults.string(forKey: "port") ?? "5555"
        let savedModel = defaults.string(forKey: "model")
        if let bundledModelURL {
            if let savedModel, savedModel != "AUTO", FileManager.default.fileExists(atPath: savedModel) {
                modelField.stringValue = savedModel
            } else {
                modelField.stringValue = bundledModelURL.path
            }
        } else {
            modelField.stringValue = savedModel ?? "AUTO"
        }
        autoModelButton.state = modelField.stringValue == "AUTO" ? .on : .off
    }

    private func saveDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(hostField.stringValue, forKey: "host")
        defaults.set(portField.stringValue, forKey: "port")
        defaults.set(modelField.stringValue, forKey: "model")
    }

    @objc private func chooseModel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "onnx")!]
        if panel.runModal() == .OK, let url = panel.url {
            modelField.stringValue = url.path
            autoModelButton.state = .off
            saveDefaults()
        }
    }

    @objc private func toggleAutoModel() {
        if autoModelButton.state == .on {
            modelField.stringValue = "AUTO"
            saveDefaults()
        }
    }

    @objc private func refreshEndpointPreview() {
        endpointPreview.stringValue = "Endpoint: \(endpoint())"
    }

    @objc private func clearLogs() {
        logView.textStorage?.setAttributedString(NSAttributedString(string: ""))
    }

    @objc private func startDetector() {
        guard process == nil else { return }
        refreshEndpointPreview()

        do {
            try FileManager.default.createDirectory(
                at: appSupportURL.appendingPathComponent("Models", isDirectory: true),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: appSupportURL.appendingPathComponent("Logs", isDirectory: true),
                withIntermediateDirectories: true
            )
        } catch {
            appendLog("Failed to create app support directories: \(error.localizedDescription)\n")
            return
        }

        let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "AUTO" : modelField.stringValue
        let modelsDir = appSupportURL.appendingPathComponent("Models", isDirectory: true).path
        openLogFile()
        appendLog("Start requested.\n")

        var args = [
            "--model", model,
            "--endpoint", endpoint(),
            "--models-dir", modelsDir,
            "--providers", "CoreMLExecutionProvider", "CPUExecutionProvider"
        ]
        if verboseButton.state == .on {
            args.append("--verbose")
        }

        let p = Process()
        p.executableURL = detectorURL
        p.arguments = args
        p.currentDirectoryURL = appSupportURL
        let pipe = Pipe()
        outputPipe = pipe
        p.standardOutput = pipe
        p.standardError = pipe
        p.environment = [
            "FRIGATE_DETECTOR_MODELS_DIR": modelsDir,
            "PYTHONUNBUFFERED": "1"
        ]

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.appendLog(text) }
        }

        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.appendLog("\nDetector exited with status \(proc.terminationStatus).\n")
                self?.process = nil
                self?.outputPipe?.fileHandleForReading.readabilityHandler = nil
                self?.outputPipe = nil
                self?.closeLogFile()
                self?.setRunning(false)
            }
        }

        do {
            try p.run()
            process = p
            saveDefaults()
            setRunning(true)
            appendLog("Đã khởi động detector. Vui lòng chờ khoảng 1 phút để runtime và model sẵn sàng hoàn toàn.\n")
            appendLog("Command: \(detectorURL.path) \(args.joined(separator: " "))\n\n")
        } catch {
            appendLog("Failed to start detector: \(error.localizedDescription)\n")
            setRunning(false)
        }
    }

    @objc private func stopDetectorAction() {
        stopDetector()
    }

    private func stopDetector() {
        guard let p = process else { return }
        p.terminate()
        process = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        appendLog("Stop requested.\n")
        closeLogFile()
        setRunning(false)
    }

    private func setRunning(_ running: Bool) {
        startButton.isEnabled = !running
        stopButton.isEnabled = running
        statusLabel.stringValue = running ? "Đang chạy: \(endpoint())" : "Đã dừng"
        statusLabel.textColor = running ? .white : .secondaryLabelColor
        statusBox.fillColor = running
            ? NSColor.systemGreen.withAlphaComponent(0.82)
            : NSColor.controlBackgroundColor
    }

    private func endpoint() -> String {
        let host = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let portText = portField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeHost = host.isEmpty ? "*" : host
        let safePort = Int(portText) ?? 5555
        return "tcp://\(safeHost):\(safePort)"
    }

    private func appendLog(_ text: String) {
        if let data = text.data(using: .utf8) {
            logFileHandle?.write(data)
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        ]
        logView.textStorage?.append(NSAttributedString(string: text, attributes: attrs))
        logView.scrollToEndOfDocument(nil)
    }

    private func openLogFile() {
        let logURL = appSupportURL
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("FrigateDetector.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        logFileHandle = try? FileHandle(forWritingTo: logURL)
        try? logFileHandle?.seekToEnd()
        appendLog("Log file: \(logURL.path)\n")
    }

    private func closeLogFile() {
        try? logFileHandle?.close()
        logFileHandle = nil
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
