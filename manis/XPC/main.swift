import Foundation
import OSLog
import SecureXPC

let logger = Logger(subsystem: "com.manis.XPC", category: "Main")

logger.info("Starting MainXPC")

let server = try XPCServer.forThisXPCService()
let xpcService = XPCService()

let getVersionRoute = XPCRoute.named("getVersion").withReplyType(String.self)

server.registerRoute(getVersionRoute, handler: xpcService.getVersion)

let getKernelStatusRoute = XPCRoute.named("getKernelStatus").withReplyType(ManisKernelStatus.self)

server.registerRoute(getKernelStatusRoute, handler: xpcService.getKernelStatus)

let startKernelRoute = XPCRoute.named("startKernel").withMessageType(KernelStartRequest.self).withReplyType(String.self)

server.registerRoute(startKernelRoute, handler: xpcService.startKernel)

let stopKernelRoute = XPCRoute.named("stopKernel").withReplyType(String.self)

server.registerRoute(stopKernelRoute, handler: xpcService.stopKernel)

let restartKernelRoute = XPCRoute.named("restartKernel").withReplyType(String.self)

server.registerRoute(restartKernelRoute, handler: xpcService.restartKernel)

let enableConnectRoute = XPCRoute.named("enableConnect").withMessageType(ConnectRequest.self).withReplyType(String.self)

server.registerRoute(enableConnectRoute, handler: xpcService.enableConnect)

let disableConnectRoute = XPCRoute.named("disableConnect").withReplyType(String.self)

server.registerRoute(disableConnectRoute, handler: xpcService.disableConnect)

let getConnectStatusRoute = XPCRoute.named("getConnectStatus").withReplyType(ConnectStatus.self)

server.registerRoute(getConnectStatusRoute, handler: xpcService.getConnectStatus)

let configureDNSRoute = XPCRoute.named("configureDNS").withMessageType(DNSRequest.self).withReplyType(String.self)

server.registerRoute(configureDNSRoute, handler: xpcService.configureDNS)

let flushDNSCacheRoute = XPCRoute.named("flushDNSCache").withReplyType(String.self)

server.registerRoute(flushDNSCacheRoute, handler: xpcService.flushDNSCache)

let getUsedPortsRoute = XPCRoute.named("getUsedPorts").withReplyType([Int].self)

server.registerRoute(getUsedPortsRoute, handler: xpcService.getUsedPorts)

let testConnectivityRoute = XPCRoute.named("testConnectivity").withMessageType(ConnectivityRequest.self).withReplyType(Bool.self)

server.registerRoute(testConnectivityRoute, handler: xpcService.testConnectivity)

let updateTunRoute = XPCRoute.named("updateTun").withMessageType(TunRequest.self).withReplyType(String.self)

server.registerRoute(updateTunRoute, handler: xpcService.updateTun)

server.startAndBlock()
