import Foundation

final class MainXPCDelegate: NSObject, NSXPCListenerDelegate {
    private let exportedObject = MainXPC()

    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: MainXPCProtocol.self)
        newConnection.exportedObject = exportedObject
        newConnection.resume()
        return true
    }
}
