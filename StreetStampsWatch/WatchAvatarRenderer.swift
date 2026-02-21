import Foundation
import SwiftUI
import UIKit

struct WatchAvatarRendererView: View {
    let loadout: WatchAvatarLoadout

    private func imageFromPNG(_ name: String) -> UIImage? {
        guard let path = Bundle.main.path(forResource: name, ofType: "png") else { return nil }
        return UIImage(contentsOfFile: path)
    }

    private func img(_ name: String) -> some View {
        Group {
            if let uiImage = imageFromPNG(name) {
                Image(uiImage: uiImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                // Fallback in case assets are moved into xcassets.
                Image(name)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            }
        }
    }

    private var hairFrontAsset: String? {
        switch loadout.hairId {
        case "hair_girl_default":
            return "avatar_hair_girl_front"
        case "hair_boy_default":
            return "avatar_hair_boy_front"
        default:
            return "avatar_hair_boy_front"
        }
    }

    private var outfitFrontAsset: String? {
        switch loadout.outfitId {
        case "outfit_girl_suit":
            return "avatar_outfit_girl_suit_front"
        case "outfit_boy_suit":
            return "avatar_outfit_boy_suit_front"
        default:
            return "avatar_outfit_boy_suit_front"
        }
    }

    private func accessoryFrontAsset(_ id: String) -> String? {
        switch id {
        case "acc_headphone":
            return "avatar_acc_headphone_front"
        default:
            return nil
        }
    }

    private var expressionFrontAsset: String? {
        switch loadout.expressionId {
        case "expr_default":
            return "avatar_expr_default_front"
        default:
            return "avatar_expr_default_front"
        }
    }

    var body: some View {
        ZStack {
            if imageFromPNG("avatar_body_front") != nil, imageFromPNG("avatar_head_front") != nil {
                img("avatar_body_front")
                img("avatar_head_front")
                img("avatar_base_top_front")

                if let outfit = outfitFrontAsset {
                    img(outfit)
                }

                if let hair = hairFrontAsset {
                    img(hair)
                }

                ForEach(loadout.accessoryIds, id: \.self) { id in
                    if let asset = accessoryFrontAsset(id) {
                        img(asset)
                    }
                }

                if let expr = expressionFrontAsset {
                    img(expr)
                }
            } else {
                Image(systemName: "figure.walk.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.white.opacity(0.96))
                    .padding(14)
            }
        }
    }
}
