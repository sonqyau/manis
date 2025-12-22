import Foundation
import OSLog

actor NetworkService {
    private let logger = Logger(subsystem: "com.manis.Daemon", category: "NetworkService")

    func getUsedPorts() async -> [Int] {
        logger.debug("Getting used ports")

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let ports = self.scanUsedPorts()
                continuation.resume(returning: ports)
            }
        }
    }

    func testConnectivity(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        logger.debug("Testing connectivity to \(host):\(port)")

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let isConnected = self.testConnection(host: host, port: port, timeout: timeout)
                continuation.resume(returning: isConnected)
            }
        }
    }

    private nonisolated func scanUsedPorts() -> [Int] {
        var ports: [Int] = []

        let process = Process()
        let pipe = Pipe()

        process.standardOutput = pipe
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        process.arguments = ["-an", "-p", "tcp"]

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                ports = parseNetstatOutput(output)
            }
        } catch {
            logger.error("Failed to execute netstat: \(error)")
        }

        return ports.sorted()
    }

    private nonisolated func parseNetstatOutput(_ output: String) -> [Int] {
        var ports: Set<Int> = []

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            if components.count >= 4, components[0] == "tcp4" {
                let localAddress = components[3]

                if let portString = localAddress.components(separatedBy: ".").last,
                   let port = Int(portString)
                {
                    ports.insert(port)
                }
            }
        }

        return Array(ports)
    }

    private nonisolated func testConnection(host: String, port: Int, timeout: TimeInterval) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        process.arguments = ["-z", "-w", "\(Int(timeout))", host, "\(port)"]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            logger.error("Failed to test connectivity: \(error)")
            return false
        }
    }
}
