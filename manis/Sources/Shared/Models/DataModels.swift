import Foundation
import SwiftData
import Algorithms
import DifferenceKit

struct DataModels {}

struct TrafficSnapshot: Codable {
    let up: Int64
    let down: Int64

    var uploadSpeed: String {
        ByteCountFormatter.string(fromByteCount: up, countStyle: .binary) + "/s"
    }

    var downloadSpeed: String {
        ByteCountFormatter.string(fromByteCount: down, countStyle: .binary) + "/s"
    }
}

struct TrafficPoint: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let upload: Double
    let download: Double
}

struct ConnectionSnapshot: Codable {
    let downloadTotal: Int64
    let uploadTotal: Int64
    let connections: [Connection]

    struct Metadata: Codable {
        let network: String
        let type: String
        let sourceIP: String
        let destinationIP: String
        let sourcePort: String
        let destinationPort: String
        let host: String
        let process: String
        let processPath: String

        enum CodingKeys: String, CodingKey {
            case network, type, host, process
            case sourceIP, destinationIP
            case sourcePort, destinationPort
            case processPath
        }
    }

    struct Connection: Codable, Identifiable, Differentiable {
        let id: String
        let chains: [String]
        let upload: Int64
        let download: Int64
        let start: Date
        let rule: String
        let rulePayload: String
        let metadata: Metadata

        var differenceIdentifier: String {
            id
        }

        func isContentEqual(to source: Self) -> Bool {
            chains == source.chains &&
                upload == source.upload &&
                download == source.download &&
                rule == source.rule &&
                rulePayload == source.rulePayload &&
                metadata.network == source.metadata.network &&
                metadata.type == source.metadata.type &&
                metadata.sourceIP == source.metadata.sourceIP &&
                metadata.destinationIP == source.metadata.destinationIP &&
                metadata.sourcePort == source.metadata.sourcePort &&
                metadata.destinationPort == source.metadata.destinationPort &&
                metadata.host == source.metadata.host &&
                metadata.process == source.metadata.process &&
                metadata.processPath == source.metadata.processPath
        }

        var displayHost: String {
            metadata.host.isEmpty ? metadata.destinationIP : metadata.host
        }

        var displayDestination: String {
            "\(displayHost):\(metadata.destinationPort)"
        }

        var chainString: String {
            chains.reversed().joined(separator: " → ")
        }

        var ruleString: String {
            rulePayload.isEmpty ? rule : "\(rule) :: \(rulePayload)"
        }
    }
}

struct MemorySnapshot: Codable {
    let inuse: Int64

    var formattedMemory: String {
        ByteCountFormatter.string(fromByteCount: inuse, countStyle: .memory)
    }
}

struct ClashVersion: Codable {
    let version: String
    let meta: Bool

    init(version: String, meta: Bool = false) {
        self.version = version
        self.meta = meta
    }
}
