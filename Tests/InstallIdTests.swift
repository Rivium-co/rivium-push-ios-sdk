import XCTest
@testable import RiviumPush

final class InstallIdTests: XCTestCase {

    private let vendorId = "2B6F0CC9-04E1-4A2E-9BE8-1F2E3D4C5B6A"
    private let bundleId = "co.rivium.push.example"

    func testStableForSameInputs() {
        let first = InstallId.compute(vendorId: vendorId, bundleId: bundleId)
        let second = InstallId.compute(vendorId: vendorId, bundleId: bundleId)
        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
    }

    func testDiffersPerBundleId() {
        XCTAssertNotEqual(
            InstallId.compute(vendorId: vendorId, bundleId: bundleId),
            InstallId.compute(vendorId: vendorId, bundleId: "co.rivium.push.other")
        )
    }

    func testDiffersPerVendorId() {
        XCTAssertNotEqual(
            InstallId.compute(vendorId: vendorId, bundleId: bundleId),
            InstallId.compute(vendorId: "00000000-0000-0000-0000-000000000001", bundleId: bundleId)
        )
    }

    func testMissingOrEmptyInputsReturnNil() {
        XCTAssertNil(InstallId.compute(vendorId: nil, bundleId: bundleId))
        XCTAssertNil(InstallId.compute(vendorId: "", bundleId: bundleId))
        XCTAssertNil(InstallId.compute(vendorId: vendorId, bundleId: nil))
        XCTAssertNil(InstallId.compute(vendorId: vendorId, bundleId: ""))
    }

    func testIs32LowercaseHexCharacters() throws {
        let value = try XCTUnwrap(InstallId.compute(vendorId: vendorId, bundleId: bundleId))
        XCTAssertEqual(value.count, 32)
        XCTAssertNil(value.rangeOfCharacter(from: CharacterSet(charactersIn: "abcdef0123456789").inverted))
        XCTAssertEqual(value, value.lowercased())
        // Same shape the backend accepts: ^[a-f0-9]{8,64}$
        XCTAssertNotNil(value.range(of: "^[a-f0-9]{8,64}$", options: .regularExpression))
    }

    func testRawVendorIdNeverAppearsInOutput() throws {
        let value = try XCTUnwrap(InstallId.compute(vendorId: vendorId, bundleId: bundleId))
        XCTAssertFalse(value.contains(vendorId))
        XCTAssertFalse(value.contains(vendorId.lowercased()))
        XCTAssertFalse(value.contains(vendorId.replacingOccurrences(of: "-", with: "").lowercased()))
        XCTAssertFalse(value.contains(bundleId))
    }

    func testKnownVector() {
        // sha256("vendor:bundle") truncated to 32 hex characters.
        XCTAssertEqual(
            InstallId.compute(vendorId: "vendor", bundleId: "bundle"),
            "ccd1e9f8014c7bde9d571237b1826d04"
        )
    }
}
