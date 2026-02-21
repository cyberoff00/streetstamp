import Foundation
import Combine

extension Notification.Name {
    static let watchAvatarLoadoutDidUpdate = Notification.Name("watchAvatarLoadoutDidUpdate")
}

struct WatchAvatarLoadout: Codable, Equatable {
    var bodyId: String = "body"
    var headId: String = "head"
    var skinId: String = "skin_default"

    var hairId: String = "hair_boy_default"
    var outfitId: String = "outfit_boy_suit"
    var accessoryIds: [String] = []

    var expressionId: String = "expr_default"

    enum CodingKeys: String, CodingKey {
        case bodyId
        case headId
        case skinId
        case hairId
        case outfitId
        case accessoryIds
        case accessoryId
        case expressionId
    }

    init(
        bodyId: String = "body",
        headId: String = "head",
        skinId: String = "skin_default",
        hairId: String = "hair_boy_default",
        outfitId: String = "outfit_boy_suit",
        accessoryIds: [String] = [],
        expressionId: String = "expr_default"
    ) {
        self.bodyId = bodyId
        self.headId = headId
        self.skinId = skinId
        self.hairId = hairId
        self.outfitId = outfitId
        self.accessoryIds = accessoryIds.filter { !$0.isEmpty && $0 != "none" }
        self.expressionId = expressionId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bodyId = try c.decodeIfPresent(String.self, forKey: .bodyId) ?? "body"
        headId = try c.decodeIfPresent(String.self, forKey: .headId) ?? "head"
        skinId = try c.decodeIfPresent(String.self, forKey: .skinId) ?? "skin_default"
        hairId = try c.decodeIfPresent(String.self, forKey: .hairId) ?? "hair_boy_default"
        outfitId = try c.decodeIfPresent(String.self, forKey: .outfitId) ?? "outfit_boy_suit"
        expressionId = try c.decodeIfPresent(String.self, forKey: .expressionId) ?? "expr_default"

        if let decodedIds = try c.decodeIfPresent([String].self, forKey: .accessoryIds) {
            accessoryIds = decodedIds.filter { !$0.isEmpty && $0 != "none" }
        } else if let legacy = try c.decodeIfPresent(String.self, forKey: .accessoryId),
                  !legacy.isEmpty,
                  legacy != "none" {
            accessoryIds = [legacy]
        } else {
            accessoryIds = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bodyId, forKey: .bodyId)
        try c.encode(headId, forKey: .headId)
        try c.encode(skinId, forKey: .skinId)
        try c.encode(hairId, forKey: .hairId)
        try c.encode(outfitId, forKey: .outfitId)
        try c.encode(accessoryIds, forKey: .accessoryIds)
        try c.encodeIfPresent(accessoryIds.first, forKey: .accessoryId)
        try c.encode(expressionId, forKey: .expressionId)
    }

    static var defaultValue: WatchAvatarLoadout {
        .init(
            bodyId: "body",
            headId: "head",
            skinId: "skin_default",
            hairId: "hair_boy_default",
            outfitId: "outfit_boy_suit",
            accessoryIds: [],
            expressionId: "expr_default"
        )
    }
}

enum WatchAvatarLoadoutStore {
    private static let key = "watch.avatar.loadout.v1"

    static func load() -> WatchAvatarLoadout {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(WatchAvatarLoadout.self, from: data)
        else {
            return .defaultValue
        }
        return decoded
    }

    static func save(_ loadout: WatchAvatarLoadout) {
        guard let data = try? JSONEncoder().encode(loadout) else { return }
        UserDefaults.standard.set(data, forKey: key)
        NotificationCenter.default.post(name: .watchAvatarLoadoutDidUpdate, object: nil)
    }
}

@MainActor
final class WatchAvatarSyncStore: ObservableObject {
    @Published private(set) var loadout: WatchAvatarLoadout = WatchAvatarLoadoutStore.load()

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .watchAvatarLoadoutDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadout = WatchAvatarLoadoutStore.load()
            }
        }

        // Ensure transport singleton is activated to receive app context updates.
        let transport = WatchConnectivityTransport.shared
        transport.requestAvatarSyncIfPossible()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
