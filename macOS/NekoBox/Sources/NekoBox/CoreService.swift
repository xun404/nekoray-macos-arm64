import Foundation

/// The native UI only depends on this protocol, not on a UI toolkit-specific
/// transport. The final implementation will launch `nekobox_core` and use the
/// existing authenticated local gRPC service generated from `libcore.proto`.
@MainActor
protocol CoreService {
    var availability: CoreAvailability { get }
    func start(profile: ProxyProfile) async throws
    func stop() async throws
}

enum CoreServiceError: LocalizedError {
    case migrationPending

    var errorDescription: String? {
        switch self {
        case .migrationPending:
            "The native Core service is not connected yet. Profile configuration and gRPC transport migrate in the next phase."
        }
    }
}

struct DeferredCoreService: CoreService {
    let availability = CoreAvailability.unavailable(
        "Core integration pending — native configuration generation and gRPC transport are not available yet."
    )

    func start(profile: ProxyProfile) async throws {
        throw CoreServiceError.migrationPending
    }

    func stop() async throws {
        throw CoreServiceError.migrationPending
    }
}
