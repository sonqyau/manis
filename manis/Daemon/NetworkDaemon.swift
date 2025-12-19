import Foundation
import Network

enum NetworkDaemon {
    static func getUsedPorts() -> [Int] {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "lsof -nP -iTCP -sTCP:LISTEN | grep LISTEN"]

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }

            let ports = output.split(separator: "\n").compactMap { line -> Int? in
                let components = line.split(separator: " ").map(String.init)
                guard components.count >= 9,
                      let portString = components[8].components(separatedBy: ":").last,
                      let port = Int(portString)
                else {
                    return nil
                }
                return port
            }

            return Array(Set(ports)).sorted()
        } catch {
            return []
        }
    }

    static func testConnectivity(
        host: String,
        port: Int,
        timeout: TimeInterval,
        completion: @escaping @Sendable (Bool) -> Void,
        ) {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: .tcp,
            )

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.cancel()
                completion(true)
            case .failed, .cancelled:
                completion(false)
            default:
                break
            }
        }

        connection.start(queue: .global())

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            connection.cancel()
            completion(false)
        }
    }

    static func isPortAvailable(_ port: Int) -> Bool {
        let usedPorts = getUsedPorts()
        return !usedPorts.contains(port)
    }

    static func findAvailablePort(startingFrom: Int = 7890, range: Int = 100) -> Int? {
        let usedPorts = Set(getUsedPorts())

        for port in startingFrom ..< (startingFrom + range) where !usedPorts.contains(port) {
            return port
        }

        return nil
    }
}
