import Foundation
import OSLog

enum KernelBridgeError: Error, LocalizedError {
    case libraryNotFound
    case symbolNotFound(String)
    case initializationFailed
    case invalidConfiguration
    case kernelCrashed
    case communicationTimeout

    var errorDescription: String? {
        switch self {
        case .libraryNotFound:
            "Kernel bridge library not found. Please ensure the application is properly installed."
        case let .symbolNotFound(symbol):
            "Required symbol '\(symbol)' not found in kernel library."
        case .initializationFailed:
            "Failed to initialize kernel bridge."
        case .invalidConfiguration:
            "Invalid kernel configuration provided."
        case .kernelCrashed:
            "Kernel process crashed unexpectedly."
        case .communicationTimeout:
            "Communication with kernel timed out."
        }
    }
}

@MainActor
final class Bridge: ObservableObject {
    static let shared = Bridge()

    private let logger = Logger(subsystem: "com.sonqyau.manis", category: "kernel")

    @Published var isLoaded = false
    @Published var isRunning = false

    private var libraryHandle: UnsafeMutableRawPointer?
    private var kernelHandle: Int64 = 0

    private init() {
        Task { @MainActor in
            await loadKernelLibrary()
        }
    }

    deinit {}

    private func loadKernelLibrary() async {
        let libraryPaths: [String]

        let bundlePath = Bundle.main.bundlePath
        libraryPaths = [
            "\(bundlePath)/Contents/Resources/Kernel/lib/libmihomo.dylib",
            "\(bundlePath)/Contents/Resources/Kernel/lib/libmihomo_arm64.dylib",
            "./manis/Resources/Kernel/lib/libmihomo.dylib",
            "./manis/Resources/Kernel/lib/libmihomo_arm64.dylib",
        ]

        for path in libraryPaths where FileManager.default.fileExists(atPath: path) {
            logger.info("Attempting to load kernel library: \(path)")

            if let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) {
                libraryHandle = handle
                isLoaded = true
                logger.info("Kernel library loaded successfully")
                return
            } else {
                let error = String(cString: dlerror())
                logger.warning("Failed to load library at \(path): \(error)")
            }
        }

        logger.error("No kernel library found in any expected location")
    }

    func validateKernelBinary(at path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw KernelBridgeError.libraryNotFound
        }

        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw NSError(domain: "com.sonqyau.manis", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Kernel binary is not executable",
            ])
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["-v"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()

            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                if task.isRunning {
                    task.terminate()
                }
            }

            task.waitUntilExit()
            timeoutTask.cancel()

            if task.terminationStatus == 0 {
                logger.info("Kernel binary validation successful")
            } else {
                throw NSError(domain: "com.sonqyau.manis", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "Kernel binary failed validation test",
                ])
            }
        } catch {
            logger.error("Kernel binary validation failed: \(error.localizedDescription)")
            throw error
        }
    }

    func createKernelInstance(configPath: String) throws -> Int64 {
        guard isLoaded, let handle = libraryHandle else {
            throw KernelBridgeError.libraryNotFound
        }

        guard let createFunc = dlsym(handle, "mihomo_create") else {
            throw KernelBridgeError.symbolNotFound("mihomo_create")
        }

        let createFunction = unsafeBitCast(createFunc, to: (@convention(c) (UnsafePointer<CChar>) -> Int64).self)

        let result = configPath.withCString { cString in
            createFunction(cString)
        }

        if result < 0 {
            let errorMsg = getLastError()
            logger.error("Failed to create kernel instance: \(errorMsg)")
            throw KernelBridgeError.initializationFailed
        }

        kernelHandle = result
        logger.info("Kernel instance created with handle: \(result)")
        return result
    }

    func startKernel(handle: Int64) throws {
        guard isLoaded, let libraryHandle else {
            throw KernelBridgeError.libraryNotFound
        }

        guard let startFunc = dlsym(libraryHandle, "mihomo_start") else {
            throw KernelBridgeError.symbolNotFound("mihomo_start")
        }

        let startFunction = unsafeBitCast(startFunc, to: (@convention(c) (Int64) -> Int32).self)
        let result = startFunction(handle)

        if result != 0 {
            let errorMsg = getLastError()
            logger.error("Failed to start kernel: \(errorMsg)")
            throw KernelBridgeError.initializationFailed
        }

        isRunning = true
        logger.info("Kernel started successfully")
    }

    func stopKernel(handle: Int64) {
        guard isLoaded, let libraryHandle else {
            return
        }

        guard let stopFunc = dlsym(libraryHandle, "mihomo_stop") else {
            logger.warning("mihomo_stop function not found")
            return
        }

        let stopFunction = unsafeBitCast(stopFunc, to: (@convention(c) (Int64) -> Int32).self)
        let result = stopFunction(handle)

        if result == 0 {
            isRunning = false
            logger.info("Kernel stopped successfully")
        } else {
            logger.warning("Kernel stop returned error code: \(result)")
        }
    }

    func destroyKernel(handle: Int64) {
        guard isLoaded, let libraryHandle else {
            return
        }

        guard let destroyFunc = dlsym(libraryHandle, "mihomo_destroy") else {
            logger.warning("mihomo_destroy function not found")
            return
        }

        let destroyFunction = unsafeBitCast(destroyFunc, to: (@convention(c) (Int64) -> Int32).self)
        let result = destroyFunction(handle)

        if result == 0 {
            logger.info("Kernel instance destroyed")
        } else {
            logger.warning("Kernel destroy returned error code: \(result)")
        }

        if kernelHandle == handle {
            kernelHandle = 0
            isRunning = false
        }
    }

    func getKernelVersion() -> String? {
        guard isLoaded, let libraryHandle else {
            return nil
        }

        guard let versionFunc = dlsym(libraryHandle, "mihomo_get_version") else {
            return nil
        }

        let versionFunction = unsafeBitCast(versionFunc, to: (@convention(c) () -> UnsafePointer<CChar>?).self)

        if let cString = versionFunction() {
            let version = String(cString: cString)

            if let freeFunc = dlsym(libraryHandle, "mihomo_free_string") {
                let freeFunction = unsafeBitCast(freeFunc, to: (@convention(c) (UnsafePointer<CChar>) -> Void).self)
                freeFunction(cString)
            }

            return version
        }

        return nil
    }

    private func getLastError() -> String {
        guard isLoaded, let libraryHandle else {
            return "Library not loaded"
        }

        guard let errorFunc = dlsym(libraryHandle, "mihomo_get_last_error") else {
            return "Error function not found"
        }

        let errorFunction = unsafeBitCast(errorFunc, to: (@convention(c) () -> UnsafePointer<CChar>?).self)

        if let cString = errorFunction() {
            let error = String(cString: cString)

            if let freeFunc = dlsym(libraryHandle, "mihomo_free_string") {
                let freeFunction = unsafeBitCast(freeFunc, to: (@convention(c) (UnsafePointer<CChar>) -> Void).self)
                freeFunction(cString)
            }

            return error
        }

        return "Unknown error"
    }

    private func cleanup() {
        if kernelHandle != 0 {
            stopKernel(handle: kernelHandle)
            destroyKernel(handle: kernelHandle)
        }

        if let handle = libraryHandle {
            dlclose(handle)
            libraryHandle = nil
            isLoaded = false
        }
    }
}
