import Foundation

/// HTTP client for Rivium Push API
internal class ApiClient {
    private let config: RiviumPushConfig
    private let retrySession: RetryingURLSession
    private let TAG = "ApiClient"

    /// The signed user token sent as `x-user-token`, when the app provides one.
    let userTokens: UserTokenManager

    /// The server refused the user's identity, or the token provider failed.
    /// Informational: the request's own completion is unchanged. Called on
    /// the main queue.
    var onAuthError: ((RiviumPushAuthErrorEvent) -> Void)?

    init(
        config: RiviumPushConfig,
        userTokens: UserTokenManager? = nil,
        session: RetryingURLSession = RetryingURLSession()
    ) {
        self.config = config
        self.retrySession = session
        self.userTokens = userTokens ?? UserTokenManager(provider: config.tokenProvider)
        self.userTokens.onProviderFailure = { [weak self] error in
            self?.reportAuthError(code: "token_provider_failed", message: "tokenProvider failed", error: error)
        }
    }

    // MARK: - Request/Response Types

    // Register body is built as a plain dictionary so metadata values keep
    // their native JSON types (number / bool / string). Encodable with
    // [String: String] would coerce everything to strings and break
    // dashboard segment operators like >, <, is (boolean).

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
        /// Optional extra gateway endpoints, tried before the default one.
        /// Malformed entries are dropped; never fails the response.
        let mqttEndpoints: MqttEndpointList?
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
        metadata: [String: Any]?,
        appIdentifier: String? = nil,
        appVersion: String? = nil,
        appBuild: Int? = nil,
        osVersion: String? = nil,
        deviceModel: String? = nil,
        language: String? = nil,
        country: String? = nil,
        timezone: String? = nil,
        installId: String? = nil,
        completion: @escaping (Result<RegisterResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(config.serverUrl)/devices/register") else {
            completion(.failure(RiviumPushError.invalidUrl))
            return
        }

        var body: [String: Any] = [
            "deviceId": deviceId,
            "platform": "ios",
            "sdkName": config.reportedSdkName,
            "sdkVersion": config.reportedSdkVersion,
        ]
        if let pushToken = pushToken { body["pushToken"] = pushToken }
        if let apnsToken = apnsToken { body["apnsToken"] = apnsToken }
        if let userId = userId { body["userId"] = userId }
        if let appIdentifier = appIdentifier { body["appIdentifier"] = appIdentifier }
        if let metadata = metadata { body["metadata"] = metadata }
        // Auto-captured device attributes — sent as top-level fields so the
        // dashboard can offer them as indexed segment filters.
        if let appVersion = appVersion { body["appVersion"] = appVersion }
        if let appBuild = appBuild { body["appBuild"] = appBuild }
        if let osVersion = osVersion { body["osVersion"] = osVersion }
        if let deviceModel = deviceModel { body["deviceModel"] = deviceModel }
        if let language = language { body["language"] = language }
        if let country = country { body["country"] = country }
        if let timezone = timezone { body["timezone"] = timezone }
        // Stable per-install fingerprint (hashed) so the server can retire the
        // device row a reinstall left behind. Omitted when it can't be computed
        // — never sent empty. Ignored by servers older than this SDK.
        if let installId = installId, !installId.isEmpty { body["installId"] = installId }

        postDict(url: url, params: body, completion: completion)
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

    /// Clear user ID for device. Also forgets the cached user token.
    func clearUserId(
        deviceId: String,
        completion: @escaping (Result<GenericResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(config.serverUrl)/devices/\(deviceId)/user") else {
            completion(.failure(RiviumPushError.invalidUrl))
            return
        }

        // The request still carries the user's token; it is forgotten right after.
        delete(url: url, forgetUserToken: true, completion: completion)
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
        request.setValue(config.sdkHeaderValue, forHTTPHeaderField: RiviumPushSDKInfo.headerName)

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

    // MARK: - Delivery Receipts

    /// Report that a message reached this device (POST /receipts/delivered).
    /// Idempotent server-side; retries transient failures a few times.
    func reportDelivered(
        messageId: String,
        deviceId: String,
        completion: @escaping (Bool) -> Void
    ) {
        DeliveryReceiptSender.send(
            messageId: messageId,
            deviceId: deviceId,
            apiKey: config.apiKey,
            serverUrl: config.serverUrl,
            sdkHeader: config.sdkHeaderValue,
            // Only a token already at hand: a receipt never waits for the provider.
            userToken: userTokens.current(),
            maxAttempts: 3,
            timeout: NetworkConfig.requestTimeout,
            completion: completion
        )
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
        request.setValue(config.sdkHeaderValue, forHTTPHeaderField: RiviumPushSDKInfo.headerName)

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

    /// POST a `[String: Any]` dict (native JSON types preserved) and decode
    /// the response into `R`. Use this when the request body carries
    /// type-heterogeneous values like device metadata.
    private func postDict<R: Decodable>(
        url: URL,
        params: [String: Any],
        completion: @escaping (Result<R, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(config.sdkHeaderValue, forHTTPHeaderField: RiviumPushSDKInfo.headerName)

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

    private func postRaw(
        url: URL,
        params: [String: Any],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(config.sdkHeaderValue, forHTTPHeaderField: RiviumPushSDKInfo.headerName)

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
        request.setValue(config.sdkHeaderValue, forHTTPHeaderField: RiviumPushSDKInfo.headerName)

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
        request.setValue(config.sdkHeaderValue, forHTTPHeaderField: RiviumPushSDKInfo.headerName)

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
        request.setValue(config.sdkHeaderValue, forHTTPHeaderField: RiviumPushSDKInfo.headerName)

        executeRawRequest(request, completion: completion)
    }

    private func delete<R: Decodable>(
        url: URL,
        forgetUserToken: Bool = false,
        completion: @escaping (Result<R, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(config.sdkHeaderValue, forHTTPHeaderField: RiviumPushSDKInfo.headerName)

        executeRequest(request, forgetUserToken: forgetUserToken, completion: completion)
    }

    // MARK: - User Token

    /// Sends `request`, adding the user token when one is available. Every
    /// request to the API goes through here.
    ///
    /// Without a token (no provider, signed out, provider failed) the request
    /// goes out exactly as built. An expired token is routine: fetch a new one
    /// and replay the request once.
    private func send(
        _ request: URLRequest,
        forgetUserToken: Bool = false,
        completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) {
        userTokens.get { [self] token in
            if forgetUserToken, let token = token { self.userTokens.clear(ifTokenIs: token) }

            self.retrySession.dataTask(with: self.withUserToken(request, token)) { data, response, error in
                guard let token = token, self.isTokenExpired(response, data) else {
                    self.reportAuthError(response: response, data: data, sentToken: token)
                    completion(data, response, error)
                    return
                }

                self.userTokens.refresh { fresh in
                    guard let fresh = fresh, fresh != token else {
                        // No newer token to try: stop sending the expired one.
                        self.userTokens.clear(ifTokenIs: token)
                        self.reportAuthError(response: response, data: data, sentToken: token)
                        completion(data, response, error)
                        return
                    }
                    if forgetUserToken { self.userTokens.clear(ifTokenIs: fresh) }

                    Log.d(self.TAG, "User token expired, retrying once with a new one")
                    self.retrySession.dataTask(with: self.withUserToken(request, fresh)) { data, response, error in
                        self.reportAuthError(response: response, data: data, sentToken: fresh)
                        completion(data, response, error)
                    }
                }
            }
        }
    }

    private func withUserToken(_ request: URLRequest, _ token: String?) -> URLRequest {
        guard let token = token else { return request }
        var request = request
        request.setValue(token, forHTTPHeaderField: "x-user-token")
        return request
    }

    private func isTokenExpired(_ response: URLResponse?, _ data: Data?) -> Bool {
        return (response as? HTTPURLResponse)?.statusCode == 401 && Self.authErrorCode(data) == "token_expired"
    }

    /// Reports an identity error in a response, if it is one.
    private func reportAuthError(response: URLResponse?, data: Data?, sentToken: String?) {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { return }

        if status == 401, let code = Self.authErrorCode(data) {
            // A rejected token is not worth sending again.
            if code == "token_invalid", let sentToken = sentToken { userTokens.clear(ifTokenIs: sentToken) }
            reportAuthError(code: code, message: Self.authErrorMessage(data) ?? "Authentication failed", error: nil)
        } else if status == 403, sentToken != nil,
                  let message = Self.authErrorMessage(data),
                  message.contains("does not match the user token") {
            reportAuthError(code: "token_mismatch", message: message, error: nil)
        }
    }

    private func reportAuthError(code: String, message: String, error: Error?) {
        Log.w(TAG, "User token error: \(code)")
        DispatchQueue.main.async { [weak self] in
            self?.onAuthError?(RiviumPushAuthErrorEvent(code: code, message: message, error: error))
        }
    }

    /// The identity error code (`token_*`) of a response body, if any.
    private static func authErrorCode(_ data: Data?) -> String? {
        guard let data = data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let code = json["code"] as? String, code.hasPrefix("token_") else { return nil }
        return code
    }

    private static func authErrorMessage(_ data: Data?) -> String? {
        guard let data = data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return json["message"] as? String
    }

    private func executeRequest<R: Decodable>(
        _ request: URLRequest,
        forgetUserToken: Bool = false,
        completion: @escaping (Result<R, Error>) -> Void
    ) {
        Log.d(TAG, "\(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "")")

        send(request, forgetUserToken: forgetUserToken) { [self] data, response, error in
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

        send(request) { [self] data, response, error in
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
