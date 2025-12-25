import AsyncAlgorithms
import Foundation
import OSLog
import SystemPackage
import Algorithms

actor NetworkService {
    private let logger = Logger(subsystem: "com.manis.Daemon", category: "NetworkService")

    func monitorPorts(interval: Duration = .seconds(5)) async -> AsyncStream<[Int]> {
        logger.debug("Starting port monitoring")

        let timer = AsyncTimerSequence(interval: interval, clock: ContinuousClock())
            .compactMap { _ in }
            .debounce(for: .seconds(0.3))

        return AsyncStream { continuation in
            Task {
                for await _ in timer {
                    let ports = await scanUsedPortsAsync()
                    continuation.yield(ports)
                }
            }
        }
    }

    func monitorConnectivity(
        host: String,
        port: Int,
        interval: Duration = .seconds(10),
        timeout: TimeInterval = 3.0
    ) async -> AsyncStream<Bool> {
        logger.debug("Starting connectivity monitoring for \(host):\(port)")

        let timer = AsyncTimerSequence(interval: interval, clock: ContinuousClock())
            .debounce(for: .seconds(0.5))

        return AsyncStream { continuation in
            Task {
                for await _ in timer {
                    let isConnected = await testConnectivity(host: host, port: port, timeout: timeout)
                    continuation.yield(isConnected)
                }
            }
        }
    }

    func getUsedPorts() async -> [Int] {
        return await scanUsedPortsAsync()
    }

    private func scanUsedPortsAsync() async -> [Int] {
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

    nonisolated private func scanUsedPorts() -> [Int] {
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
        } catch let errno as Errno {
            logger.error("Failed to execute netstat: \(errno)")
        } catch {
            logger.error("Failed to execute netstat: \(error)")
        }

        return ports.sorted()
    }

    nonisolated private func parseNetstatOutput(_ output: String) -> [Int] {
        let lines = output.components(separatedBy: .newlines)

        return lines.compactMap { line -> Int? in
            let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            guard components.count >= 4, components[0] == "tcp4" else {
                return nil
            }

            let localAddress = components[3]

            guard let portString = localAddress.components(separatedBy: ".").last,
                  let port = Int(portString) else {
                return nil
            }

            return port
        }.uniqued()
        .sorted()
    }

    nonisolated private func testConnection(host: String, port: Int, timeout: TimeInterval) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        process.arguments = ["-z", "-w", "\(Int(timeout))", host, "\(port)"]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch let errno as Errno {
            logger.error("Failed to test connectivity: \(errno)")
            return false
        } catch {
            logger.error("Failed to test connectivity: \(error)")
            return false
        }
    }
}
