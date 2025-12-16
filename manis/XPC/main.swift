import Foundation

let delegate = MainXPCDelegate()
let listener = NSXPCListener(machServiceName: MainXPCConstants.machServiceName)

listener.delegate = delegate
listener.resume()

RunLoop.current.run()
