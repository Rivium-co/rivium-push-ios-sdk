import XCTest
@testable import RiviumPush

/// X-Rivium-SDK-Report: counts only, kept until a 2xx answer, nothing at all when switched off.
final class SdkDiagnosticsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var diag: SdkDiagnostics!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SdkDiagnosticsTests")
        defaults.removePersistentDomain(forName: "SdkDiagnosticsTests")
        diag = SdkDiagnostics(defaults: defaults)
    }

    func testCountsByPublicCodeAndFormatsTheHeader() {
        diag.count(.registrationFailed)
        diag.count(.connectionLost)
        diag.count(.connectionLost)
        XCTAssertEqual(diag.pending(), [1400: 1, 1002: 2])
        XCTAssertEqual(SdkDiagnostics.headerValue(diag.pending()), "1002=2 1400=1")
        XCTAssertNil(SdkDiagnostics.headerValue([:]))
    }

    func testBounded() {
        for code in 2000..<2020 { diag.count(code) }
        XCTAssertEqual(diag.pending().count, SdkDiagnostics.maxCodes)
        for _ in 0..<10_050 { diag.count(2000) }
        XCTAssertEqual(diag.pending()[2000], SdkDiagnostics.maxCount)
    }

    func testSwitchedOffCountsKeepsAndSendsNothing() {
        diag.count(1400)
        diag.setEnabled(false)
        diag.count(1400)
        XCTAssertTrue(diag.pending().isEmpty)
        var request = URLRequest(url: URL(string: "https://example.test")!)
        XCTAssertTrue(diag.attach(to: &request).isEmpty)
        XCTAssertNil(request.value(forHTTPHeaderField: SdkDiagnostics.header))
        diag.setEnabled(true)
        XCTAssertTrue(diag.pending().isEmpty)
    }

    func testAttachThenAcknowledgeKeepsLaterCounts() {
        diag.count(1400)
        diag.count(1400)
        var request = URLRequest(url: URL(string: "https://example.test")!)
        let sent = diag.attach(to: &request)
        XCTAssertEqual(request.value(forHTTPHeaderField: SdkDiagnostics.header), "1400=2")
        diag.count(1400) // while the request is in flight
        diag.acknowledge(sent)
        XCTAssertEqual(diag.pending(), [1400: 1])
    }
}
