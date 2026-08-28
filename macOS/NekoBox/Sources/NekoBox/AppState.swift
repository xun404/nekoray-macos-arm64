import AppKit
import Combine
import Foundation

enum CoreDownloadStatus: Equatable {
    case idle
    case downloading(CoreKind)
    case completed(CoreKind, String)
    case failed(CoreKind)
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedSidebarItem: SidebarItem = .overview
    @Published var selectedGroupID: Int?
    @Published var selectedProfileID: Int?
    @Published private(set) var groups: [ProxyGroup] = []
    @Published private(set) var profiles: [ProxyProfile] = []
    @Published private(set) var connections: [Connection] = []
    @Published private(set) var activityLogs: [ActivityLog] = []
    @Published private(set) var notice: String?
    @Published private(set) var coreAvailability: CoreAvailability
    @Published private(set) var isRunning = false
    @Published private(set) var selectedCore: CoreKind
    @Published private(set) var coreInstallationRecords: [CoreKind: CoreInstallationRecord] = [:]
    @Published private(set) var coreDownloadStatus: CoreDownloadStatus = .idle

    private let legacyRepository: LegacyRepository
    private let nativeRepository: NativeRepository
    private let coreService: CoreServiceManager
    private var nativeSnapshot: NativeSnapshot
    private var legacySnapshot: LegacySnapshot?

    init(
        legacyRepository: LegacyRepository = LegacyRepository(),
        nativeRepository: NativeRepository = NativeRepository(),
        coreService: CoreServiceManager = CoreServiceManager()
    ) {
        self.legacyRepository = legacyRepository
        self.nativeRepository = nativeRepository
        self.coreService = coreService
        selectedCore = coreService.selectedCore
        coreInstallationRecords = CoreInstallation.allRecords()
        nativeSnapshot = nativeRepository.load()
        coreAvailability = coreService.availability
        reloadLegacyData()
        appendActivity(
            L10n.text("state.nativeStorageReady", nativeRepository.stateURL.path),
            level: .info
        )
    }

    var selectedGroup: ProxyGroup? {
        groups.first { $0.id == selectedGroupID }
    }

    var selectedProfile: ProxyProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    var selectedProfileIsNative: Bool {
        selectedProfile?.origin == .native
    }

    var nativeProfileCount: Int {
        nativeSnapshot.profiles.count
    }

    var nativeStorageLocation: String {
        nativeRepository.stateURL.path
    }

    var coreStatusTitle: String {
        isRunning
            ? L10n.text("core.status.connected", selectedCore.displayName)
            : L10n.text("core.status.unavailable", selectedCore.displayName)
    }

    var coreAvailabilityDescription: String {
        coreAvailability.description(for: selectedCore)
    }

    func profiles(matching query: String = "") -> [ProxyProfile] {
        let groupProfiles = profiles.filter { selectedGroupID == nil || $0.groupID == selectedGroupID }
        guard !query.isEmpty else { return groupProfiles }

        return groupProfiles.filter {
            $0.displayedName.localizedCaseInsensitiveContains(query) ||
            $0.address.localizedCaseInsensitiveContains(query) ||
            $0.type.localizedCaseInsensitiveContains(query)
        }
    }

    func profileCount(in group: ProxyGroup) -> Int {
        profiles.filter { $0.groupID == group.id }.count
    }

    func selectGroup(_ groupID: Int?) {
        selectedGroupID = groupID
        if let groupID, !profiles.contains(where: { $0.id == selectedProfileID && $0.groupID == groupID }) {
            selectedProfileID = profiles.first(where: { $0.groupID == groupID })?.id
        }
        persistSelection()
    }

    func selectProfile(_ profileID: Int?) {
        selectedProfileID = profileID
        if let profileID, let profile = profiles.first(where: { $0.id == profileID }) {
            selectedGroupID = profile.groupID
        }
        persistSelection()
    }

    func reloadLegacyData() {
        legacySnapshot = legacyRepository.load()
        rebuildVisibleData()
        appendActivity(legacySnapshot?.sourceDescription ?? L10n.text("state.legacyProfilesReloaded"), level: .info)
    }

    func makeNewProfileDraft() -> ProxyDraft {
        ProxyDraft(groupID: selectedGroupID ?? groups.first?.id ?? 0)
    }

    func makeProfileDraft(for profile: ProxyProfile) -> ProxyDraft {
        ProxyDraft(profile: profile)
    }

    func saveProfile(_ draft: ProxyDraft) {
        guard draft.isValid else {
            notice = L10n.text("state.invalidProfile")
            return
        }

        if let id = draft.id,
           let index = nativeSnapshot.profiles.firstIndex(where: { $0.id == id }) {
            nativeSnapshot.profiles[index].name = draft.trimmedName
            nativeSnapshot.profiles[index].type = draft.type
            nativeSnapshot.profiles[index].address = draft.endpoint
            nativeSnapshot.profiles[index].groupID = draft.groupID
            nativeSnapshot.profiles[index].origin = .native
            nativeSnapshot.profiles[index].xraySettings = draft.xraySettings
            selectedProfileID = id
            appendActivity(L10n.text("state.profileUpdated", draft.trimmedName), level: .success)
        } else {
            let profile = ProxyProfile(
                id: nextNativeProfileID(),
                groupID: draft.groupID,
                type: draft.type,
                name: draft.trimmedName,
                address: draft.endpoint,
                latencyMilliseconds: 0,
                uploadedBytes: 0,
                downloadedBytes: 0,
                testReport: "",
                origin: .native,
                xraySettings: draft.xraySettings
            )
            nativeSnapshot.profiles.append(profile)
            selectedGroupID = profile.groupID
            selectedProfileID = profile.id
            appendActivity(L10n.text("state.profileAdded", profile.displayedName), level: .success)
        }

        rebuildVisibleData()
        persistNativeData()
    }

    func deleteSelectedProfile() {
        guard let profile = selectedProfile else {
            notice = L10n.text("state.selectProxyToRemove")
            return
        }

        guard profile.origin == .native else {
            notice = L10n.text("state.legacyProfileReadOnly")
            return
        }

        nativeSnapshot.profiles.removeAll { $0.id == profile.id }
        selectedProfileID = profiles.first(where: { $0.groupID == selectedGroupID && $0.id != profile.id })?.id
        rebuildVisibleData()
        persistNativeData()
        appendActivity(L10n.text("state.profileRemoved", profile.displayedName), level: .warning)
    }

    func createGroup(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            notice = L10n.text("state.enterGroupName")
            return
        }

        let group = ProxyGroup(
            id: nextNativeGroupID(),
            name: trimmedName,
            isArchived: false,
            subscriptionURL: nil,
            profileOrder: [],
            origin: .native
        )
        nativeSnapshot.groups.append(group)
        selectedGroupID = group.id
        selectedProfileID = nil
        rebuildVisibleData()
        persistNativeData()
        appendActivity(L10n.text("state.groupCreated", group.name), level: .success)
    }

    func renameGroup(_ group: ProxyGroup, to name: String) {
        guard group.origin == .native else {
            notice = L10n.text("state.legacyGroupReadOnly")
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            notice = L10n.text("state.enterGroupName")
            return
        }

        guard let index = nativeSnapshot.groups.firstIndex(where: { $0.id == group.id }) else { return }
        nativeSnapshot.groups[index].name = trimmedName
        rebuildVisibleData()
        persistNativeData()
        appendActivity(L10n.text("state.groupRenamed", trimmedName), level: .success)
    }

    func deleteGroup(_ group: ProxyGroup) {
        guard group.origin == .native else {
            notice = L10n.text("state.legacyGroupReadOnly")
            return
        }

        let fallbackGroupID = groups.first(where: { $0.id != group.id })?.id ?? 0
        nativeSnapshot.groups.removeAll { $0.id == group.id }
        nativeSnapshot.profiles = nativeSnapshot.profiles.map { profile in
            var profile = profile
            if profile.groupID == group.id {
                profile.groupID = fallbackGroupID
            }
            return profile
        }
        selectedGroupID = fallbackGroupID
        selectedProfileID = nil
        rebuildVisibleData()
        persistNativeData()
        appendActivity(L10n.text("state.groupRemoved", group.name), level: .warning)
    }

    func startSelectedProfile() {
        guard let profile = selectedProfile else {
            notice = L10n.text("state.selectProxyToConnect")
            return
        }

        Task {
            do {
                try await coreService.start(profile: profile)
                isRunning = coreService.isRunning
                coreAvailability = coreService.availability
                appendActivity(L10n.text("state.profileStarted", profile.displayedName), level: .success)
            } catch {
                notice = error.localizedDescription
                appendActivity(L10n.text("state.connectionNotStarted", error.localizedDescription), level: .warning)
            }
        }
    }

    func stopCore() {
        Task {
            do {
                try await coreService.stop()
                isRunning = coreService.isRunning
                coreAvailability = coreService.availability
                appendActivity(L10n.text("state.coreStopped"), level: .info)
            } catch {
                notice = error.localizedDescription
                appendActivity(L10n.text("state.coreStopFailed", error.localizedDescription), level: .error)
            }
        }
    }

    func requestLatencyTest() {
        guard selectedProfile != nil else {
            notice = L10n.text("state.selectProxyToTest")
            return
        }
        notice = L10n.text("state.latencyUnavailable")
        appendActivity(L10n.text("state.latencyRequested"), level: .info)
    }

    func showSystemServiceStatus() {
        notice = L10n.text("state.systemServiceUnavailable")
    }

    func refreshCoreAvailability() {
        coreAvailability = coreService.availability
        isRunning = coreService.isRunning
        coreInstallationRecords = CoreInstallation.allRecords()
    }

    func selectCore(_ core: CoreKind) {
        do {
            try coreService.select(core)
            selectedCore = coreService.selectedCore
            refreshCoreAvailability()
            appendActivity(L10n.text("state.coreSelected", selectedCore.displayName), level: .info)
        } catch {
            notice = error.localizedDescription
        }
    }

    func installationRecord(for core: CoreKind) -> CoreInstallationRecord? {
        coreInstallationRecords[core]
    }

    func isDownloadingCore(_ core: CoreKind) -> Bool {
        if case .downloading(let downloadingCore) = coreDownloadStatus {
            return downloadingCore == core
        }
        return false
    }

    var hasActiveCoreDownload: Bool {
        if case .downloading = coreDownloadStatus {
            return true
        }
        return false
    }

    func downloadOfficialCore(_ core: CoreKind) {
        guard !isRunning else {
            notice = L10n.text("state.stopCoreBeforeDownload")
            return
        }
        guard !isDownloadingCore(.xray), !isDownloadingCore(.singBox) else { return }

        coreDownloadStatus = .downloading(core)
        Task {
            do {
                let result = try await CoreDownloader.downloadAndInstall(core)
                core.setExecutable(result.executableURL)
                coreDownloadStatus = .completed(core, result.version)
                refreshCoreAvailability()
                appendActivity(
                    L10n.text("state.coreDownloaded", core.displayName, result.version),
                    level: .success
                )
            } catch {
                coreDownloadStatus = .failed(core)
                notice = error.localizedDescription
                appendActivity(
                    L10n.text("state.coreDownloadFailed", core.displayName, error.localizedDescription),
                    level: .error
                )
            }
        }
    }

    func copySelectedEndpoint() {
        guard let profile = selectedProfile else {
            notice = L10n.text("state.selectProxyToCopy")
            return
        }
        copyToPasteboard(profile.address)
        notice = L10n.text("state.endpointCopied", profile.address)
        appendActivity(L10n.text("state.endpointCopyLogged", profile.displayedName), level: .info)
    }

    func copyLogs() {
        let text = activityLogs.map { entry in
            let timestamp = entry.date.formatted(date: .omitted, time: .standard)
            return "[\(timestamp)] \(entry.level.rawValue.uppercased()): \(entry.message)"
        }
        .joined(separator: "\n")
        copyToPasteboard(text)
        notice = L10n.text("state.logsCopied", String(activityLogs.count))
    }

    func clearLogs() {
        activityLogs.removeAll()
        appendActivity(L10n.text("state.logsCleared"), level: .info)
    }

    func clearNotice() {
        notice = nil
    }

    func presentNotice(_ message: String) {
        notice = message
    }

    private func rebuildVisibleData() {
        let legacyGroups = legacySnapshot?.groups ?? []
        let legacyProfiles = legacySnapshot?.profiles ?? []
        let nativeGroups = nativeSnapshot.groups.map { group -> ProxyGroup in
            var group = group
            group.origin = .native
            return group
        }
        let nativeProfiles = nativeSnapshot.profiles.map { profile -> ProxyProfile in
            var profile = profile
            profile.origin = .native
            return profile
        }

        groups = merge(legacyGroups, with: nativeGroups)
        profiles = legacyProfiles + nativeProfiles

        let requestedGroupID = selectedGroupID ?? nativeSnapshot.selectedGroupID
        selectedGroupID = groups.contains(where: { $0.id == requestedGroupID })
            ? requestedGroupID
            : groups.first?.id

        let requestedProfileID = selectedProfileID ?? nativeSnapshot.selectedProfileID
        selectedProfileID = profiles.contains(where: { $0.id == requestedProfileID })
            ? requestedProfileID
            : profiles.first(where: { $0.groupID == selectedGroupID })?.id
    }

    private func merge(_ legacyGroups: [ProxyGroup], with nativeGroups: [ProxyGroup]) -> [ProxyGroup] {
        var result = legacyGroups
        for group in nativeGroups where !result.contains(where: { $0.id == group.id }) {
            result.append(group)
        }
        return result.sorted {
            if $0.isArchived != $1.isArchived { return !$0.isArchived }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func persistSelection() {
        nativeSnapshot.selectedGroupID = selectedGroupID
        nativeSnapshot.selectedProfileID = selectedProfileID
        persistNativeData()
    }

    private func persistNativeData() {
        nativeSnapshot.selectedGroupID = selectedGroupID
        nativeSnapshot.selectedProfileID = selectedProfileID
        do {
            try nativeRepository.save(nativeSnapshot)
        } catch {
            notice = L10n.text("state.saveFailed", error.localizedDescription)
            appendActivity(L10n.text("state.storageFailed", error.localizedDescription), level: .error)
        }
    }

    private func nextNativeGroupID() -> Int {
        (nativeSnapshot.groups.map(\.id).min() ?? 0) - 1
    }

    private func nextNativeProfileID() -> Int {
        (nativeSnapshot.profiles.map(\.id).min() ?? 0) - 1
    }

    private func appendActivity(_ message: String, level: ActivityLog.Level) {
        activityLogs.append(ActivityLog(id: UUID(), date: .now, level: level, message: message))
        if activityLogs.count > 250 {
            activityLogs.removeFirst(activityLogs.count - 250)
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
