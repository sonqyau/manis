import Combine
import Foundation

@MainActor
protocol TrafficService: AnyObject {
    var statePublisher: AnyPublisher<TrafficDomain.State, Never> { get }

    func currentState() -> TrafficDomain.State
    func activate(mode: TrafficCaptureMode, context: TrafficCaptureActivationContext) async throws
    func deactivateCurrentMode() async
    func setPreferredDriver(_ id: TrafficCaptureDriverID?, for mode: TrafficCaptureMode)

    var autoFallbackEnabled: Bool { get set }
}

@MainActor
final class TrafficCaptureDomainServiceAdapter: TrafficService {
    private let domain: TrafficDomain

    init(domain: TrafficDomain = .shared) {
        self.domain = domain
    }

    var statePublisher: AnyPublisher<TrafficDomain.State, Never> {
        domain.statePublisher()
    }

    func currentState() -> TrafficDomain.State {
        domain.currentState()
    }

    func activate(mode: TrafficCaptureMode, context: TrafficCaptureActivationContext) async throws {
        try await domain.activate(mode: mode, context: context)
    }

    func deactivateCurrentMode() async {
        await domain.deactivateCurrentMode()
    }

    func setPreferredDriver(_ id: TrafficCaptureDriverID?, for mode: TrafficCaptureMode) {
        domain.setPreferredDriver(id, for: mode)
    }

    var autoFallbackEnabled: Bool {
        get { domain.autoFallbackEnabled }
        set { domain.autoFallbackEnabled = newValue }
    }
}
