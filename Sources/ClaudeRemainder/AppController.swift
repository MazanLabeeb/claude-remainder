import AppKit
import ClaudeRemainderCore
import Foundation

@MainActor
final class AppController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var statusBarIcon: NSImage?

    private var settings: AppSettings
    private var snapshots: [UUID: AccountUsageSnapshot]
    private var states: [UUID: AccountUsageState] = [:]
    private var profileDisplayNames: [UUID: String] = [:]

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
    private var dashboardWindowController: DashboardWindowController?
    private var settingsWindowController: SettingsWindowController?

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
        refreshProfileDisplayNames()
        configureStatusBarIcon()

        updateStatusBarButton()

        configureAutoRefresh()
        rebuildMenu()

        Task { await refreshAll(manualTriggered: true) }

        if !settings.hasSeenDashboardWindow {
            settings.hasSeenDashboardWindow = true
            saveSettings()
            openDashboardWindow()
        }
    }

    private var menuBarTitle: String {
        guard let profile = defaultStatusProfile() else {
            return "CR"
        }

        guard let used = snapshots[profile.id]?.window(named: "Session")?.usedPercent else {
            return "--"
        }

        return String(format: "%.0f%%", used)
    }

    private func defaultStatusProfile() -> AccountProfile? {
        if let defaultID = settings.defaultProfileID,
           let profile = settings.profiles.first(where: { $0.id == defaultID }) {
            return profile
        }

        return settings.profiles.first(where: { $0.isEnabled })
    }

    private func rebuildMenu() {
        let menu: NSMenu
        if let existingMenu = statusItem.menu {
            menu = existingMenu
            menu.removeAllItems()
        } else {
            menu = NSMenu()
            statusItem.menu = menu
        }
        menu.delegate = self

        let title = NSMenuItem(title: "Claude Remainder", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        if let defaultProfile = defaultStatusProfile() {
            let subtitle = NSMenuItem(
                title: "Status profile: \(displayName(for: defaultProfile))",
                action: nil,
                keyEquivalent: ""
            )
            subtitle.isEnabled = false
            menu.addItem(subtitle)
        } else {
            let subtitle = NSMenuItem(title: "Set default profile in Settings", action: nil, keyEquivalent: "")
            subtitle.isEnabled = false
            menu.addItem(subtitle)
        }

        let dashboardItem = NSMenuItem(title: "Open Dashboard…", action: #selector(openDashboardWindow), keyEquivalent: "d")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        if settings.profiles.isEmpty {
            let noAccount = NSMenuItem(title: "No accounts configured", action: nil, keyEquivalent: "")
            noAccount.isEnabled = false
            menu.addItem(noAccount)
        } else {
            for (index, profile) in settings.profiles.enumerated() {
                if index > 0 {
                    menu.addItem(.separator())
                }
                appendFlatProfileRows(profile, to: menu)
            }
        }

        menu.addItem(.separator())

        let refreshAll = NSMenuItem(title: "Refresh All", action: #selector(refreshAllAction), keyEquivalent: "r")
        refreshAll.target = self
        menu.addItem(refreshAll)

        let addAccount = NSMenuItem(title: "Add Account…", action: #selector(addAccountAction), keyEquivalent: "")
        addAccount.target = self
        menu.addItem(addAccount)

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

        let resources = NSMenuItem(title: "Resource Usage…", action: #selector(openResourceWindow), keyEquivalent: "")
        resources.target = self
        menu.addItem(resources)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Claude Remainder", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        updateStatusBarButton()

        dashboardWindowController?.update(
            settings: settings,
            snapshots: snapshots,
            states: states,
            menuBarTitle: menuBarTitle,
            profileDisplayNames: profileDisplayNames
        )

        settingsWindowController?.update(
            settings: settings,
            profileDisplayNames: profileDisplayNames,
            statusBarText: menuBarTitle
        )
    }

    private func appendFlatProfileRows(_ profile: AccountProfile, to menu: NSMenu) {
        let header = NSMenuItem(
            title: "\(profile.isEnabled ? "●" : "○") \(displayName(for: profile))",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)

        if let snapshot = snapshots[profile.id] {
            for window in snapshot.windows {
                let line = "   \(riskGlyph(for: window.usedPercent)) \(window.label) used \(Int(window.usedPercent.rounded()))% (reset \(Self.resetLabel(window.resetsAt)))"
                let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }

            let freshness = NSMenuItem(title: "   Updated \(Self.relativeTime(snapshot.fetchedAt))", action: nil, keyEquivalent: "")
            freshness.isEnabled = false
            menu.addItem(freshness)
        } else {
            let noData = NSMenuItem(title: "   No usage data yet", action: nil, keyEquivalent: "")
            noData.isEnabled = false
            menu.addItem(noData)
        }

        if let state = states[profile.id], let error = state.lastError {
            let errorItem = NSMenuItem(title: "   Note: \(error.errorDescription ?? "Refresh failed")", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        menu.addItem(actionMenuItem(title: "   Refresh \(profile.name)", selector: #selector(refreshProfileAction(_:)), profileID: profile.id))
        menu.addItem(actionMenuItem(title: "   Login \(profile.name)", selector: #selector(loginProfileAction(_:)), profileID: profile.id))
        menu.addItem(actionMenuItem(title: "   \(profile.isEnabled ? "Disable" : "Enable") \(profile.name)", selector: #selector(toggleProfileEnabled(_:)), profileID: profile.id))
    }

    private func actionMenuItem(title: String, selector: Selector, profileID: UUID) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.representedObject = profileID.uuidString
        return item
    }

    private func riskGlyph(for usedPercent: Double) -> String {
        switch usedPercent {
        case 90...:
            return "🔴"
        case 70...:
            return "🟠"
        default:
            return "🟢"
        }
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

    @objc private func addAccountAction() {
        guard var profile = promptForProfile(existing: nil) else { return }

        if profile.customConfigDirectory == nil {
            let suffix = settings.profiles.count + 1
            profile.customConfigDirectory = "~/.claude-account-\(suffix)"
        }

        settings.profiles.append(profile)
        states[profile.id] = AccountUsageState(status: .idle)
        refreshDisplayName(for: profile)

        if settings.defaultProfileID == nil {
            settings.defaultProfileID = profile.id
        }

        saveSettings()
        rebuildMenu()
        launchLogin(for: profile)
    }

    @objc private func toggleProfileEnabled(_ sender: NSMenuItem) {
        guard let profile = profileFrom(sender: sender),
              let index = settings.profiles.firstIndex(where: { $0.id == profile.id }) else {
            return
        }

        settings.profiles[index].isEnabled.toggle()

        if settings.defaultProfileID == profile.id, settings.profiles[index].isEnabled == false {
            settings.defaultProfileID = settings.profiles.first(where: { $0.isEnabled })?.id
        }

        saveSettings()
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

    @objc private func openDashboardWindow() {
        if dashboardWindowController == nil {
            dashboardWindowController = DashboardWindowController(
                refreshAll: { [weak self] in
                    Task { await self?.refreshAll(manualTriggered: true) }
                },
                addAccount: { [weak self] in
                    self?.addAccountAction()
                },
                openResourceUsage: { [weak self] in
                    self?.openResourceWindow()
                }
            )
        }

        dashboardWindowController?.update(
            settings: settings,
            snapshots: snapshots,
            states: states,
            menuBarTitle: menuBarTitle,
            profileDisplayNames: profileDisplayNames
        )
        dashboardWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                onSaveProfile: { [weak self] profile in
                    self?.saveProfileFromSettings(profile)
                },
                onSetDefaultProfile: { [weak self] profileID in
                    self?.setDefaultProfile(profileID)
                },
                onSetMetadataVisibility: { [weak self] isVisible in
                    self?.setMetadataVisibilityInDashboard(isVisible)
                },
                onAddAccount: { [weak self] in
                    self?.addAccountAction()
                }
            )
        }

        settingsWindowController?.update(
            settings: settings,
            profileDisplayNames: profileDisplayNames,
            statusBarText: menuBarTitle
        )
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func saveProfileFromSettings(_ profile: AccountProfile) {
        guard let index = settings.profiles.firstIndex(where: { $0.id == profile.id }) else {
            return
        }

        settings.profiles[index] = profile
        refreshDisplayName(for: profile)

        if settings.defaultProfileID == nil {
            settings.defaultProfileID = profile.id
        }

        if let defaultID = settings.defaultProfileID,
           settings.profiles.contains(where: { $0.id == defaultID }) == false {
            settings.defaultProfileID = settings.profiles.first(where: { $0.isEnabled })?.id
        }

        saveSettings()
        rebuildMenu()
    }

    private func setDefaultProfile(_ profileID: UUID?) {
        if let profileID,
           let index = settings.profiles.firstIndex(where: { $0.id == profileID }) {
            settings.profiles[index].isEnabled = true
        }

        settings.defaultProfileID = profileID
        saveSettings()
        rebuildMenu()
    }

    private func setMetadataVisibilityInDashboard(_ isVisible: Bool) {
        settings.showMetadataInDashboard = isVisible
        saveSettings()
        rebuildMenu()
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

    func menuWillOpen(_ menu: NSMenu) {
        // Refresh usage whenever the status menu is opened for fresher values.
        Task { await refreshAll(manualTriggered: true) }
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

            await withTaskGroup(of: (UUID, Result<AccountUsageSnapshot, UsageFetchError>, String?).self) { group in
                for profile in chunk {
                    group.addTask { [credentialReader, usageClient] in
                        guard let credentials = credentialReader.readCredentials(for: profile) else {
                            return (profile.id, .failure(.missingCredentials), nil)
                        }

                        do {
                            let payload = try await usageClient.fetchUsage(accessToken: credentials.accessToken)
                            return (
                                profile.id,
                                .success(
                                    AccountUsageSnapshot(
                                        profileID: profile.id,
                                        fetchedAt: Date(),
                                        windows: payload.windows,
                                        metadata: payload.metadata
                                    )
                                ),
                                credentials.email
                            )
                        } catch let error as UsageFetchError {
                            return (profile.id, .failure(error), credentials.email)
                        } catch {
                            return (profile.id, .failure(.network(error.localizedDescription)), credentials.email)
                        }
                    }
                }

                for await (profileID, result, email) in group {
                    networkRefreshCount += 1
                    applyRefreshResult(profileID: profileID, result: result)

                    if let profile = settings.profiles.first(where: { $0.id == profileID }) {
                        if let email, isPlaceholderName(profile.name) {
                            profileDisplayNames[profile.id] = "\(email) (\(profile.name))"
                        } else {
                            refreshDisplayName(for: profile)
                        }
                    }
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

    private func refreshProfileDisplayNames() {
        for profile in settings.profiles {
            refreshDisplayName(for: profile)
        }
    }

    private func refreshDisplayName(for profile: AccountProfile) {
        guard let credentials = credentialReader.readCredentials(for: profile),
              let email = credentials.email else {
            profileDisplayNames[profile.id] = profile.name
            return
        }

        if isPlaceholderName(profile.name) {
            profileDisplayNames[profile.id] = "\(email) (\(profile.name))"
        } else {
            profileDisplayNames[profile.id] = profile.name
        }
    }

    private func displayName(for profile: AccountProfile) -> String {
        profileDisplayNames[profile.id] ?? profile.name
    }

    private func isPlaceholderName(_ name: String) -> Bool {
        name == "Default" || name.hasPrefix("Account ")
    }

    private func saveSettings() {
        try? settingsStore.save(settings)
    }

    private func configureStatusBarIcon() {
        guard statusBarIcon == nil else { return }

        let icon = NSApp.applicationIconImage.copy() as? NSImage
        icon?.size = NSSize(width: 16, height: 16)
        icon?.isTemplate = false
        statusBarIcon = icon
    }

    private func updateStatusBarButton() {
        guard let button = statusItem.button else { return }

        button.image = statusBarIcon
        button.imagePosition = .imageLeading
        button.title = " \(menuBarTitle)"
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
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

    private static func resetLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = clockTime(date)

        if calendar.isDateInToday(date) {
            return "today \(time)"
        }
        if calendar.isDateInTomorrow(date) {
            return "tomorrow \(time)"
        }

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEE"
        let weekday = weekdayFormatter.string(from: date).lowercased()
        return "\(weekday) \(time)"
    }
}
