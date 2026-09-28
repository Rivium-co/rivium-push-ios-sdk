import XCTest
import PNProtocol
@testable import RiviumPush

final class MqttEndpointParsingTests: XCTestCase {

    private func decodeList(_ json: String) throws -> [PNEndpoint] {
        try JSONDecoder().decode(MqttEndpointList.self, from: Data(json.utf8)).endpoints
    }

    private func registerJSON(endpoints: String?) -> Data {
        var json = """
        {"id":"d1","deviceId":"d1","message":"ok",
         "mqtt":{"host":"pn-tcp.rivium.co","port":8883,"secure":true,"token":"t"}
        """
        if let endpoints = endpoints { json += ",\"mqttEndpoints\":\(endpoints)" }
        return Data((json + "}").utf8)
    }

    func testParsesValidEntriesAndDefaultsTlsToTrue() throws {
        let list = try decodeList("""
        [{"host":"a.example","port":443,"tls":true,"weight":3},
         {"host":"b.example","port":8883},
         {"host":"c.example","port":1883,"tls":false}]
        """)
        XCTAssertEqual(list, [
            PNEndpoint(host: "a.example", port: 443, secure: true),
            PNEndpoint(host: "b.example", port: 8883, secure: true),
            PNEndpoint(host: "c.example", port: 1883, secure: false),
        ])
    }

    func testDropsInvalidEntries() throws {
        let list = try decodeList("""
        [{"host":"","port":443},
         {"host":"  ","port":443},
         {"host":"a.example"},
         {"host":"a.example","port":0},
         {"host":"a.example","port":65536},
         {"host":"a.example","port":"443"},
         {"host":"a b","port":443},
         {"port":443},
         "not-an-object",
         42,
         {"host":" ok.example ","port":65535,"tls":"yes"}]
        """)
        XCTAssertEqual(list, [PNEndpoint(host: "ok.example", port: 65535, secure: true)])
    }

    func testKeepsAtMostFiveAndDropsDuplicates() throws {
        let entries = (1...8).map { "{\"host\":\"h\($0).example\",\"port\":443}" }
        let list = try decodeList("[{\"host\":\"h1.example\",\"port\":443}," + entries.joined(separator: ",") + "]")
        XCTAssertEqual(list.map { $0.host }, ["h1.example", "h2.example", "h3.example", "h4.example", "h5.example"])
    }

    func testRegisterResponseWithoutFieldIsUnchanged() throws {
        let r = try JSONDecoder().decode(ApiClient.RegisterResponse.self, from: registerJSON(endpoints: nil))
        XCTAssertNil(r.mqttEndpoints)
        XCTAssertEqual(r.mqtt?.host, "pn-tcp.rivium.co")
    }

    func testMalformedFieldNeverBreaksRegistration() throws {
        for bad in ["null", "{}", "\"x\"", "12", "[1,2]", "[{\"host\":5}]"] {
            let r = try JSONDecoder().decode(ApiClient.RegisterResponse.self, from: registerJSON(endpoints: bad))
            XCTAssertEqual(r.mqttEndpoints?.endpoints ?? [], [], "input: \(bad)")
            XCTAssertEqual(r.deviceId, "d1")
        }
    }

    func testRegisterResponseWithEndpoints() throws {
        let r = try JSONDecoder().decode(
            ApiClient.RegisterResponse.self,
            from: registerJSON(endpoints: "[{\"host\":\"edge.example\",\"port\":443,\"tls\":true}]")
        )
        XCTAssertEqual(r.mqttEndpoints?.endpoints, [PNEndpoint(host: "edge.example", port: 443)])
    }
}

final class MqttEndpointOrderTests: XCTestCase {
    private let a = PNEndpoint(host: "a.example", port: 443)
    private let b = PNEndpoint(host: "b.example", port: 443)
    private let def = PNEndpoint(host: "pn-tcp.rivium.co", port: 8883)

    func testNoServerListIsTodaysDefault() {
        XCTAssertEqual(MqttEndpointOrder.ordered(server: [], fallback: def, lastGood: nil), [def])
        // A remembered endpoint the server no longer offers is ignored.
        XCTAssertEqual(MqttEndpointOrder.ordered(server: [], fallback: def, lastGood: a), [def])
    }

    func testServerOrderThenDefaultLast() {
        XCTAssertEqual(MqttEndpointOrder.ordered(server: [a, b], fallback: def, lastGood: nil), [a, b, def])
        XCTAssertEqual(MqttEndpointOrder.ordered(server: [def, a, b], fallback: def, lastGood: nil), [a, b, def])
    }

    func testLastGoodFirst() {
        XCTAssertEqual(MqttEndpointOrder.ordered(server: [a, b], fallback: def, lastGood: b), [b, a, def])
        XCTAssertEqual(MqttEndpointOrder.ordered(server: [a, b], fallback: def, lastGood: def), [def, a, b])
        let gone = PNEndpoint(host: "gone.example", port: 443)
        XCTAssertEqual(MqttEndpointOrder.ordered(server: [a, b], fallback: def, lastGood: gone), [a, b, def])
    }
}

final class MqttEndpointMemoryTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "co.rivium.push.tests.endpoints"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testRemembersPerNetworkType() {
        let memory = MqttEndpointMemory(defaults: defaults)
        let a = PNEndpoint(host: "a.example", port: 443)
        let b = PNEndpoint(host: "b.example", port: 8443, secure: false)
        memory.remember(a, for: .wifi)
        memory.remember(b, for: .cellular)
        XCTAssertEqual(memory.lastGood(for: .wifi), a)
        XCTAssertEqual(memory.lastGood(for: .cellular), b)
        XCTAssertNil(memory.lastGood(for: .other))
        // Persisted: a fresh instance reads the same values.
        XCTAssertEqual(MqttEndpointMemory(defaults: defaults).lastGood(for: .cellular), b)
    }

    func testSocketManagerOrdersByCurrentNetwork() {
        let memory = MqttEndpointMemory(defaults: defaults)
        let a = PNEndpoint(host: "a.example", port: 443)
        let b = PNEndpoint(host: "b.example", port: 443)
        memory.remember(b, for: .cellular)

        var config = RiviumPushConfig(apiKey: "k")
        config.updatePNConfig(host: "pn-tcp.rivium.co", port: 8883, secure: true, token: "t", endpoints: [a, b])
        let def = PNEndpoint(host: "pn-tcp.rivium.co", port: 8883)

        var kind = NetworkKind.wifi
        let manager = PNSocketManager(
            config: config, appId: "app", deviceId: "dev",
            endpointMemory: memory, networkKind: { kind }
        )
        XCTAssertEqual(manager.orderedEndpoints(), [a, b, def])
        kind = .cellular
        XCTAssertEqual(manager.orderedEndpoints(), [b, a, def])
    }
}

final class MqttConnectionDefaultsTests: XCTestCase {

    func testSocketConfigDefaults() {
        var config = RiviumPushConfig(apiKey: "k")
        config.updatePNConfig(host: "pn-tcp.rivium.co", port: 8883, secure: true, token: "t")
        let suite = "co.rivium.push.tests.defaults"
        UserDefaults().removePersistentDomain(forName: suite)
        let manager = PNSocketManager(
            config: config, appId: "app", deviceId: "dev",
            endpointMemory: MqttEndpointMemory(defaults: UserDefaults(suiteName: suite)!)
        )
        let pn = manager.makePNConfig(clientId: "c")
        XCTAssertEqual(pn.heartbeatInterval, 30)
        XCTAssertEqual(pn.reconnectDelay, 1.0, accuracy: 0.0001)
        XCTAssertEqual(pn.maxReconnectDelay, 60.0, accuracy: 0.0001)
        XCTAssertEqual(pn.maxReconnectAttempts, 0, "never gives up")
        XCTAssertTrue(pn.autoReconnect)
        XCTAssertTrue(pn.freshStart, "cleanSession unchanged")
        XCTAssertEqual(pn.endpoints, [PNEndpoint(host: "pn-tcp.rivium.co", port: 8883, secure: true)])
    }

    func testBackoffWithSdkDefaults() {
        // 1 s, 2 s, 4 s ... capped at 60 s, +-20 %.
        for attempt in 0..<30 {
            let d = PNBackoff.delay(attempt: attempt, initial: 1, max: 60)
            let base = min(pow(2, Double(attempt)), 60)
            XCTAssertGreaterThanOrEqual(d, base * 0.8 - 0.0001)
            XCTAssertLessThanOrEqual(d, 60)
        }
        XCTAssertEqual(PNBackoff.delay(attempt: 0, initial: 1, max: 60, random: 0.5), 1, accuracy: 0.0001)
    }
}
