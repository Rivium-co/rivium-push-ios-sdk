import Foundation

/// Mock URL Protocol for intercepting HTTP requests in tests
class MockURLProtocol: URLProtocol {
    /// Handler to process requests and return mock responses
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    /// Store of recorded requests for verification
    static var recordedRequests: [URLRequest] = []

    /// Reset all state
    static func reset() {
        requestHandler = nil
        recordedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        // Record the request
        MockURLProtocol.recordedRequests.append(request)

        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("MockURLProtocol.requestHandler not set")
        }

        do {
            let (response, data) = try handler(request)

            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }

            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // No-op
    }
}

/// Helper to create mock responses
extension MockURLProtocol {
    static func mockResponse(
        statusCode: Int = 200,
        json: Any? = nil,
        string: String? = nil
    ) -> (HTTPURLResponse, Data?) {
        let url = URL(string: "https://push-api.rivium.co")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        var data: Data?
        if let json = json {
            data = try? JSONSerialization.data(withJSONObject: json)
        } else if let string = string {
            data = string.data(using: .utf8)
        }

        return (response, data)
    }

    static func mockJSONResponse<T: Encodable>(
        statusCode: Int = 200,
        value: T
    ) -> (HTTPURLResponse, Data?) {
        let url = URL(string: "https://push-api.rivium.co")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let data = try? JSONEncoder().encode(value)
        return (response, data)
    }
}
