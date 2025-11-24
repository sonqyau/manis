import Foundation

public struct MihomoFFI {
    
    @available(*, unavailable)
    private init() {}
    
    @_silgen_name("mihomo_create")
    private static func mihomo_create(configPath: UnsafePointer<CChar>) -> CLong
    
    @_silgen_name("mihomo_destroy")
    private static func mihomo_destroy(handle: CLong) -> CInt
    
    @_silgen_name("mihomo_free_string")
    private static func mihomo_free_string(ptr: UnsafePointer<CChar>)
    
    @_silgen_name("mihomo_get_last_error")
    private static func mihomo_get_last_error() -> UnsafePointer<CChar>
    
    private enum CErrorCode: CInt {
        case success = 0
        case invalidHandle = -1
        case alreadyCreated = -2
        case alreadyStarted = -3
        case notStarted = -4
        case invalidConfig = -5
        case internalError = -6
    }
    
    public enum Error: Swift.Error, LocalizedError {
        case creationFailed(String)
        case destroyFailed(String)
        case invalidHandle
        case alreadyCreated
        case invalidConfig
        
        public var errorDescription: String? {
            switch self {
            case .creationFailed(let message):
                return "Failed to create mihomo instance: \(message)"
            case .destroyFailed(let message):
                return "Failed to destroy mihomo instance: \(message)"
            case .invalidHandle:
                return "Invalid mihomo instance handle"
            case .alreadyCreated:
                return "Mihomo instance already created for this config"
            case .invalidConfig:
                return "Invalid configuration path"
            }
        }
    }
    
    public class Client {
        private let handle: CLong
        
        public init(configPath: String) throws {
            let result = configPath.withCString { ptr in
                MihomoFFI.mihomo_create(configPath: ptr)
            }
            
            if result <= 0 {
                throw Self.errorFromCode(CInt(result))
            }
            
            self.handle = result
        }
        
        deinit {
            let result = MihomoFFI.mihomo_destroy(handle: handle)
            if result != CErrorCode.success.rawValue {
                let error = Self.errorFromCode(result)
                print("Warning: Failed to destroy mihomo instance: \(error.localizedDescription)")
            }
        }
        
        public var isValid: Bool {
            return handle > 0
        }
        
        private static func errorFromCode(_ code: CInt) -> Error {
            guard let errorCode = CErrorCode(rawValue: code) else {
                return .creationFailed("Unknown error code: \(code)")
            }
            
            switch errorCode {
            case .success:
                return .creationFailed("Unexpected success code")
            case .invalidHandle:
                return .invalidHandle
            case .alreadyCreated:
                return .alreadyCreated
            case .invalidConfig:
                return .invalidConfig
            case .alreadyStarted, .notStarted, .internalError:
                return .creationFailed("Internal error: \(code)")
            }
        }
        
        private static func getLastError() -> String {
            let cString = MihomoFFI.mihomo_get_last_error()
            defer { MihomoFFI.mihomo_free_string(ptr: cString) }
            return String(cString: cString)
        }
    }
}