import AppKit
import ClaudeRemainderCore
import Foundation

@MainActor
final class AppController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private var settings: AppSettings
    private var snapshots: [UUID: AccountUsageSnapshot]
    private var states: [UUID: AccountUsageState] = [:]

    private let settingsStore: SettingsStore
    private let snapshotStore: SnapshotStore
    private let credentialReader: CredentialReader
    private let usageClient: UsageAPIClient

    private var autoRefreshTask: Task<Void, Never>?
    private var loginDetectionTasks: [UUID: Task<Void, Never>] = [:]
    private var nextAllowedRefreshAt: [UUID: Date] = [:]
    private var failureCounts: [UUID: Int] = [:]

    private var networkRefreshCount = 0
    private var resourceSampler = ResourceSampler()
    private var resourceWindowController: ResourceWindowController?

    init(paths: AppPaths? = nil) {
        let resolvedPaths: AppPaths
        if let paths {
            resolvedPaths = paths
        } else if let appSupport = try? AppPaths() {
            resolvedPaths = appSupport
        } else {
            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("ClaudeRemainder", isDirectory: true)
            resolvedPaths = try! AppPaths(root: tempRoot)
        }

        settingsStore = SettingsStore(paths: resolvedPaths)
        snapshotStore = SnapshotStore(paths: resolvedPaths)
        credentialReader = CredentialReader()
        usageClient = UsageAPIClient()

        settings = settingsStore.load()
        snapshots = snapshotStore.load()

        super.init()

        for profile in settings.profiles {
            if let snapshot = snapshots[profile.id] {
                let stale = RefreshPolicy.isSnapshotStale(fetchedAt: snapshot.fetchedAt)
                states[profile.id] = AccountUsageState(status: stale ? .stale : .fresh)
            } else {
                states[profile.id] = AccountUsageState(status: .idle)
            }
        }
    }

    func start() {
        if let button = statusItem.button {
            button.title = menuBarTitle
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        }

        configureAutoRefresh()
        rebuildMenu()
    }

    private var menuBarTitle: String {
        let enabledProfiles = settings.profiles.filter(\.isEnabled)
        guard !enabledProfiles.isEmpty else { return "CR" }

        let sessionValues = enabledProfiles.compactMap { snapshots[$0.id]?.window(named: "Session")?.remainingPercent }
        guard !sessionValues.isEmpty else { return "CR" }

        let average = sessionValues.reduce(0, +) / Double(sessionValues.count)
        return String(format: "CR %.0f%%", average)
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let title = NSMenuItem(title: "Claude Remainder", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let subtitle = NSMenuItem(title: "See what remains", action: nil, keyEquivalent: "")
        subtitle.isEnabled = false
        menu.addItem(subtitle)

        menu.addItem(.separator())

        let refreshModeItem = NSMenuItem(title: "Auto Refresh", action: nil, keyEquivalent: "")
        let refreshSubmenu = NSMenu()
        for mode in AppSettings.AutoRefreshMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectAutoRefreshMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.autoRefreshMode == mode ? .on : .off
            refreshSubmenu.addItem(item)
        }
        refreshModeItem.submenu = refreshSubmenu
        menu.addItem(refreshModeItem)

        let concurrencyItem = NSMenuItem(title: "Concurrent Refreshes: \(settings.maxConcurrentRefreshes)", action: nil, keyEquivalent: "")
        let concurrencySubmenu = NSMenu()
        for value in 1...4 {
            let item = NSMenuItem(title: "\(value)", action: #selector(selectConcurrency(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = settings.maxConcurrentRefreshes == value ? .on : .off
            concurrencySubmenu.addItem(item)
        }
        concurrencyItem.submenu = concurrencySubmenu
        menu.addItem(concurrencyItem)

        menu.addItem(.separator())

        let addAccount = NSMenuItem(title: "Add Account…", action: #selector(addAccountAction), keyEquivalent: "")
        addAccount.target = self
        menu.addItem(addAccount)

        for profile in settings.profiles {
            menu.addItem(makeAccountMenuItem(for: profile))
        }

        menu.addItem(.separator())

        let refreshAll = NSMenuItem(title: "Refresh All", action: #selector(refreshAllAction), keyEquivalent: "r")
        refreshAll.target = self
        menu.addItem(refreshAll)

        let resources = NSMenuItem(title: "Resource Usage…", action: #selector(openResourceWindow), keyEquivalent: "")
        resources.target = self
        menu.addItem(resources)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Claude Remainder", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        if let button = statusItem.button {
            button.title = menuBarTitle
        }
    }

    private func makeAccountMenuItem(for profile: AccountProfile) -> NSMenuItem {
        let item = NSMenuItem(title: profile.name, action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let status = profile.isEnabled ? "Enabled" : "Disabled"
        let statusItem = NSMenuItem(title: "Status: \(status)", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        submenu.addItem(statusItem)

        if let snapshot = snapshots[profile.id] {
            for window in snapshot.windows {
                let line = "\(window.label): \(Int(window.remainingPercent.rounded()))% left (reset \(Self.clockTime(window.resetsAt)))"
                let lineItem = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                lineItem.isEnabled = false
                submenu.addItem(lineItem)
            }

            let freshness = NSMenuItem(
                title: "Updated \(Self.relativeTime(snapshot.fetchedAt))",
                action: nil,
                keyEquivalent: ""
            )
            freshness.isEnabled = false
            submenu.addItem(freshness)
        } else {
            let noData = NSMenuItem(title: "No usage data yet", action: nil, keyEquivalent: "")
            noData.isEnabled = false
            submenu.addItem(noData)
        }

        if let state = states[profile.id], let error = state.lastError {
            let errorItem = NSMenuItem(title: "Note: \(error.errorDescription ?? "Refresh failed")", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            submenu.addItem(errorItem)
        }

        submenu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshProfileAction(_:)), keyEquivalent: "")
        refreshItem.target = self
        refreshItem.representedObject = profile.id.uuidString
        submenu.addItem(refreshItem)

        let loginItem = NSMenuItem(title: "Login", action: #selector(loginProfileAction(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.representedObject = profile.id.uuidString
        submenu.addItem(loginItem)

        let toggleItem = NSMenuItem(title: profile.isEnabled ? "Disable" : "Enable", action: #selector(toggleProfileEnabled(_:)), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.representedObject = profile.id.uuidString
        submenu.addItem(toggleItem)

        let editItem = NSMenuItem(title: "Edit…", action: #selector(editProfileAction(_:)), keyEquivalent: "")
        editItem.target = self
        editItem.representedObject = profile.id.uuidString
        submenu.addItem(editItem)

        let moveUp = NSMenuItem(title: "Move Up", action: #selector(moveProfileUpAction(_:)), keyEquivalent: "")
        moveUp.target = self
        moveUp.representedObject = profile.id.uuidString
        moveUp.isEnabled = settings.profiles.first?.id != profile.id
        submenu.addItem(moveUp)

        let moveDown = NSMenuItem(title: "Move Down", action: #selector(moveProfileDownAction(_:)), keyEquivalent: "")
        moveDown.target = self
        moveDown.representedObject = profile.id.uuidString
        moveDown.isEnabled = settings.profiles.last?.id != profile.id
        submenu.addItem(moveDown)

        let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteProfileAction(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = profile.id.uuidString
        submenu.addItem(deleteItem)

        item.submenu = submenu
        return item
    }

    @objc private func selectAutoRefreshMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? Int,
              let mode = AppSettings.AutoRefreshMode(rawValue: raw) else {
            return
        }

        settings.autoRefreshMode = mode
        saveSettings()
        configureAutoRefresh()
        rebuildMenu()
    }

    @objc private func selectConcurrency(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Int else { return }
        settings.maxConcurrentRefreshes = max(1, min(value, 4))
        saveSettings()
        rebuildMenu()
    }

    @objc private func addAccountAction() {
        guard var profile = promptForProfile(existing: nil) else { return }

        if profile.customConfigDirectory == nil {
            let suffix = settings.profiles.count + 1
            profile.customConfigDirectory = "~/.claude-account-\(suffix)"
        }

        settings.profiles.append(profile)
        states[profile.id] = AccountUsageState(status: .idle)
        saveSettings()
        rebuildMenu()
        launchLogin(for: profile)
    }

    @objc private func editProfileAction(_ sender: NSMenuItem) {
        guard let profile = profileFrom(sender: sender),
              let updated = promptForProfile(existing: profile) else {
            return
        }

        guard let index = settings.profiles.firstIndex(where: { $0.id == profile.id }) else {
            return
        }

        settings.profiles[index] = updated
        saveSettings()
        rebuildMenu()
    }

    @objc private func toggleProfileEnabled(_ sender: NSMenuItem) {
        guard let profile = profileFrom(sender: sender),
              let index = settings.profiles.firstIndex(where: { $0.id == profile.id }) else {
            return
        }

        settings.profiles[index].isEnabled.toggle()
        saveSettings()
        rebuildMenu()
    }

    @objc private func moveProfileUpAction(_ sender: NSMenuItem) {
        guard let profile = profileFrom(sender: sender),
              let index = settings.profiles.firstIndex(where: { $0.id == profile.id }),
              index > 0 else {
            return
        }

        settings.profiles.swapAt(index, index - 1)
        saveSettings()
        rebuildMenu()
    }

    @objc private func moveProfileDownAction(_ sender: NSMenuItem) {
        guard let profile = profileFrom(sender: sender),
              let index = settings.profiles.firstIndex(where: { $0.id == profile.id }),
              index < settings.profiles.count - 1 else {
            return
        }

        settings.profiles.swapAt(index, index + 1)
        saveSettings()
        rebuildMenu()
    }

    @objc private func deleteProfileAction(_ sender: NSMenuItem) {
        guard let profile = profileFrom(sender: sender) else { return }

        let alert = NSAlert()
        alert.messageText = "Delete \(profile.name)?"
        alert.informativeText = "This only removes the profile from Claude Remainder and does not delete Claude credentials from disk or keychain."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        settings.profiles.removeAll { $0.id == profile.id }
        snapshots.removeValue(forKey: profile.id)
        states.removeValue(forKey: profile.id)
        nextAllowedRefreshAt.removeValue(forKey: profile.id)
        failureCounts.removeValue(forKey: profile.id)
        loginDetectionTasks[profile.id]?.cancel()
        loginDetectionTasks.removeValue(forKey: profile.id)

        saveSettings()
        saveSnapshots()
        rebuildMenu()
    }

    @objc private func refreshAllAction() {
        Task { await refreshAll(manualTriggered: true) }
    }

    @objc private func refreshProfileAction(_ sender: NSMenuItem) {
        guard let profile = profileFrom(sender: sender) else { return }
        Task { await refreshProfiles([profile], manualTriggered: true) }
    }

    @objc private func loginProfileAction(_ sender: NSMenuItem) {
        guard let profile = profileFrom(sender: sender) else { return }
        launchLogin(for: profile)
    }

    @objc private func openResourceWindow() {
        if resourceWindowController == nil {
            resourceWindowController = ResourceWindowController(
                sampler: { [weak self] in
                    guard let self else { return nil }
                    return self.sampleResourceUsage()
                },
                openActivityMonitor: { [weak self] in
                    self?.openActivityMonitor()
                }
            )
        }

        resourceWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    private func profileFrom(sender: NSMenuItem) -> AccountProfile? {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString) else {
            return nil
        }

        return settings.profiles.first { $0.id == id }
    }

    private func refreshAll(manualTriggered: Bool) async {
        let profiles = settings.profiles.filter(\.isEnabled)
        await refreshProfiles(profiles, manualTriggered: manualTriggered)
    }

    private func refreshProfiles(_ profiles: [AccountProfile], manualTriggered: Bool) async {
        let now = Date()
        let maxConcurrent = max(1, settings.maxConcurrentRefreshes)

        let targets = profiles.filter { profile in
            if manualTriggered {
                return true
            }
            if let blockedUntil = nextAllowedRefreshAt[profile.id], now < blockedUntil {
                return false
            }
            return profile.isEnabled
        }

        guard !targets.isEmpty else { return }

        for profile in targets {
            states[profile.id] = AccountUsageState(status: .loading)
        }
        rebuildMenu()

        for chunkStart in stride(from: 0, to: targets.count, by: maxConcurrent) {
            let chunkEnd = min(chunkStart + maxConcurrent, targets.count)
            let chunk = Array(targets[chunkStart..<chunkEnd])

            await withTaskGroup(of: (UUID, Result<AccountUsageSnapshot, UsageFetchError>).self) { group in
                for profile in chunk {
                    group.addTask { [credentialReader, usageClient] in
                        guard let credentials = credentialReader.readCredentials(for: profile) else {
                            return (profile.id, .failure(.missingCredentials))
                        }

                        do {
                            let windows = try await usageClient.fetchUsage(accessToken: credentials.accessToken)
                            return (
                                profile.id,
                                .success(AccountUsageSnapshot(profileID: profile.id, fetchedAt: Date(), windows: windows))
                            )
                        } catch let error as UsageFetchError {
                            return (profile.id, .failure(error))
                        } catch {
                            return (profile.id, .failure(.network(error.localizedDescription)))
                        }
                    }
                }

                for await (profileID, result) in group {
                    networkRefreshCount += 1
                    applyRefreshResult(profileID: profileID, result: result)
                }
            }
        }

        saveSnapshots()
        rebuildMenu()
    }

    private func applyRefreshResult(profileID: UUID, result: Result<AccountUsageSnapshot, UsageFetchError>) {
        switch result {
        case .success(let snapshot):
            snapshots[profileID] = snapshot
            states[profileID] = AccountUsageState(status: .fresh)
            failureCounts[profileID] = 0
            nextAllowedRefreshAt[profileID] = nil

        case .failure(let error):
            let failures = (failureCounts[profileID] ?? 0) + 1
            failureCounts[profileID] = failures
            nextAllowedRefreshAt[profileID] = Date().addingTimeInterval(
                RefreshPolicy.nextRetryDelaySeconds(failureCount: failures)
            )

            if let snapshot = snapshots[profileID] {
                let stale = RefreshPolicy.isSnapshotStale(fetchedAt: snapshot.fetchedAt)
                states[profileID] = AccountUsageState(status: stale ? .stale : .fresh, lastError: error)
            } else {
                states[profileID] = AccountUsageState(status: .error(error.errorDescription ?? "Refresh failed"), lastError: error)
            }
        }
    }

    private func configureAutoRefresh() {
        autoRefreshTask?.cancel()

        guard settings.autoRefreshMode != .off else {
            autoRefreshTask = nil
            return
        }

        let seconds = settings.autoRefreshMode.rawValue * 60

        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(seconds))
                } catch {
                    return
                }
                await self?.refreshAll(manualTriggered: false)
            }
        }
    }

    private func launchLogin(for profile: AccountProfile) {
        let command: String
        if profile.usesDefaultConfig {
            command = "claude auth login"
        } else {
            let configPath = profile.resolvedConfigDirectory().path.replacingOccurrences(of: "'", with: "'\\''")
            command = "CLAUDE_CONFIG_DIR='\(configPath)' claude auth login"
        }

        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Terminal\" to do script \"\(escaped)\""]
        try? process.run()

        loginDetectionTasks[profile.id]?.cancel()
        loginDetectionTasks[profile.id] = Task { [weak self] in
            for _ in 0..<24 {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }

                if self.credentialReader.readCredentials(for: profile) != nil {
                    await self.refreshProfiles([profile], manualTriggered: true)
                    return
                }
            }
        }
    }

    private func promptForProfile(existing: AccountProfile?) -> AccountProfile? {
        let alert = NSAlert()
        alert.messageText = existing == nil ? "Add Account" : "Edit Account"
        alert.informativeText = "Leave config directory empty to use ~/.claude"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let nameField = NSTextField(string: existing?.name ?? "")
        nameField.placeholderString = "Account name"

        let pathField = NSTextField(string: existing?.customConfigDirectory ?? "")
        pathField.placeholderString = "~/.claude-work"

        let enabledButton = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
        enabledButton.state = (existing?.isEnabled ?? true) ? .on : .off

        stack.addArrangedSubview(nameField)
        stack.addArrangedSubview(pathField)
        stack.addArrangedSubview(enabledButton)

        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        let trimmedName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return nil
        }

        let trimmedPath = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        return AccountProfile(
            id: existing?.id ?? UUID(),
            name: trimmedName,
            customConfigDirectory: trimmedPath.isEmpty ? nil : trimmedPath,
            isEnabled: enabledButton.state == .on
        )
    }

    private func saveSettings() {
        try? settingsStore.save(settings)
    }

    private func saveSnapshots() {
        try? snapshotStore.save(snapshots)
    }

    private func sampleResourceUsage() -> ResourceMetrics {
        resourceSampler.sample(
            cacheBytes: snapshotStore.fileSizeBytes(),
            networkRefreshCount: networkRefreshCount
        )
    }

    private func openActivityMonitor() {
        let appURL = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.open(appURL)
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
