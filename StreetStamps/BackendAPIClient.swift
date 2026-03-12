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
}

struct BackendRegisterResponse: Codable {
    let userId: String
    let email: String
    let emailVerificationRequired: Bool
}

struct BackendRefreshResponse: Codable {
    let accessToken: String
}

struct BackendMemoryUploadDTO: Codable {
    var id: String
    var title: String
    var notes: String
    var timestamp: Date
    var imageURLs: [String]
}

struct BackendJourneyUploadDTO: Codable {
    var id: String
    var title: String
    var activityTag: String?
    var overallMemory: String?
    var distance: Double
    var startTime: Date?
    var endTime: Date?
    var visibility: JourneyVisibility
    var routeCoordinates: [CoordinateCodable]
    var memories: [BackendMemoryUploadDTO]
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

struct BackendProfileDTO: Codable {
    var id: String
    var handle: String?
    var exclusiveID: String?
    var inviteCode: String?
    var profileVisibility: ProfileVisibility?
    var displayName: String
    var email: String?
    var bio: String
    var loadout: RobotLoadout?
    var handleChangeUsed: Bool?
    var canUpdateHandleOneTime: Bool?
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
        case .notConfigured: return "后端地址未配置"
        case .unauthorized: return "请先登录"
        case .invalidResponse: return "后端返回格式异常"
        case .server(let msg): return msg
        case .serverCode(_, let msg): return msg
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

final class BackendAPIClient {
    static let shared = BackendAPIClient()
    private let tokenRefreshGate = BackendTokenRefreshGate()
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

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let dt = ISO8601DateFormatter.withFractional.date(from: raw) { return dt }
            if let dt = ISO8601DateFormatter.withoutFractional.date(from: raw) { return dt }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid date: \(raw)")
        }
        return d
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(ISO8601DateFormatter.withFractional.string(from: date))
        }
        return e
    }

    private func request(
        path: String,
        method: String,
        token: String? = nil,
        jsonBody: Data? = nil,
        contentType: String = "application/json"
    ) async throws -> (Data, HTTPURLResponse) {
        return try await request(path: path, method: method, token: token, jsonBody: jsonBody, contentType: contentType, queryItems: [])
    }

    private func request(
        path: String,
        method: String,
        token: String? = nil,
        jsonBody: Data? = nil,
        contentType: String = "application/json",
        queryItems: [URLQueryItem]
    ) async throws -> (Data, HTTPURLResponse) {
        let url = try makeURL(path: path, queryItems: queryItems)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 45
        let resolvedToken = try await resolvedAuthorizationToken(explicitToken: token)
        if let resolvedToken, !resolvedToken.isEmpty {
            req.setValue("Bearer \(resolvedToken)", forHTTPHeaderField: "Authorization")
        }
        if let body = jsonBody {
            req.httpBody = body
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let (data, resp) = try await transport(req)
        guard let http = resp as? HTTPURLResponse else {
            throw BackendAPIError.invalidResponse
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
        guard let snapshot = await currentSessionSnapshot() else { return nil }

        if snapshot.accessToken != failedAccessToken {
            return snapshot.accessToken
        }

        if let refreshToken = await MainActor.run(resultType: String?.self, body: { sessionStore?.currentRefreshToken }),
           !refreshToken.isEmpty {
            do {
                let body = try encoder.encode(["refreshToken": refreshToken])
                let (data, _) = try await request(path: "/v1/auth/refresh", method: "POST", jsonBody: body)
                let refreshed = try decoder.decode(BackendRefreshResponse.self, from: data)
                let currentUserID = await MainActor.run { sessionStore?.accountUserID }
                guard currentUserID == snapshot.userID else { return nil }
                await MainActor.run {
                    sessionStore?.updateAccessToken(refreshed.accessToken)
                }
                return await MainActor.run {
                    guard sessionStore?.currentAccessToken == refreshed.accessToken else { return nil }
                    return refreshed.accessToken
                }
            } catch {
                return nil
            }
        }

        do {
            let refreshed = try await FirebaseAuthSession.currentIDToken(forceRefresh: true)
            guard let refreshed, !refreshed.isEmpty else { return nil }
            let currentUserID = await MainActor.run { sessionStore?.accountUserID }
            guard currentUserID == snapshot.userID else { return nil }
            await synchronizeFirebaseSession(idToken: refreshed)
            return await MainActor.run {
                guard sessionStore?.currentAccessToken == refreshed else { return nil }
                return refreshed
            }
        } catch {
            return nil
        }
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
        _ = try await request(path: "/v1/journeys/migrate", method: "POST", token: token, jsonBody: body)
    }

    func fetchMyProfile(token: String) async throws -> BackendProfileDTO {
        let (data, _) = try await request(path: "/v1/profile/me", method: "GET", token: token)
        return try decoder.decode(BackendProfileDTO.self, from: data)
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

    func uploadMedia(token: String, data: Data, fileName: String, mimeType: String) async throws -> BackendMediaUploadResponse {
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
            contentType: "multipart/form-data; boundary=\(boundary)"
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
