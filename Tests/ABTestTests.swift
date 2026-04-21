import XCTest
@testable import RiviumPush

/// Unit tests for A/B Testing models
final class ABTestTests: XCTestCase {

    // MARK: - ABTestVariant Tests

    func testABTestVariant_initMinimal() {
        let variant = ABTestVariant(
            testId: "test1",
            variantId: "var1",
            variantName: "Variant A",
            content: nil
        )

        XCTAssertEqual(variant.testId, "test1")
        XCTAssertEqual(variant.variantId, "var1")
        XCTAssertEqual(variant.variantName, "Variant A")
        XCTAssertFalse(variant.isControlGroup)
        XCTAssertNil(variant.content)
    }

    func testABTestVariant_initWithControlGroup() {
        let variant = ABTestVariant(
            testId: "test1",
            variantId: "control",
            variantName: "Control",
            isControlGroup: true,
            content: nil
        )

        XCTAssertTrue(variant.isControlGroup)
    }

    func testABTestVariant_initWithContent() {
        let content = ABTestContent(
            title: "Test Title",
            body: "Test Body"
        )
        let variant = ABTestVariant(
            testId: "test1",
            variantId: "var1",
            variantName: "Variant A",
            content: content
        )

        XCTAssertNotNil(variant.content)
        XCTAssertEqual(variant.content?.title, "Test Title")
        XCTAssertEqual(variant.content?.body, "Test Body")
    }

    func testABTestVariant_decoding() throws {
        let json = """
        {
            "testId": "test123",
            "variantId": "variant_a",
            "variantName": "Variant A",
            "isControlGroup": false,
            "content": {
                "title": "New Feature",
                "body": "Try our new feature"
            }
        }
        """

        let data = json.data(using: .utf8)!
        let variant = try JSONDecoder().decode(ABTestVariant.self, from: data)

        XCTAssertEqual(variant.testId, "test123")
        XCTAssertEqual(variant.variantId, "variant_a")
        XCTAssertEqual(variant.variantName, "Variant A")
        XCTAssertFalse(variant.isControlGroup)
        XCTAssertEqual(variant.content?.title, "New Feature")
    }

    func testABTestVariant_decodingWithMissingOptionals() throws {
        let json = """
        {
            "testId": "test123",
            "variantId": "control",
            "variantName": "Control"
        }
        """

        let data = json.data(using: .utf8)!
        let variant = try JSONDecoder().decode(ABTestVariant.self, from: data)

        XCTAssertEqual(variant.testId, "test123")
        XCTAssertFalse(variant.isControlGroup) // Default value
        XCTAssertNil(variant.content)
    }

    func testABTestVariant_toDictionary() {
        let variant = ABTestVariant(
            testId: "test1",
            variantId: "var1",
            variantName: "Test",
            isControlGroup: true,
            content: nil
        )

        let dict = variant.toDictionary()

        XCTAssertEqual(dict["testId"] as? String, "test1")
        XCTAssertEqual(dict["variantId"] as? String, "var1")
        XCTAssertEqual(dict["variantName"] as? String, "Test")
        XCTAssertEqual(dict["isControlGroup"] as? Bool, true)
    }

    // MARK: - ABTestContent Tests

    func testABTestContent_initMinimal() {
        let content = ABTestContent(title: "Title", body: "Body")

        XCTAssertEqual(content.title, "Title")
        XCTAssertEqual(content.body, "Body")
        XCTAssertNil(content.data)
        XCTAssertNil(content.imageUrl)
        XCTAssertNil(content.deepLink)
        XCTAssertNil(content.actions)
    }

    func testABTestContent_initFull() {
        let action = ABTestAction(id: "action1", title: "Click", action: "open_url")
        let content = ABTestContent(
            title: "Title",
            body: "Body",
            data: ["key": AnyCodable("value")],
            imageUrl: "https://example.com/image.png",
            deepLink: "myapp://feature",
            actions: [action]
        )

        XCTAssertEqual(content.title, "Title")
        XCTAssertEqual(content.body, "Body")
        XCTAssertNotNil(content.data)
        XCTAssertEqual(content.imageUrl, "https://example.com/image.png")
        XCTAssertEqual(content.deepLink, "myapp://feature")
        XCTAssertEqual(content.actions?.count, 1)
    }

    func testABTestContent_decoding() throws {
        let json = """
        {
            "title": "New Feature",
            "body": "Check it out",
            "imageUrl": "https://example.com/img.png",
            "deepLink": "app://feature"
        }
        """

        let data = json.data(using: .utf8)!
        let content = try JSONDecoder().decode(ABTestContent.self, from: data)

        XCTAssertEqual(content.title, "New Feature")
        XCTAssertEqual(content.body, "Check it out")
        XCTAssertEqual(content.imageUrl, "https://example.com/img.png")
        XCTAssertEqual(content.deepLink, "app://feature")
    }

    func testABTestContent_toDictionary() {
        let content = ABTestContent(
            title: "Test",
            body: "Body",
            imageUrl: "https://example.com/img.png"
        )

        let dict = content.toDictionary()

        XCTAssertEqual(dict["title"] as? String, "Test")
        XCTAssertEqual(dict["body"] as? String, "Body")
        XCTAssertEqual(dict["imageUrl"] as? String, "https://example.com/img.png")
    }

    // MARK: - ABTestAction Tests

    func testABTestAction_init() {
        let action = ABTestAction(id: "btn1", title: "Buy Now", action: "purchase")

        XCTAssertEqual(action.id, "btn1")
        XCTAssertEqual(action.title, "Buy Now")
        XCTAssertEqual(action.action, "purchase")
    }

    func testABTestAction_decoding() throws {
        let json = """
        {
            "id": "action1",
            "title": "Learn More",
            "action": "open_url"
        }
        """

        let data = json.data(using: .utf8)!
        let action = try JSONDecoder().decode(ABTestAction.self, from: data)

        XCTAssertEqual(action.id, "action1")
        XCTAssertEqual(action.title, "Learn More")
        XCTAssertEqual(action.action, "open_url")
    }

    func testABTestAction_toDictionary() {
        let action = ABTestAction(id: "a1", title: "Click", action: "navigate")

        let dict = action.toDictionary()

        XCTAssertEqual(dict["id"] as? String, "a1")
        XCTAssertEqual(dict["title"] as? String, "Click")
        XCTAssertEqual(dict["action"] as? String, "navigate")
    }

    // MARK: - ABTestSummary Tests

    func testABTestSummary_init() {
        let summary = ABTestSummary(
            id: "test1",
            name: "Button Color Test",
            variantCount: 3,
            hasControlGroup: true
        )

        XCTAssertEqual(summary.id, "test1")
        XCTAssertEqual(summary.name, "Button Color Test")
        XCTAssertEqual(summary.variantCount, 3)
        XCTAssertTrue(summary.hasControlGroup)
    }

    func testABTestSummary_decoding() throws {
        let json = """
        {
            "id": "test123",
            "name": "Homepage Banner",
            "variantCount": 2,
            "hasControlGroup": true
        }
        """

        let data = json.data(using: .utf8)!
        let summary = try JSONDecoder().decode(ABTestSummary.self, from: data)

        XCTAssertEqual(summary.id, "test123")
        XCTAssertEqual(summary.name, "Homepage Banner")
        XCTAssertEqual(summary.variantCount, 2)
        XCTAssertTrue(summary.hasControlGroup)
    }

    func testABTestSummary_decodingWithMissingOptionals() throws {
        let json = """
        {
            "id": "test123",
            "name": "Simple Test"
        }
        """

        let data = json.data(using: .utf8)!
        let summary = try JSONDecoder().decode(ABTestSummary.self, from: data)

        XCTAssertEqual(summary.id, "test123")
        XCTAssertEqual(summary.name, "Simple Test")
        XCTAssertEqual(summary.variantCount, 0) // Default
        XCTAssertFalse(summary.hasControlGroup) // Default
    }

    func testABTestSummary_decodingArray() throws {
        let json = """
        [
            {"id": "test1", "name": "Test 1", "variantCount": 2, "hasControlGroup": true},
            {"id": "test2", "name": "Test 2", "variantCount": 3, "hasControlGroup": false}
        ]
        """

        let data = json.data(using: .utf8)!
        let summaries = try JSONDecoder().decode([ABTestSummary].self, from: data)

        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries[0].id, "test1")
        XCTAssertEqual(summaries[1].id, "test2")
    }

    func testABTestSummary_toDictionary() {
        let summary = ABTestSummary(
            id: "test1",
            name: "Test",
            variantCount: 2,
            hasControlGroup: true
        )

        let dict = summary.toDictionary()

        XCTAssertEqual(dict["id"] as? String, "test1")
        XCTAssertEqual(dict["name"] as? String, "Test")
        XCTAssertEqual(dict["variantCount"] as? Int, 2)
        XCTAssertEqual(dict["hasControlGroup"] as? Bool, true)
    }

    // MARK: - ABTestEvent Tests

    func testABTestEvent_rawValues() {
        XCTAssertEqual(ABTestEvent.impression.rawValue, "impression")
        XCTAssertEqual(ABTestEvent.opened.rawValue, "opened")
        XCTAssertEqual(ABTestEvent.clicked.rawValue, "clicked")
        XCTAssertEqual(ABTestEvent.converted.rawValue, "converted")
    }

    // MARK: - ABTestStatistics Tests

    func testABTestStatistics_init() {
        let stats = ABTestStatistics(
            isSignificant: true,
            confidenceLevel: 0.95,
            pValue: 0.03,
            lift: 15.5,
            sampleSizeRecommendation: 1000
        )

        XCTAssertTrue(stats.isSignificant)
        XCTAssertEqual(stats.confidenceLevel, 0.95)
        XCTAssertEqual(stats.pValue, 0.03)
        XCTAssertEqual(stats.lift, 15.5)
        XCTAssertEqual(stats.sampleSizeRecommendation, 1000)
    }

    func testABTestStatistics_toDictionary() {
        let stats = ABTestStatistics(
            isSignificant: false,
            confidenceLevel: 0.90,
            pValue: 0.12,
            lift: 5.0
        )

        let dict = stats.toDictionary()

        XCTAssertEqual(dict["isSignificant"] as? Bool, false)
        XCTAssertEqual(dict["confidenceLevel"] as? Double, 0.90)
        XCTAssertEqual(dict["pValue"] as? Double, 0.12)
        XCTAssertEqual(dict["lift"] as? Double, 5.0)
    }

    // MARK: - ConfidenceInterval Tests

    func testConfidenceInterval_init() {
        let ci = ConfidenceInterval(lower: 0.05, upper: 0.15)

        XCTAssertEqual(ci.lower, 0.05)
        XCTAssertEqual(ci.upper, 0.15)
    }

    func testConfidenceInterval_toDictionary() {
        let ci = ConfidenceInterval(lower: 0.10, upper: 0.20)

        let dict = ci.toDictionary()

        XCTAssertEqual(dict["lower"] as? Double, 0.10)
        XCTAssertEqual(dict["upper"] as? Double, 0.20)
    }

    // MARK: - AnyCodable Tests

    func testAnyCodable_string() throws {
        let any = AnyCodable("test string")
        XCTAssertEqual(any.value as? String, "test string")
    }

    func testAnyCodable_int() throws {
        let any = AnyCodable(42)
        XCTAssertEqual(any.value as? Int, 42)
    }

    func testAnyCodable_double() throws {
        let any = AnyCodable(3.14)
        XCTAssertEqual(any.value as? Double, 3.14)
    }

    func testAnyCodable_bool() throws {
        let any = AnyCodable(true)
        XCTAssertEqual(any.value as? Bool, true)
    }

    func testAnyCodable_decodingFromJSON() throws {
        let json = """
        {
            "stringValue": "hello",
            "intValue": 42,
            "boolValue": true
        }
        """

        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: data)

        XCTAssertEqual(decoded["stringValue"]?.value as? String, "hello")
        XCTAssertEqual(decoded["intValue"]?.value as? Int, 42)
        XCTAssertEqual(decoded["boolValue"]?.value as? Bool, true)
    }
}
