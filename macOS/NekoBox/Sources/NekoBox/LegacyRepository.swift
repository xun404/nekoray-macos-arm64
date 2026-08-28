import Foundation

/// Reads legacy profile JSON files without mutating them.
///
/// NekoBox's legacy profile format is intentionally decoded only to the level
/// needed for navigation and list presentation. Editing or generating an
/// outbound is deferred until the native configuration generator is available.
struct LegacyRepository {
    private let fileManager: FileManager
    let configurationDirectory: URL

    init(
        configurationDirectory: URL = LegacyRepository.defaultConfigurationDirectory(),
        fileManager: FileManager = .default
    ) {
        self.configurationDirectory = configurationDirectory
        self.fileManager = fileManager
    }

    func load() -> LegacySnapshot {
        let groupsDirectory = configurationDirectory.appending(path: "groups", directoryHint: .isDirectory)
        let profilesDirectory = configurationDirectory.appending(path: "profiles", directoryHint: .isDirectory)

        guard fileManager.fileExists(atPath: configurationDirectory.path) else {
            return LegacySnapshot(
                groups: [ProxyGroup(id: 0, name: L10n.text("legacy.defaultGroup"), isArchived: false, subscriptionURL: nil, profileOrder: [])],
                profiles: [],
                sourceDescription: L10n.text("legacy.noConfiguration", configurationDirectory.path)
            )
        }

        let groupOrder = loadGroupOrder(from: groupsDirectory)
        var groups = loadGroups(from: groupsDirectory)
        if groups.isEmpty {
            groups = [ProxyGroup(id: 0, name: L10n.text("legacy.defaultGroup"), isArchived: false, subscriptionURL: nil, profileOrder: [])]
        }
        groups.sort { lhs, rhs in
            let lhsIndex = groupOrder.firstIndex(of: lhs.id) ?? Int.max
            let rhsIndex = groupOrder.firstIndex(of: rhs.id) ?? Int.max
            return lhsIndex == rhsIndex ? lhs.id < rhs.id : lhsIndex < rhsIndex
        }

        let profiles = loadProfiles(from: profilesDirectory, groups: groups)
        return LegacySnapshot(
            groups: groups,
            profiles: profiles,
            sourceDescription: L10n.text("legacy.profilesLoaded", String(profiles.count), configurationDirectory.path)
        )
    }

    static func defaultConfigurationDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["NEKOBOX_LEGACY_CONFIG"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Preferences", directoryHint: .isDirectory)
            .appending(path: "nekoray", directoryHint: .isDirectory)
            .appending(path: "config", directoryHint: .isDirectory)
    }

    private func loadGroupOrder(from directory: URL) -> [Int] {
        guard let data = try? Data(contentsOf: directory.appending(path: "pm.json")),
              let metadata = try? JSONDecoder().decode(LegacyGroupIndex.self, from: data)
        else { return [] }
        return metadata.groups
    }

    private func loadGroups(from directory: URL) -> [ProxyGroup] {
        jsonFiles(in: directory).compactMap { file in
            guard file.lastPathComponent != "pm.json",
                  let data = try? Data(contentsOf: file),
                  let group = try? JSONDecoder().decode(LegacyGroup.self, from: data)
            else { return nil }

            return ProxyGroup(
                id: group.id,
                name: group.name.isEmpty ? L10n.text("legacy.untitledGroup") : group.name,
                isArchived: group.archive,
                subscriptionURL: URL(string: group.url),
                profileOrder: group.order
            )
        }
    }

    private func loadProfiles(from directory: URL, groups: [ProxyGroup]) -> [ProxyProfile] {
        let profiles = jsonFiles(in: directory).compactMap { file -> ProxyProfile? in
            guard let data = try? Data(contentsOf: file),
                  let profile = try? JSONDecoder().decode(LegacyProfile.self, from: data)
            else { return nil }

            let address = profile.bean.address.isEmpty ? L10n.text("legacy.notConfigured") : profile.bean.address
            let endpoint = profile.bean.port > 0 ? "\(address):\(profile.bean.port)" : address
            return ProxyProfile(
                id: profile.id,
                groupID: profile.groupID,
                type: profile.type,
                name: profile.bean.name,
                address: endpoint,
                latencyMilliseconds: profile.latency,
                uploadedBytes: profile.traffic.uploaded,
                downloadedBytes: profile.traffic.downloaded,
                testReport: profile.report,
                xraySettings: xraySettings(for: profile)
            )
        }

        let orderByGroup = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.profileOrder) })
        return profiles.sorted { lhs, rhs in
            guard lhs.groupID == rhs.groupID else { return lhs.groupID < rhs.groupID }
            let order = orderByGroup[lhs.groupID] ?? []
            let lhsIndex = order.firstIndex(of: lhs.id) ?? Int.max
            let rhsIndex = order.firstIndex(of: rhs.id) ?? Int.max
            return lhsIndex == rhsIndex ? lhs.id < rhs.id : lhsIndex < rhsIndex
        }
    }

    private func jsonFiles(in directory: URL) -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return files.filter { $0.pathExtension.lowercased() == "json" }
    }

    private func xraySettings(for profile: LegacyProfile) -> XrayProfileSettings? {
        let type = profile.type.lowercased()
        guard ["vmess", "vless", "trojan", "shadowsocks", "ss"].contains(type) else { return nil }

        let stream = profile.bean.stream
        let security = stream.realityPublicKey.isEmpty ? stream.security : "reality"
        let vmessSecurity = ["aes-128-gcm", "chacha20-poly1305", "auto"].contains(profile.bean.security)
            ? profile.bean.security
            : "auto"

        return XrayProfileSettings(
            userID: type == "vless"
                ? profile.bean.password
                : type == "vmess" ? profile.bean.userID : "",
            password: type == "vless" || type == "trojan" || type == "shadowsocks" || type == "ss"
                ? profile.bean.password
                : "",
            method: profile.bean.method,
            alterID: profile.bean.alterID,
            vmessSecurity: vmessSecurity,
            flow: profile.bean.flow,
            stream: XrayStreamSettings(
                network: stream.network,
                security: security,
                path: stream.path,
                host: stream.host,
                serverName: stream.serverName,
                allowInsecure: stream.allowInsecure,
                fingerprint: stream.fingerprint,
                realityPublicKey: stream.realityPublicKey,
                realityShortID: stream.realityShortID,
                realitySpiderX: stream.realitySpiderX
            )
        )
    }
}

private struct LegacyGroupIndex: Decodable {
    let groups: [Int]
}

private struct LegacyGroup: Decodable {
    let id: Int
    let archive: Bool
    let name: String
    let url: String
    let order: [Int]

    private enum CodingKeys: String, CodingKey {
        case id, archive, name, url, order
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        archive = try values.decodeIfPresent(Bool.self, forKey: .archive) ?? false
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try values.decodeIfPresent(String.self, forKey: .url) ?? ""
        order = try values.decodeIfPresent([Int].self, forKey: .order) ?? []
    }
}

private struct LegacyProfile: Decodable {
    let type: String
    let id: Int
    let groupID: Int
    let latency: Int
    let report: String
    let bean: LegacyBean
    let traffic: LegacyTraffic

    private enum CodingKeys: String, CodingKey {
        case type, id, gid, yc, report, bean, traffic
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        type = try values.decodeIfPresent(String.self, forKey: .type) ?? "custom"
        id = try values.decode(Int.self, forKey: .id)
        groupID = try values.decodeIfPresent(Int.self, forKey: .gid) ?? 0
        latency = try values.decodeIfPresent(Int.self, forKey: .yc) ?? 0
        report = try values.decodeIfPresent(String.self, forKey: .report) ?? ""
        bean = try values.decodeIfPresent(LegacyBean.self, forKey: .bean) ?? LegacyBean()
        traffic = try values.decodeIfPresent(LegacyTraffic.self, forKey: .traffic) ?? LegacyTraffic()
    }
}

private struct LegacyBean: Decodable {
    let name: String
    let address: String
    let port: Int
    let userID: String
    let password: String
    let method: String
    let alterID: Int
    let security: String
    let flow: String
    let stream: LegacyStream

    private enum CodingKeys: String, CodingKey {
        case name, address = "addr", port, userID = "id", password = "pass", method, alterID = "aid", security = "sec", flow, stream
    }

    init() {
        name = ""
        address = ""
        port = 0
        userID = ""
        password = ""
        method = "aes-128-gcm"
        alterID = 0
        security = "auto"
        flow = ""
        stream = LegacyStream()
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        address = try values.decodeIfPresent(String.self, forKey: .address) ?? ""
        port = try values.decodeIfPresent(Int.self, forKey: .port) ?? 0
        userID = try values.decodeIfPresent(String.self, forKey: .userID) ?? ""
        password = try values.decodeIfPresent(String.self, forKey: .password) ?? ""
        method = try values.decodeIfPresent(String.self, forKey: .method) ?? "aes-128-gcm"
        alterID = try values.decodeIfPresent(Int.self, forKey: .alterID) ?? 0
        security = try values.decodeIfPresent(String.self, forKey: .security) ?? "auto"
        flow = try values.decodeIfPresent(String.self, forKey: .flow) ?? ""
        stream = try values.decodeIfPresent(LegacyStream.self, forKey: .stream) ?? LegacyStream()
    }
}

private struct LegacyStream: Decodable {
    let network: String
    let security: String
    let path: String
    let host: String
    let serverName: String
    let allowInsecure: Bool
    let fingerprint: String
    let realityPublicKey: String
    let realityShortID: String
    let realitySpiderX: String

    private enum CodingKeys: String, CodingKey {
        case network = "net", security = "sec", path, host, serverName = "sni", allowInsecure = "insecure", fingerprint = "utls", realityPublicKey = "pbk", realityShortID = "sid", realitySpiderX = "spx"
    }

    init() {
        network = "tcp"
        security = "none"
        path = ""
        host = ""
        serverName = ""
        allowInsecure = false
        fingerprint = ""
        realityPublicKey = ""
        realityShortID = ""
        realitySpiderX = ""
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        network = try values.decodeIfPresent(String.self, forKey: .network) ?? "tcp"
        security = try values.decodeIfPresent(String.self, forKey: .security) ?? "none"
        path = try values.decodeIfPresent(String.self, forKey: .path) ?? ""
        host = try values.decodeIfPresent(String.self, forKey: .host) ?? ""
        serverName = try values.decodeIfPresent(String.self, forKey: .serverName) ?? ""
        allowInsecure = try values.decodeIfPresent(Bool.self, forKey: .allowInsecure) ?? false
        fingerprint = try values.decodeIfPresent(String.self, forKey: .fingerprint) ?? ""
        realityPublicKey = try values.decodeIfPresent(String.self, forKey: .realityPublicKey) ?? ""
        realityShortID = try values.decodeIfPresent(String.self, forKey: .realityShortID) ?? ""
        realitySpiderX = try values.decodeIfPresent(String.self, forKey: .realitySpiderX) ?? ""
    }
}

private struct LegacyTraffic: Decodable {
    let uploaded: Int64
    let downloaded: Int64

    private enum CodingKeys: String, CodingKey {
        case uploaded = "ul", downloaded = "dl"
    }

    init() {
        uploaded = 0
        downloaded = 0
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        uploaded = try values.decodeIfPresent(Int64.self, forKey: .uploaded) ?? 0
        downloaded = try values.decodeIfPresent(Int64.self, forKey: .downloaded) ?? 0
    }
}
