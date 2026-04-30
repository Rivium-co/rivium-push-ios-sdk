import Foundation

/// HTTP client for Rivium Push API
internal class ApiClient {
    private let config: RiviumPushConfig
    private let retrySession: RetryingURLSession
    private let TAG = "ApiClient"

    init(config: RiviumPushConfig) {
        self.config = config
        self.retrySession = RetryingURLSession()
    }

    // MARK: - Request/Response Types

    struct RegisterRequest: Encodable {
        let deviceId: String
        let platform: String = "ios"
        let pushToken: String?
        let apnsToken: String?
        let userId: String?
        let metadata: [String: String]?
        let appIdentifier: String?
    }

    /// PN Protocol gateway configuration returned from server with JWT token
    struct PNGatewayConfig: Decodable {
        let host: String
        let wsHost: String?
        let port: Int
        let wsPort: Int?
        let token: String?  // JWT token for PN Protocol authentication (per-device)
        let secure: Bool?   // Enable TLS/SSL for secure connection (default: true)
    }

    struct RegisterResponse: Decodable {
        let id: String
        let deviceId: String
        /// Backend-issued per-install UUID, addressing key for new SDK builds.
        /// New servers populate this; older servers don't, in which case the
        /// SDK falls back to the legacy `id` field which is the same value.
        let subscriptionId: String?
        let appId: String? // App ID from server (first 16 chars of projectId)
        let message: String
        let mqtt: PNGatewayConfig?  // PN Protocol gateway config (named 'mqtt' for backward compatibility)
    }

    /// Response from PN Protocol token refresh
    struct PNTokenResponse: Decodable {
        let deviceId: String
        let token: String
        let message: String?
    }

    struct TopicRequest: Encodable {
        let deviceId: String
        let topic: String
    }

    struct UserIdRequest: Encodable {
        let deviceId: String
        let userId: String?
    }

    struct GenericResponse: Decodable {
        let success: Bool?
        let message: String?
    }

    // MARK: - Device Registration

    /// Register device with server
    func registerDevice(
        deviceId: String,
        pushToken: String?,
        apnsToken: String?,
        userId: String?,
        metadata: [String: String]?,
        appIdentifier: String? = nil,
        completion: @escaping (Result<RegisterResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(config.serverUrl)/devices/register") else {
            completion(.failure(RiviumPushError.invalidUrl))
            return
        }

        let body = RegisterRequest(
            deviceId: deviceId,
            pushToken: pushToken,
            apnsToken: apnsToken,
            userId: userId,
            metadata: metadata,
            appIdentifier: appIdentifier
        )

        post(url: url, body: body, completion: completion)
    }

    /// Unregister device from server
    func unregisterDevice(
        deviceId: String,
        completion: @escaping (Result<GenericResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(config.serverUrl)/devices/\(deviceId)") else {
            completion(.failure(RiviumPushError.invalidUrl))
            return
        }

        delete(url: url, completion: completion)
    }

    // MARK: - Topic Subscriptions

    /// Subscribe to a topic
    func subscribeTopic(
        deviceId: String,
        topic: String,
        completion: @escaping (Result<GenericResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(config.serverUrl)/topics/subscribe") else {
            completion(.failure(RiviumPushError.invalidUrl))
            return
        }

        let body = TopicRequest(deviceId: deviceId, topic: topic)
        post(url: url, body: body, completion: completion)
    }

    /// Unsubscribe from a topic
    func unsubscribeTopic(
        deviceId: String,
        topic: String,
        completion: @escaping (Result<GenericResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(config.serverUrl)/topics/unsubscribe") else {
            completion(.failure(RiviumPushError.invalidUrl))
            return
        }

        let body = TopicRequest(deviceId: deviceId, topic: topic)
        post(url: url, body: body, completion: completion)
    }

    // MARK: - User Management

    /// Set user ID for device
    func setUserId(
        deviceId: String,
        userId: String,
        completion: @escaping (Result<GenericResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(config.serverUrl)/devices/\(deviceId)/user") else {
            completion(.failure(RiviumPushError.invalidUrl))
            return
        }

        let body = UserIdRequest(deviceId: deviceId, userId: userId)
        post(url: url, body: body, completion: completion)
    }

    /// Clear user ID for device
    func clearUserId(
        deviceId: String,
        completion: @escaping (Result<GenericResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(config.serverUrl)/devices/\(deviceId)/user") else {
            completion(.failure(RiviumPushError.invalidUrl))
            return
        }

        delete(url: url, completion: completion)
    }

    // MARK: - PN Protocol Token

    /// Refresh PN Protocol JWT token for a device
    func refreshPNToken(
        deviceId: String,
        completion: @escaping (Result<PNTokenResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(config.serverUrl)/devices/\(deviceId)/mqtt-token/refresh") else {
            completion(.failure(RiviumPushError.invalidUrl))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")

        executeRequest(request, completion: completion)
    }

    // MARK: - In-App Messages

    /// Get in-app messages
    func getInAppMessages(
        params: [String: Any],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let url = URL(string: "\(config.serverUrl)/in-app/fetch") else {
            completion(.failure(RiviumPushError.invalidUrl))
            return
        }

        postRaw(url: url, params: params, completion: completion)
    }

    /// Record in-app message impression
    func recordInAppImpression(
        params: [String: Any],
        completion: ((Result<GenericResponse, Error>) -> Void)? = nil
    ) {
        guard let url = URL(string: "\(config.serverUrl)/in-app/impression") else {
            completion?(.failure(RiviumPushError.invalidUrl))
            return
        }

        postRaw(url: url, params: params) { (result: Result<String, Error>) in
            switch result {
            case .success:
                completion?(.success(GenericResponse(success: true, message: nil)))
            case .failure(let error):
                completion?(.failure(error))
            }
        }
    }

    // MARK: - Inbox

    /// Get inbox messages
    func getInboxMessages(
        params: [String: Any],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let url = URL(string: "\(config.serverUrl)/inbox/messages") else {
            completion(.failure(RiviumPushError.invalidUrl))
            return
        }

        postRaw(url: url, params: params, completion: completion)
    }

    /// Get single inbox message
    func getInboxMessage(
        messageId: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let url = URL(string: "\(config.serverUrl)/inbox/messages/\(messageId)") else {
            completion(.failure(RiviumPushError.invalidUrl))
            return
        }

        getRaw(url: url, completion: completion)
    }

    /// Update inbox message status
    func updateInboxMessage(
        messageId: String,
        status: String,
        completion: @escaping (Result<GenericResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(config.serverUrl)/inbox/messages/\(messageId)") else {
            completion(.failure(RiviumPushError.invalidUrl))
            return
        }

        let params = ["status": status]
        putRaw(url: url, params: params, completion: completion)
    }

    /// Delete inbox message
    func deleteInboxMessage(
        messageId: String,
        completion: @escaping (Result<GenericResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(config.serverUrl)/inbox/messages/\(messageId)") else {
            completion(.failure(RiviumPushError.invalidUrl))
            return
        }

        delete(url: url, completion: completion)
    }

    /// Mark multiple inbox messages
    func markMultipleInboxMessages(
        messageIds: [String],
        status: String,
        completion: @escaping (Result<GenericResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(config.serverUrl)/inbox/messages/mark-multiple") else {
            completion(.failure(RiviumPushError.invalidUrl))
            return
        }

        let params: [String: Any] = [
            "messageIds": messageIds,
            "status": status
        ]
        postRaw(url: url, params: params) { (result: Result<String, Error>) in
            switch result {
            case .success:
                completion(.success(GenericResponse(success: true, message: nil)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Mark all inbox messages as read
    func markAllInboxMessagesAsRead(
        deviceId: String,
        userId: String?,
        completion: @escaping (Result<GenericResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(config.serverUrl)/inbox/messages/mark-all-read") else {
            completion(.failure(RiviumPushError.invalidUrl))
            return
        }

        var params: [String: Any] = ["deviceId": deviceId]
        if let userId = userId {
            params["userId"] = userId
        }

        postRaw(url: url, params: params) { (result: Result<String, Error>) in
            switch result {
            case .success:
                completion(.success(GenericResponse(success: true, message: nil)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - A/B Testing

    /// Get active A/B tests
    func getActiveABTests(
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let url = URL(string: "\(config.serverUrl)/ab-tests/sdk/active") else {
            completion(.failure(RiviumPushError.invalidUrl))
            return
        }

        getRaw(url: url, completion: completion)
    }

    /// Get A/B test variant assignment
    func getABTestAssignment(
        testId: String,
        deviceId: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let url = URL(string: "\(config.serverUrl)/ab-tests/sdk/assignment") else {
            completion(.failure(RiviumPushError.invalidUrl))
            return
        }

        let params: [String: Any] = [
            "testId": testId,
            "deviceId": deviceId
        ]
        postRaw(url: url, params: params, completion: completion)
    }

    /// Track A/B test event
    func trackABTestEvent(
        testId: String,
        variantId: String,
        deviceId: String,
        event: String,
        completion: @escaping (Result<GenericResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(config.serverUrl)/ab-tests/sdk/track/\(event)") else {
            completion(.failure(RiviumPushError.invalidUrl))
            return
        }

        let params: [String: Any] = [
            "testId": testId,
            "variantId": variantId,
            "deviceId": deviceId
        ]

        postRaw(url: url, params: params) { (result: Result<String, Error>) in
            switch result {
            case .success:
                completion(.success(GenericResponse(success: true, message: nil)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Private HTTP Methods

    private func post<T: Encodable, R: Decodable>(
        url: URL,
        body: T,
        completion: @escaping (Result<R, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            return
        }

        executeRequest(request, completion: completion)
    }

    private func postRaw(
        url: URL,
        params: [String: Any],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: params)
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            return
        }

        executeRawRequest(request, completion: completion)
    }

    private func put<T: Encodable, R: Decodable>(
        url: URL,
        body: T,
        completion: @escaping (Result<R, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            return
        }

        executeRequest(request, completion: completion)
    }

    private func putRaw(
        url: URL,
        params: [String: Any],
        completion: @escaping (Result<GenericResponse, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: params)
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            return
        }

        executeRequest(request, completion: completion)
    }

    private func getRaw(
        url: URL,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")

        executeRawRequest(request, completion: completion)
    }

    private func delete<R: Decodable>(
        url: URL,
        completion: @escaping (Result<R, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")

        executeRequest(request, completion: completion)
    }

    private func executeRequest<R: Decodable>(
        _ request: URLRequest,
        completion: @escaping (Result<R, Error>) -> Void
    ) {
        Log.d(TAG, "\(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "")")

        retrySession.dataTask(with: request) { [self] data, response, error in
            if let error = error {
                Log.e(self.TAG, "Request failed", error: error)
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                Log.e(self.TAG, "Invalid response type")
                DispatchQueue.main.async {
                    completion(.failure(RiviumPushError.invalidResponse))
                }
                return
            }

            guard (200...299).contains(httpResponse.statusCode), let data = data else {
                Log.e(self.TAG, "Server error: \(httpResponse.statusCode)")
                DispatchQueue.main.async {
                    completion(.failure(RiviumPushError.serverError(httpResponse.statusCode)))
                }
                return
            }

            do {
                let response = try JSONDecoder().decode(R.self, from: data)
                Log.d(self.TAG, "Request successful")
                DispatchQueue.main.async {
                    completion(.success(response))
                }
            } catch {
                Log.e(self.TAG, "Failed to decode response", error: error)
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private func executeRawRequest(
        _ request: URLRequest,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        Log.d(TAG, "\(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "")")

        retrySession.dataTask(with: request) { [self] data, response, error in
            if let error = error {
                Log.e(self.TAG, "Request failed", error: error)
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                Log.e(self.TAG, "Invalid response type")
                DispatchQueue.main.async {
                    completion(.failure(RiviumPushError.invalidResponse))
                }
                return
            }

            guard (200...299).contains(httpResponse.statusCode), let data = data else {
                Log.e(self.TAG, "Server error: \(httpResponse.statusCode)")
                DispatchQueue.main.async {
                    completion(.failure(RiviumPushError.serverError(httpResponse.statusCode)))
                }
                return
            }

            let responseString = String(data: data, encoding: .utf8) ?? ""
            Log.d(self.TAG, "Request successful")
            DispatchQueue.main.async {
                completion(.success(responseString))
            }
        }
    }

    // NOTE: Removed synchronous methods (getInAppMessagesSync, recordInAppImpressionSync)
    // that used blocking semaphores. These could cause ANR if called from main thread.
    // Use the async versions (getInAppMessages, recordInAppImpression) instead.
}
