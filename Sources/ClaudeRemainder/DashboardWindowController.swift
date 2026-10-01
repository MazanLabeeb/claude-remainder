import AppKit
import ClaudeRemainderCore
import Foundation

final class DashboardWindowController: NSWindowController {
    private let refreshAll: () -> Void
    private let addAccount: () -> Void
    private let openResourceUsage: () -> Void

    private let summaryLabel = NSTextField(labelWithString: "")
    private let detailsTextView = NSTextView()

    init(
        refreshAll: @escaping () -> Void,
        addAccount: @escaping () -> Void,
        openResourceUsage: @escaping () -> Void
    ) {
        self.refreshAll = refreshAll
        self.addAccount = addAccount
        self.openResourceUsage = openResourceUsage

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Remainder"

        super.init(window: window)
        buildUI(in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        settings: AppSettings,
        snapshots: [UUID: AccountUsageSnapshot],
        states: [UUID: AccountUsageState],
        menuBarTitle: String,
        profileDisplayNames: [UUID: String]
    ) {
        summaryLabel.stringValue = "Now: \(menuBarTitle)"

        var lines: [String] = []
        lines.append("One-click account view")
        lines.append("")

        for profile in settings.profiles {
            let displayName = profileDisplayNames[profile.id] ?? profile.name
            lines.append("────────────────────────────────────────")
            lines.append("\(profile.isEnabled ? "●" : "○") \(displayName)")

            if let snapshot = snapshots[profile.id] {
                for window in snapshot.windows {
                    lines.append("  \(window.label) used \(Int(window.usedPercent.rounded()))% (reset \(Self.clockTime(window.resetsAt)))")
                }

                if settings.showMetadataInDashboard, !snapshot.metadata.isEmpty {
                    lines.append("  API details:")
                    for item in snapshot.metadata {
                        lines.append("    • \(item.key): \(item.value)")
                    }
                }

                lines.append("  Updated \(Self.relativeTime(snapshot.fetchedAt))")
            } else {
                lines.append("  No usage data yet")
            }

            if let state = states[profile.id], let error = state.lastError {
                lines.append("  Note: \(error.errorDescription ?? "Refresh failed")")
            }

            lines.append("")
        }

        if settings.profiles.isEmpty {
            lines.append("No profiles configured yet. Use Add Account.")
        }

        lines.append("────────────────────────────────────────")
        detailsTextView.string = lines.joined(separator: "\n")
    }

    private func buildUI(in window: NSWindow) {
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView

        let titleLabel = NSTextField(labelWithString: "Claude Remainder")
        titleLabel.font = NSFont.systemFont(ofSize: 26, weight: .bold)

        let subtitleLabel = NSTextField(labelWithString: "Used usage across all accounts")
        subtitleLabel.font = NSFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor

        summaryLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)

        let refreshButton = NSButton(title: "Refresh All", target: self, action: #selector(refreshAllAction))
        refreshButton.bezelStyle = .rounded

        let addAccountButton = NSButton(title: "Add Account", target: self, action: #selector(addAccountAction))
        addAccountButton.bezelStyle = .rounded

        let resourceButton = NSButton(title: "Resource Usage", target: self, action: #selector(openResourceUsageAction))
        resourceButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [refreshButton, addAccountButton, resourceButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        detailsTextView.isEditable = false
        detailsTextView.isSelectable = true
        detailsTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        detailsTextView.textContainerInset = NSSize(width: 8, height: 8)
        detailsTextView.backgroundColor = .textBackgroundColor
        detailsTextView.isVerticallyResizable = true
        detailsTextView.isHorizontallyResizable = false
        detailsTextView.autoresizingMask = [.width]
        detailsTextView.frame = NSRect(x: 0, y: 0, width: 560, height: 320)
        detailsTextView.textContainer?.widthTracksTextView = true
        detailsTextView.textContainer?.containerSize = NSSize(width: 560, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = detailsTextView

        let stack = NSStackView(views: [titleLabel, subtitleLabel, summaryLabel, buttonRow, scrollView])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])
    }

    @objc private func refreshAllAction() {
        refreshAll()
    }

    @objc private func addAccountAction() {
        addAccount()
    }

    @objc private func openResourceUsageAction() {
        openResourceUsage()
    }

    private static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func clockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
