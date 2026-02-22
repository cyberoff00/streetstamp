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
}

struct BackendNotificationsResponse: Codable {
    var items: [BackendNotificationItem]
}

struct ProfileStompResponse: Codable {
    var ok: Bool?
    var message: String?
}

private struct JourneyLikesBatchRequestV2: Codable {
    var journeyIDs: [String]
    var ownerUserID: String?
}

private struct BackendNotificationReadRequest: Codable {
    var ids: [String]
    var all: Bool
}

struct BackendProfileDTO: Codable {
    var id: String
    var handle: String?
    var inviteCode: String?
    var profileVisibility: ProfileVisibility?
    var displayName: String
    var bio: String
    var loadout: RobotLoadout?
    var stats: ProfileStatsSnapshot?
    var journeys: [FriendSharedJourney]
    var unlockedCityCards: [FriendCityCard]
}

typealias BackendFriendDTO = BackendProfileDTO

enum BackendAPIError: LocalizedError {
    case notConfigured
    case unauthorized
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "后端地址未配置"
        case .unauthorized: return "请先登录"
        case .invalidResponse: return "后端返回格式异常"
        case .server(let msg): return msg
        }
    }
}

final class BackendAPIClient {
    static let shared = BackendAPIClient()

    private init() {}

    private func makeURL(path: String) throws -> URL {
        guard let base = BackendConfig.baseURL else { throw BackendAPIError.notConfigured }
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return base.appendingPathComponent(normalizedPath)
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
        let url = try makeURL(path: path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 45
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = jsonBody {
            req.httpBody = body
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw BackendAPIError.invalidResponse
        }
        if http.statusCode == 401 { throw BackendAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            if let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = m["message"] as? String,
               !msg.isEmpty {
                throw BackendAPIError.server(msg)
            }
            let rawMsg = String(data: data, encoding: .utf8) ?? ""
            let msg = normalizeServerMessage(raw: rawMsg, statusCode: http.statusCode)
            throw BackendAPIError.server(msg)
        }
        return (data, http)
    }

    func emailRegister(email: String, password: String) async throws -> BackendAuthResponse {
        let body = try encoder.encode(["email": email, "password": password])
        let (data, _) = try await request(path: "/v1/auth/email/register", method: "POST", jsonBody: body)
        return try decoder.decode(BackendAuthResponse.self, from: data)
    }

    func emailLogin(email: String, password: String) async throws -> BackendAuthResponse {
        let body = try encoder.encode(["email": email, "password": password])
        let (data, _) = try await request(path: "/v1/auth/email/login", method: "POST", jsonBody: body)
        return try decoder.decode(BackendAuthResponse.self, from: data)
    }

    func oauthLogin(provider: String, idToken: String) async throws -> BackendAuthResponse {
        let body = try encoder.encode(["provider": provider, "idToken": idToken])
        let (data, _) = try await request(path: "/v1/auth/oauth", method: "POST", jsonBody: body)
        return try decoder.decode(BackendAuthResponse.self, from: data)
    }

    func fetchFriends(token: String) async throws -> [BackendFriendDTO] {
        let (data, _) = try await request(path: "/v1/friends", method: "GET", token: token)
        return try decoder.decode([BackendFriendDTO].self, from: data)
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

    func updateHandle(token: String, handle: String) async throws -> BackendProfileDTO {
        let body = try encoder.encode(["handle": handle])
        let (data, _) = try await request(path: "/v1/profile/handle", method: "PATCH", token: token, jsonBody: body)
        return try decoder.decode(BackendProfileDTO.self, from: data)
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
        let q = unreadOnly ? "?unreadOnly=1" : ""
        let (data, _) = try await request(path: "/v1/notifications\(q)", method: "GET", token: token)
        let resp = try decoder.decode(BackendNotificationsResponse.self, from: data)
        return resp.items
    }

    func markNotificationsRead(token: String, ids: [String], markAll: Bool = false) async throws {
        let req = BackendNotificationReadRequest(ids: ids, all: markAll)
        let body = try encoder.encode(req)
        _ = try await request(path: "/v1/notifications/read", method: "POST", token: token, jsonBody: body)
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
