import Foundation

struct ProfileStatsSnapshot: Codable, Hashable {
    var totalJourneys: Int
    var totalDistance: Double
    var totalMemories: Int
    var totalUnlockedCities: Int
}

struct BackendAuthResponse: Codable {
    let userId: String
    let provider: String
    let email: String?
    let accessToken: String
    let refreshToken: String
    let needsProfileSetup: Bool
    let hasEmailPassword: Bool?

    init(
        userId: String,
        provider: String,
        email: String?,
        accessToken: String,
        refreshToken: String,
        needsProfileSetup: Bool = false,
        hasEmailPassword: Bool? = nil
    ) {
        self.userId = userId
        self.provider = provider
        self.email = email
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.needsProfileSetup = needsProfileSetup
        self.hasEmailPassword = hasEmailPassword
    }
}

struct BackendRegisterResponse: Codable {
    let userId: String
    let email: String
    let emailVerificationRequired: Bool
    let needsProfileSetup: Bool

    init(
        userId: String,
        email: String,
        emailVerificationRequired: Bool,
        needsProfileSetup: Bool = false
    ) {
        self.userId = userId
        self.email = email
        self.emailVerificationRequired = emailVerificationRequired
        self.needsProfileSetup = needsProfileSetup
    }
}

struct BackendRefreshResponse: Codable {
    let accessToken: String
}

struct BackendLinkEmailPasswordResponse: Codable {
    let email: String
    let emailVerificationRequired: Bool
}

struct BackendMemoryUploadDTO: Codable {
    var id: String
    var title: String
    var notes: String
    var timestamp: Date
    var imageURLs: [String]
    var latitude: Double?
    var longitude: Double?
    var locationStatus: String?
}

struct BackendJourneyUploadDTO: Codable {
    var id: String
    var title: String
    var cityID: String?
    var activityTag: String?
    var overallMemory: String?
    var overallMemoryImageURLs: [String]
    var distance: Double
    var startTime: Date?
    var endTime: Date?
    var visibility: JourneyVisibility
    var sharedAt: Date?
    var routeCoordinates: [CoordinateCodable]
    var memories: [BackendMemoryUploadDTO]
    var privacyOptions: [String]?
}

struct BackendMigrationRequest: Codable {
    var journeys: [BackendJourneyUploadDTO]
    var unlockedCityCards: [FriendCityCard]
    var removedJourneyIDs: [String]?
    var snapshotComplete: Bool?
}

struct BackendMediaUploadResponse: Codable {
    var objectKey: String
    var url: String
}

struct BackendMediaPresignResponse: Codable {
    var strategy: String       // "server" or "r2"
    var presignedURL: String?
    var objectKey: String?
    var publicURL: String?
}

struct JourneyLikesBatchRequest: Codable {
    var journeyIDs: [String]
}

struct JourneyLikesBatchItem: Codable {
    var journeyID: String
    var likes: Int
    var likedByMe: Bool?
}

struct JourneyLikesBatchResponse: Codable {
    var items: [JourneyLikesBatchItem]
}

struct JourneyLikeActionResponse: Codable {
    var ownerUserID: String
    var journeyID: String
    var likes: Int
    var likedByMe: Bool
}

struct BackendJourneyLikerItem: Codable {
    var userID: String
    var displayName: String
    var likedAt: Date
}

struct BackendJourneyLikersResponse: Codable {
    var items: [BackendJourneyLikerItem]
}

struct BackendNotificationItem: Codable, Identifiable {
    var id: String
    var type: String
    var fromUserID: String?
    var fromDisplayName: String?
    var journeyID: String?
    var journeyTitle: String?
    var message: String
    var createdAt: Date
    var read: Bool
    var postcardMessageID: String?
    var cityID: String?
    var cityName: String?
    var photoURL: String?
    var messageText: String?
}

enum SocialNotificationPolicy {
    static let supportedTypes: Set<String> = [
        "journey_like",
        "profile_stomp",
        "postcard_received",
        "friend_request",
        "friend_request_accepted"
    ]

    static func supports(type: String) -> Bool {
        supportedTypes.contains(type)
    }
}

struct BackendNotificationsResponse: Codable {
    var items: [BackendNotificationItem]
}

struct ProfileStompResponse: Codable {
    var ok: Bool?
    var message: String?
}

struct BackendFriendRequestUserLite: Codable {
    var id: String
    var displayName: String
    var handle: String?
    var loadout: RobotLoadout?
}

struct BackendFriendRequestDTO: Codable, Identifiable {
    var id: String
    var fromUserID: String
    var toUserID: String
    var fromUser: BackendFriendRequestUserLite
    var toUser: BackendFriendRequestUserLite
    var note: String?
    var createdAt: Date
}

struct BackendFriendRequestsResponse: Codable {
    var incoming: [BackendFriendRequestDTO]
    var outgoing: [BackendFriendRequestDTO]
}

struct BackendFriendRequestActionResponse: Codable {
    var ok: Bool?
    var message: String?
    var request: BackendFriendRequestDTO?
    var friend: BackendFriendDTO?
}

private struct JourneyLikesBatchRequestV2: Codable {
    var journeyIDs: [String]
    var ownerUserID: String?
}

private struct BackendNotificationReadRequest: Codable {
    var ids: [String]
    var all: Bool
}

private struct BackendProfileSetupRequest: Codable {
    var displayName: String
    var loadout: RobotLoadout
}

private actor BackendTokenRefreshGate {
    private var inFlight: Task<String?, Never>?

    func refresh(client: BackendAPIClient, failedAccessToken: String) async -> String? {
        if let task = inFlight {
            return await task.value
        }
        let task = Task {
            await client.performTokenRefresh(failedAccessToken: failedAccessToken)
        }
        inFlight = task
        let token = await task.value
        inFlight = nil
        return token
    }
}

private actor BackendRefreshBackoffGate {
    private var blockedAccessToken: String?
    private var blockedUntil: Date = .distantPast

    func shouldAttemptRefresh(failedAccessToken: String) -> Bool {
        guard let blockedAccessToken else { return true }
        guard blockedAccessToken == failedAccessToken else { return true }
        return Date() >= blockedUntil
    }

    func markFailure(failedAccessToken: String, statusCode: Int?, retryAfterSeconds: Int?) {
        let now = Date()
        let delaySeconds: TimeInterval
        if let retryAfterSeconds, retryAfterSeconds > 0 {
            delaySeconds = TimeInterval(retryAfterSeconds)
        } else if statusCode == 401 {
            delaySeconds = 30 * 60
        } else {
            delaySeconds = 60
        }
        blockedAccessToken = failedAccessToken
        blockedUntil = now.addingTimeInterval(delaySeconds)
    }

    func clear() {
        blockedAccessToken = nil
        blockedUntil = .distantPast
    }
}

struct BackendProfileDTO: Codable {
    var id: String
    var handle: String?
    var exclusiveID: String?
    var inviteCode: String?
    var profileVisibility: ProfileVisibility?
    var displayName: String
    var profileSetupCompleted: Bool?
    var email: String?
    var bio: String
    var loadout: RobotLoadout?
    var handleChangeUsed: Bool?
    var canUpdateHandleOneTime: Bool?
    var hasEmailPassword: Bool?
    var stats: ProfileStatsSnapshot?
    var journeys: [FriendSharedJourney]
    var unlockedCityCards: [FriendCityCard]

    var resolvedExclusiveID: String? {
        if let exclusiveID, !exclusiveID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return exclusiveID
        }
        return handle
    }

    var canChangeExclusiveID: Bool {
        if let canUpdateHandleOneTime {
            return canUpdateHandleOneTime
        }
        return !(handleChangeUsed ?? false)
    }

    init(
        id: String,
        handle: String? = nil,
        exclusiveID: String? = nil,
        inviteCode: String? = nil,
        profileVisibility: ProfileVisibility? = nil,
        displayName: String,
        email: String? = nil,
        bio: String,
        loadout: RobotLoadout? = nil,
        handleChangeUsed: Bool? = nil,
        canUpdateHandleOneTime: Bool? = nil,
        stats: ProfileStatsSnapshot? = nil,
        journeys: [FriendSharedJourney],
        unlockedCityCards: [FriendCityCard],
        profileSetupCompleted: Bool? = nil
    ) {
        self.id = id
        self.handle = handle
        self.exclusiveID = exclusiveID
        self.inviteCode = inviteCode
        self.profileVisibility = profileVisibility
        self.displayName = displayName
        self.profileSetupCompleted = profileSetupCompleted
        self.email = email
        self.bio = bio
        self.loadout = loadout
        self.handleChangeUsed = handleChangeUsed
        self.canUpdateHandleOneTime = canUpdateHandleOneTime
        self.stats = stats
        self.journeys = journeys
        self.unlockedCityCards = unlockedCityCards
    }
}

typealias BackendFriendDTO = BackendProfileDTO

enum BackendAPIError: LocalizedError {
    case notConfigured
    case unauthorized
    case invalidResponse
    case server(String)
    case serverCode(String, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return L10n.t("error_not_configured")
        case .unauthorized: return L10n.t("error_login_expired")
        case .invalidResponse: return L10n.t("error_network_unavailable")
        case .server(let msg): return Self.localizedServerMessage(msg)
        case .serverCode(_, let msg): return Self.localizedServerMessage(msg)
        }
    }

    private static func localizedServerMessage(_ msg: String) -> String {
        guard !msg.isEmpty else { return L10n.t("error_unknown") }
        let lower = msg.lowercased()
        // Infrastructure / auth-session errors → localized generic messages
        if lower.contains("internal error") || lower.contains("internal server") { return L10n.t("error_server_error") }
        if lower.contains("too many requests") { return L10n.t("error_too_many_requests") }
        if lower.contains("unauthorized") || lower.contains("refresh token") { return L10n.t("error_login_expired") }
        // Known business errors → localized
        let knownKey = knownServerMessageKey(lower)
        if let key = knownKey { return L10n.t(key) }
        // Unrecognized business errors → pass through the backend message directly
        return msg
    }

    private static func knownServerMessageKey(_ lower: String) -> String? {
        switch lower {
        case "invalid email":
            return "error_invalid_email"
        case "password must be at least 8 characters and include a letter, number, and special character":
            return "error_weak_password"
        case "email already exists", "email already in use by another account":
            return "error_email_exists"
        case "wrong email or password":
            return "error_wrong_credentials"
        case "email not verified":
            return "error_email_not_verified"
        case "account not found":
            return "error_account_not_found"
        case "display name already taken":
            return "error_display_name_taken"
        case "invalid display name":
            return "error_invalid_display_name"
        case "already friends":
            return "error_already_friends"
        case "cannot add yourself":
            return "error_cannot_add_self"
        case "exclusive id already taken":
            return "error_exclusive_id_taken"
        default:
            return nil
        }
    }

    var serverMessage: String? {
        switch self {
        case .server(let msg):
            return msg
        case .serverCode(_, let msg):
            return msg
        default:
            return nil
        }
    }

    var responseCode: String? {
        switch self {
        case .serverCode(let code, _):
            return code
        default:
            return nil
        }
    }
}

enum LocalizedErrorHelper {
    static func message(for error: Error) -> String {
        if let apiError = error as? BackendAPIError {
            return apiError.localizedDescription
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return L10n.t("error_network_unavailable")
        }
        return L10n.t("error_unknown")
    }
}

final class BackendAPIClient {
    static let shared = BackendAPIClient()
    private let tokenRefreshGate = BackendTokenRefreshGate()
    private let refreshBackoffGate = BackendRefreshBackoffGate()
    private var transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    @MainActor
    private weak var sessionStore: UserSessionStore?

    private init() {
        self.transport = { request in
            try await URLSession.shared.data(for: request)
        }
    }

    @MainActor
    func bindSessionStore(_ sessionStore: UserSessionStore) {
        self.sessionStore = sessionStore
    }

    func installTestingTransport(
        _ transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) {
        self.transport = transport
    }

    func resetTestingTransport() {
        self.transport = { request in
            try await URLSession.shared.data(for: request)
        }
    }

    private func makeURL(path: String) throws -> URL {
        guard let base = BackendConfig.baseURL else { throw BackendAPIError.notConfigured }
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return base.appendingPathComponent(normalizedPath)
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        let baseURL = try makeURL(path: path)
        guard !queryItems.isEmpty else { return baseURL }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw BackendAPIError.invalidResponse
        }
        components.queryItems = queryItems
        guard let finalURL = components.url else {
            throw BackendAPIError.invalidResponse
        }
        return finalURL
    }

    private func encodePathSegment(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
    }

    private func normalizeServerMessage(raw: String, statusCode: Int) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "HTTP \(statusCode)" }

        if let endpoint = extractMissingEndpoint(from: text) {
            if endpoint.contains("/stomp") || endpoint.contains("/like") || endpoint.contains("/likes/") {
                return "当前后端未部署点赞/踩一踩接口（\(endpoint)），请升级后端后重试"
            }
            return "当前后端不支持接口（\(endpoint)），请检查后端版本"
        }

        if text.localizedCaseInsensitiveContains("<!doctype html") || text.localizedCaseInsensitiveContains("<html") {
            return "后端返回 HTML 错误页（HTTP \(statusCode)），请检查 API_BASE_URL 与后端版本"
        }

        if text.count > 220 {
            return "\(text.prefix(220))..."
        }
        return text
    }

    private func extractMissingEndpoint(from text: String) -> String? {
        let pattern = #"Cannot\s+(GET|POST|PUT|PATCH|DELETE)\s+([^<\s]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 3,
              let methodRange = Range(match.range(at: 1), in: text),
              let pathRange = Range(match.range(at: 2), in: text) else { return nil }
        return "\(text[methodRange]) \(text[pathRange])"
    }

    private static let sharedDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let dt = ISO8601DateFormatter.withFractional.date(from: raw) { return dt }
            if let dt = ISO8601DateFormatter.withoutFractional.date(from: raw) { return dt }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid date: \(raw)")
        }
        return d
    }()

    private static let sharedEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(ISO8601DateFormatter.withFractional.string(from: date))
        }
        return e
    }()

    private var decoder: JSONDecoder { Self.sharedDecoder }
    private var encoder: JSONEncoder { Self.sharedEncoder }

    private func request(
        path: String,
        method: String,
        token: String? = nil,
        jsonBody: Data? = nil,
        contentType: String = "application/json",
        timeout: TimeInterval = 15
    ) async throws -> (Data, HTTPURLResponse) {
        return try await request(path: path, method: method, token: token, jsonBody: jsonBody, contentType: contentType, queryItems: [], timeout: timeout)
    }

    private func request(
        path: String,
        method: String,
        token: String? = nil,
        jsonBody: Data? = nil,
        contentType: String = "application/json",
        queryItems: [URLQueryItem],
        timeout: TimeInterval = 15
    ) async throws -> (Data, HTTPURLResponse) {
        let url = try makeURL(path: path, queryItems: queryItems)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout
        let resolvedToken = try await resolvedAuthorizationToken(explicitToken: token)
        if let resolvedToken, !resolvedToken.isEmpty {
            req.setValue("Bearer \(resolvedToken)", forHTTPHeaderField: "Authorization")
        }
        if let body = jsonBody {
            req.httpBody = body
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        var lastError: Error?
        for attempt in 0..<2 {
            do {
                let (data, resp) = try await transport(req)
                guard let http = resp as? HTTPURLResponse else {
                    throw BackendAPIError.invalidResponse
                }

                if http.statusCode == 401,
                   let resolvedToken,
                   !resolvedToken.isEmpty,
                   !shouldSkipAutoRefresh(path: path) {
                    print("[BackendAPI] 401 on \(path), attempting token refresh...")
                }

                if http.statusCode == 401,
                   let resolvedToken,
                   !resolvedToken.isEmpty,
                   !shouldSkipAutoRefresh(path: path),
                   let refreshedToken = await tokenRefreshGate.refresh(client: self, failedAccessToken: resolvedToken),
                   refreshedToken != resolvedToken {
                    var retriedReq = req
                    retriedReq.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
                    let (retryData, retryResp) = try await transport(retriedReq)
                    guard let retryHTTP = retryResp as? HTTPURLResponse else {
                        throw BackendAPIError.invalidResponse
                    }
                    return try validateResponse(
                        data: retryData,
                        http: retryHTTP,
                        path: path,
                        usedAuthorizationToken: true
                    )
                }

                return try validateResponse(
                    data: data,
                    http: http,
                    path: path,
                    usedAuthorizationToken: resolvedToken?.isEmpty == false
                )
            } catch {
                lastError = error
                let nsError = error as NSError
                let isNetworkError = nsError.domain == NSURLErrorDomain &&
                    (nsError.code == NSURLErrorTimedOut ||
                     nsError.code == NSURLErrorCannotConnectToHost ||
                     nsError.code == NSURLErrorNetworkConnectionLost)

                if attempt == 0 && isNetworkError {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                throw error
            }
        }
        throw lastError ?? BackendAPIError.invalidResponse
    }

    private func shouldSkipAutoRefresh(path: String) -> Bool {
        path.hasPrefix("/v1/auth/")
    }

    private func shouldPreserveUnauthorizedServerMessage(path: String, usedAuthorizationToken: Bool) -> Bool {
        guard !usedAuthorizationToken else { return false }
        switch path {
        case "/v1/auth/login",
             "/v1/auth/apple",
             "/v1/auth/oauth",
             "/v1/auth/email/login":
            return true
        default:
            return false
        }
    }

    private func validateResponse(
        data: Data,
        http: HTTPURLResponse,
        path: String,
        usedAuthorizationToken: Bool
    ) throws -> (Data, HTTPURLResponse) {
        if http.statusCode == 401 {
            if shouldPreserveUnauthorizedServerMessage(path: path, usedAuthorizationToken: usedAuthorizationToken) {
                if let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = m["message"] as? String,
                   !msg.isEmpty {
                    throw BackendAPIError.server(msg)
                }
                let rawMsg = String(data: data, encoding: .utf8) ?? ""
                throw BackendAPIError.server(normalizeServerMessage(raw: rawMsg, statusCode: http.statusCode))
            }
            throw BackendAPIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            if let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let msg = (m["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let code = (m["code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !code.isEmpty, !msg.isEmpty {
                    throw BackendAPIError.serverCode(code, msg)
                }
                if !msg.isEmpty {
                    throw BackendAPIError.server(msg)
                }
            }
            let rawMsg = String(data: data, encoding: .utf8) ?? ""
            let msg = normalizeServerMessage(raw: rawMsg, statusCode: http.statusCode)
            throw BackendAPIError.server(msg)
        }
        return (data, http)
    }

    private func currentSessionSnapshot() async -> (userID: String, accessToken: String)? {
        await MainActor.run {
            guard let store = sessionStore,
                  let userID = store.accountUserID, !userID.isEmpty,
                  let accessToken = store.currentAccessToken, !accessToken.isEmpty else {
                return nil
            }
            return (userID, accessToken)
        }
    }

    private func resolvedAuthorizationToken(explicitToken: String?) async throws -> String? {
        if let explicitToken, !explicitToken.isEmpty {
            return explicitToken
        }
        if let cached = await MainActor.run(resultType: String?.self, body: { sessionStore?.currentAccessToken }),
           !cached.isEmpty {
            return cached
        }
        return nil
    }

    private func synchronizeFirebaseSession(idToken: String?) async {
        let snapshot = FirebaseAuthSession.currentUser
        await MainActor.run {
            if let snapshot {
                sessionStore?.syncFirebaseAccountState(
                    firebaseUID: snapshot.uid,
                    provider: snapshot.providerID,
                    email: snapshot.email,
                    emailVerified: snapshot.emailVerified,
                    cachedIDToken: idToken
                )
            } else {
                sessionStore?.updateCachedFirebaseIDToken(idToken)
            }
        }
    }

    fileprivate func performTokenRefresh(failedAccessToken: String) async -> String? {
        guard await refreshBackoffGate.shouldAttemptRefresh(failedAccessToken: failedAccessToken) else {
            print("[BackendAPI] token refresh BLOCKED by backoff gate")
            return nil
        }
        guard let snapshot = await currentSessionSnapshot() else { return nil }

        if snapshot.accessToken != failedAccessToken {
            return snapshot.accessToken
        }

        if let refreshToken = await MainActor.run(resultType: String?.self, body: { sessionStore?.currentRefreshToken }),
           !refreshToken.isEmpty {
            do {
                let result = try await requestAccessTokenRefresh(refreshToken: refreshToken)
                guard let refreshedAccessToken = result.accessToken else {
                    print("[BackendAPI] token refresh FAILED: statusCode=\(result.statusCode ?? -1)")
                    if result.statusCode == 401 {
                        await MainActor.run {
                            sessionStore?.logoutToGuest(requireReauthenticationPrompt: true)
                        }
                    }
                    await refreshBackoffGate.markFailure(
                        failedAccessToken: failedAccessToken,
                        statusCode: result.statusCode,
                        retryAfterSeconds: result.retryAfterSeconds
                    )
                    return nil
                }
                let currentUserID = await MainActor.run { sessionStore?.accountUserID }
                guard currentUserID == snapshot.userID else { return nil }
                await MainActor.run {
                    sessionStore?.updateAccessToken(refreshedAccessToken)
                }
                await refreshBackoffGate.clear()
                return await MainActor.run {
                    guard sessionStore?.currentAccessToken == refreshedAccessToken else { return nil }
                    return refreshedAccessToken
                }
            } catch {
                print("[BackendAPI] token refresh threw: \(error)")
                await refreshBackoffGate.markFailure(
                    failedAccessToken: failedAccessToken,
                    statusCode: nil,
                    retryAfterSeconds: nil
                )
                return nil
            }
        }

        do {
            let refreshed = try await FirebaseAuthSession.currentIDToken(forceRefresh: true)
            guard let refreshed, !refreshed.isEmpty else { return nil }
            let currentUserID = await MainActor.run { sessionStore?.accountUserID }
            guard currentUserID == snapshot.userID else { return nil }
            await synchronizeFirebaseSession(idToken: refreshed)
            await refreshBackoffGate.clear()
            return await MainActor.run {
                guard sessionStore?.currentAccessToken == refreshed else { return nil }
                return refreshed
            }
        } catch {
            return nil
        }
    }

    private func requestAccessTokenRefresh(refreshToken: String) async throws -> (accessToken: String?, statusCode: Int?, retryAfterSeconds: Int?) {
        let body = try encoder.encode(["refreshToken": refreshToken])
        let url = try makeURL(path: "/v1/auth/refresh")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await transport(req)
        guard let http = resp as? HTTPURLResponse else {
            return (nil, nil, nil)
        }
        let retryAfter = parseRetryAfterSeconds(http.value(forHTTPHeaderField: "Retry-After"))
        guard http.statusCode == 200 else {
            return (nil, http.statusCode, retryAfter)
        }
        let refreshed = try decoder.decode(BackendRefreshResponse.self, from: data)
        return (refreshed.accessToken, 200, retryAfter)
    }

    private func parseRetryAfterSeconds(_ rawValue: String?) -> Int? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = Int(trimmed), seconds > 0 {
            return seconds
        }
        return nil
    }

    func register(email: String, password: String, displayName: String) async throws -> BackendRegisterResponse {
        let body = try encoder.encode([
            "email": email,
            "password": password,
            "displayName": displayName
        ])
        let (data, _) = try await request(path: "/v1/auth/register", method: "POST", jsonBody: body)
        return try decoder.decode(BackendRegisterResponse.self, from: data)
    }

    func login(email: String, password: String) async throws -> BackendAuthResponse {
        let body = try encoder.encode(["email": email, "password": password])
        let (data, _) = try await request(path: "/v1/auth/login", method: "POST", jsonBody: body)
        return try decoder.decode(BackendAuthResponse.self, from: data)
    }

    func loginWithApple(idToken: String) async throws -> BackendAuthResponse {
        let body = try encoder.encode(["idToken": idToken])
        let (data, _) = try await request(path: "/v1/auth/apple", method: "POST", jsonBody: body)
        return try decoder.decode(BackendAuthResponse.self, from: data)
    }

    func linkEmailPassword(email: String, password: String) async throws -> BackendLinkEmailPasswordResponse {
        let body = try encoder.encode(["email": email, "password": password])
        let (data, _) = try await request(path: "/v1/auth/link-email-password", method: "POST", jsonBody: body)
        return try decoder.decode(BackendLinkEmailPasswordResponse.self, from: data)
    }

    func resendVerificationEmail(email: String) async throws {
        let body = try encoder.encode(["email": email])
        _ = try await request(path: "/v1/auth/resend-verification", method: "POST", jsonBody: body)
    }

    func sendPasswordReset(email: String) async throws {
        let body = try encoder.encode(["email": email])
        _ = try await request(path: "/v1/auth/forgot-password", method: "POST", jsonBody: body)
    }

    func resetPassword(token: String, newPassword: String) async throws {
        let body = try encoder.encode([
            "token": token,
            "newPassword": newPassword
        ])
        _ = try await request(path: "/v1/auth/reset-password", method: "POST", jsonBody: body)
    }

    func fetchFriends(token: String) async throws -> [BackendFriendDTO] {
        let (data, _) = try await request(path: "/v1/friends", method: "GET", token: token)
        return try decoder.decode([BackendFriendDTO].self, from: data)
    }

    func fetchFriendRequests(token: String) async throws -> BackendFriendRequestsResponse {
        let (data, _) = try await request(path: "/v1/friends/requests", method: "GET", token: token)
        return try decoder.decode(BackendFriendRequestsResponse.self, from: data)
    }

    func sendFriendRequest(
        token: String,
        displayName: String?,
        inviteCode: String?,
        handle: String? = nil,
        note: String? = nil
    ) async throws -> BackendFriendRequestActionResponse {
        var bodyDict: [String: String] = [:]
        if let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bodyDict["displayName"] = displayName
        }
        if let inviteCode, !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bodyDict["inviteCode"] = inviteCode
        }
        if let handle, !handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bodyDict["handle"] = handle
            bodyDict["exclusiveID"] = handle
        }
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bodyDict["note"] = note
        }
        let body = try encoder.encode(bodyDict)
        let (data, _) = try await request(path: "/v1/friends/requests", method: "POST", token: token, jsonBody: body)
        return try decoder.decode(BackendFriendRequestActionResponse.self, from: data)
    }

    func acceptFriendRequest(token: String, requestID: String) async throws -> BackendFriendRequestActionResponse {
        let rid = encodePathSegment(requestID)
        let (data, _) = try await request(path: "/v1/friends/requests/\(rid)/accept", method: "POST", token: token)
        return try decoder.decode(BackendFriendRequestActionResponse.self, from: data)
    }

    func rejectFriendRequest(token: String, requestID: String) async throws -> BackendFriendRequestActionResponse {
        let rid = encodePathSegment(requestID)
        let (data, _) = try await request(path: "/v1/friends/requests/\(rid)/reject", method: "POST", token: token)
        return try decoder.decode(BackendFriendRequestActionResponse.self, from: data)
    }

    func addFriend(token: String, displayName: String?, inviteCode: String?, handle: String? = nil) async throws -> BackendFriendDTO {
        var bodyDict: [String: String] = [:]
        if let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bodyDict["displayName"] = displayName
        }
        if let inviteCode, !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bodyDict["inviteCode"] = inviteCode
        }
        if let handle, !handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bodyDict["handle"] = handle
            bodyDict["exclusiveID"] = handle
        }
        let body = try encoder.encode(bodyDict)
        let (data, _) = try await request(path: "/v1/friends", method: "POST", token: token, jsonBody: body)
        return try decoder.decode(BackendFriendDTO.self, from: data)
    }

    func removeFriend(token: String, friendID: String) async throws {
        _ = try await request(path: "/v1/friends/\(friendID)", method: "DELETE", token: token)
    }

    func migrateJourneys(token: String, payload: BackendMigrationRequest) async throws {
        let body = try encoder.encode(payload)
        _ = try await request(path: "/v1/journeys/migrate", method: "POST", token: token, jsonBody: body, timeout: 60)
    }

    func fetchMyProfile(token: String) async throws -> BackendProfileDTO {
        let (data, _) = try await request(path: "/v1/profile/me", method: "GET", token: token)
        do {
            return try decoder.decode(BackendProfileDTO.self, from: data)
        } catch {
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? "<non-utf8>"
            print("[BackendAPI] fetchMyProfile decode FAILED: \(error)\n  response preview: \(preview)")
            throw error
        }
    }

    func fetchProfile(userID: String, token: String) async throws -> BackendProfileDTO {
        let (data, _) = try await request(path: "/v1/profile/\(userID)", method: "GET", token: token)
        return try decoder.decode(BackendProfileDTO.self, from: data)
    }

    func updateDisplayName(token: String, displayName: String) async throws -> BackendProfileDTO {
        let body = try encoder.encode(["displayName": displayName])
        let (data, _) = try await request(path: "/v1/profile/display-name", method: "PATCH", token: token, jsonBody: body)
        return try decoder.decode(BackendProfileDTO.self, from: data)
    }

    func updateExclusiveID(token: String, exclusiveID: String) async throws -> BackendProfileDTO {
        let body = try encoder.encode(["exclusiveID": exclusiveID, "handle": exclusiveID])
        let (data, _) = try await request(path: "/v1/profile/exclusive-id", method: "PATCH", token: token, jsonBody: body)
        return try decoder.decode(BackendProfileDTO.self, from: data)
    }

    func updateHandle(token: String, handle: String) async throws -> BackendProfileDTO {
        try await updateExclusiveID(token: token, exclusiveID: handle)
    }

    func updateProfileVisibility(token: String, visibility: ProfileVisibility) async throws -> BackendProfileDTO {
        let body = try encoder.encode(["profileVisibility": visibility.rawValue])
        let (data, _) = try await request(path: "/v1/profile/visibility", method: "PATCH", token: token, jsonBody: body)
        return try decoder.decode(BackendProfileDTO.self, from: data)
    }

    func updateLoadout(token: String, loadout: RobotLoadout) async throws -> BackendProfileDTO {
        let body = try encoder.encode(["loadout": loadout])
        let (data, _) = try await request(path: "/v1/profile/loadout", method: "PATCH", token: token, jsonBody: body)
        return try decoder.decode(BackendProfileDTO.self, from: data)
    }

    func completeProfileSetup(token: String, displayName: String, loadout: RobotLoadout) async throws -> BackendProfileDTO {
        let body = try encoder.encode(
            BackendProfileSetupRequest(
                displayName: displayName,
                loadout: loadout.normalizedForCurrentAvatar()
            )
        )
        let (data, _) = try await request(path: "/v1/profile/setup", method: "POST", token: token, jsonBody: body)
        return try decoder.decode(BackendProfileDTO.self, from: data)
    }

    func uploadMedia(token: String, data: Data, fileName: String, mimeType: String) async throws -> BackendMediaUploadResponse {
        // CN devices always upload via server — skip presign round trip.
        if BackendConfig.isChineseMainlandDevice {
            return try await uploadMediaViaServer(token: token, data: data, fileName: fileName, mimeType: mimeType)
        }
        // International: ask server whether to upload directly to R2 or via server (fallback).
        let hash = data.md5HexString
        let rawExt = (fileName as NSString).pathExtension
        let ext = rawExt.isEmpty ? ".jpg" : ".\(rawExt)"
        if let presign = try? await presignMedia(token: token, hash: hash, ext: ext, mimeType: mimeType),
           presign.strategy == "r2",
           let presignedURL = presign.presignedURL, !presignedURL.isEmpty,
           let publicURL = presign.publicURL, !publicURL.isEmpty,
           let objectKey = presign.objectKey, !objectKey.isEmpty {
            try await putDirectToR2(presignedURL: presignedURL, data: data, mimeType: mimeType)
            return BackendMediaUploadResponse(objectKey: objectKey, url: publicURL)
        }
        // Fallback: upload through server.
        return try await uploadMediaViaServer(token: token, data: data, fileName: fileName, mimeType: mimeType)
    }

    private func presignMedia(token: String, hash: String, ext: String, mimeType: String) async throws -> BackendMediaPresignResponse {
        let region = BackendConfig.isChineseMainlandDevice ? "CN" : "global"
        let body = try encoder.encode(["hash": hash, "ext": ext, "contentType": mimeType, "region": region])
        let (data, _) = try await request(path: "/v1/media/presign", method: "POST", token: token, jsonBody: body, timeout: 10)
        return try decoder.decode(BackendMediaPresignResponse.self, from: data)
    }

    private func putDirectToR2(presignedURL: String, data: Data, mimeType: String) async throws {
        guard let url = URL(string: presignedURL) else { throw BackendAPIError.invalidResponse }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.httpBody = data
        req.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        let (_, resp) = try await transport(req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BackendAPIError.invalidResponse
        }
    }

    private func uploadMediaViaServer(token: String, data: Data, fileName: String, mimeType: String) async throws -> BackendMediaUploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func append(_ str: String) {
            body.append(Data(str.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")

        let (respData, _) = try await request(
            path: "/v1/media/upload",
            method: "POST",
            token: token,
            jsonBody: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            timeout: 120
        )
        return try decoder.decode(BackendMediaUploadResponse.self, from: respData)
    }

    func fetchJourneyLikeCounts(token: String, journeyIDs: [String]) async throws -> [String: Int] {
        let stats = try await fetchJourneyLikeStats(token: token, journeyIDs: journeyIDs, ownerUserID: nil)
        return stats.mapValues { $0.likes }
    }

    func fetchJourneyLikeStats(
        token: String,
        journeyIDs: [String],
        ownerUserID: String?
    ) async throws -> [String: (likes: Int, likedByMe: Bool)] {
        let cleaned = journeyIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return [:] }

        let reqBody = JourneyLikesBatchRequestV2(
            journeyIDs: Array(Set(cleaned)),
            ownerUserID: ownerUserID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? ownerUserID : nil
        )
        let body = try encoder.encode(reqBody)
        let (data, _) = try await request(path: "/v1/journeys/likes/batch", method: "POST", token: token, jsonBody: body)
        let resp = try decoder.decode(JourneyLikesBatchResponse.self, from: data)
        var out: [String: (likes: Int, likedByMe: Bool)] = [:]
        for item in resp.items {
            out[item.journeyID] = (max(0, item.likes), item.likedByMe ?? false)
        }
        return out
    }

    func fetchJourneyLikers(
        token: String,
        ownerUserID: String,
        journeyID: String
    ) async throws -> [JourneyLiker] {
        let owner = encodePathSegment(ownerUserID)
        let journey = encodePathSegment(journeyID)
        let (data, _) = try await request(
            path: "/v1/journeys/\(owner)/\(journey)/likes",
            method: "GET",
            token: token
        )
        let response = try decoder.decode(BackendJourneyLikersResponse.self, from: data)
        return response.items.map {
            JourneyLiker(id: $0.userID, name: $0.displayName, likedAt: $0.likedAt)
        }
    }

    func likeJourney(token: String, ownerUserID: String, journeyID: String) async throws -> JourneyLikeActionResponse {
        let owner = encodePathSegment(ownerUserID)
        let journey = encodePathSegment(journeyID)
        let (data, _) = try await request(path: "/v1/journeys/\(owner)/\(journey)/like", method: "POST", token: token)
        return try decoder.decode(JourneyLikeActionResponse.self, from: data)
    }

    func unlikeJourney(token: String, ownerUserID: String, journeyID: String) async throws -> JourneyLikeActionResponse {
        let owner = encodePathSegment(ownerUserID)
        let journey = encodePathSegment(journeyID)
        let (data, _) = try await request(path: "/v1/journeys/\(owner)/\(journey)/like", method: "DELETE", token: token)
        return try decoder.decode(JourneyLikeActionResponse.self, from: data)
    }

    func stompProfile(token: String, targetUserID: String) async throws -> ProfileStompResponse {
        let target = encodePathSegment(targetUserID)
        let (data, _) = try await request(path: "/v1/profile/\(target)/stomp", method: "POST", token: token)
        return try decoder.decode(ProfileStompResponse.self, from: data)
    }

    func fetchNotifications(token: String, unreadOnly: Bool = true) async throws -> [BackendNotificationItem] {
        let queryItems = unreadOnly ? [URLQueryItem(name: "unreadOnly", value: "1")] : []
        let (data, _) = try await request(path: "/v1/notifications", method: "GET", token: token, queryItems: queryItems)
        let resp = try decoder.decode(BackendNotificationsResponse.self, from: data)
        return resp.items
    }

    func markNotificationsRead(token: String, ids: [String], markAll: Bool = false) async throws {
        let req = BackendNotificationReadRequest(ids: ids, all: markAll)
        let body = try encoder.encode(req)
        _ = try await request(path: "/v1/notifications/read", method: "POST", token: token, jsonBody: body)
    }

    func sendPostcard(token: String, req: SendPostcardRequest) async throws -> BackendSendPostcardResponse {
        let body = try encoder.encode(req)
        let (data, _) = try await request(path: "/v1/postcards/send", method: "POST", token: token, jsonBody: body)
        return try decoder.decode(BackendSendPostcardResponse.self, from: data)
    }

    func fetchPostcards(token: String, box: String, cursor: String? = nil) async throws -> BackendPostcardsResponse {
        let normalized = box.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolvedBox = (normalized == "received") ? "received" : "sent"
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "box", value: resolvedBox)]
        if let cursor, !cursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let (data, _) = try await request(path: "/v1/postcards", method: "GET", token: token, queryItems: queryItems)
        return try decoder.decode(BackendPostcardsResponse.self, from: data)
    }

    func markPostcardViewed(token: String, messageID: String) async throws {
        _ = try await request(path: "/v1/postcards/\(messageID)/view", method: "POST", token: token)
    }

    func reactToPostcard(token: String, messageID: String, req: PostcardReactionRequest) async throws -> PostcardReactionResponse {
        let body = try encoder.encode(req)
        let (data, _) = try await request(path: "/v1/postcards/\(messageID)/react", method: "POST", token: token, jsonBody: body)
        return try decoder.decode(PostcardReactionResponse.self, from: data)
    }

    func registerPushToken(token: String, pushToken: String, platform: String = "ios") async throws {
        let body = try encoder.encode(["token": pushToken, "platform": platform])
        _ = try await request(path: "/v1/push-token", method: "PUT", token: token, jsonBody: body)
    }

    // MARK: - Block / Report

    func blockUser(token: String, userID: String) async throws {
        _ = try await request(path: "/v1/users/\(userID)/block", method: "POST", token: token)
    }

    func unblockUser(token: String, userID: String) async throws {
        _ = try await request(path: "/v1/users/\(userID)/block", method: "DELETE", token: token)
    }

    func fetchBlockedUsers(token: String) async throws -> [BlockedUserDTO] {
        let (data, _) = try await request(path: "/v1/blocks", method: "GET", token: token)
        let wrapper = try decoder.decode(BlockedUsersResponse.self, from: data)
        return wrapper.blocks
    }

    func submitReport(token: String, reportedUserID: String, contentType: String, contentID: String?, reason: String, detail: String) async throws {
        var dict: [String: String] = [
            "reportedUserID": reportedUserID,
            "contentType": contentType,
            "reason": reason,
            "detail": detail
        ]
        if let contentID { dict["contentID"] = contentID }
        let body = try encoder.encode(dict)
        _ = try await request(path: "/v1/reports", method: "POST", token: token, jsonBody: body)
    }
}

struct BlockedUserDTO: Codable, Identifiable {
    let id: String
    let displayName: String
    let handle: String?
}

private struct BlockedUsersResponse: Codable {
    let blocks: [BlockedUserDTO]
}

private extension ISO8601DateFormatter {
    static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let withoutFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
