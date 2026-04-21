import Foundation

/// Callback protocol for A/B testing events
public protocol ABTestingDelegate: AnyObject {
    /// Called when variant is assigned for a test
    func abTestingManager(_ manager: ABTestingManager, didAssignVariant variant: ABTestVariant)

    /// Called when there's an error
    func abTestingManager(_ manager: ABTestingManager, didFailWithError error: Error, forTest testId: String?)
}

/// Manages A/B tests: fetching assignments, caching, and tracking
public class ABTestingManager {
    private static let TAG = "ABTestingManager"
    private static let DEFAULTS_KEY = "rivium_push_abtesting"
    private static let CACHE_TTL: TimeInterval = 30 * 60 // 30 minutes

    // Singleton
    public static let shared = ABTestingManager()

    private var apiClient: ApiClient?
    private var deviceId: String?

    // Thread-safe access
    private let queue = DispatchQueue(label: "co.rivium.push.abtesting", attributes: .concurrent)

    // Cached variant assignments (testId -> variant)
    private var _cachedAssignments: [String: ABTestVariant] = [:]
    private var cachedAssignments: [String: ABTestVariant] {
        get { queue.sync { _cachedAssignments } }
        set { queue.async(flags: .barrier) { self._cachedAssignments = newValue } }
    }

    private var lastFetchTime: Date?

    public weak var delegate: ABTestingDelegate?

    private init() {
        loadCachedAssignments()
    }

    /// Initialize with API client and device ID
    internal func configure(apiClient: ApiClient, deviceId: String) {
        self.apiClient = apiClient
        self.deviceId = deviceId
    }

    // MARK: - Public API

    /// Get all active A/B tests for the app
    public func getActiveTests(
        completion: @escaping (Result<[ABTestSummary], Error>) -> Void
    ) {
        guard let apiClient = apiClient else {
            completion(.failure(RiviumPushError.notInitialized))
            return
        }

        apiClient.getActiveABTests { result in
            switch result {
            case .success(let responseString):
                do {
                    let data = responseString.data(using: .utf8) ?? Data()
                    let tests = try JSONDecoder().decode([ABTestSummary].self, from: data)
                    Log.d(Self.TAG, "Found \(tests.count) active A/B tests")
                    completion(.success(tests))
                } catch {
                    Log.e(Self.TAG, "Failed to parse active tests", error: error)
                    completion(.failure(error))
                }
            case .failure(let error):
                Log.e(Self.TAG, "Failed to get active tests", error: error)
                completion(.failure(error))
            }
        }
    }

    /// Get variant assignment for a specific test
    public func getVariant(
        testId: String,
        forceRefresh: Bool = false,
        completion: @escaping (Result<ABTestVariant, Error>) -> Void
    ) {
        // Check cache first
        if !forceRefresh, let cached = cachedAssignments[testId], !isCacheExpired() {
            Log.d(Self.TAG, "Returning cached variant for test \(testId): \(cached.variantName)")
            completion(.success(cached))
            return
        }

        guard let apiClient = apiClient, let deviceId = deviceId else {
            completion(.failure(RiviumPushError.notInitialized))
            return
        }

        apiClient.getABTestAssignment(testId: testId, deviceId: deviceId) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let responseString):
                do {
                    let data = responseString.data(using: .utf8) ?? Data()
                    let variant = try JSONDecoder().decode(ABTestVariant.self, from: data)

                    // Cache the assignment
                    var assignments = self.cachedAssignments
                    assignments[testId] = variant
                    self.cachedAssignments = assignments
                    self.lastFetchTime = Date()
                    self.saveCachedAssignments()

                    Log.d(Self.TAG, "Got variant \(variant.variantName) for test \(testId)")
                    self.delegate?.abTestingManager(self, didAssignVariant: variant)
                    completion(.success(variant))
                } catch {
                    Log.e(Self.TAG, "Failed to parse variant", error: error)
                    self.delegate?.abTestingManager(self, didFailWithError: error, forTest: testId)
                    completion(.failure(error))
                }
            case .failure(let error):
                Log.e(Self.TAG, "Failed to get variant for test \(testId)", error: error)
                self.delegate?.abTestingManager(self, didFailWithError: error, forTest: testId)
                completion(.failure(error))
            }
        }
    }

    /// Get cached variant for a test (synchronous, no network call)
    public func getCachedVariant(testId: String) -> ABTestVariant? {
        return cachedAssignments[testId]
    }

    /// Track an event for an A/B test
    public func trackEvent(
        testId: String,
        variantId: String,
        event: ABTestEvent,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard let apiClient = apiClient, let deviceId = deviceId else {
            completion?(.failure(RiviumPushError.notInitialized))
            return
        }

        apiClient.trackABTestEvent(
            testId: testId,
            variantId: variantId,
            deviceId: deviceId,
            event: event.rawValue
        ) { result in
            switch result {
            case .success:
                Log.d(Self.TAG, "Tracked \(event.rawValue) for test \(testId), variant \(variantId)")
                completion?(.success(()))
            case .failure(let error):
                Log.e(Self.TAG, "Failed to track event", error: error)
                completion?(.failure(error))
            }
        }
    }

    /// Track impression (variant was shown to user)
    public func trackImpression(
        testId: String,
        variantId: String,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        trackEvent(testId: testId, variantId: variantId, event: .impression, completion: completion)
    }

    /// Track opened (user opened/viewed the content)
    public func trackOpened(
        testId: String,
        variantId: String,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        trackEvent(testId: testId, variantId: variantId, event: .opened, completion: completion)
    }

    /// Track clicked (user clicked a CTA)
    public func trackClicked(
        testId: String,
        variantId: String,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        trackEvent(testId: testId, variantId: variantId, event: .clicked, completion: completion)
    }

    /// Track conversion (user completed desired action like purchase, signup, etc.)
    public func trackConverted(
        testId: String,
        variantId: String,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        trackEvent(testId: testId, variantId: variantId, event: .converted, completion: completion)
    }

    /// Track conversion using cached variant
    public func trackConversion(
        testId: String,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard let variant = cachedAssignments[testId] else {
            completion?(.failure(RiviumPushError.variantNotFound))
            return
        }
        trackConverted(testId: testId, variantId: variant.variantId, completion: completion)
    }

    /// Check if device is in control group for a test
    public func isInControlGroup(testId: String) -> Bool {
        return cachedAssignments[testId]?.isControlGroup ?? false
    }

    /// Track impression and auto-call opened when variant content is displayed
    public func trackDisplay(
        variant: ABTestVariant,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        trackImpression(testId: variant.testId, variantId: variant.variantId) { [weak self] result in
            switch result {
            case .success:
                self?.trackOpened(testId: variant.testId, variantId: variant.variantId, completion: completion)
            case .failure(let error):
                completion?(.failure(error))
            }
        }
    }

    /// Clear all cached assignments
    public func clearCache() {
        cachedAssignments = [:]
        lastFetchTime = nil
        UserDefaults.standard.removeObject(forKey: Self.DEFAULTS_KEY)
        Log.d(Self.TAG, "Cache cleared")
    }

    // MARK: - Private Methods

    private func isCacheExpired() -> Bool {
        guard let lastFetch = lastFetchTime else { return true }
        return Date().timeIntervalSince(lastFetch) > Self.CACHE_TTL
    }

    private func loadCachedAssignments() {
        RiviumPushDispatch.executeBackground { [weak self] in
            guard let self = self else { return }

            guard let data = UserDefaults.standard.data(forKey: Self.DEFAULTS_KEY) else { return }

            do {
                let cached = try JSONDecoder().decode(CachedAssignments.self, from: data)
                self.cachedAssignments = cached.assignments
                self.lastFetchTime = cached.lastFetchTime
                Log.d(Self.TAG, "Loaded \(cached.assignments.count) cached assignments")
            } catch {
                Log.e(Self.TAG, "Failed to load cached assignments", error: error)
            }
        }
    }

    private func saveCachedAssignments() {
        RiviumPushDispatch.executeBackground { [weak self] in
            guard let self = self else { return }

            do {
                let cached = CachedAssignments(
                    assignments: self.cachedAssignments,
                    lastFetchTime: self.lastFetchTime
                )
                let data = try JSONEncoder().encode(cached)
                UserDefaults.standard.set(data, forKey: Self.DEFAULTS_KEY)
            } catch {
                Log.e(Self.TAG, "Failed to save cached assignments", error: error)
            }
        }
    }
}

// MARK: - Cache Storage

private struct CachedAssignments: Codable {
    let assignments: [String: ABTestVariant]
    let lastFetchTime: Date?
}
