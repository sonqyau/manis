import ComposableArchitecture
import Foundation

public protocol DismissibleAlertAction: Equatable {
    static var dismissError: Self { get }
}

public extension AlertState {
    static func error(_ message: String) -> AlertState where Action: DismissibleAlertAction {
        AlertState {
            TextState("Error")
        } actions: {
            ButtonState(action: .dismissError) {
                TextState("OK")
            }
        } message: {
            TextState(message)
        }
    }

    static func error(_ error: Error) -> AlertState where Action: DismissibleAlertAction {
        let message = (error as NSError).localizedDescription
        return .error(message)
    }

    static func success(_ message: String) -> AlertState where Action: DismissibleAlertAction {
        AlertState {
            TextState("Success")
        } actions: {
            ButtonState(action: .dismissError) {
                TextState("OK")
            }
        } message: {
            TextState(message)
        }
    }
}
