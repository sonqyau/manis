import Foundation
import OSLog
import SwiftyXPC

let logger = Logger(subsystem: "com.manis.XPC", category: "Main")

logger.info("Starting MainXPC")

let listener = try XPCListener(type: .service, codeSigningRequirement: nil)
let xpcService = XPCService()

listener.setMessageHandler(name: "getVersion") { _ in
    try await xpcService.getVersion()
}

listener.setMessageHandler(name: "getKernelStatus") { _ in
    try await xpcService.getKernelStatus()
}

listener.setMessageHandler(name: "startKernel") { (_: XPCConnection, request: XPCRequest) in
    try await xpcService.startKernel(request)
}

listener.setMessageHandler(name: "stopKernel") { _ in
    try await xpcService.stopKernel()
}

listener.setMessageHandler(name: "restartKernel") { _ in
    try await xpcService.restartKernel()
}

listener.setMessageHandler(name: "enableConnect") { (_: XPCConnection, request: XPCRequest) in
    try await xpcService.enableConnect(request)
}

listener.setMessageHandler(name: "disableConnect") { _ in
    try await xpcService.disableConnect()
}

listener.setMessageHandler(name: "getConnectStatus") { _ in
    try await xpcService.getConnectStatus()
}

listener.setMessageHandler(name: "configureDNS") { (_: XPCConnection, request: XPCRequest) in
    try await xpcService.configureDNS(request)
}

listener.setMessageHandler(name: "flushDNSCache") { _ in
    try await xpcService.flushDNSCache()
}

listener.setMessageHandler(name: "getUsedPorts") { _ in
    try await xpcService.getUsedPorts()
}

listener.setMessageHandler(name: "testConnectivity") { (_: XPCConnection, request: XPCRequest) in
    try await xpcService.testConnectivity(request)
}

listener.setMessageHandler(name: "updateTun") { (_: XPCConnection, request: XPCRequest) in
    try await xpcService.updateTun(request)
}

listener.errorHandler = { _, error in
    logger.error("XPC connection error: \(error)")
}

listener.activate()
