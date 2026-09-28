import Foundation
import PNProtocol

/// Network type an endpoint is remembered for.
internal enum NetworkKind: String {
    case wifi
    case cellular
    case other
}

/// `mqttEndpoints` from the register response:
/// `[{ "host": "...", "port": 443, "tls": true }]`.
///
/// Decoding never fails, so a malformed list can never break registration:
/// invalid entries are dropped, unknown fields ignored.
internal struct MqttEndpointList: Decodable {
    static let maxEndpoints = 5

    let endpoints: [PNEndpoint]

    init(endpoints: [PNEndpoint]) {
        self.endpoints = endpoints
    }

    init(from decoder: Decoder) {
        var result: [PNEndpoint] = []
        if var list = try? decoder.unkeyedContainer() {
            while !list.isAtEnd {
                // Entry.init never throws, so the container always advances.
                guard let entry = try? list.decode(Entry.self) else { break }
                if let endpoint = entry.endpoint, !result.contains(endpoint) {
                    result.append(endpoint)
                }
            }
        }
        endpoints = Array(result.prefix(MqttEndpointList.maxEndpoints))
    }

    private struct Entry: Decodable {
        let endpoint: PNEndpoint?

        private enum Keys: String, CodingKey { case host, port, tls }

        init(from decoder: Decoder) {
            guard let c = try? decoder.container(keyedBy: Keys.self) else {
                endpoint = nil
                return
            }
            let host = ((try? c.decodeIfPresent(String.self, forKey: .host)) ?? nil)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let port = (try? c.decodeIfPresent(Int.self, forKey: .port)) ?? nil
            let tls = ((try? c.decodeIfPresent(Bool.self, forKey: .tls)) ?? nil) ?? true
            endpoint = MqttEndpointList.validated(host: host, port: port, tls: tls)
        }
    }

    static func validated(host: String, port: Int?, tls: Bool) -> PNEndpoint? {
        guard !host.isEmpty,
              !host.contains(where: { $0.isWhitespace || $0 == "/" }),
              let port = port, (1...65535).contains(port) else { return nil }
        return PNEndpoint(host: host, port: UInt16(port), secure: tls)
    }
}

/// Order in which to try endpoints:
/// 1. the one that last worked on this network type (if still offered),
/// 2. the server's list in order,
/// 3. the default gateway, always last.
/// With no server list this is just the default gateway, as before.
internal enum MqttEndpointOrder {
    static func ordered(
        server: [PNEndpoint],
        fallback: PNEndpoint,
        lastGood: PNEndpoint?
    ) -> [PNEndpoint] {
        let candidates = server.filter { $0 != fallback } + [fallback]
        var result: [PNEndpoint] = []
        if let lastGood = lastGood, candidates.contains(lastGood) {
            result.append(lastGood)
        }
        for endpoint in candidates where !result.contains(endpoint) {
            result.append(endpoint)
        }
        return result
    }
}

/// Remembers, per network type, the endpoint that last connected.
internal final class MqttEndpointMemory {
    private static let keyPrefix = "co.rivium.push.mqttEndpoint."
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lastGood(for kind: NetworkKind) -> PNEndpoint? {
        guard let dict = defaults.dictionary(forKey: MqttEndpointMemory.keyPrefix + kind.rawValue),
              let host = dict["host"] as? String,
              let port = dict["port"] as? Int,
              let tls = dict["tls"] as? Bool else { return nil }
        return MqttEndpointList.validated(host: host, port: port, tls: tls)
    }

    func remember(_ endpoint: PNEndpoint, for kind: NetworkKind) {
        guard lastGood(for: kind) != endpoint else { return }
        defaults.set(
            ["host": endpoint.host, "port": Int(endpoint.port), "tls": endpoint.secure],
            forKey: MqttEndpointMemory.keyPrefix + kind.rawValue
        )
    }
}
