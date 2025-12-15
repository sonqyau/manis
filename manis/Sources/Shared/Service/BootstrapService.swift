import Combine
import Foundation

@MainActor
protocol BootstrapService {
    var statePublisher: AnyPublisher<BootstrapManager.State, Never> { get }

    func currentState() -> BootstrapManager.State
    func toggle() throws
    func updateStatus()
    func openSystemSettings()
}

@MainActor
struct BootstrapManagerServiceAdapter: BootstrapService {
    private let manager: BootstrapManager

    init(manager: BootstrapManager = .shared) {
        self.manager = manager
    }

    var statePublisher: AnyPublisher<BootstrapManager.State, Never> {
        manager.statePublisher()
    }

    func currentState() -> BootstrapManager.State {
        manager.state
    }

    func toggle() throws {
        try manager.toggle()
    }

    func updateStatus() {
        manager.updateStatus()
    }

    func openSystemSettings() {
        manager.openSystemSettings()
    }
}
