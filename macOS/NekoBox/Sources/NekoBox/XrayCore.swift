import Foundation

enum XrayCoreLocator {
    private static let executablePreferenceKey = "xrayExecutablePath"

    static var executableURL: URL? {
        if let path = UserDefaults.standard.string(forKey: executablePreferenceKey), !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        for candidate in automaticCandidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    static var selectedOrDetectedPath: String {
        executableURL?.path ?? L10n.text("xray.notFound")
    }

    static var hasCustomExecutable: Bool {
        let path = UserDefaults.standard.string(forKey: executablePreferenceKey) ?? ""
        return !path.isEmpty
    }

    static func setExecutable(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: executablePreferenceKey)
    }

    static func clearCustomExecutable() {
        UserDefaults.standard.removeObject(forKey: executablePreferenceKey)
    }

    static func configurationURL() throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "NekoBox", directoryHint: .isDirectory)
            .appending(path: "config", directoryHint: .isDirectory)
            .appending(path: "xray", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "config.json")
    }

    private static var automaticCandidates: [URL] {
        var candidates: [URL] = []
        if let bundled = Bundle.main.url(forResource: "xray", withExtension: nil) {
            candidates.append(bundled)
        }
        candidates += [
            CoreInstallation.managedExecutableURL(for: .xray),
            FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library", directoryHint: .isDirectory)
                .appending(path: "Application Support", directoryHint: .isDirectory)
                .appending(path: "NekoBox", directoryHint: .isDirectory)
                .appending(path: "xray"),
            URL(fileURLWithPath: "/opt/homebrew/bin/xray"),
            URL(fileURLWithPath: "/usr/local/bin/xray"),
        ]
        return candidates
    }
}

enum XrayConfigurationError: LocalizedError {
    case unsupportedProtocol(String)
    case unsupportedTransport(String)
    case missingCredential(String)
    case invalidRealityTransport
    case missingRealityKey

    var errorDescription: String? {
        switch self {
        case .unsupportedProtocol(let protocolName):
            L10n.text("xray.unsupportedProtocol", protocolName)
        case .unsupportedTransport(let transport):
            L10n.text("xray.unsupportedTransport", transport)
        case .missingCredential(let protocolName):
            L10n.text("xray.missingCredential", protocolName)
        case .invalidRealityTransport:
            L10n.text("xray.invalidRealityTransport")
        case .missingRealityKey:
            L10n.text("xray.missingRealityKey")
        }
    }
}

enum XrayConfigurationGenerator {
    static let socksPort = 10_808
    static let httpPort = 10_809

    static func configurationData(for profile: ProxyProfile) throws -> Data {
        let configuration: [String: Any] = [
            "log": ["loglevel": "warning"],
            "inbounds": [
                [
                    "tag": "socks-in",
                    "listen": "127.0.0.1",
                    "port": socksPort,
                    "protocol": "socks",
                    "settings": ["udp": true],
                    "sniffing": ["enabled": true, "destOverride": ["http", "tls", "quic"]],
                ],
                [
                    "tag": "http-in",
                    "listen": "127.0.0.1",
                    "port": httpPort,
                    "protocol": "http",
                    "settings": [:],
                    "sniffing": ["enabled": true, "destOverride": ["http", "tls", "quic"]],
                ],
            ],
            "outbounds": [
                try outbound(for: profile),
                ["tag": "direct", "protocol": "freedom", "settings": [:]],
                ["tag": "block", "protocol": "blackhole", "settings": [:]],
            ],
            "routing": [
                "domainStrategy": "AsIs",
                "rules": [
                    [
                        "type": "field",
                        "inboundTag": ["socks-in", "http-in"],
                        "outboundTag": "proxy",
                    ],
                ],
            ],
        ]

        return try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys])
    }

    private static func outbound(for profile: ProxyProfile) throws -> [String: Any] {
        let endpoint = try endpoint(from: profile.address)
        let settings = profile.xraySettings ?? XrayProfileSettings()
        let protocolName = normalizedProtocol(profile.type)
        var outbound: [String: Any] = [
            "tag": "proxy",
            "protocol": protocolName,
            "settings": try protocolSettings(
                protocolName: protocolName,
                endpoint: endpoint,
                settings: settings
            ),
        ]
        outbound["streamSettings"] = try streamSettings(
            for: settings.stream,
            serverAddress: endpoint.address
        )
        return outbound
    }

    private static func normalizedProtocol(_ value: String) -> String {
        switch value.lowercased() {
        case "ss": "shadowsocks"
        default: value.lowercased()
        }
    }

    private static func protocolSettings(
        protocolName: String,
        endpoint: (address: String, port: Int),
        settings: XrayProfileSettings
    ) throws -> [String: Any] {
        switch protocolName {
        case "vless":
            guard !settings.userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XrayConfigurationError.missingCredential("VLESS UUID")
            }
            var result: [String: Any] = [
                "address": endpoint.address,
                "port": endpoint.port,
                "id": settings.userID,
                "encryption": "none",
                "level": 0,
            ]
            if !settings.flow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result["flow"] = settings.flow
            }
            return result
        case "vmess":
            guard !settings.userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XrayConfigurationError.missingCredential("VMess UUID")
            }
            return [
                "address": endpoint.address,
                "port": endpoint.port,
                "id": settings.userID,
                "security": settings.vmessSecurity,
                "level": 0,
            ]
        case "trojan":
            guard !settings.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XrayConfigurationError.missingCredential("Trojan password")
            }
            return [
                "address": endpoint.address,
                "port": endpoint.port,
                "password": settings.password,
                "level": 0,
            ]
        case "shadowsocks":
            guard !settings.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XrayConfigurationError.missingCredential("Shadowsocks password")
            }
            return [
                "address": endpoint.address,
                "port": endpoint.port,
                "method": settings.method,
                "password": settings.password,
                "level": 0,
            ]
        default:
            throw XrayConfigurationError.unsupportedProtocol(protocolName)
        }
    }

    private static func streamSettings(
        for settings: XrayStreamSettings,
        serverAddress: String
    ) throws -> [String: Any] {
        let method: String
        switch settings.network.lowercased() {
        case "", "tcp", "raw": method = "raw"
        case "ws", "websocket": method = "websocket"
        case "grpc": method = "grpc"
        case "httpupgrade": method = "httpupgrade"
        case "xhttp": method = "xhttp"
        default: throw XrayConfigurationError.unsupportedTransport(settings.network)
        }

        let usesReality = !settings.realityPublicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || settings.security.lowercased() == "reality"
        if usesReality, !["raw", "xhttp", "grpc"].contains(method) {
            throw XrayConfigurationError.invalidRealityTransport
        }

        var result: [String: Any] = [
            "method": method,
            "security": usesReality ? "reality" : normalizedSecurity(settings.security),
        ]

        switch method {
        case "websocket":
            var websocket: [String: Any] = [:]
            if !settings.path.isEmpty { websocket["path"] = settings.path }
            if !settings.host.isEmpty { websocket["host"] = settings.host }
            result["wsSettings"] = websocket
        case "grpc":
            if !settings.path.isEmpty { result["grpcSettings"] = ["serviceName": settings.path] }
        case "httpupgrade":
            var httpUpgrade: [String: Any] = [:]
            if !settings.path.isEmpty { httpUpgrade["path"] = settings.path }
            if !settings.host.isEmpty { httpUpgrade["host"] = settings.host }
            result["httpupgradeSettings"] = httpUpgrade
        case "xhttp":
            if !settings.path.isEmpty { result["xhttpSettings"] = ["path": settings.path] }
        default:
            break
        }

        if usesReality {
            guard !settings.realityPublicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XrayConfigurationError.missingRealityKey
            }
            var reality: [String: Any] = [
                "password": settings.realityPublicKey,
                "fingerprint": settings.fingerprint.isEmpty ? "chrome" : settings.fingerprint,
                "shortId": settings.realityShortID,
            ]
            if !settings.serverName.isEmpty { reality["serverName"] = settings.serverName }
            if !settings.realitySpiderX.isEmpty { reality["spiderX"] = settings.realitySpiderX }
            result["realitySettings"] = reality
        } else if normalizedSecurity(settings.security) == "tls" {
            var tls: [String: Any] = ["allowInsecure": settings.allowInsecure]
            if !settings.serverName.isEmpty { tls["serverName"] = settings.serverName }
            if !settings.fingerprint.isEmpty { tls["fingerprint"] = settings.fingerprint }
            result["tlsSettings"] = tls
        }

        return result
    }

    private static func normalizedSecurity(_ value: String) -> String {
        value.lowercased() == "tls" ? "tls" : "none"
    }

    private static func endpoint(from value: String) throws -> (address: String, port: Int) {
        if value.hasPrefix("["),
           let closingBracket = value.firstIndex(of: "]"),
           value.index(after: closingBracket) < value.endIndex,
           value[value.index(after: closingBracket)] == ":",
           let port = Int(value[value.index(closingBracket, offsetBy: 2)...]) {
            return (String(value[value.index(after: value.startIndex)..<closingBracket]), port)
        }

        guard let separator = value.lastIndex(of: ":"),
              let port = Int(value[value.index(after: separator)...])
        else {
            throw XrayConfigurationError.unsupportedTransport(value)
        }
        return (String(value[..<separator]), port)
    }
}

enum XrayCoreError: LocalizedError {
    case executableNotFound
    case alreadyRunning
    case validationFailed(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            L10n.text("xray.executableNotFound")
        case .alreadyRunning:
            L10n.text("xray.alreadyRunning")
        case .validationFailed(let output):
            L10n.text("xray.validationFailed", output)
        case .launchFailed(let reason):
            L10n.text("xray.launchFailed", reason)
        }
    }
}

@MainActor
final class XrayCoreService: CoreService {
    private var process: Process?

    var availability: CoreAvailability {
        XrayCoreLocator.executableURL == nil ? .unavailable : .ready
    }

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    func start(profile: ProxyProfile) async throws {
        guard !isRunning else { throw XrayCoreError.alreadyRunning }
        guard let executableURL = XrayCoreLocator.executableURL else {
            throw XrayCoreError.executableNotFound
        }

        let configurationURL = try XrayCoreLocator.configurationURL()
        try XrayConfigurationGenerator.configurationData(for: profile).write(to: configurationURL, options: .atomic)
        try validate(configurationAt: configurationURL, with: executableURL)

        let xray = Process()
        xray.executableURL = executableURL
        xray.arguments = ["run", "-config", configurationURL.path]
        xray.currentDirectoryURL = executableURL.deletingLastPathComponent()
        xray.standardOutput = Pipe()
        xray.standardError = Pipe()
        do {
            try xray.run()
        } catch {
            throw XrayCoreError.launchFailed(error.localizedDescription)
        }
        process = xray
    }

    func stop() async throws {
        guard let process else { return }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        self.process = nil
    }

    private func validate(configurationAt configurationURL: URL, with executableURL: URL) throws {
        let validator = Process()
        let output = Pipe()
        validator.executableURL = executableURL
        validator.arguments = ["run", "-test", "-config", configurationURL.path]
        validator.currentDirectoryURL = executableURL.deletingLastPathComponent()
        validator.standardOutput = output
        validator.standardError = output
        do {
            try validator.run()
        } catch {
            throw XrayCoreError.launchFailed(error.localizedDescription)
        }
        validator.waitUntilExit()
        guard validator.terminationStatus == 0 else {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            throw XrayCoreError.validationFailed(String(text.prefix(1_000)))
        }
    }
}
