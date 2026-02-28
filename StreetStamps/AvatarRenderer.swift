//
//  AvatarRenderer.swift
//  StreetStamps
//
//  Pixel avatar renderer (replaces Robot avatar)
//
//  Created by Claire Yang on 06/02/2026.
//

import Foundation
import SwiftUI

// MARK: - Facing (kept for backward compatibility)

enum RobotFace: String, CaseIterable {
    case front, right, back, left
}

func robotFaceFromHeading(_ headingDegrees: Double) -> RobotFace {
    let h = (headingDegrees.truncatingRemainder(dividingBy: 360) + 360)
        .truncatingRemainder(dividingBy: 360)

    switch h {
    case 45..<135:  return .right
    case 135..<225: return .back
    case 225..<315: return .left
    default:        return .front
    }
}

// MARK: - Loadout (v1: pixel character)

struct RobotLoadout: Codable, Equatable, Hashable {
    static let defaultHairColorHex = "#2B2A28"
    static let defaultBodyColorHex = "#E8BE9C"

    // base character
    var bodyId: String = "body"
    var headId: String = "head"

    // equipment
    var hairId: String = "hair_0001"
    var suitId: String? = nil
    var upperId: String = "upper_0001"
    var underId: String = "under_0001"
    var savedUpperIdForSuit: String = "upper_0001"
    var savedUnderIdForSuit: String = "under_0001"
    var accessoryIds: [String] = []

    // expression
    var expressionId: String = "expr_0001"

    // appearance colors
    var hairColorHex: String = defaultHairColorHex
    var bodyColorHex: String = defaultBodyColorHex

    enum CodingKeys: String, CodingKey {
        case bodyId
        case headId
        case hairId
        case suitId
        case upperId
        case underId
        case savedUpperIdForSuit
        case savedUnderIdForSuit
        case accessoryIds
        case legacyAccessoryId = "accessoryId"
        case expressionId
        case hairColorHex
        case bodyColorHex
    }

    init(
        bodyId: String = "body",
        headId: String = "head",
        hairId: String = "hair_0001",
        suitId: String? = nil,
        upperId: String = "upper_0001",
        underId: String = "under_0001",
        savedUpperIdForSuit: String = "upper_0001",
        savedUnderIdForSuit: String = "under_0001",
        accessoryIds: [String] = [],
        expressionId: String = "expr_0001",
        hairColorHex: String = defaultHairColorHex,
        bodyColorHex: String = defaultBodyColorHex
    ) {
        self.bodyId = bodyId
        self.headId = headId
        self.hairId = hairId
        self.suitId = suitId
        self.upperId = upperId
        self.underId = underId
        self.savedUpperIdForSuit = savedUpperIdForSuit
        self.savedUnderIdForSuit = savedUnderIdForSuit
        self.accessoryIds = accessoryIds
        self.expressionId = expressionId
        self.hairColorHex = hairColorHex
        self.bodyColorHex = bodyColorHex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bodyId = try c.decodeIfPresent(String.self, forKey: .bodyId) ?? "body"
        headId = try c.decodeIfPresent(String.self, forKey: .headId) ?? "head"
        hairId = try c.decodeIfPresent(String.self, forKey: .hairId) ?? "hair_0001"
        suitId = try c.decodeIfPresent(String.self, forKey: .suitId)
        upperId = try c.decodeIfPresent(String.self, forKey: .upperId) ?? "upper_0001"
        underId = try c.decodeIfPresent(String.self, forKey: .underId) ?? "under_0001"
        savedUpperIdForSuit = try c.decodeIfPresent(String.self, forKey: .savedUpperIdForSuit) ?? upperId
        savedUnderIdForSuit = try c.decodeIfPresent(String.self, forKey: .savedUnderIdForSuit) ?? underId
        let decodedAccessoryIds = try c.decodeIfPresent([String].self, forKey: .accessoryIds)
        if let decodedAccessoryIds {
            accessoryIds = decodedAccessoryIds.filter { !$0.isEmpty && $0 != "none" }
        } else if let legacyAccessoryId = try c.decodeIfPresent(String.self, forKey: .legacyAccessoryId),
                  !legacyAccessoryId.isEmpty,
                  legacyAccessoryId != "none" {
            accessoryIds = [legacyAccessoryId]
        } else {
            accessoryIds = []
        }
        expressionId = try c.decodeIfPresent(String.self, forKey: .expressionId) ?? "expr_0001"
        hairColorHex = try c.decodeIfPresent(String.self, forKey: .hairColorHex) ?? Self.defaultHairColorHex
        bodyColorHex = try c.decodeIfPresent(String.self, forKey: .bodyColorHex) ?? Self.defaultBodyColorHex
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bodyId, forKey: .bodyId)
        try c.encode(headId, forKey: .headId)
        try c.encode(hairId, forKey: .hairId)
        try c.encode(suitId, forKey: .suitId)
        try c.encode(upperId, forKey: .upperId)
        try c.encode(underId, forKey: .underId)
        try c.encode(savedUpperIdForSuit, forKey: .savedUpperIdForSuit)
        try c.encode(savedUnderIdForSuit, forKey: .savedUnderIdForSuit)
        try c.encode(accessoryIds, forKey: .accessoryIds)
        try c.encode(accessoryIds.first, forKey: .legacyAccessoryId)
        try c.encode(expressionId, forKey: .expressionId)
        try c.encode(hairColorHex, forKey: .hairColorHex)
        try c.encode(bodyColorHex, forKey: .bodyColorHex)
    }

    static var defaultBoy: RobotLoadout {
        RobotLoadout(
            bodyId: "body",
            headId: "head",
            hairId: "hair_0001",
            suitId: nil,
            upperId: "upper_0001",
            underId: "under_0001",
            savedUpperIdForSuit: "upper_0001",
            savedUnderIdForSuit: "under_0001",
            accessoryIds: [],
            expressionId: "expr_0001",
            hairColorHex: defaultHairColorHex,
            bodyColorHex: defaultBodyColorHex
        )
    }

    func normalizedForCurrentAvatar() -> RobotLoadout {
        var next = self
        // Retire legacy full-body suit layer globally; keep only upper/under pipeline.
        next.suitId = nil
        if next.upperId == "none" {
            next.upperId = next.savedUpperIdForSuit == "none" ? "upper_0001" : next.savedUpperIdForSuit
        }
        if next.underId == "none" {
            next.underId = next.savedUnderIdForSuit == "none" ? "under_0001" : next.savedUnderIdForSuit
        }
        return next
    }

}

// MARK: - Renderer

/// Renders a pixel character by stacking image layers.
/// All images use `.interpolation(.none)` to keep the pixel edges crisp.
struct RobotRendererView: View {
    let size: CGFloat
    let face: RobotFace
    let loadout: RobotLoadout

    private let catalogStore = AvatarCatalogStore.shared
    private var bodyTint: Color { Color(hexRGB: loadout.bodyColorHex, fallback: .white) }
    private var hairTint: Color { Color(hexRGB: loadout.hairColorHex, fallback: .white) }

    private func img(_ name: String) -> some View {
        Image(name)
            .resizable()
            .interpolation(.none)
            .scaledToFit()
    }

    private func maskTintedImg(_ name: String, color: Color) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .foregroundColor(color)
    }

    // MARK: Asset mapping (ids -> asset names)

    private func hairAsset(face: RobotFace) -> String? {
    guard let item = catalogStore.item(categoryId: "hair", itemId: loadout.hairId) else { return nil }
    return catalogStore.imageName(item.images, face: face)
}


    private func suitAsset(face: RobotFace) -> String? {
        guard let suitId = loadout.suitId,
              let item = catalogStore.item(categoryId: "suit", itemId: suitId) else { return nil }
        return catalogStore.imageName(item.images, face: face)
    }

    private func upperAsset(face: RobotFace) -> String? {
        guard let item = catalogStore.item(categoryId: "upper", itemId: loadout.upperId) else { return nil }
        return catalogStore.imageName(item.images, face: face)
    }

    private func underAsset(face: RobotFace) -> String? {
        guard let item = catalogStore.item(categoryId: "under", itemId: loadout.underId) else { return nil }
        return catalogStore.imageName(item.images, face: face)
    }


    private func accessoryAsset(itemId: String, face: RobotFace) -> String? {
        guard let item = catalogStore.item(categoryId: "accessory", itemId: itemId) else { return nil }
        return catalogStore.imageName(item.images, face: face)
    }


    // MARK: Layers

    @ViewBuilder
private var bodyLayer: some View {
    let part = catalogStore.catalog.base.body
    switch face {
    case .front:
        img(catalogStore.imageName(part, face: .front) ?? "avatar_body_front")
            .colorMultiply(bodyTint)
    case .right:
        img(catalogStore.imageName(part, face: .right) ?? "avatar_body_side")
            .colorMultiply(bodyTint)
    case .left:
        img(catalogStore.imageName(part, face: .left) ?? catalogStore.imageName(part, face: .right) ?? "avatar_body_side")
            .scaleEffect(x: -1, y: 1)
            .colorMultiply(bodyTint)
    case .back:
        if let back = catalogStore.imageName(part, face: .back) {
            img(back)
                .colorMultiply(bodyTint)
        } else {
            // placeholder until back assets arrive
            img(catalogStore.imageName(part, face: .front) ?? "avatar_body_front")
                .opacity(0.35)
                .colorMultiply(bodyTint)
        }
    }
}

    @ViewBuilder
private var headLayer: some View {
    let part = catalogStore.catalog.base.head
    switch face {
    case .front:
        img(catalogStore.imageName(part, face: .front) ?? "avatar_head_front")
            .colorMultiply(bodyTint)
    case .right:
        img(catalogStore.imageName(part, face: .right) ?? "avatar_head_side")
            .colorMultiply(bodyTint)
    case .left:
        img(catalogStore.imageName(part, face: .left) ?? catalogStore.imageName(part, face: .right) ?? "avatar_head_side")
            .scaleEffect(x: -1, y: 1)
            .colorMultiply(bodyTint)
    case .back:
        if let back = catalogStore.imageName(part, face: .back) {
            img(back)
                .colorMultiply(bodyTint)
        } else {
            img(catalogStore.imageName(part, face: .front) ?? "avatar_head_front")
                .opacity(0.25)
                .colorMultiply(bodyTint)
        }
    }
}

    private func expressionAsset(face: RobotFace) -> String? {
    guard let item = catalogStore.item(categoryId: "expression", itemId: loadout.expressionId) else { return nil }
    return catalogStore.imageName(item.images, face: face)
}

@ViewBuilder
private var expressionLayer: some View {
    // Prefer expression assets from catalog; fallback to procedural placeholder if missing.
    if let front = expressionAsset(face: .front) {
        switch face {
        case .front:
            img(front)
        case .right:
            if let side = expressionAsset(face: .right) {
                img(side)
            } else {
                img(front).opacity(0.20)
            }
        case .left:
            if let side = expressionAsset(face: .left) ?? expressionAsset(face: .right) {
                img(side).scaleEffect(x: -1, y: 1)
            } else {
                img(front).scaleEffect(x: -1, y: 1).opacity(0.20)
            }
        case .back:
            if let back = expressionAsset(face: .back) {
                img(back)
            } else {
                img(front).opacity(0.20)
            }
        }
    } else {
        PixelExpressionView(style: loadout.expressionId, isSide: (face == .left || face == .right))
    }
}
    @ViewBuilder
    private func clothingLayer(for front: String?, right: String?, left: String?, back: String?) -> some View {
        if let front {
            switch face {
            case .front:
                img(front)
            case .right:
                if let right {
                    img(right)
                } else {
                    img(front).opacity(0.25)
                }
            case .left:
                if let left = left ?? right {
                    img(left).scaleEffect(x: -1, y: 1)
                } else {
                    img(front).scaleEffect(x: -1, y: 1).opacity(0.25)
                }
            case .back:
                if let back {
                    img(back)
                } else {
                    img(front).opacity(0.20)
                }
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var underLayer: some View {
        clothingLayer(
            for: underAsset(face: .front),
            right: underAsset(face: .right),
            left: underAsset(face: .left),
            back: underAsset(face: .back)
        )
    }

    @ViewBuilder
    private var suitLayer: some View {
        clothingLayer(
            for: suitAsset(face: .front),
            right: suitAsset(face: .right),
            left: suitAsset(face: .left),
            back: suitAsset(face: .back)
        )
    }

    @ViewBuilder
    private var upperLayer: some View {
        clothingLayer(
            for: upperAsset(face: .front),
            right: upperAsset(face: .right),
            left: upperAsset(face: .left),
            back: upperAsset(face: .back)
        )
    }

@ViewBuilder
private var hairLayer: some View {
    // Prefer exact facing; fallback to front with opacity when side/back is missing.
    if let front = hairAsset(face: .front) {
        switch face {
        case .front:
            maskTintedImg(front, color: hairTint)
        case .right:
            if let side = hairAsset(face: .right) {
                maskTintedImg(side, color: hairTint)
            } else {
                maskTintedImg(front, color: hairTint)
                    .opacity(0.20)
            }
        case .left:
            if let side = hairAsset(face: .left) ?? hairAsset(face: .right) {
                maskTintedImg(side, color: hairTint)
                    .scaleEffect(x: -1, y: 1)
            } else {
                maskTintedImg(front, color: hairTint)
                    .scaleEffect(x: -1, y: 1)
                    .opacity(0.20)
            }
        case .back:
            if let back = hairAsset(face: .back) {
                maskTintedImg(back, color: hairTint)
            } else {
                maskTintedImg(front, color: hairTint)
                    .opacity(0.20)
            }
        }
    } else {
        EmptyView()
    }
}

    @ViewBuilder
    private var accessoryLayer: some View {
        let ids = loadout.accessoryIds.filter { $0 != "none" }
        if ids.isEmpty {
            EmptyView()
        } else {
            ForEach(ids, id: \.self) { itemId in
                if let front = accessoryAsset(itemId: itemId, face: .front) {
                    switch face {
                    case .front:
                        img(front)
                    case .right:
                        if let side = accessoryAsset(itemId: itemId, face: .right) {
                            img(side)
                        } else {
                            img(front).opacity(0.20)
                        }
                    case .left:
                        if let side = accessoryAsset(itemId: itemId, face: .left) ?? accessoryAsset(itemId: itemId, face: .right) {
                            img(side).scaleEffect(x: -1, y: 1)
                        } else {
                            img(front).scaleEffect(x: -1, y: 1).opacity(0.20)
                        }
                    case .back:
                        if let back = accessoryAsset(itemId: itemId, face: .back) {
                            img(back)
                        } else {
                            img(front).opacity(0.20)
                        }
                    }
                }
            }
        }
    }

var body: some View {
        ZStack {
            bodyLayer
            underLayer
            upperLayer
            headLayer
            expressionLayer
            hairLayer
            accessoryLayer

            if face == .back {
                Text(L10n.t("avatar_placeholder_back"))
                    .font(.system(size: max(10, size * 0.09), weight: .bold))
                    .foregroundColor(.black.opacity(0.35))
                    .padding(.top, size * 0.45)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: size * 0.10, x: 0, y: size * 0.08)
        .accessibilityLabel(L10n.key("accessibility_avatar"))
    }
}


// MARK: - Procedural Expression (placeholder until expression assets arrive)

private struct PixelExpressionView: View {
    let style: String
    var isSide: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // Tune these offsets for your current art scale
            let eyeSize = max(2, w * 0.04)
            let eyeY = h * 0.29
            let leftEyeX = w * 0.43
            let rightEyeX = w * 0.57
            let mouthY = h * 0.36

            ZStack {
                // Eyes
                Rectangle()
                    .frame(width: eyeSize, height: eyeSize)
                    .offset(x: leftEyeX - w/2, y: eyeY - h/2)

                if !isSide {
                    Rectangle()
                        .frame(width: eyeSize, height: eyeSize)
                        .offset(x: rightEyeX - w/2, y: eyeY - h/2)
                }

                // Mouth
                mouthShape(eyeSize: eyeSize)
                    .offset(x: 0, y: mouthY - h/2)
            }
            .foregroundColor(.black.opacity(0.9))
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func mouthShape(eyeSize: CGFloat) -> some View {
        let w = eyeSize * 3.0
        let t = eyeSize * 0.85

        switch style {
        case "smile":
            RoundedRectangle(cornerRadius: t * 0.45, style: .continuous)
                .frame(width: w, height: t)
        case "sad":
            RoundedRectangle(cornerRadius: t * 0.45, style: .continuous)
                .frame(width: w, height: t)
                .rotationEffect(.degrees(180))
        default: // neutral
            Rectangle()
                .frame(width: w, height: t * 0.8)
                .opacity(0.85)
        }
    }
}



// MARK: - Persist loadout

enum AvatarLoadoutStore {
    private static let key = "avatar.loadout.v2"

    static func load() -> RobotLoadout {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode(RobotLoadout.self, from: data)
        else {
            return .defaultBoy
        }
        return decoded.normalizedForCurrentAvatar()
    }

    static func save(_ loadout: RobotLoadout) {
        guard let data = try? JSONEncoder().encode(loadout.normalizedForCurrentAvatar()) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

extension Color {
    init(hexRGB hex: String, fallback: Color = .white) {
        var normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("#") {
            normalized.removeFirst()
        }
        if normalized.count != 6 {
            self = fallback
            return
        }
        guard let value = UInt64(normalized, radix: 16) else {
            self = fallback
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}
