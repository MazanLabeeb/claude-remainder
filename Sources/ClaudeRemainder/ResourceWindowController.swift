import AppKit
import ClaudeRemainderCore
import Foundation

final class ResourceWindowController: NSWindowController, NSWindowDelegate {
    private let sampler: () -> ResourceMetrics?
    private let openActivityMonitor: () -> Void

    private var timer: Timer?

    private let cpuLabel = NSTextField(labelWithString: "CPU: --")
    private let memoryLabel = NSTextField(labelWithString: "Memory: --")
    private let uptimeLabel = NSTextField(labelWithString: "Uptime: --")
    private let cacheLabel = NSTextField(labelWithString: "Snapshot cache: --")
    private let networkLabel = NSTextField(labelWithString: "Network refresh calls: --")

    init(
        sampler: @escaping () -> ResourceMetrics?,
        openActivityMonitor: @escaping () -> Void
    ) {
        self.sampler = sampler
        self.openActivityMonitor = openActivityMonitor

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Resource Usage"

        super.init(window: window)

        buildUI(in: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refreshLabels()
        startSampling()
    }

    func windowWillClose(_ notification: Notification) {
        stopSampling()
    }

    private func buildUI(in window: NSWindow) {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 10
        container.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        container.translatesAutoresizingMaskIntoConstraints = false

        for label in [cpuLabel, memoryLabel, uptimeLabel, cacheLabel, networkLabel] {
            label.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            container.addArrangedSubview(label)
        }

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let monitorButton = NSButton(title: "Open Activity Monitor", target: self, action: #selector(openActivityMonitorAction))
        monitorButton.bezelStyle = .rounded
        buttonRow.addArrangedSubview(monitorButton)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addArrangedSubview(spacer)

        container.addArrangedSubview(buttonRow)

        let contentView = NSView()
        contentView.addSubview(container)
        window.contentView = contentView

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            container.topAnchor.constraint(equalTo: contentView.topAnchor),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func startSampling() {
        stopSampling()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshLabels()
        }
    }

    private func stopSampling() {
        timer?.invalidate()
        timer = nil
    }

    private func refreshLabels() {
        guard let metrics = sampler() else { return }

        cpuLabel.stringValue = String(format: "CPU: %.1f%%", metrics.cpuPercent)
        memoryLabel.stringValue = "Memory: \(ByteCountFormatter.string(fromByteCount: Int64(metrics.residentMemoryBytes), countStyle: .memory))"
        uptimeLabel.stringValue = "Uptime: \(Self.uptimeString(metrics.uptimeSeconds))"
        cacheLabel.stringValue = "Snapshot cache: \(ByteCountFormatter.string(fromByteCount: Int64(metrics.cacheBytes), countStyle: .memory))"
        networkLabel.stringValue = "Network refresh calls: \(metrics.networkRefreshCount)"
    }

    @objc private func openActivityMonitorAction() {
        openActivityMonitor()
    }

    private static func uptimeString(_ seconds: TimeInterval) -> String {
        let intValue = Int(seconds)
        let hours = intValue / 3600
        let minutes = (intValue % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
