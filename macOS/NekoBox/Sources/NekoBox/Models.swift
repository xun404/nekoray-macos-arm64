import Foundation

enum DataOrigin: String, Codable, Hashable {
    case legacy
    case native
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview
    case proxies
    case connections
    case logs

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: L10n.text("sidebar.overview")
        case .proxies: L10n.text("sidebar.proxies")
        case .connections: L10n.text("sidebar.connections")
        case .logs: L10n.text("sidebar.logs")
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "rectangle.grid.1x2"
        case .proxies: "server.rack"
        case .connections: "point.3.connected.trianglepath.dotted"
        case .logs: "text.alignleft"
        }
    }
}

struct ProxyGroup: Identifiable, Hashable, Codable {
    var id: Int
    var name: String
    var isArchived: Bool
    var subscriptionURL: URL?
    var profileOrder: [Int]
    var origin: DataOrigin = .legacy
}

struct ProxyProfile: Identifiable, Hashable, Codable {
    var id: Int
    var groupID: Int
    var type: String
    var name: String
    var address: String
    var latencyMilliseconds: Int
    var uploadedBytes: Int64
    var downloadedBytes: Int64
    var testReport: String
    var origin: DataOrigin = .legacy
    var xraySettings: XrayProfileSettings?

    var displayedName: String {
        name.isEmpty ? address : name
    }

    var latencyDescription: String {
        switch latencyMilliseconds {
        case ..<0: L10n.text("profile.unavailable")
        case 1...: "\(latencyMilliseconds) ms"
        default: "—"
        }
    }

    var trafficDescription: String {
        guard uploadedBytes + downloadedBytes > 0 else { return "—" }
        return "\(ByteCountFormatter.string(fromByteCount: uploadedBytes, countStyle: .binary)) ↑  \(ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .binary)) ↓"
    }
}

struct XrayProfileSettings: Hashable, Codable {
    var userID: String
    var password: String
    var method: String
    var alterID: Int
    var vmessSecurity: String
    var flow: String
    var stream: XrayStreamSettings

    init(
        userID: String = "",
        password: String = "",
        method: String = "aes-128-gcm",
        alterID: Int = 0,
        vmessSecurity: String = "auto",
        flow: String = "",
        stream: XrayStreamSettings = XrayStreamSettings()
    ) {
        self.userID = userID
        self.password = password
        self.method = method
        self.alterID = alterID
        self.vmessSecurity = vmessSecurity
        self.flow = flow
        self.stream = stream
    }
}

struct XrayStreamSettings: Hashable, Codable {
    var network: String
    var security: String
    var path: String
    var host: String
    var serverName: String
    var allowInsecure: Bool
    var fingerprint: String
    var realityPublicKey: String
    var realityShortID: String
    var realitySpiderX: String

    init(
        network: String = "tcp",
        security: String = "none",
        path: String = "",
        host: String = "",
        serverName: String = "",
        allowInsecure: Bool = false,
        fingerprint: String = "",
        realityPublicKey: String = "",
        realityShortID: String = "",
        realitySpiderX: String = ""
    ) {
        self.network = network
        self.security = security
        self.path = path
        self.host = host
        self.serverName = serverName
        self.allowInsecure = allowInsecure
        self.fingerprint = fingerprint
        self.realityPublicKey = realityPublicKey
        self.realityShortID = realityShortID
        self.realitySpiderX = realitySpiderX
    }
}

struct ProxyDraft {
    var id: Int?
    var name: String
    var type: String
    var host: String
    var port: Int
    var groupID: Int
    var xraySettings: XrayProfileSettings

    init(groupID: Int) {
        id = nil
        name = ""
        type = "Shadowsocks"
        host = ""
        port = 443
        self.groupID = groupID
        xraySettings = XrayProfileSettings()
    }

    init(profile: ProxyProfile) {
        id = profile.origin == .native ? profile.id : nil
        name = profile.origin == .native ? profile.name : L10n.text("profile.copyName", profile.displayedName)
        type = profile.type
        let endpoint = ProxyDraft.endpoint(from: profile.address)
        host = endpoint.host
        port = endpoint.port
        groupID = profile.groupID
        xraySettings = profile.xraySettings ?? XrayProfileSettings()
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !trimmedName.isEmpty && !trimmedHost.isEmpty && (1...65_535).contains(port)
    }

    var endpoint: String {
        trimmedHost.contains(":") && !trimmedHost.hasPrefix("[")
            ? "[\(trimmedHost)]:\(port)"
            : "\(trimmedHost):\(port)"
    }

    private static func endpoint(from address: String) -> (host: String, port: Int) {
        guard let separator = address.lastIndex(of: ":"),
              let port = Int(address[address.index(after: separator)...])
        else {
            return (address, 443)
        }

        let host = String(address[..<separator])
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return (host, port)
    }
}

struct ActivityLog: Identifiable, Hashable {
    enum Level: String, Codable, Hashable {
        case info
        case success
        case warning
        case error

        var systemImage: String {
            switch self {
            case .info: "info.circle"
            case .success: "checkmark.circle"
            case .warning: "exclamationmark.triangle"
            case .error: "xmark.octagon"
            }
        }
    }

    let id: UUID
    let date: Date
    let level: Level
    let message: String
}

struct Connection: Identifiable, Hashable {
    let id: UUID
    let inbound: String
    let destination: String
    let rule: String
    let createdAt: Date
}

enum CoreAvailability: Equatable {
    case unavailable
    case ready

    func description(for core: CoreKind) -> String {
        switch self {
        case .ready: L10n.text("core.available", core.displayName)
        case .unavailable: L10n.text("core.unavailableDetail", core.displayName)
        }
    }
}

struct LegacySnapshot {
    let groups: [ProxyGroup]
    let profiles: [ProxyProfile]
    let sourceDescription: String
}
