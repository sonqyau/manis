import Foundation

final class MainXPC: NSObject, MainXPCProtocol {
    private let helperBridge = DaemonBridge()

    func getVersion(reply: @escaping (String) -> Void) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        reply(version)
    }

    func getKernelStatus(reply: @escaping (ManisKernelStatus) -> Void) {
        helperBridge.getMihomoStatus { result in
            switch result {
            case let .success(status):
                reply(
                    ManisKernelStatus(
                        isRunning: status.isRunning,
                        processId: status.processId,
                        externalController: status.externalController,
                        secret: status.secret,
                        ),
                    )

            case .failure:
                reply(ManisKernelStatus(isRunning: false, processId: 0, externalController: nil, secret: nil))
            }
        }
    }

    func startKernel(
        executablePath: String,
        configPath: String,
        configContent: String,
        reply: @escaping (String?, MainXPCError?) -> Void,
        ) {
        helperBridge.startMihomo(
            executablePath: executablePath,
            configPath: configPath,
            configContent: configContent,
            ) { result in
            switch result {
            case let .success(message):
                reply(message, nil)
            case let .failure(error):
                reply(nil, MainXPCError(error: error))
            }
        }
    }

    func stopKernel(reply: @escaping (MainXPCError?) -> Void) {
        helperBridge.stopMihomo { result in
            switch result {
            case .success:
                reply(nil)
            case let .failure(error):
                reply(MainXPCError(error: error))
            }
        }
    }
}
