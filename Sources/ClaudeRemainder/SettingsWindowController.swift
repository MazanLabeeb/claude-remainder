import AppKit
import ClaudeRemainderCore
import Foundation

final class SettingsWindowController: NSWindowController {
    private let onSaveProfile: (AccountProfile) -> Void
    private let onSetDefaultProfile: (UUID?) -> Void
    private let onSetMetadataVisibility: (Bool) -> Void
    private let onAddAccount: () -> Void

    private var settings: AppSettings = .default()
    private var profileDisplayNames: [UUID: String] = [:]

    private let statusTextLabel = NSTextField(labelWithString: "Status bar: --")
    private let defaultProfilePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let profilePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let nameField = NSTextField(string: "")
    private let pathField = NSTextField(string: "")
    private let enabledCheckbox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let metadataCheckbox = NSButton(checkboxWithTitle: "Show API metadata in dashboard", target: nil, action: nil)
    private let defaultProfileLabel = NSTextField(labelWithString: "Default profile: --")

    init(
        onSaveProfile: @escaping (AccountProfile) -> Void,
        onSetDefaultProfile: @escaping (UUID?) -> Void,
        onSetMetadataVisibility: @escaping (Bool) -> Void,
        onAddAccount: @escaping () -> Void
    ) {
        self.onSaveProfile = onSaveProfile
        self.onSetDefaultProfile = onSetDefaultProfile
        self.onSetMetadataVisibility = onSetMetadataVisibility
        self.onAddAccount = onAddAccount

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Remainder Settings"

        super.init(window: window)
        buildUI(in: window)
        wireActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(settings: AppSettings, profileDisplayNames: [UUID: String], statusBarText: String) {
        self.settings = settings
        self.profileDisplayNames = profileDisplayNames

        statusTextLabel.stringValue = "Status bar: \(statusBarText)"
        metadataCheckbox.state = settings.showMetadataInDashboard ? .on : .off

        let previousSelectionID = selectedProfileID()
        let previousDefaultSelectionID = selectedDefaultProfileID()
        profilePopup.removeAllItems()
        defaultProfilePopup.removeAllItems()
        defaultProfilePopup.addItem(withTitle: "(auto) first enabled profile")
        defaultProfilePopup.lastItem?.representedObject = ""

        for profile in settings.profiles {
            let display = profileDisplayNames[profile.id] ?? profile.name
            profilePopup.addItem(withTitle: display)
            profilePopup.lastItem?.representedObject = profile.id.uuidString

            defaultProfilePopup.addItem(withTitle: display)
            defaultProfilePopup.lastItem?.representedObject = profile.id.uuidString
        }

        if settings.profiles.isEmpty {
            nameField.stringValue = ""
            pathField.stringValue = ""
            enabledCheckbox.state = .off
            profilePopup.isEnabled = false
            defaultProfilePopup.isEnabled = false
            defaultProfileLabel.stringValue = "Default profile: --"
            return
        }

        profilePopup.isEnabled = true
        defaultProfilePopup.isEnabled = true

        if let previousSelectionID,
           let selectionIndex = settings.profiles.firstIndex(where: { $0.id == previousSelectionID }) {
            profilePopup.selectItem(at: selectionIndex)
        } else {
            profilePopup.selectItem(at: 0)
        }

        if let defaultID = settings.defaultProfileID,
           let defaultIndex = settings.profiles.firstIndex(where: { $0.id == defaultID }) {
            defaultProfilePopup.selectItem(at: defaultIndex + 1)
        } else if let previousDefaultSelectionID,
                  let defaultIndex = settings.profiles.firstIndex(where: { $0.id == previousDefaultSelectionID }) {
            defaultProfilePopup.selectItem(at: defaultIndex + 1)
        } else {
            defaultProfilePopup.selectItem(at: 0)
        }

        updateSelectedProfileFields()
        updateDefaultProfileLabel()
    }

    private func buildUI(in window: NSWindow) {
        let contentView = NSView()
        window.contentView = contentView

        let titleLabel = NSTextField(labelWithString: "Profile Settings")
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)

        let profileLabel = NSTextField(labelWithString: "Profile")
        profileLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let defaultProfileSelectLabel = NSTextField(labelWithString: "Default status profile")
        defaultProfileSelectLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        let nameLabel = NSTextField(labelWithString: "Name")
        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        let pathLabel = NSTextField(labelWithString: "Config directory")
        pathLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        pathField.placeholderString = "Leave empty to use ~/.claude"
        pathField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let saveButton = NSButton(title: "Save Profile", target: self, action: #selector(saveProfileAction))
        saveButton.bezelStyle = .rounded

        let setDefaultButton = NSButton(title: "Set Selected As Default", target: self, action: #selector(setDefaultAction))
        setDefaultButton.bezelStyle = .rounded

        let addAccountButton = NSButton(title: "Add Account", target: self, action: #selector(addAccountAction))
        addAccountButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [saveButton, setDefaultButton, addAccountButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let stack = NSStackView(views: [
            titleLabel,
            statusTextLabel,
            defaultProfileLabel,
            defaultProfileSelectLabel,
            defaultProfilePopup,
            profileLabel,
            profilePopup,
            nameLabel,
            nameField,
            pathLabel,
            pathField,
            enabledCheckbox,
            metadataCheckbox,
            buttonRow
        ])

        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16)
        ])
    }

    private func wireActions() {
        profilePopup.target = self
        profilePopup.action = #selector(profileSelectionChanged)

        defaultProfilePopup.target = self
        defaultProfilePopup.action = #selector(defaultProfileSelectionChanged)

        metadataCheckbox.target = self
        metadataCheckbox.action = #selector(metadataVisibilityChanged)
    }

    @objc private func profileSelectionChanged() {
        updateSelectedProfileFields()
    }

    @objc private func metadataVisibilityChanged() {
        onSetMetadataVisibility(metadataCheckbox.state == .on)
    }

    @objc private func defaultProfileSelectionChanged() {
        guard let represented = defaultProfilePopup.selectedItem?.representedObject as? String else {
            onSetDefaultProfile(nil)
            return
        }

        if represented.isEmpty {
            onSetDefaultProfile(nil)
        } else if let id = UUID(uuidString: represented) {
            onSetDefaultProfile(id)
        }
    }

    @objc private func saveProfileAction() {
        guard let profile = selectedProfile() else { return }

        let trimmedName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let trimmedPath = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        let updated = AccountProfile(
            id: profile.id,
            name: trimmedName,
            customConfigDirectory: trimmedPath.isEmpty ? nil : trimmedPath,
            isEnabled: enabledCheckbox.state == .on
        )

        onSaveProfile(updated)
    }

    @objc private func setDefaultAction() {
        guard let profile = selectedProfile() else { return }
        onSetDefaultProfile(profile.id)
    }

    @objc private func addAccountAction() {
        onAddAccount()
    }

    private func selectedProfileID() -> UUID? {
        guard let represented = profilePopup.selectedItem?.representedObject as? String else {
            return nil
        }

        return UUID(uuidString: represented)
    }

    private func selectedDefaultProfileID() -> UUID? {
        guard let represented = defaultProfilePopup.selectedItem?.representedObject as? String else {
            return nil
        }
        if represented.isEmpty {
            return nil
        }
        return UUID(uuidString: represented)
    }

    private func selectedProfile() -> AccountProfile? {
        guard let id = selectedProfileID() else { return nil }
        return settings.profiles.first { $0.id == id }
    }

    private func updateSelectedProfileFields() {
        guard let profile = selectedProfile() else {
            nameField.stringValue = ""
            pathField.stringValue = ""
            enabledCheckbox.state = .off
            return
        }

        nameField.stringValue = profile.name
        pathField.stringValue = profile.customConfigDirectory ?? ""
        enabledCheckbox.state = profile.isEnabled ? .on : .off
    }

    private func updateDefaultProfileLabel() {
        if let defaultID = settings.defaultProfileID,
           let profile = settings.profiles.first(where: { $0.id == defaultID }) {
            let display = profileDisplayNames[profile.id] ?? profile.name
            defaultProfileLabel.stringValue = "Default profile: \(display)"
        } else {
            defaultProfileLabel.stringValue = "Default profile: (auto) first enabled profile"
        }
    }
}
