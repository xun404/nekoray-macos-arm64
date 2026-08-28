import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview
    case proxies
    case connections
    case logs

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .proxies: "Proxies"
        case .connections: "Connections"
        case .logs: "Logs"
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

struct ProxyGroup: Identifiable, Hashable {
    let id: Int
    var name: String
    var isArchived: Bool
    var subscriptionURL: URL?
    var profileOrder: [Int]
}

struct ProxyProfile: Identifiable, Hashable {
    let id: Int
    let groupID: Int
    let type: String
    let name: String
    let address: String
    let latencyMilliseconds: Int
    let uploadedBytes: Int64
    let downloadedBytes: Int64
    let testReport: String

    var displayedName: String {
        name.isEmpty ? address : name
    }

    var latencyDescription: String {
        switch latencyMilliseconds {
        case ..<0: "Unavailable"
        case 1...: "\(latencyMilliseconds) ms"
        default: "—"
        }
    }

    var trafficDescription: String {
        guard uploadedBytes + downloadedBytes > 0 else { return "—" }
        return "\(ByteCountFormatter.string(fromByteCount: uploadedBytes, countStyle: .binary)) ↑  \(ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .binary)) ↓"
    }
}

struct Connection: Identifiable, Hashable {
    let id: UUID
    let inbound: String
    let destination: String
    let rule: String
    let createdAt: Date
}

enum CoreAvailability: Equatable {
    case unavailable(String)
    case ready

    var description: String {
        switch self {
        case .ready: "Core service available"
        case .unavailable(let reason): reason
        }
    }
}

struct LegacySnapshot {
    let groups: [ProxyGroup]
    let profiles: [ProxyProfile]
    let sourceDescription: String
}
