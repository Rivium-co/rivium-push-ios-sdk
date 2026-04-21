import Foundation

/// Network configuration for API communication
/// Provides HTTP retry logic with exponential backoff
internal struct NetworkConfig {

    // MARK: - Retry Configuration

    /// Maximum number of retry attempts
    static let maxRetryAttempts = 3

    /// Initial retry delay in seconds
    static let initialRetryDelay: TimeInterval = 1.0

    /// Maximum retry delay in seconds
    static let maxRetryDelay: TimeInterval = 30.0

    /// Multiplier for exponential backoff
    static let retryBackoffMultiplier: Double = 2.0

    /// HTTP status codes that should trigger a retry
    static let retryableStatusCodes: Set<Int> = [
        408, // Request Timeout
        429, // Too Many Requests
        500, // Internal Server Error
        502, // Bad Gateway
        503, // Service Unavailable
        504  // Gateway Timeout
    ]

    // MARK: - Timeout Configuration

    /// Request timeout in seconds
    static let requestTimeout: TimeInterval = 30.0

    /// Resource timeout in seconds
    static let resourceTimeout: TimeInterval = 60.0
}

// MARK: - Retrying URL Session

/// URLSession wrapper with automatic retry logic
internal class RetryingURLSession {

    private let session: URLSession
    private let TAG = "RetryingURLSession"

    init(delegate: URLSessionDelegate? = nil) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = NetworkConfig.requestTimeout
        config.timeoutIntervalForResource = NetworkConfig.resourceTimeout
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    /// Execute a request with automatic retry logic
    func dataTask(
        with request: URLRequest,
        retryCount: Int = 0,
        completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) {
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                completion(data, response, error)
                return
            }

            // Check if we should retry
            if self.shouldRetry(response: response, error: error, retryCount: retryCount) {
                let delay = self.calculateRetryDelay(attempt: retryCount)
                Log.w(self.TAG, "Request failed, retrying in \(delay)s (attempt \(retryCount + 1)/\(NetworkConfig.maxRetryAttempts))")

                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self.dataTask(with: request, retryCount: retryCount + 1, completion: completion)
                }
                return
            }

            completion(data, response, error)
        }.resume()
    }

    private func shouldRetry(response: URLResponse?, error: Error?, retryCount: Int) -> Bool {
        // Don't retry if we've exceeded max attempts
        guard retryCount < NetworkConfig.maxRetryAttempts else {
            return false
        }

        // Retry on network errors
        if let nsError = error as NSError? {
            let retryableErrorCodes: Set<Int> = [
                NSURLErrorTimedOut,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet
            ]
            if retryableErrorCodes.contains(nsError.code) {
                return true
            }
        }

        // Retry on certain HTTP status codes
        if let httpResponse = response as? HTTPURLResponse {
            return NetworkConfig.retryableStatusCodes.contains(httpResponse.statusCode)
        }

        return false
    }

    private func calculateRetryDelay(attempt: Int) -> TimeInterval {
        let delay = NetworkConfig.initialRetryDelay * pow(NetworkConfig.retryBackoffMultiplier, Double(attempt))
        return min(delay, NetworkConfig.maxRetryDelay)
    }
}
